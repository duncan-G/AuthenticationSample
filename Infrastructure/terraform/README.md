# Terraform CI/CD Pipeline Setup

Automated setup and management scripts for Terraform CI/CD pipeline with GitHub Actions and AWS OIDC authentication.

## 🛠️ Available Scripts

This directory contains automated scripts to setup your Terraform CI/CD pipeline infrastructure:

### 🚀 `setup-github-actions-oidc.sh` - Pipeline Setup Script

Interactive script that automatically creates all required AWS resources for GitHub Actions OIDC authentication.

**What it creates:**
- GitHub OIDC Identity Provider in AWS
- IAM Policy with Terraform execution permissions
- IAM Role for GitHub Actions with trust policy
- Proper trust relationships for your GitHub repository

**Usage:**
```bash
# Run with your configured AWS SSO profile
AWS_PROFILE=your-profile ./setup-github-actions-oidc.sh

# Or run interactively (script will prompt for profile)
./setup-github-actions-oidc.sh
```

**Interactive prompts:**
- AWS SSO profile name (default: `terraform-setup`)
- GitHub username/organization
- Repository name
- AWS region (default: `us-west-1`)

**Required AWS permissions:** Uses the `setup-github-actions-oidc-policy.json` permission set for minimal, secure access.

### 🗑️ `remove-github-actions-oidc.sh` - Pipeline Cleanup Script

Safely removes all AWS resources created by the setup script.

**What it deletes:**
- IAM Role: `GitHubActionsTerraform`
- IAM Policy: `TerraformGitHubActionsOIDCPolicy`
- OIDC Provider: `token.actions.githubusercontent.com`

**Usage:**
```bash
# Run with your configured AWS SSO profile
AWS_PROFILE=your-profile ./remove-github-actions-oidc.sh

# Or run interactively
./remove-github-actions-oidc.sh
```

### 🐳 Docker Swarm Setup Scripts

Scripts for setting up Docker Swarm cluster on EC2 instances:

#### `install-docker-manager.sh`
- Installs Docker on EC2 instance
- Initializes Docker Swarm as manager node
- Creates overlay network for applications
- Stores swarm tokens in AWS SSM for worker nodes

#### `install-docker-worker.sh`
- Installs Docker on EC2 instance  
- Retrieves swarm join token from SSM
- Joins the Docker Swarm as worker node
- Polls for manager readiness (up to 5 minutes)


## 🔐 Prerequisites

### AWS IAM Identity Center Setup Required

Before running this setup, configure IAM Identity Center with the appropriate permissions using the AWS Console.

#### Step 1: Enable IAM Identity Center

1. **Go to AWS Console** → **IAM Identity Center** → **Enable**
2. **Choose organization instance** (recommended) if you have AWS Organizations
3. **Choose identity source:**
   - **IAM Identity Center** - Create users directly in Identity Center
   - **Active Directory** - Connect existing AD
   - **External identity provider** - Connect SAML/OIDC provider

#### Step 2: Create Permission Set

1. **Go to IAM Identity Center** → **Permission sets** → **Create permission set**
2. **Choose Custom permission set** → **Next**
3. **Permission set name:** `TerraformPipelineSetup`
4. **Description:** "Minimal permissions for terraform pipeline setup"
5. **Session duration:** 1 hour (or as needed)
6. **Permissions policies** → **Create a custom permissions policy**
7. **Click JSON tab** and paste the contents from `setup-github-actions-oidc-policy.json`
8. **Click Next** → **Create permission set**

#### Step 3: Create or Add User

**Option A: Create new user in Identity Center**
1. **Go to Users** → **Add user**
2. **Username:** `terraform-pipeline-user`
3. **Fill in required details** → **Create user**

**Option B: Use existing user** (if using external identity provider)

#### Step 4: Assign User to Account with Permission Set

1. **Go to AWS accounts** → **Select your account** → **Assign users or groups**
2. **Select Users** → Choose your user → **Next**
3. **Select permission sets** → Choose `TerraformPipelineSetup` → **Next**
4. **Submit**

#### Step 5: Configure AWS CLI with SSO

1. **Get your SSO start URL:**
   - Go to **IAM Identity Center** → **Dashboard**
   - Copy the **AWS access portal URL**

