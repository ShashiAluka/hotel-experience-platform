variable "project_name"       { type = string }
variable "environment"        { type = string }
variable "db_subnet_group"    { type = string }
variable "vpc_id"             { type = string }
variable "allowed_sg_ids"     { type = list(string) }
variable "instance_class"     { type = string; default = "db.t3.micro" }
variable "allocated_storage"  { type = number; default = 20 }
variable "multi_az"           { type = bool;   default = false }
variable "deletion_protection"{ type = bool;   default = false }

locals {
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
  identifier = "${var.project_name}-${var.environment}-postgres"
}

resource "aws_security_group" "rds" {
  name        = "${local.identifier}-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_sg_ids
    description     = "PostgreSQL from allowed services"
  }

  egress {
    from_port   = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "${local.identifier}-sg" })
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${local.identifier}-params"
  family = "postgres15"
  parameter { name = "log_connections"; value = "1" }
  parameter { name = "log_disconnections"; value = "1" }
  parameter { name = "log_min_duration_statement"; value = "1000" }
  tags = local.tags
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/rds/credentials"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "hxp_admin"
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = "hxp"
  })
}

resource "aws_db_instance" "postgres" {
  identifier             = local.identifier
  engine                 = "postgres"
  engine_version         = "15.4"
  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = "hxp"
  username               = "hxp_admin"
  password               = random_password.db_password.result
  db_subnet_group_name   = var.db_subnet_group
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  multi_az               = var.multi_az
  deletion_protection    = var.deletion_protection
  skip_final_snapshot    = !var.deletion_protection
  backup_retention_period = var.environment == "prod" ? 7 : 1
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  performance_insights_enabled = true
  monitoring_interval    = 60
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  tags = merge(local.tags, { Name = local.identifier })
}

output "db_endpoint"         { value = aws_db_instance.postgres.address }
output "db_port"             { value = aws_db_instance.postgres.port }
output "db_secret_arn"       { value = aws_secretsmanager_secret.db_credentials.arn }
output "db_security_group_id"{ value = aws_security_group.rds.id }
