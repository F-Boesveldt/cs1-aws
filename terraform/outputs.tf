output "vpc_id" {
  value = module.network.vpc_id
}

output "web_asg_name" {
  value = module.compute.web_asg_name
}

output "alb_dns_name" {
  description = "The public address for reaching the web application"
  value       = module.compute.alb_dns_name
}

output "vpn_public_ip" {
  description = "WireGuard endpoint for pfSense (VPN > WireGuard > Peers > Endpoint)"
  value       = module.network.vpn_public_ip
}
