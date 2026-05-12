resource "aws_kms_key" "sns" {
  count                   = var.localstack ? 0 : 1
  description             = "KMS key for SNS topic encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountRoot"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEventBridgeEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_kms_alias" "sns" {
  count         = var.localstack ? 0 : 1
  name          = "alias/aws-cloudwatch-sns-${var.environment}"
  target_key_id = aws_kms_key.sns[0].key_id
}

data "aws_caller_identity" "current" {}

# Uses AWS-managed SNS KMS key (no CMK monthly fee). Trivy prefers CMKs by policy (AVD-AWS-0136).
resource "aws_sns_topic" "alerts" {
  name              = "AWS-CloudWatch-Alerts-${var.environment}"
  kms_master_key_id = var.localstack ? null : aws_kms_key.sns[0].arn

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.localstack || trimspace(var.alert_email) == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "AWS-CloudWatch-HighCPU-${var.environment}"
  alarm_description   = "CPU usage above 70% for two consecutive 5-minute periods"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.ec2_instance.id
  }

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  alarm_name          = "AWS-CloudWatch-StatusCheckFailed-${var.environment}"
  alarm_description   = "EC2 status check failure detected"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 120
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.ec2_instance.id
  }

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "AWS-CloudWatch-HighMemory-${var.environment}"
  alarm_description   = "Memory usage above threshold from CloudWatch agent metrics"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.memory_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.ec2_instance.id
  }

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_cloudwatch_log_metric_filter" "nextjs_5xx" {
  name           = "AWS-CloudWatch-NextJs5xxFilter-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.nextjs_app.name
  pattern        = "{ $.status >= 500 }"

  metric_transformation {
    name      = "NextJs5xxCount"
    namespace = "AWS-CloudWatch/NextJs"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "nextjs_5xx" {
  alarm_name          = "AWS-CloudWatch-NextJs5xx-${var.environment}"
  alarm_description   = "5xx responses detected in Next.js application logs"
  namespace           = "AWS-CloudWatch/NextJs"
  metric_name         = "NextJs5xxCount"
  statistic           = "Sum"
  period              = 120
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_cloudwatch_event_rule" "alarm_ok_to_alarm" {
  name        = "AWS-CloudWatch-AlarmStateChange-${var.environment}"
  description = "Notify when CloudWatch alarms transition from OK to ALARM"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      previousState = {
        value = ["OK"]
      }
      state = {
        value = ["ALARM"]
      }
    }
  })

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_cloudwatch_event_rule" "ec2_state_change" {
  name        = "AWS-CloudWatch-EC2StateChange-${var.environment}"
  description = "Notify on EC2 instance state changes"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state       = ["pending", "running", "stopping", "stopped", "terminated"]
      instance-id = [aws_instance.ec2_instance.id]
    }
  })

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_cloudwatch_event_rule" "scheduled_health_check" {
  name                = "AWS-CloudWatch-ScheduledHealthCheck-${var.environment}"
  description         = "Scheduled health-check reminder notifications"
  schedule_expression = var.health_check_schedule_expression

  tags = {
    Managed_By = "Terraform"
  }
}

resource "aws_cloudwatch_event_target" "alarm_ok_to_alarm_sns" {
  rule      = aws_cloudwatch_event_rule.alarm_ok_to_alarm.name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn
}

resource "aws_cloudwatch_event_target" "ec2_state_change_sns" {
  rule      = aws_cloudwatch_event_rule.ec2_state_change.name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn
}

resource "aws_cloudwatch_event_target" "scheduled_health_check_sns" {
  rule      = aws_cloudwatch_event_rule.scheduled_health_check.name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn
  input     = "{\"source\":\"terraform-health-check\",\"message\":\"Scheduled health check event triggered.\"}"
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"
    actions = [
      "SNS:Publish",
    ]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values = [
        aws_cloudwatch_event_rule.alarm_ok_to_alarm.arn,
        aws_cloudwatch_event_rule.ec2_state_change.arn,
        aws_cloudwatch_event_rule.scheduled_health_check.arn,
      ]
    }
  }

  statement {
    sid    = "AllowCloudWatchAlarmsPublish"
    effect = "Allow"
    actions = [
      "SNS:Publish",
    ]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}