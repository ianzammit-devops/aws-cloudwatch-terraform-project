# Interface endpoints so instances in private subnets can use Session Manager without relying on
# general internet egress for SSM APIs (still need NAT or endpoints for other AWS APIs as modeled elsewhere).

resource "aws_security_group" "vpc_interface_endpoints" {
  count       = var.localstack ? 0 : 1
  name        = "AWS-CloudWatch-VPC-Interface-Endpoints-${var.environment}"
  description = "HTTPS from EC2 to interface VPC endpoints (SSM)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from application instances"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
  }

  egress {
    description = "Allow outbound for endpoint traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  count               = var.localstack ? 0 : 1
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_interface_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count               = var.localstack ? 0 : 1
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_interface_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  count               = var.localstack ? 0 : 1
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_interface_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Managed_By = "Terraform"
  }
}
