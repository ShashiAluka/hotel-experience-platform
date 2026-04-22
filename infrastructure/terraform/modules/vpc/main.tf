variable "project_name" { type = string }
variable "environment"  { type = string }
variable "vpc_cidr"     { type = string default = "10.0.0.0/16" }
variable "az_count"     { type = number default = 2 }

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  public_cidrs    = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_cidrs   = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  database_cidrs  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 20)]
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform" }
}

data "aws_availability_zones" "available" { state = "available" }

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = "${var.project_name}-${var.environment}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${var.project_name}-${var.environment}-igw" })
}

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.tags, { Name = "${var.project_name}-${var.environment}-public-${count.index + 1}", Tier = "public" })
}

resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = merge(local.tags, { Name = "${var.project_name}-${var.environment}-private-${count.index + 1}", Tier = "private" })
}

resource "aws_subnet" "database" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.database_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = merge(local.tags, { Name = "${var.project_name}-${var.environment}-database-${count.index + 1}", Tier = "database" })
}

resource "aws_eip" "nat" {
  count  = var.az_count
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}" })
}

resource "aws_nat_gateway" "main" {
  count         = var.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.tags, { Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}" })
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0"; gateway_id = aws_internet_gateway.main.id }
  tags = merge(local.tags, { Name = "${var.project_name}-${var.environment}-public-rt" })
}

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0"; nat_gateway_id = aws_nat_gateway.main[count.index].id }
  tags = merge(local.tags, { Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}" })
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id
  tags       = merge(local.tags, { Name = "${var.project_name}-${var.environment}-db-subnet-group" })
}

output "vpc_id"              { value = aws_vpc.main.id }
output "public_subnet_ids"  { value = aws_subnet.public[*].id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "database_subnet_ids"{ value = aws_subnet.database[*].id }
output "db_subnet_group_name"{ value = aws_db_subnet_group.main.name }
