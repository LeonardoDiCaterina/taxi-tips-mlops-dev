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
      # Updated the image path to match Artifact Registry and point to latest
      image = "${var.region}-docker.pkg.dev/${var.project_id}/mlops-docker-repo/taxi-tips-api:latest"
      
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

# ------------------------------------------------------------------------------
# PHASE C: WORKLOAD IDENTITY FEDERATION (WIF) & CI/CD SETUP
# ------------------------------------------------------------------------------

# 7. Create a dedicated Service Account for GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = "github-deployer-sa"
  display_name = "GitHub Actions Deployer"
}

# 8. Grant the Service Account the permissions it needs to deploy
resource "google_project_iam_member" "sa_permissions" {
  for_each = toset([
    "roles/run.admin",
    "roles/iam.serviceAccountUser",
    "roles/artifactregistry.writer"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# 9. Create the Workload Identity Pool
resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Identity pool for automated GitHub deployments"
}

# 10. Create the Workload Identity Provider (Trusting GitHub)
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  # Hardcoded the exact case-sensitive repository string
  attribute_condition = "assertion.repository == \"LeonardoDiCaterina/taxi-tips-mlops-dev\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# 11. Allow the specific GitHub repository to impersonate the Service Account
resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  # Hardcoded the exact case-sensitive repository string
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/LeonardoDiCaterina/taxi-tips-mlops-dev"
}

# 12. Allow the GitHub repository to mint access tokens
resource "google_service_account_iam_member" "sa_token_creator" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.serviceAccountTokenCreator"
  # Hardcoded the exact case-sensitive repository string
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/LeonardoDiCaterina/taxi-tips-mlops-dev"
}

# 13. Outputs we will need for our GitHub Actions YAML file later
output "github_service_account_email" {
  value = google_service_account.github_actions.email
}

output "workload_identity_provider_name" {
  value = google_iam_workload_identity_pool_provider.github_provider.name
}