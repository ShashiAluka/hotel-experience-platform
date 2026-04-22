variable "project_name" { type = string }
variable "environment"  { type = string }
variable "api_arn"      { type = string }

locals {
  name = "${var.project_name}-${var.environment}"
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_wafv2_web_acl" "api" {
  name        = "${local.name}-api-waf"
  description = "WAF rules for HXP API Gateway (${var.environment})"
  scope       = "REGIONAL"

  default_action { allow {} }

  # Rule 1: AWS Managed — Common Rule Set (SQLi, XSS, etc.)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed — Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Rate limiting — 1000 requests per 5 minutes per IP
  rule {
    name     = "RateLimitPerIP"
    priority = 3
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Block requests with oversized bodies (>8KB) on write endpoints
  rule {
    name     = "BlockOversizedBodies"
    priority = 4
    action { block {} }
    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = 8192
        field_to_match { body { oversize_handling = "MATCH" } }
        text_transformation { priority = 0; type = "NONE" }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-oversized-body"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = var.api_arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name}"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "api" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.api.arn
}

output "waf_arn"        { value = aws_wafv2_web_acl.api.arn }
output "waf_metric_name"{ value = "${local.name}-waf" }
