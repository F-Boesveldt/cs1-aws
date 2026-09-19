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
