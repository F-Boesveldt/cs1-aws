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
