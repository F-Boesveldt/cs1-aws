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
  tags = { Name = "${var.project_name}-web-subnet" }
}

resource "aws_subnet" "monitoring" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = "10.0.33.0/24"
  availability_zone = "${var.region}a"
  tags = { Name = "${var.project_name}-monitoring-subnet" }
}

# ---- Security Groups ----
# Unchanged in logic from before — just pointing at the existing VPC's ID
# instead of one this config created.

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

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

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

  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  ingress {
    from_port       = 9104
    to_port         = 9104
    protocol        = "tcp"
    security_groups = [aws_security_group.db.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-monitoring-sg" }
}

# ---- Route table for the two NEW subnets, routing monitoring-bound
# traffic through the hub ----
# This governs web and monitoring, which this config owns. The db and
# db-secondary subnets are PRE-EXISTING and keep their own already-working
# route tables — adding a "route to monitoring via hub" entry into those
# is intentionally left as a follow-up once the hub NVA actually exists
# (var.hub_nva_eni_id is still a placeholder), since editing a route table
# this config doesn't own is a deliberate decision, not something to do
# silently.

resource "aws_route_table" "web" {
  vpc_id = data.aws_vpc.main.id

  # TODO: uncomment once the hub NVA exists and hub_nva_eni_id is real
  # route {
  #   cidr_block           = aws_subnet.monitoring.cidr_block
  #   network_interface_id = var.hub_nva_eni_id
  # }

  tags = { Name = "${var.project_name}-web-rt" }
}

  tags = { Name = "${var.project_name}-web-rt" }
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.web.id
}
