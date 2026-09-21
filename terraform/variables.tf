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

variable "admin_ssh_public_key" {
  description = "SSH public key for EC2 instance admin access"
  type        = string
  sensitive   = true
}

variable "db_admin_password" {
  description = "Admin password for the RDS MySQL instance"
  type        = string
  sensitive   = true
}
