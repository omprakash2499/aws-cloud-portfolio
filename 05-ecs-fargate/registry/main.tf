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

resource "aws_ecr_repository" "app" {
  name                 = "portfolio-ecs-lab"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
}
output "repository_url" { value = aws_ecr_repository.app.repository_url }
output "repository_name" { value = aws_ecr_repository.app.name }
