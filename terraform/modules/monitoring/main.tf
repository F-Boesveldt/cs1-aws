# Monitoring instance: Prometheus + Grafana + Alertmanager. No public IP —
# reachable only through the hub, matching the segmentation design.

data "aws_iam_instance_profile" "lab" {
  name = "cs1-ec2-role"
}

resource "aws_instance" "monitoring" {
  ami                    = "ami-0303e2e4a29f041a3"
  instance_type          = "t3.medium"
  subnet_id              = var.monitoring_subnet_id
  vpc_security_group_ids = [var.monitoring_sg_id]
  key_name               = var.key_name

  iam_instance_profile = data.aws_iam_instance_profile.lab.name

  # TODO Week 3: cloud-init installing Prometheus (with ec2_sd_config for
  # auto-discovery of new web-tier instances), Grafana, and Alertmanager
  # per the Design Document.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "placeholder - Prometheus/Grafana/Alertmanager setup goes here"
  EOF
  )

  tags = { Name = "${var.project_name}-monitoring" }
}
