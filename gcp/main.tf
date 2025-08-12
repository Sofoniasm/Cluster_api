module "gcp_infra" {
  source       = "../modules/gcp"
  project      = var.gcp_project
  region       = var.gcp_region
  network_cidr = var.gcp_network_cidr
  subnet_cidr  = var.gcp_subnet_cidr
}

# Optional future: clusterctl init for GCP (if using kind mgmt cluster from parent repo)
# resource "null_resource" "clusterctl_init_gcp" { }

output "gcp_network_id" { value = module.gcp_infra.network_id }
output "gcp_subnet_id"  { value = module.gcp_infra.subnet_id }
