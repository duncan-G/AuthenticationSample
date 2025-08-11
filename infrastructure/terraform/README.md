# 🏗️ Terraform Infrastructure

This directory contains the complete Terraform infrastructure configuration for the Authentication Sample application. The infrastructure provides a production-ready, scalable environment with security, monitoring, and CI/CD capabilities.

## 🏛️ Architecture Overview

The infrastructure deploys a **Docker Swarm cluster** on AWS with the following components:

> **⚠️ Important**: TLS is terminated at the Network Load Balancer. Certificate automation (certbot, EBS, SDS) has been removed from infrastructure and runtime.

- **🔐 Authentication**: AWS Cognito with social providers (Google, Apple)
- **⚡ Compute**: EC2-based Docker Swarm cluster (managers + workers)
- **🌐 Network**: VPC with public/private subnets and IPv4/IPv6 support
- **🔒 Security**: Security groups and IAM roles (certificate automation removed)
- **🚀 Deployment**: AWS CodeDeploy for microservices
- **📊 Monitoring**: OpenTelemetry collector and CloudWatch
- **🌍 DNS**: Route53 domain management
- **📦 Registry**: ECR for container images
- **🎨 Frontend**: Vercel integration

### Instance Architecture

```
┌─ Public Subnet (10.0.1.0/24) ─────────────────────┐
│  Public Workers                                   │
│  ├─ Envoy Proxy                                   |
│  ├─ Certificate renewal (Certbot)                 │
│  └─ External traffic handling                     │
└───────────────────────────────────────────────────┘
┌─ Private Subnet (10.0.2.0/24) ────────────────────┐
│  Managers & Private Workers                       │
│  ├─ Application workloads                         │
│  ├─ Database services                             │
│  └─ Internal microservices                        │
└───────────────────────────────────────────────────┘
```

## 📋 Prerequisites

### Required Tools

- **Terraform** `>= 1.5.0`
- **AWS CLI** configured with appropriate credentials
- **Domain** with Route53 hosted zone
- **Vercel Account** with API token

### Required AWS Permissions

Your AWS credentials need the following permissions:
- EC2 (VPC, instances, security groups)
- IAM (roles, policies, instance profiles)
- Route53 (DNS records)
- Cognito (user pools, identity pools)
- CodeDeploy (applications, deployment groups)
- CloudWatch (logs, metrics)
- ECR (repositories)
- SSM (parameter store)
- Secrets Manager

## 🚀 Quick Start

### 1. Configure Backend

Create an S3 bucket for Terraform state:

```bash
aws s3 mb s3://your-terraform-state-bucket-name
```

### 2. Set Environment Variables

**Required Variables:**
```bash
export TF_VAR_region="us-west-1"
export TF_VAR_project_name="auth-sample"
export TF_VAR_environment="staging"  # or "production"
export TF_VAR_domain_name="yourdomain.com"
export TF_VAR_route53_hosted_zone_id="Z1D633PJN98FT9"
export TF_VAR_bucket_suffix="unique-suffix-123"
export TF_VAR_vercel_api_token="your-vercel-api-token"

# Authentication Configuration
export TF_VAR_auth_callback='["https://yourdomain.com/auth/callback"]'
export TF_VAR_auth_logout='["https://yourdomain.com/auth/logout"]'

# Deployment Configuration
export TF_VAR_microservices='["authentication"]'
export TF_VAR_microservices_with_logs='["authentication"]'

# DNS Configuration
export TF_VAR_subdomains='["api", "auth"]'

# Frontend Configuration
export TF_VAR_vercel_root_directory="clients/authentication-sample"
```

**Optional Variables:**
```bash
export TF_VAR_deployment_bucket="your-deployment-artifacts-bucket"
export TF_VAR_github_repository="yourusername/yourrepo"
export TF_VAR_staging_environment_name="staging"
export TF_VAR_production_environment_name="production"

# Instance Configuration (optional - uses defaults if not set)
export TF_VAR_public_worker_instance_type="t4g.micro"
export TF_VAR_private_worker_instance_type="t4g.small"
export TF_VAR_manager_instance_type="t4g.micro"
export TF_VAR_public_worker_count=1
export TF_VAR_private_worker_count=1
export TF_VAR_manager_count=1
```

### 3. Initialize and Apply

