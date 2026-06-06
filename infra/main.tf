terraform {
  # --- RESTORED: GCS Backend ---
  backend "gcs" {
    bucket = "YOUR_GCS_BUCKET_NAME" # <-- Replace this with your actual state bucket name from Phase B2!
    prefix = "terraform/state"
  }
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Artifact Registry for our Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "mlops-docker-repo"
  description   = "Docker repository for MLOps project managed by Terraform"
  format        = "DOCKER"
}

# ----------------------------------------------------------------------
# UPDATED PHASE D6: Cloud Run Service
# ----------------------------------------------------------------------

# 2. Deploy the FastAPI Cloud Run Service
resource "google_cloud_run_v2_service" "api_service" {
  name     = "${var.service_name}-${var.env}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    # Attach the new service account so the app can securely talk to Vertex
    # (This account is defined over in iam.tf)
    service_account = google_service_account.api_sa.email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/mlops-docker-repo/taxi-tips-api:latest"
      
      # Inject project and region as environment variables for main.py
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }

      ports {
        container_port = 8080
      }
    }
  }
}

# 3. Make the Cloud Run URL publicly accessible over the internet
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.api_service.location
  project  = google_cloud_run_v2_service.api_service.project
  service  = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}