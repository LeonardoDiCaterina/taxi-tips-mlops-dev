terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # THIS IS THE NEW PART: Move the state file to Cloud Storage
  backend "gcs" {
    bucket = "taxi-tips-mlops-tf-state-taxi-tips-mlops-dev"
    prefix = "terraform/state"
  }
}