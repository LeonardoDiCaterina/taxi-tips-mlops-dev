terraform {
  # --- RESTORED: GCS Backend ---
  backend "gcs" {
    bucket = "taxi-tips-mlops-tf-state-taxi-tips-mlops-dev"
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

# ======================================================================
# RESTORED PHASE C: Workload Identity Federation (WIF)
# ======================================================================

# 1. WIF Pool
resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool-v2"
  display_name              = "GitHub Actions Pool v2"
}

# 2. WIF Provider
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider-v2"
  display_name                       = "GitHub Actions Provider v2"

  # ADD THIS LINE: It securely locks authentication to your specific GitHub repo
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# 3. GitHub Deployer Service Account
resource "google_service_account" "github_deployer_sa" {
  account_id   = "github-deployer-sa"
  display_name = "GitHub Deployer Service Account"
}

# 4. Allow GitHub Actions to impersonate the Service Account
resource "google_service_account_iam_member" "wif_sa_impersonation" {
  service_account_id = google_service_account.github_deployer_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}

# 5. Grant deployment permissions to the GitHub Service Account
resource "google_project_iam_member" "github_sa_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_deployer_sa.email}"
}

resource "google_project_iam_member" "github_sa_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_deployer_sa.email}"
}

resource "google_project_iam_member" "github_sa_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_deployer_sa.email}"
}

# ======================================================================
# PHASE B & D: Artifact Registry & Cloud Run Service
# ======================================================================

# Artifact Registry for our Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "mlops-docker-repo"
  description   = "Docker repository for MLOps project managed by Terraform"
  format        = "DOCKER"
}

# Deploy the FastAPI Cloud Run Service
resource "google_cloud_run_v2_service" "api_service" {
  name     = "${var.service_name}-${var.env}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # Add this block to prevent Terraform from fighting your CI/CD
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }

  template {
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

# Make the Cloud Run URL publicly accessible over the internet
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.api_service.location
  project  = google_cloud_run_v2_service.api_service.project
  service  = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}