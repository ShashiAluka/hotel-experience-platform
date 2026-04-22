variable "project_name"             { type = string }
variable "environment"              { type = string }
variable "vpc_id"                   { type = string }
variable "private_subnet_ids"       { type = list(string) }
variable "guest_profiles_table_name"{ type = string }
variable "guest_profiles_table_arn" { type = string }
variable "sessions_table_name"      { type = string }

locals {
  name = "${var.project_name}-${var.environment}"
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Lambda Security Group ──────────────────────────────────────
resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda-sg"
  description = "Lambda functions security group"
  vpc_id      = var.vpc_id
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(local.tags, { Name = "${local.name}-lambda-sg" })
}

# ── IAM Role — Guest Profile Lambda ───────────────────────────
resource "aws_iam_role" "guest_profile_lambda" {
  name = "${local.name}-guest-profile-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow"; Principal = { Service = "lambda.amazonaws.com" }; Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "guest_profile_vpc" {
  role       = aws_iam_role.guest_profile_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "guest_profile_dynamodb" {
  name = "${local.name}-guest-profile-dynamo"
  role = aws_iam_role.guest_profile_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:DeleteItem","dynamodb:Query","dynamodb:Scan"]
      Resource = [var.guest_profiles_table_arn, "${var.guest_profiles_table_arn}/index/*"]
    }]
  })
}

# ── IAM Role — Notification Lambda ────────────────────────────
resource "aws_iam_role" "notification_lambda" {
  name = "${local.name}-notification-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow"; Principal = { Service = "lambda.amazonaws.com" }; Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "notification_vpc" {
  role       = aws_iam_role.notification_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "notification_ses" {
  name = "${local.name}-notification-ses"
  role = aws_iam_role.notification_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow"; Action = ["ses:SendEmail","ses:SendRawEmail","sesv2:SendEmail"]; Resource = ["*"] }]
  })
}

# ── CloudWatch Log Groups ──────────────────────────────────────
resource "aws_cloudwatch_log_group" "guest_profile" {
  name              = "/aws/lambda/${local.name}-guest-profile"
  retention_in_days = var.environment == "prod" ? 14 : 3
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "notification" {
  name              = "/aws/lambda/${local.name}-notification"
  retention_in_days = var.environment == "prod" ? 14 : 3
  tags              = local.tags
}

# ── Lambda Functions ───────────────────────────────────────────
resource "aws_lambda_function" "guest_profile" {
  function_name = "${local.name}-guest-profile"
  role          = aws_iam_role.guest_profile_lambda.arn
  package_type  = "Zip"
  filename      = "${path.module}/placeholder.zip"  # replaced by CI/CD
  handler       = "handler.handler"
  runtime       = "nodejs20.x"
  timeout       = 30
  memory_size   = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      GUEST_PROFILES_TABLE = var.guest_profiles_table_name
      SESSIONS_TABLE       = var.sessions_table_name
      NODE_OPTIONS         = "--enable-source-maps"
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.guest_profile]
  tags = local.tags
}

resource "aws_lambda_function" "notification" {
  function_name = "${local.name}-notification"
  role          = aws_iam_role.notification_lambda.arn
  package_type  = "Zip"
  filename      = "${path.module}/placeholder.zip"
  handler       = "handler.handler"
  runtime       = "nodejs20.x"
  timeout       = 60
  memory_size   = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      FROM_EMAIL_ADDRESS = "noreply@${var.project_name}.com"
      NODE_OPTIONS       = "--enable-source-maps"
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.notification]
  tags = local.tags
}

# ── SQS Queue + DLQ for notifications ─────────────────────────
resource "aws_sqs_queue" "notification_dlq" {
  name                      = "${local.name}-notification-dlq"
  message_retention_seconds = 1209600  # 14 days
  tags                      = local.tags
}

resource "aws_sqs_queue" "notification" {
  name                       = "${local.name}-notification"
  visibility_timeout_seconds = 90
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn
    maxReceiveCount     = 3
  })
  tags = local.tags
}

resource "aws_lambda_event_source_mapping" "notification_sqs" {
  event_source_arn                   = aws_sqs_queue.notification.arn
  function_name                      = aws_lambda_function.notification.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}

# ── EventBridge → SQS Rule ─────────────────────────────────────
resource "aws_cloudwatch_event_bus" "main" {
  name = "${local.name}-event-bus"
  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "reservation_events" {
  name           = "${local.name}-reservation-to-notification"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  event_pattern = jsonencode({
    source      = ["hxp.reservation-service"]
    detail-type = ["reservation.confirmed", "reservation.cancelled", "reservation.checkedIn"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "notification_sqs" {
  rule           = aws_cloudwatch_event_rule.reservation_events.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "NotificationSQS"
  arn            = aws_sqs_queue.notification.arn
}

output "function_arns" {
  value = {
    guest_profile = aws_lambda_function.guest_profile.arn
    notification  = aws_lambda_function.notification.arn
  }
}
output "notification_queue_url" { value = aws_sqs_queue.notification.url }
output "event_bus_name"         { value = aws_cloudwatch_event_bus.main.name }