```bash
cd infrastructure/terraform/modules

# Initialize with backend configuration
terraform init -backend-config="bucket=your-terraform-state-bucket-name"

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

## 📁 Module Structure

| File | Purpose |
|------|---------|
| **`providers.tf`** | Terraform and provider configuration |
| **`variables.tf`** | Shared input variables |
| **`data.tf`** | Data sources (AMIs, availability zones) |
| **`network.tf`** | VPC, subnets, routing |
| **`network-security.tf`** | Security groups and rules |
| **`compute.tf`** | EC2 instances and IAM roles |
| **`auth-provider.tf`** | AWS Cognito configuration |
| **`auth-user.tf`** | Cognito user management |
| **`auth-email-delivery.tf`** | Email service configuration |
| **`container-registry.tf`** | ECR repositories |
| **`deploy-microservices.tf`** | CodeDeploy setup |
| **`route53.tf`** | DNS configuration |
| **`otel-collector.tf`** | Monitoring setup |
| **`vercel.tf`** | Frontend deployment |
| **`scripts.tf`** | Instance initialization scripts |

## ⚙️ Configuration

### Core Infrastructure Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `region` | `string` | ✅ | - | AWS region for all resources |
| `project_name` | `string` | ✅ | - | Project name used as resource prefix |
| `environment` | `string` | ✅ | - | Environment name (`staging` or `production`) |
| `domain_name` | `string` | ✅ | - | Root domain for the application |
| `route53_hosted_zone_id` | `string` | ✅ | - | Route53 hosted zone ID |
| `bucket_suffix` | `string` | ✅ | - | Suffix to ensure unique S3 bucket names |
| `vercel_api_token` | `string` | ✅ | - | Vercel API token (sensitive) |
| `deployment_bucket` | `string` | ❌ | `""` | S3 bucket name for deployment artifacts |
| `github_repository` | `string` | ❌ | `""` | GitHub repo in 'owner/repo' format for OIDC |
| `staging_environment_name` | `string` | ❌ | `staging` | GitHub Actions staging environment name |
| `production_environment_name` | `string` | ❌ | `production` | GitHub Actions production environment name |

### Compute Configuration Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `public_worker_instance_type` | `string` | ❌ | `t4g.micro` | EC2 instance type for public worker nodes |
| `private_worker_instance_type` | `string` | ❌ | `t4g.small` | EC2 instance type for private worker nodes |
| `manager_instance_type` | `string` | ❌ | `t4g.micro` | EC2 instance type for manager nodes |
| `public_worker_count` | `number` | ❌ | `1` | Number of public worker instances |
| `private_worker_count` | `number` | ❌ | `1` | Number of private worker instances |
| `manager_count` | `number` | ❌ | `1` | Number of manager instances |

### Authentication Configuration Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `idps` | `map(object)` | ❌ | `{}` | Social/OIDC identity providers (Google, Apple) |
| `auth_callback` | `list(string)` | ✅ | - | Cognito callback URLs |
| `auth_logout` | `list(string)` | ✅ | - | Cognito logout URLs |

### Deployment Configuration Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `microservices` | `list(string)` | ✅ | - | List of microservices to deploy via CodeDeploy |
| `microservices_with_logs` | `list(string)` | ✅ | - | List of microservices for CloudWatch log collection |

### DNS Configuration Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `subdomains` | `list(string)` | ✅ | - | List of subdomains (e.g., `["api", "admin"]`) |


### Frontend Configuration Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `vercel_root_directory` | `string` | ✅ | - | Root directory for the Vercel app |

### Social Authentication Providers

To enable social authentication, configure the `idps` variable. You can set this via environment variable:

```bash
export TF_VAR_idps='{
  google = {
    client_id     = "your-google-client-id"
    client_secret = "your-google-client-secret"
    scopes        = "profile email openid"
    provider_name = "Google"
    provider_type = "Google"
  }
  apple = {
    client_id     = "your-apple-client-id"
    client_secret = "your-apple-client-secret"
    scopes        = "email name"
    provider_name = "SignInWithApple"
    provider_type = "SignInWithApple"
  }
}'
```

Or in a `.tfvars` file:

```hcl
idps = {
  google = {
    client_id     = "your-google-client-id"
    client_secret = "your-google-client-secret"
    scopes        = "profile email openid"
    provider_name = "Google"
    provider_type = "Google"
  }
  apple = {
    client_id     = "your-apple-client-id"
    client_secret = "your-apple-client-secret"
    scopes        = "email name"
    provider_name = "SignInWithApple"
    provider_type = "SignInWithApple"
  }
}
```

## 🔐 Security Features

### Network Security
- **VPC Isolation**: Private subnets for internal services
- **Security Groups**: Least-privilege access rules
- **IPv6 Support**: Modern networking capabilities

### Identity & Access Management
- **IAM Roles**: Service-specific permissions
- **Instance Profiles**: Secure EC2 access
- **OIDC Integration**: GitHub Actions authentication

### TLS/SSL
- **Certificate Generation**: Let's Encrypt via Certbot on public workers
- **Certificate Storage**: S3 bucket and EBS volume for persistence  
- **Certificate Renewal**: Automated via systemd service
- **TLS Termination**: Handled by Envoy proxy (not infrastructure)
- **Multiple Domains**: Support for staging/production environments

### Authentication
- **AWS Cognito**: Managed identity provider
- **Social Logins**: Google and Apple integration
- **JWT Tokens**: Secure token-based authentication

## 📊 Monitoring & Observability

### CloudWatch Integration
- **Instance Metrics**: CPU, memory, disk usage
- **Application Logs**: Structured logging
- **Custom Metrics**: Business-specific monitoring

### OpenTelemetry
- **Distributed Tracing**: Request flow tracking
- **Metrics Collection**: Performance monitoring
- **Log Aggregation**: Centralized logging

## 🚀 Deployment

### CodeDeploy Integration
- **Automated Deployments**: GitHub Actions integration
- **Rolling Updates**: Zero-downtime deployments
- **Health Checks**: Automatic rollback on failure

### Docker Swarm
- **Container Orchestration**: Service management
- **Load Balancing**: Built-in service discovery
- **High Availability**: Multi-node cluster

## 🛠️ Maintenance

### Instance Management
```bash
# SSH to manager instance
aws ec2-instance-connect ssh --instance-id i-1234567890abcdef0

