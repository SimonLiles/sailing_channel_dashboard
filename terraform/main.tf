# U2 Terraform full-adopt — Iteration 1B
# Data layer FIRST, serving LAST. Import-then-verify.
# All resources match live GCP infrastructure discovered 2026-10-18.

resource "google_bigquery_dataset" "dev_dataset" {
  dataset_id              = "yt_sailing_data_dev"
  location                = "US"
  delete_contents_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = google_bigquery_dataset.dev_dataset
  id = "projects/yt-sailing-dashboard/datasets/yt_sailing_data_dev"
}

resource "google_bigquery_dataset" "prod_dataset" {
  dataset_id              = "yt_sailing_data"
  location                = "US"
  delete_contents_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = google_bigquery_dataset.prod_dataset
  id = "projects/yt-sailing-dashboard/datasets/yt_sailing_data"
}

resource "google_bigquery_dataset" "pre_migration_dataset" {
  dataset_id              = "yt_sailing_data_pre_migration"
  location                = "US"
  delete_contents_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = google_bigquery_dataset.pre_migration_dataset
  id = "projects/yt-sailing-dashboard/datasets/yt_sailing_data_pre_migration"
}

resource "google_storage_bucket" "cache" {
  name     = "yt-sailing-dashboard-cache"
  location = "US-CENTRAL1"

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age          = 60
      matches_prefix = ["backups/"]
    }
  }
}

import {
  to = google_storage_bucket.cache
  id = "yt-sailing-dashboard-cache"
}

resource "google_storage_bucket" "tf_state" {
  name     = "yt-sailing-dashboard-tf-state"
  location = "US-CENTRAL1"
}

import {
  to = google_storage_bucket.tf_state
  id = "yt-sailing-dashboard-tf-state"
}

resource "google_artifact_registry_repository" "containers" {
  repository_id = "yt-sailing-dashboard-containers"
  location      = "us-central1"
  format        = "Docker"
  description = "Repository for the Docker containers containing the different services for the YT Sailing Channel Dashboard"
  lifecycle {
    ignore_changes = [
      cleanup_policy_dry_run,
      docker_config,
    ]
  }
}

import {
  to = google_artifact_registry_repository.containers
  id = "projects/yt-sailing-dashboard/locations/us-central1/repositories/yt-sailing-dashboard-containers"
}

resource "google_cloud_scheduler_job" "etl_daily" {
  name        = "yt-sailing-channel-etl-job-scheduler-trigger"
  region      = "us-central1"
  project     = "yt-sailing-dashboard"
  schedule    = "0 0 */1 * *"
  time_zone   = "Etc/UTC"
  attempt_deadline = "180s"
  paused           = false
  description      = null

  http_target {
    body        = null
    headers     = {}
    http_method = "POST"
    uri         = "https://us-central1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/yt-sailing-dashboard/jobs/yt-sailing-channel-etl-job:run"

    oauth_token {
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
      service_account_email = "110550153049-compute@developer.gserviceaccount.com"
    }
  }

  retry_config {
    max_backoff_duration = "3600s"
    max_doublings        = 5
    max_retry_duration   = "0s"
    min_backoff_duration = "5s"
    retry_count          = 0
  }
}

import {
  to = google_cloud_scheduler_job.etl_daily
  id = "projects/yt-sailing-dashboard/locations/us-central1/jobs/yt-sailing-channel-etl-job-scheduler-trigger"
}

resource "google_cloud_run_v2_service" "shiny" {
  name     = "yt-sailing-shiny"
  location = "us-central1"
  project  = "yt-sailing-dashboard"

  deletion_protection = true
  ingress             = "INGRESS_TRAFFIC_ALL"
  invoker_iam_disabled = true
  labels              = {}
  annotations         = {}

  scaling {
    manual_instance_count = 0
    min_instance_count    = 1
  }

  template {
    annotations                      = {}
    execution_environment            = null
    gpu_zonal_redundancy_disabled    = false
    labels                           = {}
    max_instance_request_concurrency = 80
    revision                         = null
    service_account                  = "110550153049-compute@developer.gserviceaccount.com"
    session_affinity                 = false
    timeout                          = "3600s"

    containers {
      args           = []
      base_image_uri = null
      command        = []
      depends_on     = []
      image          = "us-central1-docker.pkg.dev/yt-sailing-dashboard/yt-sailing-dashboard-containers/yt-sailing-shiny:latest"
      name           = "yt-sailing-shiny-1"
      working_dir    = null

      env {
        name  = "SHINY_ENV"
        value = "production"
      }

      ports {
        container_port = 8080
        name           = "http1"
      }

      resources {
        cpu_idle          = true
        limits            = {
          "cpu"    = "1000m"
          "memory" = "1Gi"
        }
        startup_cpu_boost = true
      }

      startup_probe {
        failure_threshold     = 1
        initial_delay_seconds = 0
        period_seconds        = 240
        timeout_seconds       = 240

        tcp_socket {
          port = 8080
        }
      }
    }

    scaling {
      max_instance_count = 20
      min_instance_count = 0
    }
  }

  traffic {
    percent  = 100
    revision = null
    tag      = null
    type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

import {
  to = google_cloud_run_v2_service.shiny
  id = "projects/yt-sailing-dashboard/locations/us-central1/services/yt-sailing-shiny"
}

resource "google_cloud_run_v2_job" "etl_job" {
  name     = "yt-sailing-channel-etl-job"
  location = "us-central1"
  project  = "yt-sailing-dashboard"

  deletion_protection = true
  labels              = {}
  annotations         = {}
  launch_stage        = "GA"

  template {
    annotations = {}
    labels      = {}
    parallelism = 0
    task_count  = 1

    template {
      encryption_key                = null
      execution_environment         = "EXECUTION_ENVIRONMENT_GEN2"
      gpu_zonal_redundancy_disabled = false
      max_retries                   = 3
      service_account               = "110550153049-compute@developer.gserviceaccount.com"
      timeout                       = "600s"

      containers {
        args        = ["main.R"]
        command     = ["Rscript"]
        depends_on  = []
        image       = "us-central1-docker.pkg.dev/yt-sailing-dashboard/yt-sailing-dashboard-containers/yt-sailing-channel-etl:latest"
        name        = "yt-sailing-channel-etl-job-1"
        working_dir = null

        env {
          name  = "ETL_ENV"
          value = "production"
        }
        env {
          name  = "YT_API_KEY"
          value = null

          value_source {
            secret_key_ref {
              secret  = "YOUTUBE_API_KEY"
              version = "latest"
            }
          }
        }

        resources {
          limits = {
            "cpu"    = "1000m"
            "memory" = "2048Mi"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

import {
  to = google_cloud_run_v2_job.etl_job
  id = "projects/yt-sailing-dashboard/locations/us-central1/jobs/yt-sailing-channel-etl-job"
}