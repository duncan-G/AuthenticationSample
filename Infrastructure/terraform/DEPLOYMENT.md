# 🚀 Deployment Guide

This guide covers the complete deployment process for the Terraform infrastructure, from initial setup to production deployment.

---

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Environment Configuration](#environment-configuration)
- [Deployment Process](#deployment-process)
- [CI/CD Pipeline](#cicd-pipeline)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

---

## ✅ Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **Terraform** | >= 1.5.0 | Infrastructure provisioning |
| **AWS CLI** | >= 2.0 | AWS API access |
| **GitHub CLI** | >= 2.0 | Repository management |
| **Docker** | >= 20.0 | Local development |

### AWS Requirements

- **AWS Account** with appropriate permissions
- **IAM Identity Center (SSO)** configured
- **Route53 Hosted Zone** for your domain
- **Domain Name** registered and configured

### GitHub Requirements

- **GitHub Repository** with your application code
- **GitHub Personal Access Token** for API access
- **GitHub Actions** enabled for the repository

---

## 🛠️ Initial Setup

### 1. AWS Configuration

```bash
# Configure AWS SSO
aws configure sso --profile infra-setup

# Login to AWS
aws sso login --profile infra-setup

# Verify access
aws sts get-caller-identity --profile infra-setup
```

### 2. Environment Variables

```bash
# Core configuration
export TF_VAR_region="us-west-1"
export TF_VAR_app_name="my-auth-app"
export TF_VAR_environment="staging"
export TF_VAR_domain_name="example.com"
export TF_VAR_route53_hosted_zone_id="Z1234567890"

# GitHub configuration
export TF_VAR_github_repository="myorg/my-app"
export TF_VAR_vercel_api_token="your-vercel-token"

# Certificate configuration
export TF_VAR_bucket_suffix="prod"
export TF_VAR_certbot_ebs_volume_id="vol-1234567890"
```

### 3. Terraform Backend Setup

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://my-app-terraform-state --region us-west-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-app-terraform-state \
  --versioning-configuration Status=Enabled

# Initialize Terraform
terraform init -backend-config="bucket=my-app-terraform-state"
```

---

## 🌍 Environment Configuration

### Staging Environment

```bash
# Staging configuration
export TF_VAR_environment="staging"
export TF_VAR_app_name="my-app-staging"
export TF_VAR_public_worker_count=1
export TF_VAR_private_worker_count=1
export TF_VAR_manager_count=1

# Deploy staging
terraform workspace new staging
terraform plan
terraform apply
```

### Production Environment

```bash
# Production configuration
export TF_VAR_environment="production"
export TF_VAR_app_name="my-app-prod"
export TF_VAR_public_worker_count=3
export TF_VAR_private_worker_count=5
export TF_VAR_manager_count=3

# Deploy production
terraform workspace new production
terraform plan
terraform apply
```

### Environment-Specific Variables

| Environment | Instance Counts | Purpose |
|-------------|-----------------|---------|
| **Staging** | 1 public, 1 private, 1 manager | Development and testing |
| **Production** | 3 public, 5 private, 3 manager | High availability |

---

## 🔄 Deployment Process

### 1. Infrastructure Deployment

```bash
# Step 1: Plan the deployment
terraform plan -out=tfplan

# Step 2: Review the plan
terraform show tfplan

# Step 3: Apply the changes
terraform apply tfplan
```

### 2. Post-Deployment Verification

```bash
# Check instance status
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=my-app-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value]'

# Verify security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=my-app-*"

# Check IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `my-app`)]'
```

### 3. Docker Swarm Setup

The infrastructure automatically sets up Docker Swarm using SSM documents:

```bash
# Check SSM associations
aws ssm describe-associations \
  --filters "Key=Name,Values=my-app-*"

# Monitor setup progress
aws logs tail /aws/ec2/my-app-manager --follow
```

### 4. Certificate Management

```bash
# Check certificate manager status
aws ssm send-command \
  --instance-ids i-1234567890 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo systemctl status certificate-manager"]'

# View certificate logs
aws logs tail /aws/ec2/my-app-certificate-manager --follow
```

---

## 🔄 CI/CD Pipeline

### GitHub Actions Setup

#### 1. OIDC Configuration

```bash
# Run the OIDC setup script
./Scripts/deployment/terraform/setup-github-actions-oidc.sh

# This script will:
# - Create GitHub OIDC Identity Provider
# - Create S3 bucket for Terraform state
# - Create IAM roles and policies
# - Configure GitHub repository secrets
```

#### 2. Repository Configuration

The setup script automatically configures:

| Type | Name | Description |
|------|------|-------------|
| **Secret** | `AWS_ACCOUNT_ID` | AWS account identifier |
| **Secret** | `TF_STATE_BUCKET` | Terraform state bucket |
| **Secret** | `TF_APP_NAME` | Application name |
| **Variable** | `AWS_DEFAULT_REGION` | AWS region |
| **Environment** | `terraform-staging` | Staging environment |
| **Environment** | `terraform-production` | Production environment |

#### 3. Workflow Configuration

```yaml
# .github/workflows/infrastructure-release.yml
name: Infrastructure Release

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      action:
        description: 'Action to perform'
        required: true
        default: 'plan'
        type: choice
        options:
        - plan
        - deploy
        - destroy
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'terraform-staging'
        type: choice
        options:
        - terraform-staging
        - terraform-production

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment }}
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: "1.5.0"
    
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: ${{ vars.AWS_DEFAULT_REGION }}
    
    - name: Terraform Init
      run: terraform init
    
    - name: Terraform Plan
      if: github.event.inputs.action == 'plan'
      run: terraform plan
    
    - name: Terraform Apply
      if: github.event.inputs.action == 'deploy'
      run: terraform apply -auto-approve
    
    - name: Terraform Destroy
      if: github.event.inputs.action == 'destroy'
      run: terraform destroy -auto-approve
