# AWS Deployment with EC2, Load Balancer, Route53, and CodeDeploy

## Overview

The authentication system deploys to AWS using a comprehensive infrastructure stack that includes EC2 instances for compute, Network Load Balancer for traffic distribution, Route53 for DNS management, and CodeDeploy for automated deployments. This provides a production-ready, scalable, and highly available deployment platform.

## Implementation

### AWS Architecture Components

#### Compute Layer (EC2)
- **Auto Scaling Groups**: Separate ASGs for manager and worker nodes
- **Launch Templates**: Standardized instance configuration with user data scripts
- **Instance Types**: ARM64-based instances (t4g.small, m6g.medium) for cost optimization
- **Placement**: Single AZ deployment for cost efficiency
- **Bootstrap**: Automated Docker Swarm setup via user data scripts

#### Load Balancing (Network Load Balancer)
- **Type**: Internet-facing Network Load Balancer (Layer 4)
- **IP Support**: Dual-stack IPv4/IPv6 for modern networking
- **TLS Termination**: SSL/TLS certificates managed by ACM
- **Health Checks**: TCP health checks on port 80
- **Target Groups**: Worker nodes registered automatically via ASG

#### DNS Management (Route53)
- **Hosted Zone**: Manages DNS records for the domain
- **A/AAAA Records**: Point to the Network Load Balancer
- **Certificate Validation**: DNS validation for ACM certificates
- **Subdomains**: Separate records for API and auth endpoints

#### Deployment Automation (CodeDeploy)
- **Application**: Manages deployment configurations
- **Deployment Groups**: Target EC2 instances by tags
- **Deployment Strategy**: Rolling deployments with health checks
- **Rollback**: Automatic rollback on deployment failures

### Infrastructure Components

#### VPC and Networking
```hcl
# Dual-stack VPC with IPv4 and IPv6 support
resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true
}

# Public subnet for load balancer
resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = "10.0.1.0/24"
  map_public_ip_on_launch         = true
  availability_zone               = data.aws_availability_zones.this.names[0]
}

# Private subnet for application instances
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.this.names[0]
}
```

#### Security Groups
```hcl
# Instance security group
resource "aws_security_group" "instance" {
  name_prefix = "${var.project_name}-instance-${var.env}-"
  vpc_id      = aws_vpc.main.id

  # HTTP from load balancer
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # Docker Swarm communication
  ingress {
    from_port = 2377
    to_port   = 2377
    protocol  = "tcp"
    self      = true
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

#### IAM Roles and Policies
```hcl
# Worker instance role
resource "aws_iam_role" "worker" {
  name = "${var.project_name}-ec2-worker-role-${var.env}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Core permissions for workers
resource "aws_iam_policy" "worker_core" {
  name = "${var.project_name}-worker-core-${var.env}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.region}:*:parameter/docker/swarm/*"
      }
    ]
  })
}
```

### Deployment Process

#### 1. Infrastructure Provisioning

The deployment starts with Terraform provisioning the AWS infrastructure:

```bash
# Initialize Terraform
terraform init -backend-config="bucket=terraform-state-bucket"

# Plan infrastructure changes
terraform plan -var-file="prod.tfvars"

# Apply infrastructure
terraform apply -var-file="prod.tfvars"
```

#### 2. Instance Bootstrap

EC2 instances are automatically configured using user data scripts:

**Manager Node Bootstrap**:
1. Install Docker, AWS CLI, and dependencies
2. Configure ECR credential helper for container registry access
3. Initialize Docker Swarm cluster
4. Create overlay network for service communication
5. Store join tokens in SSM Parameter Store
6. Install CloudWatch agent for log shipping
7. Install CodeDeploy agent for deployment automation

**Worker Node Bootstrap**:
1. Install Docker and dependencies
2. Wait for manager node initialization
3. Retrieve join token from SSM Parameter Store
4. Join Docker Swarm as worker node
5. Configure CloudWatch logging
6. Register with CodeDeploy for deployments

#### 3. Service Deployment

Applications are deployed using CodeDeploy with Docker Swarm:

```yaml
# CodeDeploy appspec.yml
version: 0.0
os: linux
hooks:
  BeforeInstall:
    - location: scripts/before-install.sh
      timeout: 300
  ApplicationStart:
    - location: scripts/application-start.sh
      timeout: 600
  ApplicationStop:
    - location: scripts/application-stop.sh
      timeout: 300
  ValidateService:
    - location: scripts/validate-service.sh
      timeout: 300
