variable "region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "web_subnet_id" {
  type = string
}

variable "web_sg_id" {
  type = string
}

variable "db_sg_id" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "admin_ssh_public_key" {
  type      = string
  sensitive = true
}

variable "db_admin_password" {
  type      = string
  sensitive = true
}

variable "acm_certificate_arn" {
  description = "Leave empty and keep the listener on HTTP if you don't have a domain + certificate yet"
  type        = string
  default     = ""
}
