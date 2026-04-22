terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws"; version = "~> 5.0" }
    random = { source = "hashicorp/random"; version = "~> 3.5" }
  }
  backend "s3" {
    bucket         = "hxp-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "hxp-terraform-locks"
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Project = "hxp", Environment = "prod", ManagedBy = "terraform" } }
}

locals {
  project_name = "hxp"
  environment  = "prod"
}

module "vpc" {
  source       = "../../modules/vpc"
  project_name = local.project_name
  environment  = local.environment
  vpc_cidr     = "10.2.0.0/16"   # separate CIDR from dev (10.0) and staging (10.1)
  az_count     = 3               # 3 AZs for high availability in prod
}

module "dynamodb" {
  source       = "../../modules/dynamodb"
  project_name = local.project_name
  environment  = local.environment
}

module "rds" {
  source              = "../../modules/rds"
  project_name        = local.project_name
  environment         = local.environment
  db_subnet_group     = module.vpc.db_subnet_group_name
  vpc_id              = module.vpc.vpc_id
  allowed_sg_ids      = [module.ecs.ecs_security_group_id]
  instance_class      = "db.t3.medium"  # production-grade instance
  allocated_storage   = 100
  multi_az            = true            # multi-AZ for high availability
  deletion_protection = true            # cannot delete prod DB accidentally
}

module "s3" {
  source       = "../../modules/s3"
  project_name = local.project_name
  environment  = local.environment
}

module "ecs" {
  source             = "../../modules/ecs"
  project_name       = local.project_name
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_secret_arn      = module.rds.db_secret_arn
  db_endpoint        = module.rds.db_endpoint
  task_cpu           = 1024   # 1 vCPU per task
  task_memory        = 2048   # 2GB per task
  image_tag          = var.reservation_image_tag
}

module "api_gateway" {
  source          = "../../modules/api-gateway"
  project_name    = local.project_name
  environment     = local.environment
  ecs_service_url = module.ecs.service_url
  lambda_arns     = module.lambda.function_arns
}

module "lambda" {
  source                    = "../../modules/lambda"
  project_name              = local.project_name
  environment               = local.environment
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  guest_profiles_table_name = module.dynamodb.guest_profiles_table_name
  guest_profiles_table_arn  = module.dynamodb.guest_profiles_table_arn
  sessions_table_name       = module.dynamodb.sessions_table_name
}

module "monitoring" {
  source        = "../../modules/monitoring"
  project_name  = local.project_name
  environment   = local.environment
  alarm_email   = var.alarm_email
  ecs_cluster   = module.ecs.cluster_name
  api_id        = module.api_gateway.api_id
  rds_endpoint  = module.rds.db_endpoint
  sqs_queue_url = module.lambda.notification_queue_url
}

module "waf" {
  source       = "../../modules/waf"
  project_name = local.project_name
  environment  = local.environment
  api_arn      = module.api_gateway.api_arn
}

variable "reservation_image_tag" {
  type        = string
  description = "Docker image tag to deploy for reservation-service"
}

variable "alarm_email" {
  type        = string
  description = "Email address to receive CloudWatch alarm notifications"
}

output "api_gateway_url"   { value = module.api_gateway.invoke_url }
output "cloudfront_domain" { value = module.s3.cloudfront_domain }
output "rds_endpoint"      { value = module.rds.db_endpoint; sensitive = true }
output "environment"       { value = local.environment }
