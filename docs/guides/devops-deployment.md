# DevOps Deployment Guide

This comprehensive guide covers the complete infrastructure deployment process for the authentication system using Terraform, AWS services, and GitHub Actions workflows.

## Overview

The deployment process involves setting up a complete production-ready infrastructure stack including:

- **Authentication Infrastructure**: AWS Cognito for user management
- **Email Infrastructure**: Amazon SES for email delivery
- **Application Infrastructure**: EC2 instances with load balancing
- **Container Infrastructure**: ECR for container images
- **Networking**: VPC, subnets, security groups, and DNS
- **Monitoring**: CloudWatch and OpenTelemetry integration
- **CI/CD**: GitHub Actions with OIDC authentication & AWS CodeDeploy

## Prerequisites

### AWS Account Setup

1. **AWS Account**: Active AWS account with administrative access
2. **AWS CLI**: Version 2.x installed and configured
3. **Domain**: Registered domain name for the application
4. **Route53**: Hosted zone configured for your domain

### Local Development Tools

```bash
# Required tools
aws --version          # AWS CLI v2.x
terraform --version    # Terraform v1.0+
gh --version          # GitHub CLI
jq --version          # JSON processor
docker --version      # Docker for local testing
```

### AWS Permissions

Your AWS user/role needs the following permissions:
- Full access to EC2, VPC, Route53, SES, Cognito
- IAM role and policy management
- S3 bucket creation and management
- CloudWatch and Systems Manager access

## Phase 1: Initial AWS Setup

### Step 1: AWS Setup (Production account setup)

- Create an AWS SSO user group and profile with permissions listed in [setup-github-actions-oidc-policy.json](../../infrastructure/terraform/setup-github-actions-oidc-policy.json)
  - Configure SSO profile `aws sso configure infra-setup`
  - This profile is used to provision prod resources in AWS
- Set up OIDC access for GitHub Actions to deploy AWS resources:
  ```bash
  ./scripts/deployment/setup-infra-worfklow.sh

  # Optional: remove most of the provisioned resources
  ./scripts/deployment/remove-infra-workflow.sh
  ```
- In GitHub, run the Infrastructure Release workflow to provision cloud resources for production
  - Workflow: Infrastructure Release (environment: prod)
- Create an AWS SSO user group and profile with permissions listed in [developer-policy.json](../../infrastructure/terraform/developer-policy.json)
  - Configure SSO profile `aws sso configure developer`
  - This profile is used by applications to access AWS
  - NOTE: There are variables in the JSON that need to be substituted with real values

### Step 2: Set up secrets

Use the `setup-secrets.sh` script to configure secrets. This creates client `.env.local` files and stores backend secrets in AWS Secrets Manager.

For development and production:
```bash
# Development secrets (stored in AWS Secrets Manager)
./scripts/deployment/setup-secrets.sh -a your-project-name -p your-aws-profile <optional -f>

# Production secrets (stored in AWS Secrets Manager)
./scripts/deployment/setup-secrets.sh -a your-project-name -p your-aws-profile -P <optional -f>
```

The script will:
1. Discover all `.env.template` files
2. Prompt you for values for each configuration key
3. Store backend secrets in AWS Secrets Manager
4. Create local `.env` files for frontend applications
5. When re-run, only prompt for new secrets; use `-f` to overwrite all values

NOTE: It is recommended to manage production secrets in the AWS Console.

### Step 3: SES Domain Verification

Set up Amazon SES for email delivery:

```bash
# Run the SES setup script
cd scripts/deployment
./setup_ses_email_identity.sh
```

This script will:
- Create SES domain identity
- Add DNS verification records to Route53
- Set up DKIM authentication
- Wait for verification completion (up to 20 minutes)

**Verification Process**:
1. Domain verification via TXT record
2. DKIM verification via CNAME records
3. Automatic DNS record creation in Route53

## Phase 2: GitHub Actions Infrastructure

### Step 4: GitHub Repository Setup

Ensure your repository is properly configured:

```bash
# Authenticate with GitHub CLI
gh auth login

# Verify repository access
gh repo view
```

### Step 5: OIDC and IAM Setup

Set up GitHub Actions OIDC authentication:

