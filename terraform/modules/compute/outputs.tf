output "web_asg_name" {
  value = aws_autoscaling_group.web.name
}

output "alb_dns_name" {
  value = aws_lb.web.dns_name
}

output "key_name" {
  value = var.key_name
}
