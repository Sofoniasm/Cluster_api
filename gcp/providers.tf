terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">=5.0"
    }
    random = {
      source = "hashicorp/random"
      version = ">=3.5"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
