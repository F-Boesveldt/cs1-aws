# Hub-and-spoke network module (AWS version).
# Matches the Design Document: Hub (firewall/NVA + DoH resolver, public),
# Web spoke, DB spoke (web-tier-only access via Security Group), Monitoring
# subnet (routed through the hub via a route table entry rather than a
# direct route).

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ---- Subnets ----
# hub_secondary and db_secondary exist only because ALB and RDS subnet
# groups both require subnets in two Availability Zones, even for a
# single-instance / single-AZ deployment. They are not extra "spokes" in
# the architecture — just an AWS platform requirement.

resource "aws_subnet" "hub" {
  vpc_id                  = aws_vpc.main.id
  cidr_block               = "10.0.0.0/24"
  availability_zone        = "${var.region}a"
  map_public_ip_on_launch  = true
  tags = { Name = "${var.project_name}-hub-subnet" }
}

resource "aws_subnet" "hub_secondary" {
  vpc_id                  = aws_vpc.main.id
  cidr_block               = "10.0.5.0/24"
  availability_zone        = "${var.region}b"
  map_public_ip_on_launch  = true
  tags = { Name = "${var.project_name}-hub-subnet-secondary" }
}

resource "aws_subnet" "web" {
  vpc_id            = aws_vpc.main.id
  cidr_block         = "10.0.1.0/24"
  availability_zone  = "${var.region}a"
  tags = { Name = "${var.project_name}-web-subnet" }
}

resource "aws_subnet" "db" {
  vpc_id            = aws_vpc.main.id
  cidr_block         = "10.0.2.0/24"
  availability_zone  = "${var.region}a"
  tags = { Name = "${var.project_name}-db-subnet" }
}

resource "aws_subnet" "db_secondary" {
  vpc_id            = aws_vpc.main.id
  cidr_block         = "10.0.4.0/24"
  availability_zone  = "${var.region}b"
  tags = { Name = "${var.project_name}-db-subnet-secondary" }
}

resource "aws_subnet" "monitoring" {
  vpc_id            = aws_vpc.main.id
  cidr_block         = "10.0.3.0/24"
  availability_zone  = "${var.region}a"
  tags = { Name = "${var.project_name}-monitoring-subnet" }
}

# ---- Hub subnets get a route to the internet ----

resource "aws_route_table" "hub" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-hub-rt" }
}

resource "aws_route_table_association" "hub" {
  subnet_id      = aws_subnet.hub.id
  route_table_id = aws_route_table.hub.id
}

resource "aws_route_table_association" "hub_secondary" {
  subnet_id      = aws_subnet.hub_secondary.id
  route_table_id = aws_route_table.hub.id
}

# ---- Security Groups ----
# AWS Security Groups are stateful and default-deny inbound — there is no
# explicit "deny all" rule to write, unlike the Azure NSG version.

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web tier - allows HTTP from the internet"
  vpc_id      = aws_vpc.main.id

  # NOTE: port 80/HTTP for now — see the note in the compute module about
  # why the ALB listener is HTTP rather than HTTPS. Change both together
  # to 443 once a domain + ACM certificate are available.
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
  vpc_id      = aws_vpc.main.id

  # REQ-02: referencing the web SG by ID, not a CIDR block, so this stays
  # correct automatically as the Auto Scaling Group adds/removes instances.
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
  vpc_id      = aws_vpc.main.id

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

# ---- Route table forcing web/db -> monitoring traffic through the hub ----
# Same "route through the hub NVA" design decision as the Azure version.
# The NVA's ENI doesn't exist yet, so hub_nva_eni_id stays a placeholder
# until that resource is built.

resource "aws_route_table" "via_hub" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = aws_subnet.monitoring.cidr_block
    network_interface_id = var.hub_nva_eni_id # TODO: set once the hub NVA exists
  }

  tags = { Name = "${var.project_name}-via-hub-rt" }
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.via_hub.id
}

resource "aws_route_table_association" "db" {
  subnet_id      = aws_subnet.db.id
  route_table_id = aws_route_table.via_hub.id
}
