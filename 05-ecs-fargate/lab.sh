#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export AWS_PAGER=""
unset MSYS_NO_PATHCONV
REGION="${AWS_REGION:-us-east-1}"
[[ ! -f .lab-region ]] || REGION="$(cat .lab-region)"
export TF_VAR_region="$REGION"
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
    echo "AWS account differs from this lab's saved account. Restore the original AWS profile."
    exit 1
  fi
  printf '%s' "$account" > .lab-account
  printf '%s' "$REGION" > .lab-region
  echo "Region: $REGION  Project: portfolio-ecs-lab"
}
endpoint() {
  local task eni
  task="$(aws_lab ecs list-tasks --cluster portfolio-ecs-lab --service-name portfolio-ecs-lab --desired-status RUNNING --query 'taskArns[0]' --output text)"
  [[ "$task" != "None" ]] || { echo "No running task. Run: bash lab.sh status" >&2; return 1; }
  eni="$(aws_lab ecs describe-tasks --cluster portfolio-ecs-lab --tasks "$task" --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" --output text)"
  TASK_IP="$(aws_lab ec2 describe-network-interfaces --network-interface-ids "$eni" --query 'NetworkInterfaces[0].Association.PublicIp' --output text)"
  [[ "$TASK_IP" != "None" ]] || { echo "Task has no public IP yet." >&2; return 1; }
  echo "Website: http://$TASK_IP:8080"
}
check_app() {
  endpoint
  python test_app.py "http://$TASK_IP:8080"
  echo "Save screenshots, then run: bash lab.sh delete"
}
case "${1:-}" in
  deploy)
    for cmd in aws terraform docker python curl; do command -v "$cmd" >/dev/null || { echo "Missing: $cmd"; exit 1; }; done
    docker info >/dev/null
    identity
    echo "Creates ECR, a VPC, one Fargate service, IAM execution role and CloudWatch logs."
    echo "Fargate, public IPv4, storage, logs and traffic may incur charges until cleanup."
    operator_ip="$(curl -4fsS --max-time 15 https://checkip.amazonaws.com | tr -d '\r\n')"
    python -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$operator_ip"
    export LAB_ALLOWED_CIDR="$operator_ip/32"
    echo "Web access will be restricted to: $LAB_ALLOWED_CIDR"
    terraform -chdir=registry init -input=false
    terraform -chdir=registry fmt
    terraform -chdir=registry validate
    terraform -chdir=registry plan -input=false -out=registry.tfplan
    confirm "Create the image repository?" deploy
    terraform -chdir=registry apply -input=false registry.tfplan
    rm -f registry/registry.tfplan
    repo="$(terraform -chdir=registry output -raw repository_url)"
    registry="${repo%%/*}"
    tag="build-$(date -u +%Y%m%d%H%M%S)-$RANDOM"
    aws_lab ecr get-login-password | docker login --username AWS --password-stdin "$registry"
    docker build --platform linux/amd64 -t "$repo:$tag" .
    docker push "$repo:$tag"
    digest="$(aws_lab ecr describe-images --repository-name portfolio-ecs-lab --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text)"
    [[ "$digest" == sha256:* ]] || { echo "Could not resolve pushed image digest."; exit 1; }
    export LAB_IMAGE_URI="$repo@$digest"
    python - <<'PY'
import json, os
from pathlib import Path
Path('infra/lab.auto.tfvars.json').write_text(json.dumps({
    'image_uri': os.environ['LAB_IMAGE_URI'],
    'allowed_cidr': os.environ['LAB_ALLOWED_CIDR']
}, indent=2))
PY
    terraform -chdir=infra init -input=false
    terraform -chdir=infra fmt
    terraform -chdir=infra validate
    terraform -chdir=infra plan -input=false -out=deploy.tfplan
    confirm "Deploy the Fargate application?" deploy
    terraform -chdir=infra apply -input=false deploy.tfplan
    rm -f infra/deploy.tfplan
    echo "Waiting for the ECS service..."
    aws_lab ecs wait services-stable --cluster portfolio-ecs-lab --services portfolio-ecs-lab
    check_app
    ;;
  test) identity; check_app ;;
  status)
    identity
    aws_lab ecs describe-services --cluster portfolio-ecs-lab --services portfolio-ecs-lab --query 'services[].{Desired:desiredCount,Running:runningCount,Pending:pendingCount,Events:events[:3].message}' --output json
    ;;
  logs)
    identity
    aws_lab logs tail /ecs/portfolio-ecs-lab --since 10m --format short
    ;;
  delete)
    [[ -f .lab-account ]] || { echo "No saved deployment identity here. Use the original deployment folder."; exit 1; }
    identity
    echo "Deletes this lab's tracked infrastructure, container images and CloudWatch logs."
    confirm "Delete portfolio-ecs-lab?" portfolio-ecs-lab
    if [[ -f infra/terraform.tfstate ]]; then
      terraform -chdir=infra init -input=false
      terraform -chdir=infra destroy -input=false -auto-approve
    fi
    if [[ -f registry/terraform.tfstate ]]; then
      terraform -chdir=registry init -input=false
      terraform -chdir=registry destroy -input=false -auto-approve
    fi
    echo "Lab resources destroyed. Local Docker images and Terraform state files remain on your laptop."
    ;;
  *) echo "Usage: bash lab.sh {deploy|test|status|logs|delete}"; exit 1 ;;
esac
