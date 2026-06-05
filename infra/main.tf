# 1. Specify which provider (plugin) we need. We are using Google Cloud.
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# 2. Configure the Google Cloud provider with our specific project and region
provider "google" {
  project = "taxi-tips-mlops-dev"
  region  = "europe-west1"
}

# 3. Declare our first resource: An Artifact Registry repository
resource "google_artifact_registry_repository" "docker_repo" {
  location      = "europe-west1"
  repository_id = "mlops-docker-repo" # Name of the repo in GCP
  description   = "Docker repository for MLOps project managed by Terraform"
  format        = "DOCKER"
}