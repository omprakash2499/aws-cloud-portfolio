terraform {
  required_version = ">= 1.6, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
variable "region" {
  type    = string
  default = "us-east-1"
}
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "portfolio-ecs-lab" }
  }
}

variable "image_uri" {
  type = string
}
variable "allowed_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.allowed_cidr)) && endswith(var.allowed_cidr, "/32")
    error_message = "Use a single IPv4 address with a /32 suffix."
  }
}
data "aws_availability_zones" "available" { state = "available" }
resource "aws_vpc" "lab" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "portfolio-ecs-lab" }
}
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.50.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "portfolio-ecs-public" }
}
resource "aws_internet_gateway" "lab" { vpc_id = aws_vpc.lab.id }
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "app" {
  name_prefix = "portfolio-ecs-"
  vpc_id      = aws_vpc.lab.id
  ingress {
    description = "Demo access from operator IPv4 only"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/portfolio-ecs-lab"
  retention_in_days = 7
}
resource "aws_iam_role" "execution" {
  name = "portfolio-ecs-lab-execution"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_ecs_cluster" "lab" { name = "portfolio-ecs-lab" }
resource "aws_ecs_task_definition" "app" {
  family                   = "portfolio-ecs-lab"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name                   = "web"
    image                  = var.image_uri
    essential              = true
    readonlyRootFilesystem = true
    portMappings           = [{ containerPort = 8080, protocol = "tcp" }]
    healthCheck = {
      command     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3)"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 20
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}
resource "aws_ecs_service" "app" {
  name                  = "portfolio-ecs-lab"
  cluster               = aws_ecs_cluster.lab.id
  task_definition       = aws_ecs_task_definition.app.arn
  desired_count         = 1
  launch_type           = "FARGATE"
  wait_for_steady_state = true
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }
  depends_on = [aws_iam_role_policy_attachment.execution, aws_route_table_association.public]
  timeouts { create = "15m" }
}
output "cluster" { value = aws_ecs_cluster.lab.name }
output "service" { value = aws_ecs_service.app.name }
output "log_group" { value = aws_cloudwatch_log_group.app.name }
output "security_group" { value = aws_security_group.app.id }
