# DevOps Deployment Guide

This guide covers the complete infrastructure deployment process for the authentication system using Terraform, AWS services, and GitHub Actions workflows. It also explains how to deploy to production from a development machine for testing only.

## Prerequisites

- **bash**
- **AWS CLI** and an AWS account with a **Hosted Zone** (domain) on Route53
- **Git & GitHub CLI** with your repository on GitHub
- **Vercel** account with an API key

## Setup

### Step 1: AWS Setup
*Perform these steps if they have not been done yet.*

- Create an AWS SSO user/group and a profile with permissions listed in [setup-github-actions-oidc-policy.json](../../infrastructure/terraform/setup-github-actions-oidc-policy.json).
  - Create the SSO profile (e.g., named `infra-setup`) using `aws configure sso`, then authenticate with `aws sso login --profile infra-setup`.
  - This profile is used to provision production resources in AWS.
- Set up OIDC access for GitHub Actions to deploy AWS resources:
  ```bash
  ./scripts/deployment/setup-infra-worfklow.sh
  ```


### Step 2: Set up secrets

Use the `setup-secrets.sh` script to configure secrets. This stores backend secrets in AWS Secrets Manager.

- Development (default mode):
```bash
./scripts/deployment/setup-secrets.sh -a <project-name> -p <aws-profile>
```

- Production (adds a `-prod` suffix to the secret name and shows an extra confirmation):
```bash
./scripts/deployment/setup-secrets.sh -a <project-name> -p <aws-profile> -P
```

Options:
- `-f` forces prompting for all keys (overwrite existing values)
- `-P` enables production mode

The script will:
1. Discover all `.env.template` files
2. Prompt you for values for each configuration key
3. Store backend secrets in AWS Secrets Manager
4. Create local `.env` files for frontend applications (dev only)
5. When re-run, only prompt for new secrets; use `-f` to overwrite all values

NOTE: For production, it is recommended to manage secrets in the AWS Console.

### Step 3: Deploy Infrastructure
In GitHub Actions (in your repository), run the "Infrastructure Prod" workflow to provision cloud resources for production.


### Step 4: Deploy Microservices
In GitHub Actions, run the microservice deployment workflows:
  - OpenTelemetry Collector
  - Envoy Proxy
  - Auth Service
  - Greeter Service


## Testing
You may need to deploy to AWS from a development environment to test deployment faster.
To do so, perform the following actions:
  - Grant your SSO profile the same permissions as GitHub Actions by updating the Terraform OIDC trust policy (in the IAM console) to match the policy listed [here](../../infrastructure/terraform/terraform-testing-trust-policy.json).
  - Add a new AWS profile that assumes the same role as GitHub Actions by modifying `~/.aws/config`.
  Add the following:
  ```
  [profile github-terraform]
  role_arn = arn:aws:iam::<ACCOUNT_ID>:role/github-actions-terraform
  source_profile = infra-setup
  role_session_name = terraform-local
  region = us-west-1
  ```
  - Obtain a Vercel API key. Used when running `prod-infra.sh` script.

Now the `github-terraform` profile can be used to deploy directly to AWS.

**Deploy Dev Environment**
```bash
# Runs Terraform commands to deploy or destroy the dev environment
# Expects profile to be called github-terraform
./scripts/deployment/dev-infra.sh -a <deploy|destroy>
```

**Deploy Prod Environment***
```bash
# Runs Terraform commands to deploy or destroy the dev environment
# Expects profile to be called github-terraform
./scripts/deployment/prod-infra.sh -a <deploy|destroy> -e <prod|stage>
```
