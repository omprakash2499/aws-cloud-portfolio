#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export AWS_PAGER=""
unset MSYS_NO_PATHCONV
REGION="${AWS_REGION:-us-east-1}"
[[ ! -f .lab-region ]] || REGION="$(cat .lab-region)"
export TF_VAR_region="$REGION"
ALARM="portfolio-monitoring-lab-high-value"
aws_lab() { MSYS_NO_PATHCONV=1 aws --region "$REGION" "$@"; }
confirm() {
  local answer
  read -r -p "$1 Type $2: " answer
  [[ "$answer" == "$2" ]] || { echo "Cancelled."; exit 1; }
}
identity() {
  local account
  account="$(aws_lab sts get-caller-identity --query Account --output text)"
  if [[ -f .lab-account && "$(cat .lab-account)" != "$account" ]]; then
    echo "AWS account changed. Use the profile used to deploy this lab."; exit 1
  fi
  printf '%s' "$account" > .lab-account
  printf '%s' "$REGION" > .lab-region
  echo "Region: $REGION  Lab: portfolio-monitoring-lab"
}
require_deployment() {
  [[ -f .lab-account && -f terraform.tfstate ]] || { echo "Use the original deployment folder and deploy first."; exit 1; }
  identity
}
subscribe() {
  local email topic existing
  topic="$(terraform output -raw topic_arn)"
  existing="$(aws_lab sns list-subscriptions-by-topic --topic-arn "$topic" --query 'length(Subscriptions)' --output text)"
  if [[ "$existing" != "0" ]]; then
    echo "A subscription already exists. Confirm the AWS email, then run: bash lab.sh subscription"
    return
  fi
  read -r -p "Enter your notification email (kept locally): " email
  [[ "$email" == *@*.* && "$email" != *' '* ]] || { echo "Enter a valid email address."; exit 1; }
  printf '%s' "$email" > .lab-email
  aws_lab sns subscribe --topic-arn "$topic" --protocol email --notification-endpoint "$email" >/dev/null
  echo "Open the AWS Notifications email and click Confirm subscription. Check spam if needed."
  echo "Then run: bash lab.sh subscription"
}
subscription() {
  local topic count
  topic="$(terraform output -raw topic_arn)"
  count="$(aws_lab sns list-subscriptions-by-topic --topic-arn "$topic" --query "length(Subscriptions[?starts_with(SubscriptionArn, 'arn:')])" --output text)"
  if [[ "$count" == "0" ]]; then
    echo "Subscription is not confirmed yet. Open the AWS confirmation email first."
    return 1
  fi
  echo "PASS: SNS subscription is confirmed."
}
state() {
  aws_lab cloudwatch describe-alarms --alarm-names "$ALARM" --query 'MetricAlarms[0].StateValue' --output text
}
exercise() {
  local value="$1" target="$2" current
  subscription
  current="$(state)"
  if [[ "$current" == "$target" ]]; then
    echo "Alarm is already $target. No new state-transition email is expected."
    echo "Use the opposite command first (trigger or recover) to test another transition."
    return
  fi
  echo "Publishing DemoSignal=$value every 30 seconds; waiting for $target (up to 10 minutes)."
  for ((attempt=1; attempt<=20; attempt++)); do
    aws_lab cloudwatch put-metric-data --namespace Portfolio/MonitoringLab --metric-name DemoSignal --dimensions Lab=portfolio-monitoring-lab --unit Count --value "$value"
    sleep 30
    current="$(state)"
    echo "Check $attempt/20: $current"
    if [[ "$current" == "$target" ]]; then
      echo "PASS: CloudWatch evaluated the metric and changed to $target."
      echo "Check your inbox for the $target notification. Email delivery must be verified separately."
      return
    fi
  done
  echo "Timed out. Run bash lab.sh status and bash lab.sh history. Resources remain deployed."
  return 1
}
case "${1:-}" in
  deploy)
    identity
    echo "Creates an SNS topic, topic policy and CloudWatch alarm, then requests an email subscription."
    echo "Custom metrics, alarms and SNS usage may incur charges until cleanup."
    terraform init -input=false
    terraform fmt
    terraform validate
    terraform plan -input=false -out=deploy.tfplan
    confirm "Review the plan above." deploy
    terraform apply -input=false deploy.tfplan
    rm -f deploy.tfplan
    subscribe
    ;;
  subscribe) require_deployment; subscribe ;;
  subscription) require_deployment; subscription ;;
  trigger) require_deployment; exercise 5 ALARM ;;
  recover) require_deployment; exercise 0 OK ;;
  status)
    require_deployment
    aws_lab cloudwatch describe-alarms --alarm-names "$ALARM" --query 'MetricAlarms[].{Alarm:AlarmName,State:StateValue,Reason:StateReason}' --output table
    ;;
  history)
    require_deployment
    aws_lab cloudwatch describe-alarm-history --alarm-name "$ALARM" --max-records 10 --query 'AlarmHistoryItems[].{Type:HistoryItemType,Summary:HistorySummary}' --output table
    ;;
  delete)
    require_deployment
    terraform init -input=false
    terraform plan -destroy -input=false -out=destroy.tfplan
    confirm "Delete this lab alarm, SNS topic and its subscriptions?" delete
    terraform apply -input=false destroy.tfplan
    rm -f destroy.tfplan .lab-email
    echo "Lab alarm and SNS resources destroyed. Metric history expires under CloudWatch retention."
    ;;
  *) echo "Usage: bash lab.sh {deploy|subscribe|subscription|recover|trigger|status|history|delete}"; exit 1 ;;
esac
