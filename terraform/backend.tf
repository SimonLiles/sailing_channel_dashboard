terraform {
  backend "gcs" {
    bucket = "yt-sailing-dashboard-tf-state"
    prefix = "terraform/state"
  }
}