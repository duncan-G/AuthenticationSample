# Production Infrastructure

## Overview

This directory contains the Terraform code and supporting documentation for provisioning and managing production infrastructure, including CI/CD integration with GitHub Actions and AWS.

---

## Table of Contents

- [Where are the Terraform-related scripts?](#where-are-the-terraform-related-scripts)
- [Terraform CI/CD Pipeline](#terraform-cicd-pipeline)
  - [Prerequisites](#prerequisites)
  - [Setup Scripts](#setup-scripts)
  - [GitHub Repository Setup](#github-repository-setup)
  - [GitHub Actions Usage](#github-actions-usage)
- [Infrastructure Details](#infrastructure-details)
  - [Docker Swarm Setup Scripts](#docker-swarm-setup-scripts)

---

## Where are the Terraform-related scripts?

| Purpose                        | New Location                                         |
|--------------------------------|------------------------------------------------------|
| Setup GitHub Actions OIDC      | `Scripts/deployment/terraform/setup-github-actions-oidc.sh` |
| Remove OIDC resources          | `Scripts/deployment/terraform/remove-github-actions-oidc.sh` |
| AWS utility functions          | `Scripts/utils/aws-utils.sh`           |
| GitHub utility functions       | `Scripts/utils/github-utils.sh`        |
| User prompt/print utilities    | `Scripts/utils/print-utils.sh`, `Scripts/utils/prompt.sh` |

---

## Terraform CI/CD Pipeline

Terraform is integrated with GitHub Actions for CI/CD. The setup scripts automate the creation of AWS resources and permissions required for secure deployments.

### Prerequisites

- AWS CLI
- GitHub CLI
- AWS IAM Identity Center (SSO) configured with a user and the policy in `setup-github-actions-oidc-policy.json`
  - Enable IAM Identity Center - [AWS Documentation](https://docs.aws.amazon.com/singlesignon/latest/userguide/getting-started-enable-identity-center.html)
  - Create a Permission Set with the policy from `setup-github-actions-oidc-policy.json`
  - Create or assign a user to your AWS account with the permission set
  - Configure AWS CLI with SSO:
    ```bash
    aws configure sso --profile infra-setup
    # Follow the prompts to configure your SSO profile.
    # Note: You can call your profile whatever you want

    aws sso login --profile infra-setup
    ```

---

## Setup Scripts

### 🚀 OIDC Setup

**Location:** `Scripts/deployment/terraform/setup-github-actions-oidc.sh`

This interactive script creates all AWS resources needed for GitHub Actions OIDC authentication, including:
- GitHub OIDC Identity Provider
- S3 bucket for Terraform state
- IAM Policy and Role for GitHub Actions
- GitHub repository secrets, variables, and environments

**Usage:**
```bash
./Scripts/deployment/terraform/setup-github-actions-oidc.sh
```

### 🗑️ OIDC Cleanup

**Location:** `Scripts/deployment/terraform/remove-github-actions-oidc.sh`

Removes most AWS resources created by the setup script (except the S3 bucket).

**Usage:**
```bash
./Scripts/deployment/terraform/remove-github-actions-oidc.sh
```

---

## GitHub Repository Setup

The setup script (`setup-github-actions-oidc.sh`) automatically configures your GitHub repository with the required secrets, variables, and environments:

The script adds:
- **Secrets** (encrypted):
  - `AWS_ACCOUNT_ID` - Your AWS account identifier
  - `TF_STATE_BUCKET` - S3 bucket name for Terraform state (auto-generated)
  - `TF_APP_NAME` - Application name for Terraform resource naming
- **Variables** (visible):
  - `AWS_DEFAULT_REGION` - AWS region for deployments (defaults to `us-west-1`)
- **Environments**: 
  - `terraform-staging` (default name, configurable)
  - `terraform-production` (default name, configurable)

---

## GitHub Actions Usage

See `.github/workflows/infrastructure-release.yml` for the main workflow.

- **Automatic:** PRs to `main` trigger a Terraform plan (no auto-deploy)
- **Manual:**  
  1. Go to **Actions** → **Infrastructure Release**
  2. Choose: `plan`, `deploy`, or `destroy`
  3. Select environment: `terraform-staging` or `terraform-production`
  4. Click **Run workflow**

> **Note:** AWS will only trust workflows from the environments you defined (see `github-trust-policy.json`).

---

## Infrastructure Details

The Terraform configuration provisions:
- **VPC** with public/private subnets and internet gateway
- **EC2 instances** (public and private)
- **Security groups** for Docker Swarm
- **IAM roles** for EC2
- **Docker Swarm** cluster with automated setup

---

## Docker Swarm Setup Scripts

- `install-docker-manager.sh`: Installs Docker, initializes Swarm, creates overlay network, stores tokens in SSM
- `install-docker-worker.sh`: Installs Docker, retrieves join token, joins Swarm

---

**For all shared utility scripts, see the `Scripts/` directory at the project root.**

If you need further help, see the top-level `Scripts/README.md` for more on script usage and organization.
