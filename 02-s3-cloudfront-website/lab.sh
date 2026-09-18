#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export AWS_PAGER=""
unset MSYS_NO_PATHCONV
REGION="${AWS_REGION:-us-east-1}"
STACK="portfolio-s3-cloudfront-lab"
aws_lab() { MSYS_NO_PATHCONV=1 aws --region "$REGION" "$@"; }
fail() { echo "ERROR: $*" >&2; exit 1; }
out() { aws_lab cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text; }
action="${1:-help}"
case "$action" in deploy|test|outputs|delete) ;; help) echo 'Usage: bash lab.sh deploy | test | outputs | delete'; exit 0;; *) fail 'Unknown action';; esac
command -v aws >/dev/null || fail 'AWS CLI v2 is required.'
command -v curl >/dev/null || fail 'curl is required; use Git Bash.'
# Validate credentials without printing account identity into screenshots.
aws_lab sts get-caller-identity >/dev/null
echo "Region: $REGION  Stack: $STACK"
if [[ "$action" == delete ]]; then
  aws_lab cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].[StackName,StackStatus]' --output table
  read -r -p "Delete this lab and all objects in its bucket? Type $STACK: " answer
  [[ "$answer" == "$STACK" ]] || fail 'Cancelled.'
  # Resolve the bucket from this stack, including partially created/rolled-back stacks.
  bucket="$(aws_lab cloudformation list-stack-resources --stack-name "$STACK" --query "StackResourceSummaries[?LogicalResourceId=='WebsiteBucket' && ResourceStatus!='DELETE_COMPLETE'].PhysicalResourceId | [0]" --output text)"
  if [[ -n "$bucket" && "$bucket" != None ]]; then
    if aws_lab s3api head-bucket --bucket "$bucket" 2>/dev/null; then
      # This lab bucket has no versioning. Refuse to empty a versioned bucket.
      versioning="$(aws_lab s3api get-bucket-versioning --bucket "$bucket" --query Status --output text)"
      [[ "$versioning" == None ]] || fail 'Bucket versioning was changed. Review and remove object versions manually before deleting the stack.'
      aws_lab s3 rm "s3://$bucket" --recursive --only-show-errors
    else
      echo 'Bucket is missing or inaccessible; CloudFormation will attempt deletion and report any failure.'
    fi
  fi
  aws_lab cloudformation delete-stack --stack-name "$STACK"
  echo 'Waiting for deletion. CloudFront removal can take several minutes.'
  if ! aws_lab cloudformation wait stack-delete-complete --stack-name "$STACK"; then
    fail 'Deletion is not confirmed. Inspect stack events; a timeout can mean deletion is still running. Do not assume cleanup succeeded.'
  fi
  echo 'Lab stack deleted.'
  exit 0
fi
if [[ "$action" == deploy ]]; then
  echo 'Creates an S3 bucket and a CloudFront distribution. Storage, requests and data transfer may incur charges.'
  aws_lab cloudformation validate-template --template-body file://template.json >/dev/null
  aws_lab cloudformation create-stack --stack-name "$STACK" --template-body file://template.json --tags Key=Project,Value=aws-cloud-portfolio --query StackId --output text >/dev/null
  echo 'Waiting for CloudFront deployment. Keep this terminal open.'
  if ! aws_lab cloudformation wait stack-create-complete --stack-name "$STACK"; then
    aws_lab cloudformation describe-stack-events --stack-name "$STACK" --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceStatusReason]" --output table
    fail 'Deployment not confirmed. Check CloudFormation status. If CREATE_COMPLETE later appears, run test to upload and verify. If it failed, use delete to clean up.'
  fi
fi
if [[ "$action" == outputs ]]; then
  aws_lab cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].Outputs' --output table
  exit 0
fi
status="$(aws_lab cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].StackStatus' --output text)"
[[ "$status" == CREATE_COMPLETE || "$status" == UPDATE_COMPLETE ]] || fail "Stack status: $status. Wait for completion before running tests."
bucket="$(out BucketName)"
distribution="$(out DistributionId)"
website="$(out WebsiteUrl)"
direct="$(out DirectS3Url)"
# Upload the page on deploy and on test, making interrupted deployments recoverable.
aws_lab s3 cp index.html "s3://$bucket/index.html" --content-type 'text/html; charset=utf-8' --cache-control 'public,max-age=60' --sse AES256 --only-show-errors
aws_lab s3api head-object --bucket "$bucket" --key index.html --query '[ContentLength,ServerSideEncryption]' --output table
echo 'Waiting for CloudFront to finish distributing its configuration.'
aws_lab cloudfront wait distribution-deployed --id "$distribution"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
# The page has short cache lifetime; retries also allow bucket-policy propagation.
code=000
for ((i=0;i<30;i++)); do
  if code="$(curl -sS --connect-timeout 10 --max-time 30 -o "$tmp_dir/page" -w '%{http_code}' "$website/")"; then
    if [[ "$code" == 200 ]] && grep -q 'private-origin-lab-v1' "$tmp_dir/page"; then break; fi
  fi
  sleep 10
done
[[ "$code" == 200 ]] && grep -q 'private-origin-lab-v1' "$tmp_dir/page" || fail "CloudFront page did not pass the content check (HTTP $code). Resources remain deployed; inspect the origin, OAC and bucket policy."
echo 'PASS 1: CloudFront HTTPS returns HTTP 200 with the expected website content.'
code="$(curl -sS --connect-timeout 10 --max-time 30 -o "$tmp_dir/denied" -w '%{http_code}' "$direct")"
[[ "$code" == 403 ]] && grep -q 'AccessDenied' "$tmp_dir/denied" || fail "Anonymous S3 request was not the expected AccessDenied/403 (HTTP $code)."
echo 'PASS 2: Anonymous access to the existing S3 object returns HTTP 403 AccessDenied.'
code="$(curl -sS --connect-timeout 10 --max-time 30 -D "$tmp_dir/headers" -o /dev/null -w '%{http_code}' "${website/https:/http:}/")"
[[ "$code" == 301 || "$code" == 302 || "$code" == 307 || "$code" == 308 ]] || fail "HTTP did not redirect (HTTP $code)."
grep -Fqi "location: $website/" "$tmp_dir/headers" || fail 'Redirect Location does not match the HTTPS website.'
echo 'PASS 3: HTTP redirects to the HTTPS website.'
public_block="$(aws_lab s3api get-public-access-block --bucket "$bucket" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text)"
[[ "${public_block,,}" =~ ^true[[:space:]]+true[[:space:]]+true[[:space:]]+true$ ]] || fail 'Not all S3 Block Public Access settings are enabled.'
echo 'PASS 4: All four S3 Block Public Access settings are enabled.'
printf '\nWebsite: %s\nDirect S3 object: %s\n' "$website" "$direct"
echo 'Open the Website URL in your browser for the website screenshot.'
echo 'When finished with screenshots: bash lab.sh delete'
