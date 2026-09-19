output "vpc_id" {
  value = aws_vpc.main.id
}

output "hub_subnet_id" {
  value = aws_subnet.hub.id
}

output "web_subnet_id" {
  value = aws_subnet.web.id
}

output "db_subnet_id" {
  value = aws_subnet.db.id
}

output "monitoring_subnet_id" {
  value = aws_subnet.monitoring.id
}

output "db_subnet_ids" {
  value = [aws_subnet.db.id, aws_subnet.db_secondary.id]
}

output "public_subnet_ids" {
  value = [aws_subnet.hub.id, aws_subnet.hub_secondary.id]
}

output "web_sg_id" {
  value = aws_security_group.web.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}

output "monitoring_sg_id" {
  value = aws_security_group.monitoring.id
}
