variable "project_name" { type = string }
variable "environment"  { type = string }

locals {
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_dynamodb_table" "guest_profiles" {
  name         = "${var.project_name}-${var.environment}-guest-profiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "guestId"

  attribute { name = "guestId";    type = "S" }
  attribute { name = "email";      type = "S" }
  attribute { name = "loyaltyTier";type = "S" }

  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "LoyaltyTierIndex"
    hash_key        = "loyaltyTier"
    range_key       = "guestId"
    projection_type = "INCLUDE"
    non_key_attributes = ["firstName", "lastName", "totalNights"]
  }

  ttl { attribute_name = "expiresAt"; enabled = true }

  point_in_time_recovery { enabled = true }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.tags, { Name = "${var.project_name}-${var.environment}-guest-profiles" })
}

resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project_name}-${var.environment}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sessionId"

  attribute { name = "sessionId"; type = "S" }
  ttl { attribute_name = "expiresAt"; enabled = true }
  server_side_encryption { enabled = true }
  tags = merge(local.tags, { Name = "${var.project_name}-${var.environment}-sessions" })
}

output "guest_profiles_table_name" { value = aws_dynamodb_table.guest_profiles.name }
output "guest_profiles_table_arn"  { value = aws_dynamodb_table.guest_profiles.arn }
output "sessions_table_name"       { value = aws_dynamodb_table.sessions.name }
