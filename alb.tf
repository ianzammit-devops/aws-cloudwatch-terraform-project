# ALB security group (attach to the load balancer when you add it). Internet-facing listeners live here, not on EC2.
resource "aws_security_group" "alb" {
  name        = "AWS-CloudWatch-ALB-${var.environment}"
  description = "Public ALB; forwards to Node.js on EC2 target port"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward only to VPC app targets"
    from_port   = var.node_app_port
    to_port     = var.node_app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Managed_By = "Terraform"
  }
}

# Application must accept traffic from the public internet via this ALB (not an internal-only LB).
#trivy:ignore:AVD-AWS-0053
resource "aws_lb" "main" {
  name                       = "aws-cloudwatch-alb-${var.environment}"
  load_balancer_type         = "application"
  internal                   = var.alb_internal
  drop_invalid_header_fields = true

  security_groups = [aws_security_group.alb.id]
  subnets         = [aws_subnet.public.id, aws_subnet.public_b.id]

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_lb_target_group" "node" {
  name        = "aws-cloudwatch-tg-${var.environment}"
  port        = var.node_app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    path                = "/health"
    matcher             = "200-399"
  }

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.alb_listener_port
  protocol          = var.alb_listener_protocol
  ssl_policy        = var.alb_listener_protocol == "HTTPS" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = var.alb_listener_protocol == "HTTPS" ? var.alb_certificate_arn : null

  lifecycle {
    precondition {
      condition     = var.alb_listener_protocol != "HTTPS" || trimspace(var.alb_certificate_arn) != ""
      error_message = "alb_certificate_arn must be set when alb_listener_protocol is HTTPS."
    }
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.node.arn
  }
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.node.arn
  target_id        = aws_instance.ec2_instance.id
  port             = var.node_app_port
}