```bash
# Run the infrastructure workflow setup
cd scripts/deployment
./setup-infra-worfklow.sh
```

**What this creates**:
- OIDC provider for GitHub Actions
- IAM roles with appropriate permissions
- S3 buckets for Terraform state and CodeDeploy
- GitHub secrets and environment variables
- ECR repository for container images

**Required Inputs**:
- AWS profile name
- Project name (for resource naming)
- Domain name
- Terraform workspace names (stage/prod)
- Vercel API key (optional, for frontend deployment)

### Step 6: Secrets Management

Configure application secrets:

```bash
# Set up development secrets
cd scripts/deployment
./setup-secrets.sh -a your-project-name -p infra-setup

# Set up production secrets
./setup-secrets.sh -a your-project-name -p infra-setup -P
```

**Secret Categories**:
- **Client Secrets**: Stored in `.env` files for development
- **Backend Secrets**: Stored in AWS Secrets Manager
- **Infrastructure Secrets**: Stored as GitHub repository secrets

## Phase 3: Infrastructure Deployment

### Step 7: Terraform Configuration

Configure Terraform variables:

```bash
cd infrastructure/terraform

# Copy and edit the variables file
cp terraform.tfvars.example terraform.tfvars
```

**Required Variables**:
```hcl
# terraform.tfvars
project_name = "auth-sample"
domain_name = "yourdomain.com"
route53_hosted_zone_id = "Z1234567890ABC"
bucket_suffix = "a1b2c3d4"
github_repository = "username/repo-name"

# Environment-specific
env = "stage"  # or "prod"
api_subdomain = "api"
auth_subdomain = "auth"
```

### Step 8: Terraform Deployment

Deploy infrastructure using GitHub Actions:

1. **Navigate to GitHub Actions**:
   - Go to your repository on GitHub
   - Click "Actions" tab
   - Find "Infrastructure Release" workflow

2. **Run Deployment**:
   - Click "Run workflow"
   - Select branch (main/master)
   - Choose environment (stage/prod)
   - Click "Run workflow"

**Manual Deployment** (if needed):
```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init -backend-config="bucket=terraform-state-your-suffix"

# Select workspace
terraform workspace select terraform-stage  # or terraform-prod

# Plan deployment
terraform plan -var-file="terraform.tfvars"

# Apply changes
terraform apply -var-file="terraform.tfvars"
```

### Step 9: Deployment Validation

Verify the infrastructure deployment:

```bash
# Check Terraform outputs
terraform output

# Verify key resources
aws ec2 describe-instances --profile infra-setup
aws elbv2 describe-load-balancers --profile infra-setup
aws route53 list-resource-record-sets --hosted-zone-id YOUR_ZONE_ID --profile infra-setup
```

**Key Resources Created**:
- VPC with public/private subnets
- EC2 instances for application hosting
- Network Load Balancer for traffic distribution
- Security groups for network access control
- Route53 DNS records for domain routing
- Cognito User Pool for authentication
- SES configuration for email delivery

## Phase 4: Application Deployment

### Step 10: Container Registry Setup

The infrastructure setup automatically creates an ECR repository. Verify it exists:

```bash
# List ECR repositories
aws ecr describe-repositories --profile infra-setup

# Get login token for Docker
aws ecr get-login-password --region us-west-1 --profile infra-setup | \
  docker login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-west-1.amazonaws.com
```

### Step 11: Microservice Deployment

Deploy microservices using CodeDeploy:

1. **Build and Push Images**:
   ```bash
   # Build microservice images
   cd microservices/Auth
   docker build -t auth-service .
   
   # Tag and push to ECR
   docker tag auth-service:latest YOUR_ACCOUNT_ID.dkr.ecr.us-west-1.amazonaws.com/auth-service:latest
   docker push YOUR_ACCOUNT_ID.dkr.ecr.us-west-1.amazonaws.com/auth-service:latest
   ```

2. **Deploy via GitHub Actions**:
   - Go to "Actions" → "Authentication Service Deployment"
   - Run workflow with appropriate environment

### Step 12: Frontend Deployment

Deploy the Next.js frontend:

