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
    tags = { Project = "portfolio-monitoring-lab" }
  }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
locals {
  name      = "portfolio-monitoring-lab"
  alarm     = "portfolio-monitoring-lab-high-value"
  alarm_arn = "arn:${data.aws_partition.current.partition}:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:portfolio-monitoring-lab-high-value"
}
resource "aws_sns_topic" "alerts" {
  name = local.name
}
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowThisCloudWatchAlarm"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = local.alarm_arn }
      }
    }]
  })
}
resource "aws_cloudwatch_metric_alarm" "demo" {
  alarm_name          = local.alarm
  alarm_description   = "Demo: a manually published signal exceeds 1; not a production service monitor."
  namespace           = "Portfolio/MonitoringLab"
  metric_name         = "DemoSignal"
  dimensions          = { Lab = local.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  depends_on          = [aws_sns_topic_policy.alerts]
}
output "topic_arn" { value = aws_sns_topic.alerts.arn }
output "alarm_name" { value = aws_cloudwatch_metric_alarm.demo.alarm_name }