# Check Docker Swarm status
docker node ls

# View service status
docker service ls
```

### Certificate Management
Certificates are generated and renewed on public worker instances, then distributed for use by Envoy proxy. Manual renewal:

**Note**: TLS is terminated at the NLB. Envoy runs HTTP only.

### Monitoring
- **CloudWatch Dashboard**: AWS console monitoring
- **Application Logs**: `/var/log/docker/` on instances
- **System Metrics**: CloudWatch agent integration

## 🗂️ Outputs

After successful deployment, Terraform outputs important resource identifiers:

- **VPC ID**: For network references
- **Subnet IDs**: For additional resources
- **Security Group IDs**: For application configuration
- **Instance IDs**: For management and monitoring
- **Cognito Pool IDs**: For application configuration
- **ECR Repository URLs**: For container deployment

## 🔄 Upgrades & Updates

### Terraform Updates
```bash
# Update providers
terraform init -upgrade

# Plan changes
terraform plan

# Apply updates
terraform apply
```

### Instance Updates
Updates are handled through CodeDeploy for zero-downtime deployments. For infrastructure changes:

1. Update Terraform configuration
2. Run `terraform plan` to review changes
3. Apply with `terraform apply`
4. Monitor deployment through AWS Console

## 🆘 Troubleshooting

### Common Issues

**🔴 Terraform State Lock**
```bash
# Force unlock (use carefully)
terraform force-unlock <lock-id>
```

**🔴 DNS Resolution Issues**
- Verify Route53 hosted zone configuration
- Check domain name settings
- Confirm DNS propagation

**🔴 Certificate Issues**
- Check Certbot logs on public workers
- Verify domain accessibility
- Review Route53 DNS records

**🔴 Instance Connection Issues**
- Verify security group rules
- Check instance status in EC2 console
- Review CloudWatch logs

### Debugging Commands
```bash
# Check instance status
aws ec2 describe-instances --filters "Name=tag:Environment,Values=staging"

# View CodeDeploy deployments
aws deploy list-deployments --application-name authsample-microservice-staging

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix="/aws/codedeploy"
```

## 📞 Support

For infrastructure issues:
1. Check CloudWatch logs and metrics
2. Review Terraform plan output
3. Validate AWS service limits
4. Check GitHub Actions workflow logs (for deployment issues)

---
