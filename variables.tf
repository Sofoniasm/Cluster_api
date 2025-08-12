variable "bootstrap_kind" { default = true }
variable "kind_cluster_name" { default = "capi-mgmt" }

variable "enable_azure" { default = false }
variable "enable_aws"   { default = false }
variable "enable_gcp"   { default = false }
variable "enable_linode" { default = false }
variable "auto_workload_examples" { default = false }
variable "gcp_create_service_account" { 
	description = "Whether to create a service account for Cluster API GCP provider (no key created)."
	default     = true 
}

# AWS
variable "aws_region" { default = "us-east-1" }
variable "aws_vpc_cidr" { default = "10.10.0.0/16" }

# Azure
variable "azure_location" { default = "eastus" }
variable "azure_vnet_cidr" { default = "10.20.0.0/16" }
variable "azure_subnet_cidr" { default = "10.20.1.0/24" }

# GCP
# Provide a non-empty placeholder so that the google provider doesn't error when enable_gcp=false.
# When enabling GCP set -var="gcp_project=your-real-project-id".
variable "gcp_project" { 
	description = "GCP project id (required only if enable_gcp=true)."
	default     = "gcp-disabled-placeholder"
}
variable "gcp_region" { default = "us-central1" }
variable "gcp_network_cidr" { default = "10.30.0.0/16" }
variable "gcp_subnet_cidr" { default = "10.30.1.0/24" }

# Linode
variable "linode_region" { default = "us-east" }
variable "linode_label_prefix" { default = "capi" }
variable "linode_ssh_public_key" { default = "" }
