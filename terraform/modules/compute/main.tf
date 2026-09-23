# Web tier: Auto Scaling Group behind an Application Load Balancer, plus
# the RDS database. Skeleton stage — cloud-init and Instance Refresh are
# TODOs for Week 2/3 per the Design Document.

data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile" # check your Academy lab's exact name if this fails
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.project_name}-admin-key"
  public_key = var.admin_ssh_public_key
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.admin.key_name

  iam_instance_profile {
    arn = data.aws_iam_instance_profile.lab.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.web_sg_id]
    subnet_id                   = var.web_subnet_id
  }

  # TODO Week 2: replace with real cloud-init that installs Docker and
  # runs the Nginx container.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "placeholder - Docker/Nginx setup goes here"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.project_name}-web" }
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
    version = "$Latest"
  }

  # TODO Week 2/3: instance_refresh block for the rolling deployment
  # strategy described in the Design Document.

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
  identifier              = "${var.project_name}-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.medium"
  allocated_storage       = 20
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [var.db_sg_id]
  username                = "admin"
  password                = var.db_admin_password
  publicly_accessible     = false
  skip_final_snapshot     = true # fine for a student project; wouldn't be for production
}
