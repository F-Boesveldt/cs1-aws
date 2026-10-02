# Web tier: Auto Scaling Group behind an Application Load Balancer, plus
# the RDS database. Skeleton stage — cloud-init and Instance Refresh are
# TODOs for Week 2/3 per the Design Document.

data "aws_iam_instance_profile" "lab" {
  name = "cs1-ec2-role"
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = "ami-0303e2e4a29f041a3"
  instance_type = "t3.medium"
  key_name      = var.key_name

  iam_instance_profile {
    arn = data.aws_iam_instance_profile.lab.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.web_sg_id]
    subnet_id                   = var.web_subnet_id
  }

  # Real cloud-init: installs Docker and runs Nginx in a container.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    until apt-get update -y; do sleep 10; done
    until apt-get install -y docker.io; do sleep 10; done
    systemctl enable --now docker
    docker run -d --name web --restart unless-stopped -p 80:80 nginx:stable
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-web" }
  }
}

# ---- ALB ----
# NOTE: listener is plain HTTP on port 80 for now. An HTTPS listener needs
# a real ACM certificate tied to a domain you control — AWS Academy labs
# typically have neither. Once you have a domain and a certificate, switch
# this listener AND the web Security Group's ingress rule (network module)
# to port 443 / HTTPS with certificate_arn set to the ACM cert's ARN.

resource "aws_lb" "web" {
  name               = "${var.project_name}-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.web_sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---- Auto Scaling Group ----

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-web-asg"
  min_size            = 2
  max_size            = 6
  desired_capacity    = 2
  vpc_zone_identifier = [var.web_subnet_id]
  target_group_arns   = [aws_lb_target_group.web.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }
}

# ---- Scaling policies + CloudWatch alarms ----
# Thresholds match the Design Document: scale-out at CPU>70% for 5 min,
# scale-in at CPU<30% for 10 min (2 periods x 300s).

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.web.name
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.web.name }
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.web.name
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 30
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.web.name }
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
}

# ---- RDS for MySQL ----
# db_secondary (network module) exists only to satisfy RDS's two-AZ subnet
# group requirement — see the comment there.

resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids
}

resource "aws_db_instance" "main" {
  identifier             = "${var.project_name}-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [var.db_sg_id]
  username               = "admin"
  password               = var.db_admin_password
  publicly_accessible    = false
  skip_final_snapshot    = true # fine for a student project; wouldn't be for production
}
