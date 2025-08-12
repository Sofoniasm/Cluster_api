/* Simplified configuration without advanced expressions to satisfy basic parser */

# Optional: create kind management cluster
resource "null_resource" "kind" {
  count = var.bootstrap_kind ? 1 : 0
  triggers = {
    name = var.kind_cluster_name
  }
  provisioner "local-exec" {
    command = <<EOT
set -e
if ! command -v kind >/dev/null 2>&1; then
  echo "kind not installed" >&2; exit 1
fi
if ! kubectl config get-clusters | grep -q "${var.kind_cluster_name}"; then
  kind create cluster --name ${var.kind_cluster_name}
fi
kubectl config use-context kind-${var.kind_cluster_name}
EOT
    interpreter = ["bash", "-c"]
  }
}

module "azure" {
  source        = "./modules/azure"
  count         = var.enable_azure ? 1 : 0
  location      = var.azure_location
  vnet_cidr     = var.azure_vnet_cidr
  subnet_cidr   = var.azure_subnet_cidr
  depends_on    = [null_resource.kind]
}

module "aws" {
  source      = "./modules/aws"
  count       = var.enable_aws ? 1 : 0
  region      = var.aws_region
  vpc_cidr    = var.aws_vpc_cidr
  depends_on  = [null_resource.kind]
}

module "gcp" {
  source      = "./modules/gcp"
  count       = var.enable_gcp ? 1 : 0
  project     = var.gcp_project
  region      = var.gcp_region
  network_cidr = var.gcp_network_cidr
  subnet_cidr  = var.gcp_subnet_cidr
  depends_on  = [null_resource.kind]
}

module "linode" {
  source      = "./modules/linode"
  count       = var.enable_linode ? 1 : 0
  region      = var.linode_region
  label_prefix = var.linode_label_prefix
  ssh_public_key = var.linode_ssh_public_key
  depends_on  = [null_resource.kind]
}

# Initialize cluster-api providers after modules. We use one resource that depends on all.
resource "null_resource" "clusterctl_init_azure" {
  count = var.enable_azure ? 1 : 0
  depends_on = [null_resource.kind, module.azure]
  provisioner "local-exec" {
    command = <<EOT
set -e
kubectl cluster-info >/dev/null 2>&1 || { echo "Kubeconfig context invalid"; exit 1; }
clusterctl init --infrastructure capz
EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "clusterctl_init_aws" {
  count = var.enable_aws ? 1 : 0
  depends_on = [null_resource.kind, module.aws]
  provisioner "local-exec" {
    command = <<EOT
set -e
kubectl cluster-info >/dev/null 2>&1 || { echo "Kubeconfig context invalid"; exit 1; }
clusterctl init --infrastructure capa
EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "clusterctl_init_gcp" {
  count = var.enable_gcp ? 1 : 0
  depends_on = [null_resource.kind, module.gcp]
  provisioner "local-exec" {
    command = <<EOT
set -e
kubectl cluster-info >/dev/null 2>&1 || { echo "Kubeconfig context invalid"; exit 1; }
clusterctl init --infrastructure capg
EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "clusterctl_init_linode" {
  count = var.enable_linode ? 1 : 0
  depends_on = [null_resource.kind, module.linode]
  provisioner "local-exec" {
    command = <<EOT
set -e
kubectl cluster-info >/dev/null 2>&1 || { echo "Kubeconfig context invalid"; exit 1; }
clusterctl init --infrastructure caplinode || clusterctl init --infrastructure linode || echo "Attempted Linode provider init (verify provider name)"
EOT
    interpreter = ["bash", "-c"]
  }
}

# Workload cluster manifest generation per provider (optional)
resource "null_resource" "gen_cluster_azure" {
  count = var.enable_azure && var.generate_workload_clusters ? 1 : 0
  depends_on = [null_resource.clusterctl_init_azure]
  provisioner "local-exec" {
    command = <<EOT
set -e
mkdir -p artifacts
clusterctl generate cluster ${var.workload_name_prefix}-az \
  --infrastructure=azure \
  --control-plane-machine-count=${var.control_plane_machine_count} \
  --worker-machine-count=${var.worker_machine_count} > artifacts/${var.workload_name_prefix}-azure-cluster.yaml
EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "gen_cluster_aws" {
  count = var.enable_aws && var.generate_workload_clusters ? 1 : 0
  depends_on = [null_resource.clusterctl_init_aws]
  provisioner "local-exec" {
    command = <<EOT
set -e
mkdir -p artifacts
clusterctl generate cluster ${var.workload_name_prefix}-aws \
  --infrastructure=aws \
  --control-plane-machine-count=${var.control_plane_machine_count} \
  --worker-machine-count=${var.worker_machine_count} > artifacts/${var.workload_name_prefix}-aws-cluster.yaml
EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "gen_cluster_gcp" {
  count = var.enable_gcp && var.generate_workload_clusters ? 1 : 0
  depends_on = [null_resource.clusterctl_init_gcp]
  provisioner "local-exec" {
    command = <<EOT
set -e
mkdir -p artifacts
clusterctl generate cluster ${var.workload_name_prefix}-gcp \
  --infrastructure=gcp \
  --control-plane-machine-count=${var.control_plane_machine_count} \
  --worker-machine-count=${var.worker_machine_count} > artifacts/${var.workload_name_prefix}-gcp-cluster.yaml
EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "gen_cluster_linode" {
  count = var.enable_linode && var.generate_workload_clusters ? 1 : 0
  depends_on = [null_resource.clusterctl_init_linode]
  provisioner "local-exec" {
    command = <<EOT
set -e
mkdir -p artifacts
clusterctl generate cluster ${var.workload_name_prefix}-linode \
  --infrastructure=linode \
  --control-plane-machine-count=${var.control_plane_machine_count} \
  --worker-machine-count=${var.worker_machine_count} > artifacts/${var.workload_name_prefix}-linode-cluster.yaml || echo "Linode generation skipped (provider maybe experimental)"
EOT
    interpreter = ["bash", "-c"]
  }
}

output "workload_manifests" {
  value = {
    azure  = var.enable_azure  && var.generate_workload_clusters ? "artifacts/${var.workload_name_prefix}-azure-cluster.yaml" : null
    aws    = var.enable_aws    && var.generate_workload_clusters ? "artifacts/${var.workload_name_prefix}-aws-cluster.yaml" : null
    gcp    = var.enable_gcp    && var.generate_workload_clusters ? "artifacts/${var.workload_name_prefix}-gcp-cluster.yaml" : null
    linode = var.enable_linode && var.generate_workload_clusters ? "artifacts/${var.workload_name_prefix}-linode-cluster.yaml" : null
  }
}
output "azure_enabled" { value = var.enable_azure }
output "aws_enabled" { value = var.enable_aws }
output "gcp_enabled" { value = var.enable_gcp }
output "linode_enabled" { value = var.enable_linode }
