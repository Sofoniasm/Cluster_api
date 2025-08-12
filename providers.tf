terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = ">=3.80.0" }
    aws     = { source = "hashicorp/aws" version = ">=5.0" }
    google  = { source = "hashicorp/google" version = ">=5.0" }
    random  = { source = "hashicorp/random" version = ">=3.5" }
    local   = { source = "hashicorp/local"  version = ">=2.4" }
    null    = { source = "hashicorp/null"   version = ">=3.2" }
  linode  = { source = "linode/linode" version = ">=2.30" }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
  # subscription_id, client_id, client_secret, tenant_id can be set via env vars ARM_*
}

provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

provider "linode" {
  # LINODE_TOKEN env var should be set. Region specified in module.
}
