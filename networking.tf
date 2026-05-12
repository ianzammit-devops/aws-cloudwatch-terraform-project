# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    name       = "AWS-CloudWatch-VPC-${var.environment}"
    Managed_By = "Terraform"
  }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    name       = "AWS-CloudWatch-Public-Subnet-${var.environment}"
    Managed_By = "Terraform"
  }
}

# Public subnet (2nd AZ) - required for ALB
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_b
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    name       = "AWS-CloudWatch-Public-Subnet-b-${var.environment}"
    Managed_By = "Terraform"
  }
}

# Internet gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    name       = "AWS-CloudWatch-Internet-Gateway-${var.environment}"
    Managed_By = "Terraform"
  }
}

# Route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    name       = "AWS-CloudWatch-Public-Route-Table-${var.environment}"
    Managed_By = "Terraform"
  }
}

# Associate route table with public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private subnet (no public IP; outbound via NAT on real AWS)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    name       = "AWS-CloudWatch-Private-Subnet-${var.environment}"
    Managed_By = "Terraform"
  }
}

# Private subnet (2nd AZ) - future HA targets
resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr_b
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    name       = "AWS-CloudWatch-Private-Subnet-b-${var.environment}"
    Managed_By = "Terraform"
  }
}

resource "aws_eip" "nat" {
  count      = var.localstack ? 0 : 1
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    name       = "AWS-CloudWatch-NAT-EIP-${var.environment}"
    Managed_By = "Terraform"
  }
}

resource "aws_nat_gateway" "main" {
  count         = var.localstack ? 0 : 1
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id

  tags = {
    name       = "AWS-CloudWatch-NAT-${var.environment}"
    Managed_By = "Terraform"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.localstack ? [] : [1]
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = {
    name       = "AWS-CloudWatch-Private-Route-Table-${var.environment}"
    Managed_By = "Terraform"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# NACLs: stateless network controls layered on top of security groups.
resource "aws_network_acl" "public" {
  count      = var.localstack ? 0 : 1
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id, aws_subnet.public_b.id]

  # Allow internet traffic to ALB listeners.
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Return path for stateful targets and downstream dependencies.
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow ALB -> EC2 app traffic inside the VPC (covers LocalStack mode too).
  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.node_app_port
    to_port    = var.node_app_port
  }

  ingress {
  protocol   = "tcp"
  rule_no    = 140
  action     = "allow"
  cidr_block = var.private_subnet_cidr
  from_port  = 1024
  to_port    = 65535
}

ingress {
  protocol   = "tcp"
  rule_no    = 150
  action     = "allow"
  cidr_block = var.private_subnet_cidr_b
  from_port  = 1024
  to_port    = 65535
}

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.node_app_port
    to_port    = var.node_app_port
  }

  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    name       = "AWS-CloudWatch-Public-NACL-${var.environment}"
    Managed_By = "Terraform"
  }
}

resource "aws_network_acl" "private" {
  count      = var.localstack ? 0 : 1
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private.id, aws_subnet.private_b.id]

  # Only ALB subnets can reach the app port.
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.public_subnet_cidr
    from_port  = var.node_app_port
    to_port    = var.node_app_port
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.public_subnet_cidr_b
    from_port  = var.node_app_port
    to_port    = var.node_app_port
  }

  # HTTPS to interface VPC endpoints / internal services (dst port 443). Stateless NACLs require this
  # explicitly; rule 120 below only covers ephemeral destination ports (NAT return path).
  ingress {
    protocol   = "tcp"
    rule_no    = 115
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 443
    to_port    = 443
  }

  # Return traffic for outbound connections through NAT/services.
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.public_subnet_cidr
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.public_subnet_cidr_b
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound HTTPS to VPC-internal destinations (e.g. SSM interface endpoints in 10.0.0.0/16).
  egress {
    protocol   = "tcp"
    rule_no    = 115
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Add this to the private NACL egress
  egress {
    protocol   = "tcp"
    rule_no    = 90
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    name       = "AWS-CloudWatch-Private-NACL-${var.environment}"
    Managed_By = "Terraform"
  }
}