```

## Configuration

### Environment Variables

```bash
# AWS Configuration
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"

# Terraform Variables
export TF_VAR_region="us-east-1"
export TF_VAR_project_name="auth-sample"
export TF_VAR_env="prod"
export TF_VAR_domain_name="example.com"
export TF_VAR_route53_hosted_zone_id="Z1234567890ABC"

# Application Configuration
export DATABASE_NAME="authsample"
export JWT_ISSUER="https://auth.example.com"
export ASPNETCORE_ENVIRONMENT="Production"
```

### Terraform Variables

```hcl
# terraform.tfvars
region                    = "us-east-1"
project_name             = "auth-sample"
env                      = "prod"
domain_name              = "example.com"
api_subdomain            = "api"
auth_subdomain           = "auth"
route53_hosted_zone_id   = "Z1234567890ABC"
bucket_suffix            = "unique-suffix-123"

# Instance configuration
instance_type_managers   = "t4g.small"
instance_types_workers   = ["t4g.small", "m6g.medium"]
desired_workers          = 3
min_workers             = 1
max_workers             = 6

# Load balancer configuration
enable_deletion_protection = true
enable_cross_zone_load_balancing = true
```

### CodeDeploy Configuration

```json
{
  "applicationName": "auth-sample-app",
  "deploymentGroupName": "auth-sample-deployment-group",
  "deploymentConfigName": "CodeDeployDefault.EC2AllAtOneTime",
  "ec2TagFilters": [
    {
      "Type": "KEY_AND_VALUE",
      "Key": "Environment",
      "Value": "prod"
    },
    {
      "Type": "KEY_AND_VALUE",
      "Key": "Role",
      "Value": "worker"
    }
  ],
  "autoRollbackConfiguration": {
    "enabled": true,
    "events": ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }
}
```

## Usage

### Initial Deployment

#### Prerequisites

1. **AWS Account Setup**:
   ```bash
   # Configure AWS CLI
   aws configure
   
   # Verify access
   aws sts get-caller-identity
   ```

2. **Domain and DNS**:
   ```bash
   # Create Route53 hosted zone
   aws route53 create-hosted-zone --name example.com --caller-reference $(date +%s)
   
   # Note the hosted zone ID for Terraform variables
   aws route53 list-hosted-zones --query 'HostedZones[?Name==`example.com.`].Id' --output text
   ```

3. **S3 Backend**:
   ```bash
   # Create Terraform state bucket
   aws s3 mb s3://auth-sample-terraform-state-unique-suffix
   
   # Enable versioning
   aws s3api put-bucket-versioning --bucket auth-sample-terraform-state-unique-suffix --versioning-configuration Status=Enabled
   ```

#### Deployment Steps

1. **Infrastructure Deployment**:
   ```bash
   cd infrastructure/terraform/modules-single-az
   
   # Initialize with backend configuration
   terraform init -backend-config="bucket=auth-sample-terraform-state-unique-suffix"
   
   # Plan deployment
   terraform plan -var-file="prod.tfvars" -out=tfplan
   
   # Apply infrastructure
   terraform apply tfplan
   ```

2. **Verify Infrastructure**:
   ```bash
   # Check Auto Scaling Groups
   aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names auth-sample-workers-asg-prod
   
   # Check Load Balancer
   aws elbv2 describe-load-balancers --names auth-sample-nlb-prod
   
   # Check DNS records
   aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC
   ```

3. **Application Deployment**:
   ```bash
   # Create CodeDeploy application
   aws deploy create-application --application-name auth-sample-app --compute-platform EC2_OnPremises
   
   # Deploy application
   aws deploy create-deployment \
     --application-name auth-sample-app \
     --deployment-group-name auth-sample-deployment-group \
     --s3-location bucket=deployment-artifacts,key=auth-sample-v1.0.zip,bundleType=zip
   ```

### Ongoing Operations

#### Scaling Operations

```bash
# Scale worker nodes
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name auth-sample-workers-asg-prod \
  --desired-capacity 5

