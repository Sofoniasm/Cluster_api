terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">=5.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

variable "project" { type = string }
variable "region" { type = string }
variable "network_cidr" { type = string }
variable "subnet_cidr" { type = string }

resource "random_pet" "suffix" {}

resource "google_compute_network" "this" {
  name                    = "capi-${random_pet.suffix.id}-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name          = "capi-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.this.id
  region        = var.region
}

output "network_id" { value = google_compute_network.this.id }
output "subnet_id" { value = google_compute_subnetwork.this.id }