```

### Vercel Frontend Deployment

#### 1. Automatic Deployment

The infrastructure automatically configures Vercel for:

- **Automatic deployments** from GitHub repository
- **Preview deployments** for pull requests
- **Environment variables** for API endpoints
- **Custom domain** configuration

#### 2. Manual Deployment

```bash
# Deploy to Vercel manually
vercel --prod

# Set environment variables
vercel env add NEXT_PUBLIC_AUTHENTICATION_SERVICE_URL production
```

---

## 📊 Monitoring & Health Checks

### 1. Infrastructure Health Checks

```bash
# Check EC2 instance health
aws ec2 describe-instance-status \
  --instance-ids $(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=my-app-*" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-1234567890 \
  --start-time $(date -d '1 hour ago' --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 300 \
  --statistics Average
```

### 2. Application Health Checks

```bash
# Check Docker Swarm status
aws ssm send-command \
  --instance-ids i-1234567890 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker node ls", "docker service ls"]'

# Check service logs
aws logs tail /aws/ec2/my-app-manager --follow
```

### 3. Certificate Health Checks

```bash
# Check certificate expiration
aws ssm send-command \
  --instance-ids i-1234567890 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo certbot certificates"]'

# Check certificate manager logs
aws logs tail /aws/ec2/my-app-certificate-manager --follow
```

### 4. DNS Health Checks

```bash
# Check DNS resolution
dig @8.8.8.8 example.com
dig @8.8.8.8 api.example.com

# Check Route53 health checks
aws route53 list-health-checks
```

---

## 🔄 Rollback Procedures

### 1. Infrastructure Rollback

```bash
# Rollback to previous Terraform state
terraform plan -refresh-only
terraform apply -target=aws_instance.public_workers

# Or rollback to specific state
terraform apply -var-file=backup.tfvars
```

### 2. Application Rollback

```bash
# Rollback Docker services
aws ssm send-command \
  --instance-ids i-1234567890 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker service rollback authentication"]'

# Rollback CodeDeploy deployment
aws deploy rollback-application-revision \
  --application-name my-app-authentication-production \
  --deployment-group-name my-app-authentication-production-deployment-group
```

### 3. Certificate Rollback

```bash
# Restore certificates from backup
aws ssm send-command \
  --instance-ids i-1234567890 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo systemctl restart certificate-manager"]'
```

### 4. DNS Rollback

```bash
# Update DNS records to point to backup instances
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch file://dns-rollback.json
```

---

## 🔧 Troubleshooting

### Common Issues

#### 1. Terraform State Issues

**Problem**: State file corruption or conflicts
**Solution**:
```bash
# Refresh state
terraform refresh

# Import missing resources
terraform import aws_instance.example i-1234567890

# Recreate state file
terraform init -reconfigure
```

#### 2. Docker Swarm Issues

**Problem**: Nodes not joining swarm
**Solution**:
```bash
# Check swarm status
docker node ls

# Rejoin worker nodes
docker swarm join --token $(aws ssm get-parameter --name "/my-app/staging/docker-swarm-worker-token" --with-decryption --query 'Parameter.Value' --output text) $(aws ssm get-parameter --name "/my-app/staging/docker-swarm-manager-ip" --query 'Parameter.Value' --output text):2377
```

#### 3. Certificate Issues

**Problem**: Certificate renewal failures
**Solution**:
```bash
# Check certbot logs
sudo journalctl -u certificate-manager -f

# Manual certificate renewal
sudo certbot renew --force-renewal

# Check DNS records
dig @8.8.8.8 _acme-challenge.example.com
```

#### 4. GitHub Actions Issues

**Problem**: OIDC authentication failures
**Solution**:
```bash
# Verify OIDC provider
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com

# Check role trust relationships
aws iam get-role --role-name my-app-github-actions-role-certbot
```

### Debugging Commands

```bash
# Check all resources
terraform show

# Validate configuration
terraform validate

# Check variable values
terraform console
> var.app_name
> var.environment

# View dependency graph
terraform graph | dot -Tsvg > graph.svg
```

### Support Resources

- **Terraform Documentation**: [terraform.io/docs](https://www.terraform.io/docs)
- **AWS Documentation**: [docs.aws.amazon.com](https://docs.aws.amazon.com)
- **GitHub Actions**: [docs.github.com/en/actions](https://docs.github.com/en/actions)
- **Docker Swarm**: [docs.docker.com/engine/swarm](https://docs.docker.com/engine/swarm)

---

## 📚 Related Documentation

- [Main README](./README.md) - Complete infrastructure documentation
- [Variables Reference](./VARIABLES.md) - All variables with descriptions
- [Module Documentation](./MODULES.md) - Detailed module reference
- [Security Guide](./SECURITY.md) - Security best practices

---

*Last updated: $(date)* 