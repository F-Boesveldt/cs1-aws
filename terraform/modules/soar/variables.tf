variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Monitoring subnet: has the route to on-prem through cs2-vpn01"
  type        = string
}

variable "monitoring_sg_id" {
  type = string
}

variable "ssh_key_parameter" {
  description = "SSM SecureString with the private key for the pfSense user soar (persistent layer)"
  type        = string
  default     = "/cs2/soar/pfsense-ssh-private-key"
}

variable "pfsense_host" {
  description = "pfSense address on the WireGuard tunnel"
  type        = string
  default     = "172.16.255.1"
}
