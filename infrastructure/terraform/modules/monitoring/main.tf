variable "project_name"  { type = string }
variable "environment"   { type = string }
variable "alarm_email"   { type = string }
variable "ecs_cluster"   { type = string }
variable "api_id"        { type = string }
variable "rds_endpoint"  { type = string }
variable "sqs_queue_url" { type = string }

locals {
  name = "${var.project_name}-${var.environment}"
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
}

# ── SNS Topic for alarm notifications ─────────────────────────
resource "aws_sns_topic" "alarms" {
  name = "${local.name}-alarms"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ── ECS Alarms ─────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${local.name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU utilization above 80%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  dimensions          = { ClusterName = var.ecs_cluster }
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${local.name}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "ECS memory utilization above 85%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions          = { ClusterName = var.ecs_cluster }
  tags                = local.tags
}

# ── API Gateway Alarms ─────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "${local.name}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Gateway 5XX errors exceeded 10 in 1 minute"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions          = { ApiId = var.api_id }
  treat_missing_data  = "notBreaching"
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "api_latency_high" {
  alarm_name          = "${local.name}-api-latency-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "IntegrationLatency"
  namespace           = "AWS/ApiGateway"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 3000   # 3 seconds p99
  alarm_description   = "API p99 latency exceeded 3s"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions          = { ApiId = var.api_id }
  tags                = local.tags
}

# ── RDS Alarms ─────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${local.name}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.environment == "prod" ? 80 : 30
  alarm_description   = "RDS connection count high"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${local.name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120   # 5 GB in bytes
  alarm_description   = "RDS free storage below 5GB"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  tags                = local.tags
}

# ── SQS DLQ Alarm ──────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "notification_dlq_messages" {
  alarm_name          = "${local.name}-notification-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in notification DLQ — failed emails need investigation"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = local.tags
}

# ── CloudWatch Dashboard ───────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name}-operations"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text"; x = 0; y = 0; width = 24; height = 1
        properties = { markdown = "## HXP ${upper(var.environment)} — Operations Dashboard" }
      },
      {
        type = "metric"; x = 0; y = 1; width = 8; height = 6
        properties = {
          title  = "ECS CPU & Memory"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization",    "ClusterName", var.ecs_cluster, { label = "CPU %" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster, { label = "Memory %" }]
          ]
        }
      },
      {
        type = "metric"; x = 8; y = 1; width = 8; height = 6
        properties = {
          title  = "API Gateway — Requests & Errors"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApiGateway", "Count",    "ApiId", var.api_id, { label = "Requests", stat = "Sum" }],
            ["AWS/ApiGateway", "5XXError", "ApiId", var.api_id, { label = "5XX Errors", stat = "Sum", color = "#d62728" }],
            ["AWS/ApiGateway", "4XXError", "ApiId", var.api_id, { label = "4XX Errors", stat = "Sum", color = "#ff7f0e" }]
          ]
        }
      },
      {
        type = "metric"; x = 16; y = 1; width = 8; height = 6
        properties = {
          title  = "API Latency (p50 / p99)"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApiGateway", "IntegrationLatency", "ApiId", var.api_id, { stat = "p50", label = "p50 ms" }],
            ["AWS/ApiGateway", "IntegrationLatency", "ApiId", var.api_id, { stat = "p99", label = "p99 ms", color = "#d62728" }]
          ]
        }
      },
      {
        type = "metric"; x = 0; y = 7; width = 8; height = 6
        properties = {
          title  = "RDS Connections & Storage"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "DatabaseConnections", { label = "Connections", stat = "Average" }],
            ["AWS/RDS", "FreeStorageSpace",    { label = "Free Storage (bytes)", stat = "Average", yAxis = "right" }]
          ]
        }
      },
      {
        type = "metric"; x = 8; y = 7; width = 8; height = 6
        properties = {
          title  = "SQS Notification Queue"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent",     { label = "Sent",     stat = "Sum" }],
            ["AWS/SQS", "NumberOfMessagesDeleted",  { label = "Processed",stat = "Sum" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", { label = "Oldest msg age (s)", stat = "Maximum", color = "#d62728" }]
          ]
        }
      },
      {
        type = "alarm"; x = 16; y = 7; width = 8; height = 6
        properties = {
          title  = "Active Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.ecs_cpu_high.arn,
            aws_cloudwatch_metric_alarm.ecs_memory_high.arn,
            aws_cloudwatch_metric_alarm.api_5xx_errors.arn,
            aws_cloudwatch_metric_alarm.api_latency_high.arn,
            aws_cloudwatch_metric_alarm.rds_connections_high.arn,
            aws_cloudwatch_metric_alarm.rds_storage_low.arn,
            aws_cloudwatch_metric_alarm.notification_dlq_messages.arn
          ]
        }
      }
    ]
  })
}

output "dashboard_url" {
  value = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
output "alarm_topic_arn" { value = aws_sns_topic.alarms.arn }
