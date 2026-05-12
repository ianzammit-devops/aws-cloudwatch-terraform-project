provider "aws" {
  region = var.aws_region

  dynamic "endpoints" {
    for_each = var.localstack ? [1] : []
    content {
      ec2        = "http://localhost:4566"
      cloudwatch = "http://localhost:4566"
      iam        = "http://localhost:4566"
      sns        = "http://localhost:4566"
      logs       = "http://localhost:4566"
      events     = "http://localhost:4566"
      s3         = "http://localhost:4566"
      elbv2      = "http://localhost:4566"
      sts        = "http://localhost:4566"
    }
  }

  skip_credentials_validation = var.localstack
  skip_metadata_api_check     = var.localstack
  skip_requesting_account_id  = var.localstack

  # MiniStack/LocalStack emulators may not implement IAM tagging APIs
  # (e.g. TagInstanceProfile). Only apply default tags on real AWS.
  dynamic "default_tags" {
    for_each = var.localstack ? [] : [1]
    content {
      tags = {
        Environment = var.environment
        Project     = "AWS-CloudWatch-Terraform-${var.environment}"
        Managed_By  = "Terraform"
      }
    }
  }
}