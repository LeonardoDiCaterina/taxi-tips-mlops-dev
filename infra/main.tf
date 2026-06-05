# 1. Specify which provider (plugin) we need
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "taxi-tips-mlops-tf-state-taxi-tips-mlops-dev" 
    prefix = "terraform/state"
  }
}

# 2. Configure the Google Cloud provider
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
      # Updated to match the repository name and image name used in your deploy.yml
      image = "${var.region}-docker.pkg.dev/${var.project_id}/mlops-docker-repo/taxi-tips-api:${var.image_tag}"
      
      # FIX: Ensure Cloud Run listens on 8080
      env {
        name  = "PORT"
        value = "8080"
      }
      
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

# 6. Output the final URL
output "api_url" {
  value = google_cloud_run_v2_service.api_service.uri
}

# 7-13. Identity and IAM Setup remains the same
resource "google_service_account" "github_actions" {
  account_id   = "github-deployer-sa"
  display_name = "GitHub Actions Deployer"
}

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.sub != ''"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/LeonardoDiCaterina/taxi-tips-mlops-dev"
}

resource "google_service_account_iam_member" "sa_token_creator" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/LeonardoDiCaterina/taxi-tips-mlops-dev"
}

resource "google_project_iam_member" "sa_permissions" {
  for_each = toset([
    "roles/cloudbuild.builds.editor",
    "roles/storage.objectAdmin",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/run.admin",
    "roles/iam.serviceAccountUser"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}