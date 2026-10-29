variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resource names"
  type        = string
  default     = "cs1"
}

variable "environment" {
  description = "Environment name (dev/prod) — kept simple for a case study"
  type        = string
  default     = "dev"
}

variable "key_name" {
  description = "Name of the EC2 key pair created manually in the console"
  type        = string
  default     = "cs1-key"
}

variable "db_admin_password" {
  description = "Admin password for the RDS MySQL instance"
  type        = string
  sensitive   = true
}

variable "pfsense_wg_pubkey" {
  description = "WireGuard public key of pfSense cs2-fw01 (Educloud) - not secret"
  type        = string
  default     = "vWU9Ekp4MEV0kWJLZWPJW1get7PwWWC3Vk+r7BgINmI="
}

variable "onprem_public_ip" {
  description = "Public egress IP of Educloud/Fontys"
  type        = string
  default     = "145.220.72.5/32"
}

variable "onprem_cidr" {
  description = "On-prem address space behind pfSense"
  type        = string
  default     = "172.16.0.0/16"
}
