# 1. Create a dedicated runtime Service Account for the API
resource "google_service_account" "api_sa" {
  account_id   = "taxi-api-runtime-sa"
  display_name = "Taxi API Runtime Service Account"
}

# 2. Grant the API Service Account permission to call Vertex AI
resource "google_project_iam_member" "api_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}