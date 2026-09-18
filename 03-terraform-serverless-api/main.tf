terraform {
  required_version = ">= 1.6, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
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
    tags = { Project = "portfolio-serverless-lab" }
  }
}

locals {
  name = "portfolio-serverless-lab"
}

resource "aws_dynamodb_table" "tasks" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 7
}

resource "aws_iam_role" "function" {
  name = "${local.name}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "function" {
  name = "tasks-and-logs"
  role = aws_iam_role.function.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.tasks.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.function.arn}:*"
      }
    ]
  })
}

data "archive_file" "function" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/function.zip"
}

resource "aws_lambda_function" "tasks" {
  function_name    = local.name
  role             = aws_iam_role.function.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  timeout          = 10
  memory_size      = 128
  environment {
    variables = { TABLE_NAME = aws_dynamodb_table.tasks.name }
  }
  depends_on = [aws_iam_role_policy.function]
}

resource "aws_apigatewayv2_api" "tasks" {
  name          = local.name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "tasks" {
  api_id                 = aws_apigatewayv2_api.tasks.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.tasks.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "tasks" {
  for_each           = toset(["POST /tasks", "GET /tasks/{id}", "DELETE /tasks/{id}"])
  api_id             = aws_apigatewayv2_api.tasks.id
  route_key          = each.value
  authorization_type = "AWS_IAM"
  target             = "integrations/${aws_apigatewayv2_integration.tasks.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.tasks.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 2
  }
}

resource "aws_lambda_permission" "gateway" {
  statement_id  = "AllowThisApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tasks.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.tasks.execution_arn}/*/*"
}

output "api_url" { value = aws_apigatewayv2_api.tasks.api_endpoint }
output "region" { value = var.region }
output "table_name" { value = aws_dynamodb_table.tasks.name }
output "function_name" { value = aws_lambda_function.tasks.function_name }
output "log_group" { value = aws_cloudwatch_log_group.function.name }
output "invoke_resource_arn" { value = "${aws_apigatewayv2_api.tasks.execution_arn}/*/*/tasks*" }
