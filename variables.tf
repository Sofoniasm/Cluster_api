variable "bootstrap_kind" { default = true }
variable "kind_cluster_name" { default = "capi-mgmt" }

variable "enable_azure" { default = false }
variable "enable_aws"   { default = false }
variable "enable_gcp"   { default = false }
variable "enable_linode" { default = false }
variable "auto_workload_examples" { default = false }

# AWS
variable "aws_region" { default = "us-east-1" }
variable "aws_vpc_cidr" { default = "10.10.0.0/16" }

# Azure
variable "azure_location" { default = "eastus" }
variable "azure_vnet_cidr" { default = "10.20.0.0/16" }
variable "azure_subnet_cidr" { default = "10.20.1.0/24" }

# GCP
variable "gcp_project" { default = "" }
variable "gcp_region" { default = "us-central1" }
variable "gcp_network_cidr" { default = "10.30.0.0/16" }
variable "gcp_subnet_cidr" { default = "10.30.1.0/24" }

# Linode
variable "linode_region" { default = "us-east" }
variable "linode_label_prefix" { default = "capi" }
variable "linode_ssh_public_key" { default = "" }
