# 1. Specify which provider (plugin) we need
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    # Note: State bucket names must be hardcoded in the backend block 
    # because variables aren't loaded yet when Terraform initializes.
    bucket = "taxi-tips-mlops-tf-state-taxi-tips-mlops-dev" 
    prefix = "terraform/state"
  }
}

# 2. Configure the Google Cloud provider using variables!
provider "google" {
  project = var.project_id
  region  = var.region
}

# 3. Declare our Artifact Registry repository
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "mlops-docker-repo"
  description   = "Docker repository for MLOps project managed by Terraform"
  format        = "DOCKER"
}

# 4. Deploy the FastAPI Cloud Run Service
resource "google_cloud_run_v2_service" "api_service" {
  name     = "${var.service_name}-${var.env}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      # Injecting the variables directly into the image string
      image = "${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/hello:${var.image_tag}"
      
      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
      }
    }
  }

  depends_on = [google_artifact_registry_repository.docker_repo]
}

# 5. Make the Cloud Run service public
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = google_cloud_run_v2_service.api_service.project
  location = google_cloud_run_v2_service.api_service.location
  name     = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 6. Output the final URL so we can click it
output "api_url" {
  value = google_cloud_run_v2_service.api_service.uri
}