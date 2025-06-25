# GitHub Actions Workflows for Microservice Deployment

This directory contains GitHub Actions workflows for deploying microservices to AWS using CodeDeploy and Docker Swarm.

## Architecture Overview

The deployment system uses a **reusable workflow pattern** that provides:

- **Automatic deployments** when service code changes
- **Manual deployments** with service selection
- **Consistent deployment process** across all services
- **Easy service addition** with templates and scripts

## Workflow Structure

```
.github/workflows/
├── deploy-microservice.yml          # Reusable workflow template
├── service-release.yml              # Manual deployment (any service)
├── authentication-service.yml       # Service-specific workflow
├── templates/
│   └── service-template.yml         # Template for new services
└── README.md                        # This file
```

## Workflow Types

### 1. Reusable Workflow (`deploy-microservice.yml`)

**Purpose**: Core deployment logic that can be called by other workflows

**Features**:
- Builds and pushes containers to ECR
- Deploys to Docker Swarm via CodeDeploy
- Handles health checks and validation
- Provides deployment summaries

**Usage**: Called by service-specific workflows or manual triggers

### 2. Service-Specific Workflows (e.g., `authentication-service.yml`)

**Purpose**: Handle automatic deployments for specific services

**Features**:
- Detect changes in specific service directories
- Support manual triggers for the service
- Call the reusable workflow with service-specific parameters

**Triggers**:
- **Automatic**: Changes to `Microservices/{ServiceName}/**`
- **Manual**: Workflow dispatch with environment selection

### 3. Manual Service Release (`service-release.yml`)

**Purpose**: Manual deployment of any service

**Features**:
- Dropdown selection of available services
- Environment selection (staging/production)
- Force deployment option

**Usage**: For emergency deployments or testing

## Adding New Services

### Option 1: Using the Script (Recommended)

```bash
# Make the script executable
chmod +x Scripts/create-service-workflow.sh

# Create workflow for a new service
./Scripts/create-service-workflow.sh user-service
```

This script will:
- Create the service workflow file
- Update Terraform configuration
- Optionally create basic service structure
- Provide next steps

### Option 2: Manual Creation

1. **Copy the template**:
   ```bash
   cp .github/workflows/templates/service-template.yml .github/workflows/new-service-service.yml
   ```

2. **Replace placeholders**:
   ```bash
   sed -i 's/{{ SERVICE_NAME }}/new-service/g' .github/workflows/new-service-service.yml
   ```

3. **Update Terraform configuration**:
   ```hcl
   # In Infrastructure/terraform/codedeploy.tf
   for_each = toset(["authentication", "new-service"])
   ```

4. **Add to manual workflow options**:
   ```yaml
   # In .github/workflows/service-release.yml
   options:
     - authentication
     - new-service  # Add this line
   ```

## Usage Examples

### Automatic Deployment

```bash
# Make changes to authentication service
echo "# Updated code" >> Microservices/Authentication/src/Program.cs
git add .
git commit -m "Update authentication service"
git push origin main

# This automatically triggers authentication-service.yml
```

### Manual Deployment

1. **Service-Specific Manual**:
   - Go to Actions → Authentication Service Deployment
   - Click "Run workflow"
   - Select environment and options

2. **General Manual**:
   - Go to Actions → Manual Service Release
   - Select service from dropdown
   - Choose environment and options

### Force Deployment

Use the "Force deployment" option to deploy even when no changes are detected.

## Configuration

### Required GitHub Secrets

- `AWS_ACCOUNT_ID`: Your AWS account ID
- `ECR_REPOSITORY_PREFIX`: ECR repository prefix (e.g., "authentication-sample")
- `DEPLOYMENT_BUCKET`: S3 bucket name for deployment artifacts

### Required GitHub Variables

- `AWS_DEFAULT_REGION`: AWS region (defaults to "us-west-1")

### Environment-Specific Configuration

Each environment (staging/production) requires:
- CodeDeploy application and deployment group
- ECR repository
- S3 deployment bucket
- IAM roles and policies

## Deployment Process

1. **Change Detection**: Service-specific workflows detect changes
2. **Build**: .NET container is built using `dotnet publish /t:PublishContainer`
3. **Push**: Container is pushed to ECR with commit-based tags
4. **Deploy**: CodeDeploy deploys to Docker Swarm cluster
5. **Validate**: Health checks ensure successful deployment
6. **Summary**: Deployment results are reported

## Monitoring

### GitHub Actions

- **Workflow Runs**: View in Actions tab
- **Deployment Logs**: Available in each workflow run
- **Deployment Summary**: Generated at the end of each deployment

### AWS Resources

- **CodeDeploy**: Monitor deployment status and history
- **CloudWatch**: Logs and alarms for deployment failures
- **ECR**: Container image versions and tags
- **S3**: Deployment artifacts and history

## Troubleshooting

### Common Issues

1. **Workflow not triggering**:
   - Check path filters in service workflow
   - Verify changes are in the correct service directory

2. **Build failures**:
   - Check .NET project structure
   - Verify ContainerRepository property in .csproj

3. **Deployment failures**:
   - Check CodeDeploy logs on EC2 instances
   - Verify Docker Swarm is running
   - Check required secrets exist

4. **Health check failures**:
   - Verify service is listening on correct port
   - Check health endpoint is accessible
   - Review service logs

### Debugging Commands

```bash
# Check Docker Swarm status
docker info --format '{{.Swarm.LocalNodeState}}'

# Check service status
docker stack ps {stack-name}

# Check service logs
docker service logs {stack-name}_app

# Check CodeDeploy agent
sudo service codedeploy-agent status
sudo tail -f /var/log/aws/codedeploy-agent/codedeploy-agent.log
```

## Best Practices

### Service Development

1. **Follow naming conventions**:
   - Service directories: `Microservices/{service-name}`
   - Workflow files: `{service-name}-service.yml`
   - ECR repositories: `{prefix}/{service-name}`

2. **Include health checks**:
   - Implement `/health` endpoint
   - Return appropriate HTTP status codes

3. **Environment configuration**:
   - Use `.env` and `.env.docker` files
   - Never commit sensitive values

### Deployment

1. **Test in staging first**:
   - Always deploy to staging before production
   - Use manual triggers for testing

2. **Monitor deployments**:
   - Check deployment logs
   - Verify service health after deployment

3. **Rollback strategy**:
   - CodeDeploy provides automatic rollback
   - Keep previous container images in ECR

## Security Considerations

- **IAM Roles**: Use least privilege principle
- **Secrets**: Store sensitive data in GitHub secrets
- **Network**: Restrict communication to VPC
- **Images**: Scan containers for vulnerabilities
- **Access**: Limit who can trigger deployments

## Cost Optimization

- **ECR Lifecycle**: Set up image cleanup policies
- **S3 Lifecycle**: Clean up old deployment artifacts
- **CloudWatch**: Set appropriate log retention
- **Monitoring**: Use CloudWatch alarms sparingly

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review GitHub Actions logs
3. Check AWS CloudWatch logs
4. Consult the CodeDeploy documentation 