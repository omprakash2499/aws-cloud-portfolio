#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export AWS_PAGER=""
unset MSYS_NO_PATHCONV
command -v terraform >/dev/null || { echo 'Terraform is required.'; exit 1; }
command -v aws >/dev/null || { echo 'AWS CLI is required.'; exit 1; }
case "${1:-help}" in
  deploy)
    command -v python >/dev/null || { echo 'Python 3 is required for testing.'; exit 1; }
    aws sts get-caller-identity >/dev/null
    echo 'Creates API Gateway, Lambda, DynamoDB, IAM and CloudWatch resources. AWS charges may apply.'
    terraform init
    terraform fmt
    terraform validate
    terraform plan -out=deploy.tfplan
    read -r -p 'Review the plan above. Type deploy to apply: ' answer
    [[ "$answer" == deploy ]] || { echo 'Cancelled.'; exit 1; }
    terraform apply deploy.tfplan
    rm -f deploy.tfplan
    echo 'Deployment complete. Waiting briefly for route and IAM propagation.'
    sleep 15
    python test_api.py
    ;;
  test) python test_api.py ;;
  outputs) terraform output ;;
  delete)
    echo 'Deletes this Terraform deployment, including all tasks and its logs.'
    terraform plan -destroy -out=destroy.tfplan
    read -r -p 'Review the destroy plan. Type delete to continue: ' answer
    [[ "$answer" == delete ]] || { echo 'Cancelled.'; exit 1; }
    terraform apply destroy.tfplan
    rm -f destroy.tfplan
    echo 'Lab resources destroyed.'
    ;;
  *) echo 'Usage: bash lab.sh deploy | test | outputs | delete' ;;
esac
