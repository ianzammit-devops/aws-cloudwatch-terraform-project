# VPC & Subnet outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "public_subnet_id" {
  value       = aws_subnet.public.id
  description = "The ID of the public subnet"
}

output "public_subnet_b_id" {
  value       = aws_subnet.public_b.id
  description = "The ID of the second public subnet (ALB)"
}

output "private_subnet_id" {
  value       = aws_subnet.private.id
  description = "The ID of the private subnet (EC2 when not using LocalStack)"
}

output "private_subnet_b_id" {
  value       = aws_subnet.private_b.id
  description = "The ID of the second private subnet"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "Attach this security group to the internet-facing load balancer"
}

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "Public DNS name of the application load balancer"
}

output "internet_gateway_id" {
  value       = aws_internet_gateway.main.id
  description = "The ID of the internet gateway"
}

# EC2 Instance ID
output "ec2_instance_id" {
  value       = aws_instance.ec2_instance.id
  description = "The ID of the EC2 instance"
}

# EC2 Instance Public IP
output "ec2_instance_public_ip" {
  value       = aws_instance.ec2_instance.public_ip
  description = "The public IP of the EC2 instance"
}

# AWS Session Manager (interactive shell on the instance)
output "aws_session_manager_command" {
  value       = "aws ssm start-session --target ${aws_instance.ec2_instance.id} --region ${var.aws_region}"
  description = "CLI command to open an SSM session to the EC2 instance"
}