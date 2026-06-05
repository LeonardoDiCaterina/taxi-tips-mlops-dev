variable "project_id" {
  description = "The GCP Project ID"
  type        = string
  default     = "taxi-tips-mlops-dev"
}

variable "region" {
  description = "The GCP region to deploy resources in"
  type        = string
  default     = "europe-west1"
}

variable "env" {
  description = "The environment to deploy resources in (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "image_tag" {
    description = "The Docker image tag to use for the model training and prediction jobs"
    type        = string
    default     = "v1"
    }

variable "service_name" {
    description = "The name of the Cloud Run service to deploy the model to"
    type        = string
    default     = "taxi-tips-api"
    }

variable "memory_limit" {
  description = "Memory limit for the Cloud Run container"
  type        = string
  default     = "512Mi"
}

variable "cpu_limit" {
  description = "CPU limit for the Cloud Run container"
  type        = string
  default     = "1"
}

variable "github_repo" {
  description = "The GitHub repository in the format owner/repo"
  type        = string
  default     = "leonardodicaterina/taxi-tips-mlops-dev"
}