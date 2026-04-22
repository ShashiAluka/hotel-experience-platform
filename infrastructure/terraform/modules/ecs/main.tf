variable "project_name"       { type = string }
variable "environment"        { type = string }
variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "db_secret_arn"      { type = string }
variable "db_endpoint"        { type = string }
variable "task_cpu"           { type = number; default = 256 }
variable "task_memory"        { type = number; default = 512 }
variable "image_tag"          { type = string; default = "latest" }

locals {
  name = "${var.project_name}-${var.environment}"
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── ECR ────────────────────────────────────────────────────────
resource "aws_ecr_repository" "reservation" {
  name                 = "${local.name}-reservation-service"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "reservation" {
  repository = aws_ecr_repository.reservation.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = { tagStatus = "any"; countType = "imageCountMoreThan"; countNumber = 10 }
      action = { type = "expire" }
    }]
  })
}

# ── ECS Cluster ────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"
  setting { name = "containerInsights"; value = "enabled" }
  tags = local.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = var.environment == "prod" ? "FARGATE" : "FARGATE_SPOT"
    weight            = 1
  }
}

# ── IAM ────────────────────────────────────────────────────────
resource "aws_iam_role" "task_execution" {
  name = "${local.name}-ecs-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow"; Principal = { Service = "ecs-tasks.amazonaws.com" }; Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${local.name}-ecs-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow"; Principal = { Service = "ecs-tasks.amazonaws.com" }; Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "task_permissions" {
  name = "${local.name}-task-policy"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"; Action = ["secretsmanager:GetSecretValue"]; Resource = [var.db_secret_arn] },
      { Effect = "Allow"; Action = ["events:PutEvents"]; Resource = ["arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/${var.project_name}-${var.environment}-event-bus"] },
      { Effect = "Allow"; Action = ["cloudwatch:PutMetricData"]; Resource = ["*"] },
      { Effect = "Allow"; Action = ["xray:PutTraceSegments","xray:PutTelemetryRecords"]; Resource = ["*"] }
    ]
  })
}

# ── Security Group ─────────────────────────────────────────────
resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs-sg"
  description = "ECS tasks security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8080; to_port = 8080; protocol = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "HTTP from VPC"
  }
  egress {
    from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "${local.name}-ecs-sg" })
}

# ── CloudWatch Log Group ───────────────────────────────────────
resource "aws_cloudwatch_log_group" "reservation" {
  name              = "/ecs/${local.name}/reservation-service"
  retention_in_days = var.environment == "prod" ? 30 : 7
  tags              = local.tags
}

# ── Task Definition ────────────────────────────────────────────
resource "aws_ecs_task_definition" "reservation" {
  family                   = "${local.name}-reservation-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "reservation-service"
    image     = "${aws_ecr_repository.reservation.repository_url}:${var.image_tag}"
    essential = true
    portMappings = [{ containerPort = 8080; protocol = "tcp" }]
    environment = [
      { name = "SPRING_PROFILES_ACTIVE";       value = var.environment },
      { name = "HXP_EVENTBRIDGE_BUS_NAME";     value = "${var.project_name}-${var.environment}-event-bus" },
      { name = "SPRING_DATASOURCE_URL";        value = "jdbc:postgresql://${var.db_endpoint}:5432/hxp" }
    ]
    secrets = [
      { name = "SPRING_DATASOURCE_USERNAME"; valueFrom = "${var.db_secret_arn}:username::" },
      { name = "SPRING_DATASOURCE_PASSWORD"; valueFrom = "${var.db_secret_arn}:password::" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.reservation.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:8080/actuator/health || exit 1"]
      interval    = 10; timeout = 5; retries = 3; startPeriod = 30
    }
  }])
  tags = local.tags
}

# ── ECS Service ────────────────────────────────────────────────
resource "aws_ecs_service" "reservation" {
  name                               = "${local.name}-reservation-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.reservation.arn
  desired_count                      = var.environment == "prod" ? 2 : 1
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 60
  force_new_deployment               = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  deployment_circuit_breaker { enable = true; rollback = true }
  deployment_controller { type = "ECS" }
  tags = local.tags
}

output "ecs_security_group_id" { value = aws_security_group.ecs.id }
output "ecr_repository_url"    { value = aws_ecr_repository.reservation.repository_url }
output "service_url"           { value = "http://${local.name}-reservation-service.${var.environment}.local:8080" }
output "cluster_name"          { value = aws_ecs_cluster.main.name }
