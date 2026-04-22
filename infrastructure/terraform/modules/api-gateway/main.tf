variable "project_name"    { type = string }
variable "environment"     { type = string }
variable "ecs_service_url" { type = string }
variable "lambda_arns"     { type = map(string) }

locals {
  name = "${var.project_name}-${var.environment}"
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.name}-api"
  description = "HXP REST API Gateway"
  endpoint_configuration { types = ["REGIONAL"] }
  tags = local.tags
}

# ── /reservations → ECS (HTTP proxy via VPC Link) ─────────────
resource "aws_api_gateway_resource" "reservations" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "reservations"
}

resource "aws_api_gateway_resource" "reservations_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.reservations.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "reservations_any" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.reservations_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
  request_parameters = { "method.request.path.proxy" = true }
}

resource "aws_api_gateway_integration" "reservations" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.reservations_proxy.id
  http_method             = aws_api_gateway_method.reservations_any.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "${var.ecs_service_url}/api/v1/reservations/{proxy}"
  request_parameters      = { "integration.request.path.proxy" = "method.request.path.proxy" }
}

# ── /guests → Lambda ──────────────────────────────────────────
resource "aws_api_gateway_resource" "guests" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "guests"
}

resource "aws_api_gateway_resource" "guests_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.guests.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "guests_any" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.guests_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "guests" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.guests_proxy.id
  http_method             = aws_api_gateway_method.guests_any.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${var.lambda_arns["guest_profile"]}/invocations"
}

data "aws_region" "current" {}

resource "aws_lambda_permission" "api_gateway_guest_profile" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_arns["guest_profile"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ── Deployment & Stage ─────────────────────────────────────────
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  depends_on  = [aws_api_gateway_integration.reservations, aws_api_gateway_integration.guests]

  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "main" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = var.environment

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      duration       = "$context.responseLatency"
    })
  }

  xray_tracing_enabled = true
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = var.environment == "prod" ? 14 : 3
  tags              = local.tags
}

output "invoke_url" { value = aws_api_gateway_stage.main.invoke_url }
output "api_id"     { value = aws_api_gateway_rest_api.main.id }