1. **Vercel Deployment** (if configured):
   - Automatic deployment via GitHub integration
   - Environment variables configured via Vercel dashboard

2. **Manual Deployment**:
   ```bash
   cd clients/auth-sample
   npm run build
   # Deploy to your preferred hosting platform
   ```

## Phase 5: Configuration and Testing

### Step 13: DNS and SSL Configuration

Verify DNS resolution and SSL certificates:

```bash
# Test DNS resolution
nslookup yourdomain.com
nslookup api.yourdomain.com
nslookup auth.yourdomain.com

# Test SSL certificates (after deployment)
curl -I https://yourdomain.com
curl -I https://api.yourdomain.com
```

### Step 14: Application Configuration

Configure application-specific settings:

1. **Cognito Configuration**:
   - User Pool settings
   - App Client configuration
   - Social identity providers (Google, Apple)

2. **SES Configuration**:
   - Email templates
   - Sending quotas
   - Bounce/complaint handling

3. **Load Balancer Configuration**:
   - Health check settings
   - Target group configuration
   - SSL certificate attachment

### Step 15: Monitoring Setup

Configure monitoring and observability:

```bash
# Verify CloudWatch log groups
aws logs describe-log-groups --profile infra-setup

# Check Systems Manager parameters
aws ssm describe-parameters --profile infra-setup
```

**Monitoring Components**:
- CloudWatch logs for application logging
- CloudWatch metrics for performance monitoring
- Systems Manager for configuration management
- OpenTelemetry for distributed tracing

## Phase 6: Validation and Testing

### Step 16: Infrastructure Validation

Run comprehensive validation tests:

```bash
# Test load balancer health
aws elbv2 describe-target-health --target-group-arn YOUR_TARGET_GROUP_ARN --profile infra-setup

# Test EC2 instance status
aws ec2 describe-instance-status --profile infra-setup

# Test security group rules
aws ec2 describe-security-groups --profile infra-setup
```

### Step 17: Application Testing

Test the deployed application:

1. **Authentication Flow**:
   - User registration
   - Email verification
   - User login
   - Token refresh

2. **API Endpoints**:
   ```bash
   # Test health endpoints
   curl https://api.yourdomain.com/health
   
   # Test authentication endpoints
   curl -X POST https://api.yourdomain.com/auth/signup \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","password":"TestPass123!"}'
   ```

3. **Frontend Application**:
   - Navigate to https://yourdomain.com
   - Test user registration flow
   - Test login functionality
   - Verify responsive design

### Step 18: Performance Testing

Conduct performance validation:

```bash
# Load testing with curl
for i in {1..100}; do
  curl -s https://yourdomain.com > /dev/null &
done
wait

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 300 \
  --statistics Sum \
  --profile infra-setup
```

## Phase 7: Production Considerations

### Step 19: Security Hardening

Implement additional security measures:

1. **Network Security**:
   - Review security group rules
   - Implement WAF rules (if needed)
   - Configure VPC Flow Logs

2. **Application Security**:
   - Enable AWS Config rules
   - Set up CloudTrail logging
   - Configure GuardDuty (optional)

3. **Access Control**:
   - Review IAM policies
   - Implement least privilege access
   - Enable MFA for administrative access

### Step 20: Backup and Recovery

Set up backup procedures:

1. **Database Backups**:
   - Configure automated RDS snapshots
   - Set up cross-region backup replication

2. **Configuration Backups**:
   - Export Terraform state
   - Backup Secrets Manager secrets
   - Document manual configuration steps

3. **Disaster Recovery**:
   - Document recovery procedures
   - Test recovery processes
   - Maintain infrastructure documentation

## Troubleshooting

### Common Issues

#### SES Verification Failures
```bash
# Check SES identity status
aws ses get-identity-verification-attributes \
  --identities yourdomain.com \
  --region us-west-1 \
  --profile infra-setup

# Verify DNS records
dig TXT _amazonses.yourdomain.com
dig CNAME token._domainkey.yourdomain.com
```

#### Terraform State Issues
```bash
# List Terraform workspaces
terraform workspace list

# Switch workspace
terraform workspace select terraform-stage

# Refresh state
terraform refresh
```

