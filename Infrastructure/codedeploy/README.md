# CodeDeploy Infrastructure for Microservice Deployments

This directory contains the AWS CodeDeploy configuration and scripts for deploying microservices to Docker Swarm clusters.

## Overview

The deployment infrastructure consists of:
- **GitHub Actions workflow** that builds containers and triggers CodeDeploy
- **CodeDeploy applications and deployment groups** for each microservice
- **Deployment scripts** that handle Docker Swarm deployments
- **Terraform configuration** for AWS infrastructure

## Architecture

```
GitHub Actions → ECR → CodeDeploy → Docker Swarm
     ↓              ↓         ↓           ↓
  Build Image   Push Image  Deploy    Update Stack
```

## Files Structure

```
Infrastructure/codedeploy/
├── appspec.yml                    # CodeDeploy AppSpec file
├── scripts/
│   ├── env.sh                     # Environment variables
│   ├── before-install.sh          # Pre-installation checks
│   ├── after-install.sh           # Post-installation tasks
│   ├── application-start.sh       # Start new version
│   ├── validate-service.sh        # Health checks
│   ├── before-allow-traffic.sh    # Pre-traffic validation
│   └── after-allow-traffic.sh     # Post-deployment cleanup
└── README.md                      # This file
```

## Prerequisites

1. **Docker Swarm Cluster**: Must be running on target EC2 instances
2. **Required Secrets**: `aspnetapp.pfx` certificate secret
3. **Overlay Network**: `net` network must exist
4. **Environment Files**: Service-specific `.env` and `.env.docker` files

## Setup

### 1. Deploy Infrastructure

```bash
# Deploy CodeDeploy infrastructure
cd Infrastructure/terraform/modules
terraform workspace select staging  # or production
terraform plan
terraform apply
```

### 2. Configure GitHub Secrets

Add the following secrets to your GitHub repository:

- `AWS_ACCOUNT_ID`: Your AWS account ID
- `ECR_REPOSITORY_PREFIX`: ECR repository prefix (e.g., "authentication-sample")
- `DEPLOYMENT_BUCKET`: S3 bucket name for deployment artifacts

### 3. Install CodeDeploy Agent

The CodeDeploy agent must be installed on target EC2 instances. Add this to your instance user data:

```bash
#!/bin/bash
yum update -y
yum install -y ruby wget
cd /home/ec2-user
wget https://aws-codedeploy-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/install
chmod +x ./install
./install auto
service codedeploy-agent start
```

## Usage

### Automatic Deployment

The GitHub Actions workflow automatically triggers when changes are pushed to microservice directories:

```bash
# Changes to authentication service
git push origin main  # Triggers deployment if Microservices/Authentication/ changed
```

### Manual Deployment

1. Go to **Actions** → **Microservice Release**
2. Select the service to deploy
3. Choose environment (staging/production)
4. Click **Run workflow**

### Adding New Services

1. **Update GitHub Actions workflow**:
   ```yaml
   # In .github/workflows/service-release.yml
   options:
     - authentication
     - new-service  # Add new service
   ```

2. **Update change detection**:
   ```bash
   # Add detection logic
   if echo "$CHANGED_FILES" | grep -q "^Microservices/NewService/"; then
     SERVICE_NAME="new-service"
   fi
   ```

3. **Update Terraform configuration**:
   ```hcl
   # In Infrastructure/terraform/codedeploy.tf
   for_each = toset(["authentication", "new-service"])
   ```

4. **Create service-specific configuration**:
   - Add environment files
   - Update stack configuration if needed

## Deployment Process

1. **BeforeInstall**: Validate Docker Swarm and required resources
2. **AfterInstall**: Pull new container image
3. **ApplicationStart**: Deploy to Docker Swarm
4. **ValidateService**: Health checks and validation
5. **BeforeAllowTraffic**: Final validation
6. **AfterAllowTraffic**: Cleanup and logging

## Monitoring

### CloudWatch Logs

Deployment logs are available in CloudWatch:
- Log Group: `/aws/codedeploy/{service}-{environment}`

### CloudWatch Alarms

Deployment failure alarms are automatically created:
- Alarm: `{app-name}-{service}-deployment-alarm`

### Manual Monitoring

```bash
# Check deployment status
aws deploy get-deployment --deployment-id {deployment-id}

# Check Docker Swarm services
docker stack ps {stack-name}

# Check service logs
docker service logs {stack-name}_app
```

## Troubleshooting

### Common Issues

1. **Docker Swarm not active**:
   ```bash
   docker swarm init
   ```

2. **Missing secrets**:
   ```bash
   docker secret create aspnetapp.pfx /path/to/certificate.pfx
   ```

3. **Network not found**:
   ```bash
   docker network create -d overlay --attachable net
   ```

4. **CodeDeploy agent not running**:
   ```bash
   sudo service codedeploy-agent status
   sudo service codedeploy-agent start
   ```

### Debugging

1. **Check CodeDeploy logs**:
   ```bash
   sudo tail -f /var/log/aws/codedeploy-agent/codedeploy-agent.log
   ```

2. **Check deployment scripts**:
   ```bash
   sudo tail -f /opt/codedeploy-agent/deployment-root/*/deployment-archive/logs/scripts.log
   ```

3. **Check Docker Swarm**:
   ```bash
   docker stack ps {stack-name}
   docker service logs {stack-name}_app
   ```

## Security

- All scripts run with minimal required permissions
- Secrets are managed through Docker Swarm secrets
- Network communication is restricted to VPC
- IAM roles follow least privilege principle

## Cost Optimization

- S3 lifecycle policies automatically clean up old deployments
- CloudWatch logs have retention policies
- Old Docker images are cleaned up after successful deployments 