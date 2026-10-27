variable "region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "key_name" {
  description = "Name of the EC2 key pair, needed so the NAT instance can be reached for troubleshooting"
  type        = string
}
