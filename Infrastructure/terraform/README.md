# Production Infrastructure

### Table of Contents
- [Terraform CI/CD pipeline](#terraform-cicd-pipeline)
  - [Prerequisites](#prerequisites)
  - [Setup scripts](#setup-scripts)
  - [Github repo setup](#github-repo-setup)
  - [Github actions usage](#github-actions-usage)
- [Infrastructure](#infrastructure)
   - [Docker Swarm Setup Scripts](#usage)


## Terraform CI/CD pipeline

Terraform running on Github Actions requires permissions to manipulate AWS resources. The following covers how to set that up.


### 🔐 Prerequisites

- AWS CLI
- Github CLI

#### AWS IAM Identity Center Setup

Before running this setup, you need to configure IAM Identity Center with a user with permissions defined in `setup-github-actions-oidc-policy.json`.

##### Required Setup Steps

1. **Enable IAM Identity Center** - [AWS Documentation](https://docs.aws.amazon.com/singlesignon/latest/userguide/getting-started-enable-identity-center.html)

2. **Create a Permission Set** with the following policy:
   - `setup-github-actions-oidc-policy.json`
3. **Create or assign a user** to your AWS account with the permission set

4. **Configure AWS CLI with SSO**
##### Quick AWS CLI Setup

After completing the IAM Identity Center setup:

```bash
aws configure sso --profile terraform-setup
# Follow the prompts to configure your SSO profile.
# Note: You can call your profile whatever you want

aws sso login --profile terraform-setup
```

### 🛠️ Setup Scripts


#### 🚀 `setup-github-actions-oidc.sh` - Github Action Permission Setup Script

Interactive script that automatically creates all required AWS resources for GitHub Actions OIDC authentication.

**What it creates:**
- GitHub OIDC Identity Provider
- S3 bucket to store terraform state
- IAM Policy with permissions Terraform needs (See `terraform-policy.json`)
- Trust policy allowing AWS to trust Github actions (See `github-trust-policy.json`)
- IAM Role with afformentioned policies that GitHub Actions will use when making requests to AWS
- Add secrets, variables and environemnts to github repository

> **NOTE:** The name of the S3 Bucket created is `terraform-state-<md5_hash[8]>`, where `md5_hash[8]` is the first 8 characters of an MD5 hash calucated based on AWS AccountId and repository name. The script will print out this name.
You will need it later if you choose not to let the script add variables to your github repository.

**Usage:**
```bash
# Run interactively (script will prompt for )
./setup-github-actions-oidc.sh
```

**Interactive prompts:**
- AWS SSO profile name (default: `terraform-setup`)
- App name (used to tag all AWS resource terraform creates)
- AWS region (default: `us-west-1`)
- Github staging environment name
- Github production environment name

#### 🗑️ `remove-github-actions-oidc.sh` - Pipeline Cleanup Script

Safely removes most AWS resources created by the setup script.

**What it deletes:**
- IAM Role: `github-actions-terraform`
- IAM Policy: `terraform-github-actions-oidc-policy`
- OIDC Provider: `token.actions.githubusercontent.com`

*Does not remove S3 bucket used to store terraform state. You will need to do that manually.*

**Usage:**
```bash
# Run interactively
./remove-github-actions-oidc.sh
```


**Interactive prompts:**
- AWS SSO profile name (default: `terraform-setup`)

**💡 Pro Tips:**
- All operations are idempotent (safe to run multiple times)
- Scripts validate AWS CLI access before proceeding


### GitHub Repository Setup

If you chose not to add secrets, variables and environments using `setup-github-actions-oidc.sh`:

Add staging and production environments to repository. (Settings → Environments → New environment)
Shoule have the same names as the arguments used when you ran  `setup-github-actions-oidc.sh`.

Add the following secrets to repository (Settings → Secrets → Actions):

| Secret | Value |
|--------|-------|
| `AWS_ACCOUNT_ID` | Your AWS Account ID |
| `TF_APP_NAME` | Your chosen app name (kebab case preferred) |
| `TF_STATE_BUCKET` | Bucket name that was created when  `setup-github-actions-oidc.sh` was executed. |

**Optional Environment Variables:**
- `AWS_DEFAULT_REGION` - AWS region for infrastructure deployment (defaults to `us-west-1`)

### 🚀 GitHub Actions Usage
(See `<APP_ROOT>/.github/workflows/infrastrucutre-release.yml`)
The github action will always plan automatically, but deployment or destruction of the infrastructure must be triggered manually.
 
#### Automatic Planning

- Pull requests to `main` branch automatically trigger a Terraform plan
- The plan results are posted as a comment on the PR
- No automatic deployment occurs - manual approval is required


#### Manual Workflows:

1. Go to **Actions** → **Infrastructure Release**
2. Choose your action:
   - `plan`: Generate a plan without applying
   - `deploy`: Apply infrastructure changes
   - `destroy`: Destroy infrastructure (use with caution)
3. Select the target environment: `terraform-staging` or `terraform-production`
4. Click **Run workflow**

> NOTE: Github will send a cliam that includes the environment.
AWS will only trust a workflow from the environment that you defined.
(see `github-trust-policy.json`)

## 🏗️ Infrastructure

The Terraform configuration creates:
- **VPC** with public and private subnets and internet
- **EC2 instances**
   - 1 public instnace
   - 1 private instance
   - 1 internet gateway
- **Security groups** for Docker Swarm communication  
- **IAM roles** for EC2 instances to access AWS resources
- **Docker Swarm** cluster with automated setup


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