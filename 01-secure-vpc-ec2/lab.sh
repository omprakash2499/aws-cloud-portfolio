#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export AWS_PAGER=""
# Prevent Git Bash from rewriting AWS arguments as Windows paths.
export MSYS_NO_PATHCONV=1
REGION="${AWS_REGION:-us-east-1}"
STACK="om-vpc-portfolio-lab"
aws_lab() { aws --region "$REGION" "$@"; }
output() { aws_lab cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text; }
fail() { echo "$*" >&2; exit 1; }
command -v aws >/dev/null || fail 'Install AWS CLI v2 first, then reopen this terminal.'
action="${1:-help}"
if [[ "$action" == help ]]; then
  echo 'Usage: bash lab.sh deploy | test | outputs | delete'
  echo "Region: $REGION   Stack: $STACK"
  exit 0
fi
case "$action" in deploy|test|outputs|delete) ;; *) fail 'Unknown action.' ;; esac
aws_lab sts get-caller-identity --output table
echo "Region: $REGION   Stack: $STACK"
if [[ "$action" == delete ]]; then
  aws_lab cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].[StackName,StackStatus]' --output table
  read -r -p "Delete this lab and its data? Type $STACK: " answer
  [[ "$answer" == "$STACK" ]] || fail 'Cancelled.'
  aws_lab cloudformation delete-stack --stack-name "$STACK"
  aws_lab cloudformation wait stack-delete-complete --stack-name "$STACK"
  echo 'Lab stack deleted. Check the console for any separately created resources.'
  exit 0
fi
if [[ "$action" == deploy ]]; then
  echo 'Creates 2 t3.micro EC2 instances, disks, a NAT gateway and public IPv4 addresses. Charges apply.'
  aws_lab cloudformation validate-template --template-body file://template.json >/dev/null
  # create-stack deliberately refuses to overwrite an existing stack.
  aws_lab cloudformation create-stack --stack-name "$STACK" --template-body file://template.json --capabilities CAPABILITY_IAM --tags Key=Project,Value=aws-cloud-portfolio --output table
  echo 'Waiting for CloudFormation. This can take several minutes.'
  if ! aws_lab cloudformation wait stack-create-complete --stack-name "$STACK"; then
    aws_lab cloudformation describe-stack-events --stack-name "$STACK" --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceStatusReason]" --output table
    fail 'Stack did not complete. Inspect CloudFormation events; clean up remaining lab resources. Do not create another copy.'
  fi
fi
aws_lab cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].Outputs' --output table
[[ "$action" != outputs ]] || exit 0
public_id="$(output PublicInstanceId)"
private_id="$(output PrivateInstanceId)"
private_ip="$(output PrivateIp)"
for instance in "$public_id" "$private_id"; do
  echo "Waiting for Systems Manager: $instance"
  ready=false
  for ((i=0;i<60;i++)); do
    status="$(aws_lab ssm describe-instance-information --filters "Key=InstanceIds,Values=$instance" --query 'InstanceInformationList[0].PingStatus' --output text)"
    if [[ "$status" == Online ]]; then ready=true; break; fi
    sleep 10
  done
  [[ "$ready" == true ]] || fail 'SSM is not ready. Check instance role, NAT/routes and SSM Agent. Resources remain billable; retry with test or delete the lab.'
done
run_test() {
  local instance="$1" params="$2" command_id status
  command_id="$(aws_lab ssm send-command --instance-ids "$instance" --document-name AWS-RunShellScript --parameters "$params" --timeout-seconds 600 --query 'Command.CommandId' --output text)"
  for ((i=0;i<120;i++)); do
    # Invocation records can take a few seconds to appear.
    status="$(aws_lab ssm get-command-invocation --command-id "$command_id" --instance-id "$instance" --query Status --output text 2>/dev/null || true)"
    case "$status" in
      Success) aws_lab ssm get-command-invocation --command-id "$command_id" --instance-id "$instance" --query '[Status,StandardOutputContent,StandardErrorContent]' --output text; return 0 ;;
      Failed|Cancelled|TimedOut|Cancelling) aws_lab ssm get-command-invocation --command-id "$command_id" --instance-id "$instance" --output json; return 1 ;;
    esac
    sleep 5
  done
  echo "Command still pending or unavailable: $command_id. Inspect Systems Manager Run Command." >&2
  return 1
}
echo 'TEST 1: Nginx on the private instance and outbound HTTPS'
run_test "$private_id" 'file://private-test.json'
echo 'TEST 2: Public instance reaches private web server'
params="{\"commands\":[\"set -eu\",\"curl --fail --connect-timeout 10 http://$private_ip\"],\"executionTimeout\":[\"60\"]}"
run_test "$public_id" "$params"
echo 'TEST 3: Check private instance has no public IPv4'
public_ip="$(aws_lab ec2 describe-instances --instance-ids "$private_id" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
[[ "$public_ip" == None ]] || fail "Unexpected public IP: $public_ip"
echo 'PASS: private instance has no public IPv4.'
echo 'Automated checks passed. Save screenshots; firewall-denial testing is not included.'
echo 'When finished: bash lab.sh delete'
