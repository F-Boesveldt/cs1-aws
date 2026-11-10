# Persistent layer: resources that must survive the daily destroy of the
# main stack, so the WireGuard tunnel comes back after a rebuild without
# touching pfSense. Created once, never destroyed, run locally only.

# Fixed VPN endpoint. Imported from the main stack (was module.network.aws_eip.vpn).
import {
  to = aws_eip.vpn
  id = "eipalloc-069493c307041a04a"
}

resource "aws_eip" "vpn" {
  domain = "vpc"
  tags   = { Name = "cs2-vpn-eip" }

  lifecycle {
    prevent_destroy = true
  }
}

# WireGuard private key of cs2-vpn01. Terraform declares the parameter;
# the real value is written out of band, so the secret is never in code
# or state.
resource "aws_ssm_parameter" "wg_private_key" {
  name        = "/cs2/wireguard/vpn01-private-key"
  description = "WireGuard private key of cs2-vpn01 - value set out of band"
  type        = "SecureString"
  value       = "set-out-of-band"

  lifecycle {
    ignore_changes  = [value]
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "soar_ssh_key" {
  name  = "/cs2/soar/pfsense-ssh-private-key"
  type  = "SecureString"
  value = "set-out-of-band"

  lifecycle {
    ignore_changes  = [value]
    prevent_destroy = true
  }
}
