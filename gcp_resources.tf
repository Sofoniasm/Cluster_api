# Optional GCP project bootstrap (APIs + service account) when enable_gcp=true.
# Assumes the caller credentials have permission (project owner or appropriate roles) on the target project.

locals {
  gcp_api_services = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "serviceusage.googleapis.com"
  ]
}

resource "google_project_service" "required" {
  for_each           = var.enable_gcp ? toset(local.gcp_api_services) : []
  project            = var.gcp_project
  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "capi" {
  count        = var.enable_gcp && var.gcp_create_service_account ? 1 : 0
  project      = var.gcp_project
  account_id   = "capi-controller"
  display_name = "Cluster API Controller"
  depends_on   = [google_project_service.required]
}

# Basic roles for infrastructure provisioning; adjust to least privilege as needed.
resource "google_project_iam_member" "capi_compute_admin" {
  count   = var.enable_gcp && var.gcp_create_service_account ? 1 : 0
  project = var.gcp_project
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.capi[0].email}"
}

resource "google_project_iam_member" "capi_network_admin" {
  count   = var.enable_gcp && var.gcp_create_service_account ? 1 : 0
  project = var.gcp_project
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.capi[0].email}"
}

output "gcp_service_account_email" {
  value       = var.enable_gcp && var.gcp_create_service_account ? google_service_account.capi[0].email : null
  description = "Email of the created GCP service account (if created)."
}
