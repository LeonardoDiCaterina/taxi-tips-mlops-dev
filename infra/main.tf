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

# ------------------------------------------------------------------------------
# PHASE C: WORKLOAD IDENTITY FEDERATION (WIF) & CI/CD SETUP
# ------------------------------------------------------------------------------

# 7. Create a dedicated Service Account for GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = "github-deployer-sa"
  display_name = "GitHub Actions Deployer"
}

# 8. Grant the Service Account the permissions it needs to deploy
resource "google_project_iam_member" "sa_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "sa_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "sa_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# 9. Create the Workload Identity Pool
resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Identity pool for automated GitHub deployments"
}
# 10. Provider
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  
  # KEEP THIS WIDE OPEN during debug to rule out string mismatches
  attribute_condition = "assertion.sub != ''"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# 11. Allow the specific GitHub repository to impersonate the Service Account
resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/leonardodicaterina/taxi-tips-mlops-dev"
}
# 12. Token Creator (Ensure it uses the provider name correctly)
resource "google_service_account_iam_member" "sa_token_creator" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/LeonardoDiCaterina/taxi-tips-mlops-dev"
}

# 13. Grant Cloud Build Editor to the Service Account
resource "google_project_iam_member" "sa_cloud_build_editor" {
  project = "taxi-tips-mlops-dev"
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# 14. Grant Storage Object Admin (to manage the build bucket)
resource "google_project_iam_member" "sa_storage_admin" {
  project = "taxi-tips-mlops-dev"
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# 15. Grant Service Usage Consumer role (Required to use APIs like Cloud Build)
resource "google_project_iam_member" "sa_service_usage" {
  project = "taxi-tips-mlops-dev"
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}