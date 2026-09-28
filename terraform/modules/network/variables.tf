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
  type = string
}

variable "nat_ami_id" {
  type    = string
  default = "ami-0303e2e4a29f041a3" # same Ubuntu AMI as the other instances
}
