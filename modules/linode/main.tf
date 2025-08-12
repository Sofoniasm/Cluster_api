# Minimal Linode (Akamai) infra scaffold for Cluster API (experimental)
# Provider: https://registry.terraform.io/providers/linode/linode/latest

variable "region" { default = "us-east" }
variable "label_prefix" { default = "capi" }

resource "random_pet" "suffix" {}

# Simple SSH key placeholder (user should supply their public key instead)
variable "ssh_public_key" { default = "" }

resource "linode_sshkey" "capi" {
  count      = length(var.ssh_public_key) > 0 ? 1 : 0
  label      = "${var.label_prefix}-${random_pet.suffix.id}-key"
  ssh_key    = var.ssh_public_key
}

# (Optional) Create a dummy private VLAN or tag grouping (cluster-api templates will provision actual nodes)
# Using a tag for grouping resources
locals { tag = "${var.label_prefix}-${random_pet.suffix.id}" }

output "tag" { value = local.tag }
output "ssh_key_label" { value = linode_sshkey.capi[0].label if length(linode_sshkey.capi) > 0 }
