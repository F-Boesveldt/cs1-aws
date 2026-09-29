variable "region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "hub_nva_eni_id" {
  description = "ENI ID of the hub NVA, for routing monitoring traffic through it"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "Name of the EC2 key pair, needed so the NAT instance can be reached for troubleshooting"
  type        = string
}
