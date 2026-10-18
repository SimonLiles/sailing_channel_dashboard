variable "project" {
  description = "GCP project ID for all managed resources."
  type        = string
  default     = "yt-sailing-dashboard"
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "dev_dataset_id" {
  description = "BigQuery dataset ID for the dev dataset (config.yml points here)."
  type        = string
  default     = "yt_sailing_data_dev"
}

variable "prod_dataset_id" {
  description = "BigQuery dataset ID for the prod dataset."
  type        = string
  default     = "yt_sailing_data"
}

variable "cache_bucket_name" {
  description = "GCS bucket name for the Shiny/RDS cache (also the Terraform state bucket)."
  type        = string
  default     = "yt-sailing-dashboard-cache"
}