#### EC2 Instance Issues
```bash
# Check instance status
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=your-project-name" \
  --profile infra-setup

# View instance logs
aws logs get-log-events \
  --log-group-name /aws/ec2/your-instance \
  --log-stream-name your-stream \
  --profile infra-setup
```

#### Load Balancer Issues
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn YOUR_TARGET_GROUP_ARN \
  --profile infra-setup

# View load balancer logs
aws logs get-log-events \
  --log-group-name /aws/elasticloadbalancing/app/your-lb \
  --profile infra-setup
```

### Error Resolution

#### "Route53 Hosted Zone Not Found"
1. Verify domain ownership
2. Check hosted zone configuration
3. Ensure nameservers are correctly set

#### "SES Identity Not Verified"
1. Check DNS propagation (can take up to 72 hours)
2. Verify TXT and CNAME records
3. Re-run SES setup script if needed

#### "Terraform Apply Failures"
1. Check AWS credentials and permissions
2. Verify variable values in terraform.tfvars
3. Review Terraform logs for specific errors
4. Ensure S3 backend bucket exists

#### "GitHub Actions Workflow Failures"
1. Verify GitHub secrets are correctly set
2. Check OIDC provider configuration
3. Ensure IAM roles have correct permissions
4. Review workflow logs for specific errors

## Infrastructure Teardown

### Safe Teardown Process

When you need to destroy the infrastructure:

1. **Backup Important Data**:
   ```bash
   # Export Terraform state
   terraform show > infrastructure-backup.txt
   
   # Backup secrets
   aws secretsmanager get-secret-value \
     --secret-id your-project-secrets \
     --profile infra-setup > secrets-backup.json
   ```

2. **Destroy Infrastructure**:
   ```bash
   # Via GitHub Actions (recommended)
   # Go to Actions → Infrastructure Release → Run workflow → Select "destroy"
   
   # Or manually
   cd infrastructure/terraform
   terraform destroy -var-file="terraform.tfvars"
   ```

3. **Clean Up Supporting Resources**:
   ```bash
   # Run cleanup script
   cd scripts/deployment
   ./remove-infra-workflow.sh
   ```

4. **Manual Cleanup**:
   - Delete S3 buckets (if not managed by Terraform)
   - Remove GitHub secrets and environments
   - Delete ECR repositories
   - Remove SES identities (if desired)

### Cleanup Verification

Verify all resources are removed:

```bash
# Check for remaining EC2 instances
aws ec2 describe-instances --profile infra-setup

# Check for remaining load balancers
aws elbv2 describe-load-balancers --profile infra-setup

# Check for remaining S3 buckets
aws s3 ls --profile infra-setup

# Check for remaining IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `github-actions`)]' --profile infra-setup
```

## Best Practices

### Security
- Use least privilege IAM policies
- Enable CloudTrail for audit logging
- Regularly rotate access keys and secrets
- Implement network segmentation with security groups
- Use HTTPS/TLS for all communications

### Reliability
- Deploy across multiple availability zones for production
- Implement health checks and auto-scaling
- Set up monitoring and alerting
- Maintain infrastructure as code
- Test disaster recovery procedures

### Cost Optimization
- Use appropriate instance sizes
- Implement auto-scaling policies
- Monitor and optimize resource usage
- Use reserved instances for predictable workloads
- Clean up unused resources regularly

### Operational Excellence
- Maintain comprehensive documentation
- Implement automated testing
- Use infrastructure as code
- Monitor application and infrastructure metrics
- Establish incident response procedures

## Support and Resources

### Documentation Links
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS SES Documentation](https://docs.aws.amazon.com/ses/)
- [AWS Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

### Troubleshooting Resources
- AWS CloudTrail for API call auditing
- CloudWatch logs for application debugging
- Terraform state files for infrastructure state
- GitHub Actions logs for deployment debugging

### Getting Help
1. Check the troubleshooting section above
2. Review AWS CloudTrail logs for permission issues
3. Examine Terraform plan output for resource conflicts
4. Verify all prerequisites are met
5. Consult AWS documentation for service-specific issues

This deployment guide provides a comprehensive approach to deploying the authentication system infrastructure. Follow each phase carefully and refer to the troubleshooting section when issues arise.