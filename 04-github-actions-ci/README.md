# GitHub Actions checks for the serverless API

This workflow checks the Terraform configuration and Lambda request handling from
project 3 whenever a commit or pull request targets main. It can also be started
manually from the Actions tab.

## What runs

| Job | Checks |
| --- | --- |
| Lambda unit tests | Task creation, validation, base64 bodies, retrieval, deletion and missing routes |
| Terraform checks | Formatting, provider initialization and configuration validation |

The Python tests replace DynamoDB with a mock. They run on Python 3.12, matching
the Lambda runtime. No AWS credentials are configured in the workflow.
Terraform uses the committed provider lock file and does not apply infrastructure.

## Files

- [Workflow](../.github/workflows/portfolio-ci.yml)
- [Unit tests](../03-terraform-serverless-api/tests/test_handler.py)
- [API and Terraform configuration](../03-terraform-serverless-api/)

## Run locally

From the repository root:

```bash
python -m unittest discover -s 03-terraform-serverless-api/tests -v
terraform -chdir=03-terraform-serverless-api fmt -check -recursive
terraform -chdir=03-terraform-serverless-api init -backend=false -input=false -lockfile=readonly
terraform -chdir=03-terraform-serverless-api validate
```

If formatting fails, run `terraform -chdir=03-terraform-serverless-api fmt`
and commit the formatted file.

## Scope

These checks do not verify IAM enforcement, a deployed API or real DynamoDB
operations. The live integration checks remain in project 3's `test_api.py` and
run separately after deployment. Deployment and cleanup remain manual.

After pushing, open **Actions → Portfolio CI** and inspect both jobs. A successful
run there is the evidence for this project; adding the workflow alone does not
prove that it passed.

## Verified run

[View the successful GitHub Actions run](https://github.com/omprakash2499/aws-cloud-portfolio/actions/runs/35367591518).

Both jobs passed:
- Lambda unit tests
- Terraform formatting and configuration validation

The first run exposed a provider checksum mismatch on Linux.
Adding Windows and Linux checksums to the committed Terraform lock file
resolved the failure.
