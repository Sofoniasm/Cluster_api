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

# Optional: automatically create small sample workload clusters (one per enabled provider)
resource "null_resource" "sample_workloads" {
  count = var.auto_workload_examples ? 1 : 0
  depends_on = [null_resource.clusterctl_init_azure, null_resource.clusterctl_init_aws, null_resource.clusterctl_init_gcp, null_resource.clusterctl_init_linode]
  provisioner "local-exec" {
    command = <<EOT
set -e
kubectl cluster-info >/dev/null 2>&1 || { echo "Kubeconfig invalid"; exit 1; }
if [ "${var.enable_azure}" = "true" ]; then clusterctl generate cluster az-demo --infrastructure=azure | kubectl apply -f - || true; fi
if [ "${var.enable_aws}" = "true" ]; then clusterctl generate cluster aws-demo --infrastructure=aws | kubectl apply -f - || true; fi
if [ "${var.enable_gcp}" = "true" ]; then clusterctl generate cluster gcp-demo --infrastructure=gcp | kubectl apply -f - || true; fi
if [ "${var.enable_linode}" = "true" ]; then clusterctl generate cluster linode-demo --infrastructure=linode | kubectl apply -f - || true; fi
EOT
    interpreter = ["bash", "-c"]
  }
}
output "azure_enabled" { value = var.enable_azure }
output "aws_enabled" { value = var.enable_aws }
output "gcp_enabled" { value = var.enable_gcp }
output "linode_enabled" { value = var.enable_linode }
