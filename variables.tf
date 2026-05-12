# general
variable "aws_region" {
  description = "The AWS region to deploy the resources to"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "The environment to deploy the resources to"
  type        = string
  default     = "dev"
}

variable "localstack" {
  description = "Whether to use LocalStack instead of real AWS"
  type        = bool
  default     = false
}

# Networking
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_cidr_b" {
  description = "CIDR block for the second public subnet (ALB requires 2 AZs)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (EC2 targets; no public IP)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_cidr_b" {
  description = "CIDR block for the second private subnet (future HA targets)"
  type        = string
  default     = "10.0.4.0/24"
}

# EC2
variable "ec2_ami" {
  description = "AMI for EC2 on real AWS (must exist in aws_region). Not used when localstack = true."
  type        = string
  default     = "ami-0e294ce625e6437e2"
}

variable "ec2_ami_localstack" {
  description = "AMI for EC2 when localstack = true. Use a LocalStack-managed image ID (see LocalStack EC2 docs); default is bundled Amazon Linux 2."
  type        = string
  default     = "ami-07b643b5e45e"
}


# Node App
variable "node_app_port" {
  description = "TCP port exposed on the EC2 instance for the Node.js app (SSH is not opened; use SSM Session Manager)"
  type        = number
  default     = 3000
}

variable "alb_internal" {
  description = "Whether the ALB is internal-only (false = internet-facing)"
  type        = bool
  default     = false
}

variable "alb_listener_protocol" {
  description = "ALB listener protocol. Demo default HTTP (no ACM). Use HTTPS + alb_certificate_arn for production TLS."
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.alb_listener_protocol)
    error_message = "alb_listener_protocol must be either HTTP or HTTPS."
  }
}

variable "alb_listener_port" {
  description = "ALB listener port (80 with HTTP for demo; 443 typical for HTTPS)"
  type        = number
  default     = 80
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN required when using HTTPS ALB listener"
  type        = string
  default     = ""
}

# Monitoring & alerting
variable "cloudwatch_log_retention_days" {
  description = "Retention period in days for CloudWatch log groups"
  type        = number
  default     = 14
}

variable "vpc_flow_logs_use_existing_log_group" {
  description = "If true, look up the existing log group /aws/vpc/flow-logs/<environment> instead of creating it. Use when the group already exists in the account (manual console, earlier stack, or partial apply)."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for SNS alert subscriptions (leave empty to skip email subscription)"
  type        = string
  default     = ""
}

variable "memory_alarm_threshold_percent" {
  description = "Memory usage percentage threshold for the high-memory CloudWatch alarm"
  type        = number
  default     = 80
}

variable "health_check_schedule_expression" {
  description = "EventBridge schedule expression for periodic health-check notifications"
  type        = string
  default     = "rate(15 minutes)"
}