2. **Configure AWS CLI:**
```bash
aws configure sso --profile terraform-setup
# SSO session name: terraform-setup
# SSO start URL: [Your AWS access portal URL from step 1]
# SSO region: us-west-1 (or your IAM Identity Center region)
# SSO registration scopes: sso:account:access
# Account ID: [Your AWS Account ID]
# Role name: TerraformPipelineSetup
# CLI default client Region: us-west-1
# CLI default output format: json
```

3. **Login to SSO:**
```bash
aws sso login --profile terraform-setup
```

### GitHub Repository Setup

Add this secret to your GitHub repository (Settings → Secrets → Actions):

| Secret | Value |
|--------|-------|
| `AWS_ACCOUNT_ID` | Your AWS Account ID |

## 🏃‍♂️ Quick Start

1. **Setup the pipeline:**
   ```bash
   ./setup-github-actions-oidc.sh
   ```

2. **Add AWS_ACCOUNT_ID to GitHub secrets**

3. **Your pipeline is ready!** 🎉

## 🚀 GitHub Actions Usage

### Manual Workflows:
- **Actions** → "Terraform Infrastructure" → "Run workflow"
- Choose action: `plan`, `deploy`, or `destroy`  
- Choose environment: `staging` or `production`

### Automatic Workflows:
- **Push to main** → Runs terraform plan (no auto-deploy for safety)
- **Pull Request from infra/* branches** → Shows terraform plan with changes

The GitHub Actions workflow can only run automatically when:
1. Changes are pushed to the `main` branch
2. A pull request is created from a branch starting with `infra/`

For all other branches or manual runs, you'll need to use the workflow dispatch trigger.

## 🏗️ Infrastructure Resources

The Terraform configuration creates:
- **VPC** with public and private subnets
- **EC2 instances** (public worker, private manager)
- **Security groups** for Docker Swarm communication  
- **IAM roles** with SSM and CloudWatch permissions
- **Docker Swarm** cluster with automated setup

## 🧹 Cleanup

When you're done, remove all pipeline infrastructure:

```bash
./remove-github-actions-oidc.sh
```

## 📋 Local Development

```bash
cd deployments
terraform init
terraform workspace select staging  # or production
terraform plan
terraform apply
```

---

**💡 Pro Tips:**
- Scripts include colorized output and progress indicators
- All operations are idempotent (safe to run multiple times)
- Resources are tagged for easy identification
- Scripts validate AWS CLI access before proceeding

# Terraform Infrastructure

This directory contains the Terraform configuration for the authentication sample application infrastructure.

## Backend Configuration

The Terraform state is stored in an S3 bucket using partial backend configuration. The bucket name is provided via environment variables in the CI/CD pipeline.

### Required Environment Variables

In your GitHub repository secrets, you need to set:

- `TF_STATE_BUCKET`: The name of the S3 bucket where Terraform state will be stored
- `AWS_ACCOUNT_ID`: Your AWS account ID for IAM role assumption

### Setting up GitHub Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Add the following secrets:
   - `TF_STATE_BUCKET`: Your S3 bucket name (e.g., `my-terraform-state-bucket`)
   - `AWS_ACCOUNT_ID`: Your AWS account ID

### Local Development

For local development, you can set the environment variable:

```bash
export TF_STATE_BUCKET="your-terraform-state-bucket"
terraform init -backend-config="bucket=$TF_STATE_BUCKET"
```

### CI/CD Pipeline

The GitHub Actions workflow automatically uses the `TF_STATE_BUCKET` secret to configure the backend during `terraform init`.

## Usage

The infrastructure supports multiple environments through Terraform workspaces:

- `terraform-staging`: Staging environment
- `terraform-production`: Production environment

### Manual Deployment

1. Go to **Actions** → **Infrastructure Release**
2. Choose your action:
   - `plan`: Generate a plan without applying
   - `deploy`: Apply infrastructure changes
   - `destroy`: Destroy infrastructure (use with caution)
3. Select the target environment
4. Click **Run workflow**

### Automatic Planning

- Pull requests to `main` branch automatically trigger a Terraform plan
- The plan results are posted as a comment on the PR
- No automatic deployment occurs - manual approval is required 