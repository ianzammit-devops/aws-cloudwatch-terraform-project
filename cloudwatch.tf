locals {
  nextjs_log_group_name   = "/aws/ec2/nextjs/${var.environment}"
  vpc_flow_log_group_name = "/aws/vpc/flow-logs/${var.environment}"

  # Exactly one of managed resource vs data source is populated when not LocalStack.
  vpc_flow_logs_log_group_arn = var.localstack ? null : one(concat(
    aws_cloudwatch_log_group.vpc_flow_logs[*].arn,
    data.aws_cloudwatch_log_group.vpc_flow_logs_existing[*].arn,
  ))
}

resource "aws_cloudwatch_log_group" "nextjs_app" {
  name              = local.nextjs_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Managed_By = "Terraform"
  }
}

# IAM policy for the CloudWatch Agent on the EC2 host.
data "aws_iam_policy_document" "ec2_cloudwatch_agent" {
  statement {
    sid = "AllowPublishingMetrics"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowCloudWatchLogsWrite"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowEc2MetadataLookupsForDimensions"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ec2_cloudwatch_agent" {
  name        = "AWS-CloudWatch-EC2-CloudWatch-Agent-${var.environment}"
  description = "Allows EC2 CloudWatch agent to ship logs and metrics"
  policy      = data.aws_iam_policy_document.ec2_cloudwatch_agent.json
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.localstack || var.vpc_flow_logs_use_existing_log_group ? 0 : 1
  name              = local.vpc_flow_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Managed_By = "Terraform"
  }
}

data "aws_cloudwatch_log_group" "vpc_flow_logs_existing" {
  count = var.localstack || !var.vpc_flow_logs_use_existing_log_group ? 0 : 1
  name  = local.vpc_flow_log_group_name
}

data "aws_iam_policy_document" "vpc_flow_logs_assume_role" {
  count = var.localstack ? 0 : 1

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  count              = var.localstack ? 0 : 1
  name               = "AWS-CloudWatch-VPC-Flow-Logs-Role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume_role[0].json
}

data "aws_iam_policy_document" "vpc_flow_logs_permissions" {
  count = var.localstack ? 0 : 1

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count  = var.localstack ? 0 : 1
  name   = "AWS-CloudWatch-VPC-Flow-Logs-Policy-${var.environment}"
  role   = aws_iam_role.vpc_flow_logs[0].id
  policy = data.aws_iam_policy_document.vpc_flow_logs_permissions[0].json
}

resource "aws_flow_log" "vpc" {
  count                = var.localstack ? 0 : 1
  log_destination_type = "cloud-watch-logs"
  log_destination      = local.vpc_flow_logs_log_group_arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs[0].arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id

  tags = {
    Managed_By = "Terraform"
  }
}
