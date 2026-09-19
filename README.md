# AWS Cloud Portfolio

I'm Om Prakash. This portfolio documents my hands-on AWS work
with infrastructure as code, Python, Docker, CI and monitoring.

Each project includes deployment instructions, test results, troubleshooting
and cleanup steps.

## Projects

| Project | What I built | Verified results |
| --- | --- | --- |
| [01 — VPC and EC2](01-secure-vpc-ec2/README.md) | Public and private subnets, private Nginx server, NAT and Systems Manager access using CloudFormation | Internal HTTP connectivity and private-instance outbound HTTPS |
| [02 — S3 and CloudFront](02-s3-cloudfront-website/README.md) | HTTPS website with a private S3 origin and CloudFront Origin Access Control | Website access, blocked direct S3 access, HTTPS redirect and public-access blocking |
| [03 — Serverless API](03-terraform-serverless-api/README.md) | IAM-protected API Gateway routes, Python Lambda and DynamoDB using Terraform | Six live checks covering authentication, validation, creation, retrieval and deletion |
| [04 — GitHub Actions CI](04-github-actions-ci/README.md) | Automated Lambda unit tests and Terraform checks for Project 3 | Eight unit tests, formatting and configuration validation passed |
| [05 — ECS Fargate](05-ecs-fargate/README.md) | Dockerized Python application, ECR and Fargate with Terraform | Homepage, health endpoint and unknown-path checks passed |
| [06 — CloudWatch and SNS](06-cloudwatch-sns-alerts/README.md) | Custom metric, alarm and SNS notifications using Terraform | OK → ALARM → OK transitions and successful SNS actions; inbox delivery unverified |

## Skills demonstrated

- AWS networking, security groups and private service access
- CloudFormation and Terraform deployment and cleanup
- IAM authentication and service permissions
- Python APIs, automated tests and Docker packaging
- GitHub Actions continuous integration
- CloudWatch logs, metric evaluation and SNS alert actions

## Troubleshooting examples

- Fixed Git Bash path conversion affecting website checks.
- Added Linux provider checksums after Terraform validation failed in CI.
- Resolved stale Docker Hub credentials blocking a container build.
- Corrected metric dimensions when a CloudWatch alarm remained in
  INSUFFICIENT_DATA.

The individual project READMEs explain these issues and the verified outcomes.

## Deployment status and scope

The AWS lab resources were removed after testing. Website and API addresses
shown in deployment evidence are historical.

These are learning labs, not production services. Their READMEs document
limitations, including single-AZ networking, HTTP-only container access and
manually published monitoring signals.

The current GitHub Actions workflow checks Project 3; it does not validate
every project in this repository.

To reproduce a lab, follow its README and remove its resources after testing.
AWS usage may incur charges. Keep credentials, Terraform state, saved plans
and local configuration outside version control.
