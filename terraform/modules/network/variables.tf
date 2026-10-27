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

variable "pfsense_wg_pubkey" {
  description = "WireGuard public key of pfSense cs2-fw01 (Educloud) - not secret"
  type        = string
}

variable "onprem_public_ip" {
  description = "Public egress IP of Educloud/Fontys - only source allowed to reach WireGuard"
  type        = string
}

variable "onprem_cidr" {
  description = "On-prem address space behind pfSense (MGMT/WORKSTATIONS/SERVERS + tunnel)"
  type        = string
}