# Scale application services
docker service scale auth-sample_auth-service=3
```

#### Rolling Updates

```bash
# Deploy new application version
aws deploy create-deployment \
  --application-name auth-sample-app \
  --deployment-group-name auth-sample-deployment-group \
  --s3-location bucket=deployment-artifacts,key=auth-sample-v2.0.zip,bundleType=zip \
  --deployment-config-name CodeDeployDefault.EC2AllAtOneTime
```

#### Health Monitoring

```bash
# Check instance health
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names auth-sample-workers-asg-prod \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]'

# Check load balancer targets
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/auth-sample-worker-tg-prod/1234567890abcdef
```

## Testing

### Infrastructure Testing

1. **Terraform Validation**:
   ```bash
   terraform validate
   terraform fmt -check
   terraform plan -detailed-exitcode
   ```

2. **Resource Verification**:
   ```bash
   # Test load balancer connectivity
   curl -I https://api.example.com/health
   
   # Test DNS resolution
   nslookup api.example.com
   dig api.example.com AAAA  # IPv6 test
   ```

3. **Security Testing**:
   ```bash
   # Test security group rules
   nmap -p 80,443 api.example.com
   
   # Test SSL certificate
   openssl s_client -connect api.example.com:443 -servername api.example.com
   ```

### Deployment Testing

1. **CodeDeploy Validation**:
   ```bash
   # Test deployment configuration
   aws deploy validate-deployment-config --deployment-config-name CodeDeployDefault.EC2AllAtOneTime
   
   # Dry run deployment
   aws deploy create-deployment --dry-run \
     --application-name auth-sample-app \
     --deployment-group-name auth-sample-deployment-group
   ```

2. **Application Health**:
   ```bash
   # Test application endpoints
   curl https://api.example.com/health
   curl https://auth.example.com/.well-known/openid_configuration
   
   # Test service discovery
   docker exec -it $(docker ps -q -f name=auth-service) nslookup greeter-service
   ```

## Troubleshooting

### Common Issues

#### 1. Instance Launch Failures

```bash
# Check launch template
aws ec2 describe-launch-templates --launch-template-names auth-sample-worker-prod

# Check Auto Scaling Group events
aws autoscaling describe-scaling-activities --auto-scaling-group-name auth-sample-workers-asg-prod

# Check instance logs
aws logs get-log-events --log-group-name /aws/ec2/auth-sample-prod-docker-worker --log-stream-name i-1234567890abcdef0
```

#### 2. Load Balancer Health Check Failures

```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-1234567890abcdef0

# Test connectivity from load balancer subnet
aws ec2 run-instances --image-id ami-12345678 --instance-type t3.micro --subnet-id subnet-12345678
```

#### 3. DNS Resolution Issues

```bash
# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC

# Test DNS propagation
dig @8.8.8.8 api.example.com
dig @1.1.1.1 api.example.com

# Check certificate validation
aws acm describe-certificate --certificate-arn arn:aws:acm:...
```

#### 4. CodeDeploy Failures

```bash
# Check deployment status
aws deploy get-deployment --deployment-id d-1234567890

# View deployment logs
aws deploy get-deployment-instance --deployment-id d-1234567890 --instance-id i-1234567890abcdef0

# Check CodeDeploy agent status
sudo service codedeploy-agent status
```

### Debugging Commands

```bash
# SSH to instances (if bastion host configured)
aws ssm start-session --target i-1234567890abcdef0

# Check Docker Swarm status
docker node ls
docker service ls
docker stack ls

# View system logs
journalctl -u docker
journalctl -u codedeploy-agent
tail -f /var/log/docker-worker-setup.log
```

### Performance Monitoring

```bash
# CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=net/auth-sample-nlb-prod/1234567890abcdef \
  --start-time 2023-01-01T00:00:00Z \
  --end-time 2023-01-01T01:00:00Z \
  --period 300 \
  --statistics Average

# Auto Scaling metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/AutoScaling \
  --metric-name GroupDesiredCapacity \
  --dimensions Name=AutoScalingGroupName,Value=auth-sample-workers-asg-prod
```

## Related Features

- [Terraform Infrastructure Deployment](terraform-deployment.md) - Infrastructure as Code
- [Docker Containerization](docker-containerization.md) - Container orchestration
- [Load Balancing](load-balancing.md) - Traffic distribution and SSL termination
- [Monitoring and Observability](monitoring-observability.md) - Infrastructure monitoring