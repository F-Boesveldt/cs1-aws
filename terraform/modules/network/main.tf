# Hub-and-spoke network module (AWS version), built ON TOP of the
# pre-existing AWS Academy VPC (cs1-aws-vpc) rather than creating a new
# one — ec2:CreateVpc is denied for this account. Existing public1/public2
# subnets are repurposed as hub/hub-secondary; existing private1/private2
# are repurposed as db/db-secondary (convenient, since RDS needs a two-AZ
# subnet group anyway). Only web and monitoring are newly created here.

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["cs1-aws-vpc"]
  }
}

data "aws_internet_gateway" "main" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

data "aws_subnet" "hub" {
  filter {
    name   = "tag:Name"
    values = ["cs1-aws-subnet-public1-eu-central-1a"]
  }
}

data "aws_subnet" "hub_secondary" {
  filter {
    name   = "tag:Name"
    values = ["cs1-aws-subnet-public2-eu-central-1b"]
  }
}

data "aws_subnet" "db" {
  filter {
    name   = "tag:Name"
    values = ["cs1-aws-subnet-private1-eu-central-1a"]
  }
}

data "aws_subnet" "db_secondary" {
  filter {
    name   = "tag:Name"
    values = ["cs1-aws-subnet-private2-eu-central-1b"]
  }
}

# ---- New subnets: web and monitoring ----
# Carved from free space within 10.0.0.0/16 — clear of all four existing
# subnets (10.0.0.0/20, 10.0.16.0/20, 10.0.128.0/20, 10.0.144.0/20).

resource "aws_subnet" "web" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = "10.0.32.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "${var.project_name}-web-subnet" }
}

resource "aws_subnet" "monitoring" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = "10.0.33.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "${var.project_name}-monitoring-subnet" }
}

# ---- Security Groups ----
# Unchanged in logic from before — just pointing at the existing VPC's ID
# instead of one this config created.
#
# Cross-SG references (REQ-02, Prometheus scraping) are defined as separate
# aws_security_group_rule resources below, not inline, because web, db and
# monitoring reference each other in a triangle (web->monitoring,
# monitoring->web, monitoring->db, db->web) — inline blocks make Terraform
# treat those references as resource-level dependencies, which creates a
# cycle it can't resolve. Separate rule resources break that: the three
# (now ruleless) security groups have no dependency on each other at
# creation, only the rule resources do, and those can be created in any
# order once all three groups exist.

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web tier - allows HTTP from the internet"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Prometheus scrape of node_exporter"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "DB tier - allows MySQL only from the web tier"
  vpc_id      = data.aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-db-sg" }
}

resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-monitoring-sg"
  description = "Monitoring - allows exporter ports from web and db only"
  vpc_id      = data.aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-monitoring-sg" }
}

# ---- Cross-SG rules (separate resources to avoid a dependency cycle) ----

# db: allow MySQL from web tier (REQ-02)
resource "aws_security_group_rule" "db_from_web_mysql" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.web.id
}

# Moved inline into aws_security_group.web - mixing inline ingress with
# separate rule resources on one SG made them overwrite each other.
removed {
  from = aws_security_group_rule.web_from_monitoring_9100

  lifecycle {
    destroy = false
  }
}

# monitoring: allow scraping db's mysqld_exporter
resource "aws_security_group_rule" "monitoring_from_db_9104" {
  type                     = "ingress"
  from_port                = 9104
  to_port                  = 9104
  protocol                 = "tcp"
  security_group_id        = aws_security_group.monitoring.id
  source_security_group_id = aws_security_group.db.id
}

# ---- Route table for the web and monitoring subnets ----
# 0.0.0.0/0 goes through the NAT instance (internet egress); the on-prem
# range (Educloud) goes through the WireGuard gateway cs2-vpn01.
# The db subnets keep their own route tables and deliberately get NO route
# to on-prem: the database stays reachable from the web tier only (REQ-03).
# Routes are inline on purpose - mixing inline routes with separate
# aws_route resources makes them overwrite each other on every apply.

resource "aws_route_table" "web" {
  vpc_id = data.aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  route {
    cidr_block           = var.onprem_cidr
    network_interface_id = aws_instance.vpn.primary_network_interface_id
  }

  tags = { Name = "${var.project_name}-web-rt" }
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.web.id
}

resource "aws_route_table_association" "monitoring" {
  subnet_id      = aws_subnet.monitoring.id
  route_table_id = aws_route_table.web.id
}

# ---- NAT instance ----
# Gives the web and monitoring subnets outbound internet access (apt-get,
# docker pull) without exposing them to inbound traffic from the internet.
# Sits in the hub (public) subnet, has a public IP, and forwards traffic
# for the private subnets via iptables MASQUERADE.

resource "aws_security_group" "nat" {
  name        = "${var.project_name}-nat-sg"
  description = "NAT instance - forwards outbound internet traffic for the web and monitoring subnets"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.web.cidr_block, aws_subnet.monitoring.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-nat-sg" }
}

resource "aws_instance" "nat" {
  ami                         = "ami-0303e2e4a29f041a3"
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.hub.id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  # Required for a NAT instance: it must be allowed to receive/send traffic
  # that isn't addressed to itself.
  source_dest_check = false

  # NOTE: this is a plain aws_instance, so user_data must NOT be wrapped in
  # base64encode() — Terraform base64-encodes it for you automatically here.
  # (This is the opposite rule from aws_launch_template below, which does
  # need base64encode() explicitly. Easy to mix up, so flagging it.)
  user_data = <<-EOF
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    until apt-get update -y; do sleep 5; done
    apt-get install -y iptables iptables-persistent
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf
    IFACE=$(ip route show default | awk '{print $5}' | head -n1)
    iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
    netfilter-persistent save
  EOF

  tags = { Name = "${var.project_name}-nat" }
}

# ---- CS2: WireGuard VPN gateway (hub NVA for the hybrid link) ----
# Site-to-site tunnel to pfSense cs2-fw01 in Educloud. pfSense sits behind
# the school's NAT, so it always initiates; this side only listens.
# Separate from the NAT instance so internet egress and the VPN fail
# independently (design-for-failure). No SSH: managed via Session Manager.

data "aws_iam_instance_profile" "lab" {
  name = "cs1-ec2-role"
}

resource "aws_security_group" "vpn" {
  name        = "cs2-vpn-sg"
  description = "WireGuard gateway - tunnel from Educloud only, forwarding for web and monitoring"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "WireGuard from Educloud egress IP only"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = [var.onprem_public_ip]
  }

  ingress {
    description = "Traffic from web and monitoring towards on-prem"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.web.cidr_block, aws_subnet.monitoring.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "cs2-vpn-sg" }
}

resource "aws_instance" "vpn" {
  ami                    = "ami-0303e2e4a29f041a3"
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnet.hub.id
  vpc_security_group_ids = [aws_security_group.vpn.id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  # Must forward traffic not addressed to itself (same as the NAT instance).
  source_dest_check = false

  user_data = replace(templatefile("${path.module}/vpn_userdata.sh.tftpl", {
    pfsense_pubkey = var.pfsense_wg_pubkey
    onprem_cidr    = var.onprem_cidr
  }), "\r", "")

  tags = { Name = "cs2-vpn01" }
}

# Fixed public IP, so pfSense's endpoint survives Learner Lab stop/start.
resource "aws_eip" "vpn" {
  domain   = "vpc"
  instance = aws_instance.vpn.id
  tags     = { Name = "cs2-vpn-eip" }
}
