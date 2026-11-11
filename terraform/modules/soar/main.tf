# SOAR instance (Flavor B: IaC for SOAR). The service code in /soar is
# shipped inside user_data, so a code change gives a new user_data hash
# and Terraform replaces the instance: every deploy is a clean rebuild.

data "aws_iam_instance_profile" "lab" {
  name = "cs1-ec2-role"
}

locals {
  soar_dir = "${path.module}/../../../soar"

  # The files the SOAR image needs. Add a line here when you add a
  # new Python file; tests and the public key stay out on purpose.
  soar_files = {
    "Dockerfile"       = filebase64("${local.soar_dir}/Dockerfile")
    "rules.yml"        = filebase64("${local.soar_dir}/rules.yml")
    "requirements.txt" = filebase64("${local.soar_dir}/requirements.txt")
    "app/__init__.py"  = filebase64("${local.soar_dir}/app/__init__.py")
    "app/actions.py"   = filebase64("${local.soar_dir}/app/actions.py")
    "app/main.py"      = filebase64("${local.soar_dir}/app/main.py")
    "app/rules.py"     = filebase64("${local.soar_dir}/app/rules.py")
  }
}

resource "aws_security_group" "soar" {
  name        = "cs2-soar-sg"
  description = "SOAR: webhook and metrics from the monitoring instance only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Alertmanager webhook and Prometheus scrape"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [var.monitoring_sg_id]
  }

  egress {
    description = "apt, Docker Hub and PyPI via NAT; SSH to pfSense via the VPN"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "cs2-soar-sg" }
}

resource "aws_instance" "soar" {
  ami                    = "ami-0303e2e4a29f041a3"
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.soar.id]
  private_ip             = "10.0.33.20"
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = replace(templatefile("${path.module}/soar_userdata.sh.tftpl", {
    region       = var.region
    key_param    = var.ssh_key_parameter
    pfsense_host = var.pfsense_host
    files        = local.soar_files
  }), "\r", "")

  tags = { Name = "cs2-soar01" }
}
