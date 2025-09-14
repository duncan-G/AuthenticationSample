# Terraform Infrastructure Deployment

## Overview

The authentication system uses Terraform Infrastructure as Code (IaC) to provision AWS resources for production deployment. The infrastructure is designed as a single-AZ deployment optimized for cost-effectiveness while maintaining production-grade security and scalability.

## Implementation

### Architecture Components

The Terraform configuration creates a complete AWS infrastructure stack including:

- **VPC with dual-stack IPv4/IPv6 support** for modern networking
- **Public and private subnets** for proper network segmentation
- **Auto Scaling Groups** for EC2 instances running Docker Swarm
- **Network Load Balancer** with TLS termination for high availability
- **DynamoDB table** for refresh token storage
- **Route53 DNS** records for custom domain routing
- **ACM certificates** for SSL/TLS encryption
- **IAM roles and policies** for secure service access

### Directory Structure

```text
infrastructure/terraform/modules-single-az/
├── providers.tf          # Terraform and AWS provider configuration
├── variables.tf          # Input variables and validation
├── network.tf            # VPC, subnets, and routing
├── compute.tf            # EC2 instances and Auto Scaling Groups
├── load-balancer.tf      # Network Load Balancer and listeners
├── database.tf           # DynamoDB table for refresh tokens
├── certificate.tf        # ACM certificates and validation
├── dns.tf                # Route53 DNS records
├── network-security.tf   # Security groups and NACLs
└── userdata/
    ├── manager.sh        # Docker Swarm manager bootstrap script
    └── worker.sh         # Docker Swarm worker bootstrap script
```

### Key Features

#### Dual-Stack Networking
- IPv4 and IPv6 support for future-proofing
- Public subnet (10.0.1.0/24) for load balancer
- Private subnet (10.0.2.0/24) for application instances
- Internet Gateway for external connectivity
- No NAT Gateway required (IPv6 egress via IGW)

#### Auto Scaling Infrastructure
- **Manager nodes**: Run Docker Swarm managers with cluster orchestration
- **Worker nodes**: Run application containers with auto-scaling capabilities
- **Launch templates**: Standardized instance configuration
- **CloudWatch alarms**: CPU-based scaling triggers

#### Security Model
- **IAM roles**: Separate roles for managers and workers with least privilege
- **Security groups**: Network-level access controls
- **ECR integration**: Secure container image access
- **Secrets management**: AWS Secrets Manager integration
- **SSM access**: Systems Manager for remote administration

## Configuration

### Required Variables

```hcl
# Core configuration
variable "region" {
  description = "AWS region for all resources"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "env" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "Environment must be one of: dev, stage, prod"
  }
}

variable "domain_name" {
  description = "Primary domain (e.g., example.com)"
  type        = string
}

# Infrastructure sizing
variable "instance_type_managers" {
  description = "EC2 instance type for Swarm managers"
  type        = string
  default     = "t4g.small"
}

variable "desired_workers" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}
```

### Backend Configuration

The Terraform state is stored in S3 with encryption:

```hcl
terraform {
  backend "s3" {
    # Bucket is passed via -backend-config during terraform init
    key     = "terraform.tfstate"
    encrypt = true
  }
}
```

### Provider Requirements

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 2.0"
    }
  }
}
```

## Usage

### Initial Deployment

1. **Set up backend storage**:
   ```bash
   # Create S3 bucket for Terraform state
   aws s3 mb s3://your-terraform-state-bucket
   ```

2. **Initialize Terraform**:
   ```bash
   cd infrastructure/terraform/modules-single-az
   terraform init -backend-config="bucket=your-terraform-state-bucket"
   ```

3. **Plan deployment**:
   ```bash
   terraform plan \
     -var="region=us-east-1" \
     -var="project_name=auth-sample" \
     -var="env=prod" \
     -var="domain_name=example.com"
   ```

4. **Apply configuration**:
   ```bash
   terraform apply
   ```

### Environment Variables

Set these environment variables before deployment:

```bash
export TF_VAR_region="us-east-1"
export TF_VAR_project_name="auth-sample"
export TF_VAR_env="prod"
export TF_VAR_domain_name="example.com"
export TF_VAR_vercel_api_token="your-vercel-token"
export TF_VAR_route53_hosted_zone_id="Z1234567890"
```

### Resource Naming Convention

All resources follow a consistent naming pattern:
- Format: `{project_name}-{resource_type}-{env}`
- Example: `auth-sample-nlb-prod`
- Tags include Environment and Purpose for organization

## Testing

### Infrastructure Validation

1. **Terraform validation**:
   ```bash
   terraform validate
   terraform fmt -check
   ```

2. **Plan verification**:
   ```bash
   terraform plan -detailed-exitcode
   ```

3. **Resource verification**:
   ```bash
   # Check VPC creation
   aws ec2 describe-vpcs --filters "Name=tag:Name,Values=auth-sample-vpc-prod"
   
   # Check Auto Scaling Groups
   aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names auth-sample-workers-asg-prod
   
   # Check Load Balancer
   aws elbv2 describe-load-balancers --names auth-sample-nlb-prod
   ```

### Health Checks

The infrastructure includes built-in health monitoring:

- **Load Balancer health checks**: TCP health checks on port 80
- **Auto Scaling health checks**: ELB health checks with 300s grace period
- **CloudWatch alarms**: CPU utilization monitoring for scaling
- **Instance health**: EC2 and ELB health check integration

## Troubleshooting

### Common Issues

#### 1. Certificate Validation Timeout
```bash
# Check DNS validation records
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890
```

#### 2. Auto Scaling Group Launch Failures
```bash
# Check launch template configuration
aws ec2 describe-launch-templates --launch-template-names auth-sample-worker-prod

# Check IAM role permissions
aws iam get-role --role-name auth-sample-ec2-worker-role-prod
```

#### 3. Docker Swarm Join Issues
```bash
# Check SSM parameters
aws ssm get-parameter --name /docker/swarm/worker-token
aws ssm get-parameter --name /docker/swarm/manager-ip

# Check instance logs
aws logs get-log-events --log-group-name /aws/ec2/auth-sample-prod-docker-worker
```

#### 4. Load Balancer Target Health
```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...
```

### Debugging Commands

```bash
# View Terraform state
terraform show

# Check specific resource
terraform state show aws_lb.main

# Import existing resource
terraform import aws_lb.main arn:aws:elasticloadbalancing:...

# Refresh state
terraform refresh
```

### Log Locations

- **Manager bootstrap logs**: `/var/log/docker-manager-setup.log`
- **Worker bootstrap logs**: `/var/log/docker-worker-setup.log`
- **CloudWatch log groups**: 
  - `/aws/ec2/{project_name}-{env}-docker-manager`
  - `/aws/ec2/{project_name}-{env}-docker-worker`

## Related Features

- [Docker Containerization](docker-containerization.md) - Container orchestration setup
- [AWS Deployment](aws-deployment.md) - Complete deployment process
- [Monitoring and Observability](monitoring-observability.md) - Infrastructure monitoring
- [Load Balancing](load-balancing.md) - Traffic distribution and SSL termination