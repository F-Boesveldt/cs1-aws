output "soar_private_ip" {
  value = aws_instance.soar.private_ip
}

output "soar_instance_id" {
  value = aws_instance.soar.id
}
