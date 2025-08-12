variable "gcp_project" {
	description = "GCP project id"
	type        = string
}

variable "gcp_region" {
	description = "GCP region"
	type        = string
	default     = "us-central1"
}

variable "gcp_network_cidr" {
	default = "10.30.0.0/16"
}

variable "gcp_subnet_cidr"  {
	default = "10.30.1.0/24"
}
