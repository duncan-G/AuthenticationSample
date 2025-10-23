# Terraform Infrastructure Configuration

This directory contains the Terraform configuration for deploying the complete infrastructure stack.

## Structure

- `main.tf` - Main configuration file that calls the modules
- `modules-single-az/` - Single availability zone infrastructure modules
- `modules-multi-az/` - Multi availability zone infrastructure modules (for production)
- `terraform.tfvars.example` - Example variables file

## Prerequisites

1. **SES Domain Identity**: The domain must be verified in SES before running Terraform
2. **Route53 Hosted Zone**: The domain must have a Route53 hosted zone
3. **AWS Credentials**: Configured AWS CLI with appropriate permissions

## Quick Start

### 1. Set up SES Domain Identity

First, verify your domain in SES:

```bash
cd scripts/deployment
./setup_ses_email_identity.sh
```

This will:
- Create the SES domain identity
- Add verification records to Route53
- Wait for verification to complete

### 2. Configure Terraform Variables

Copy the example variables file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual values
```

### 3. Initialize Terraform

```bash
cd infrastructure/terraform
terraform init -backend-config="bucket=YOUR_TERRAFORM_STATE_BUCKET"
```

### 4. Plan and Apply

```bash
terraform plan
terraform apply
```

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_name` | Project name for resource naming | `"auth-sample"` |
| `domain_name` | Primary domain name | `"ultramotiontech.com"` |
| `route53_hosted_zone_id` | Route53 hosted zone ID | `"Z1234567890ABC"` |
| `bucket_suffix` | S3 bucket name suffix | `"a1b2c3d4"` |
| `github_repository` | GitHub repository | `"username/repo-name"` |

## What Gets Created

### Authentication Infrastructure
- **Cognito User Pool** - User authentication and management
- **Cognito User Pool Clients** - Web and backend applications
- **Cognito Identity Pool** - AWS credentials for authenticated users
- **Social Identity Providers** - Google, Apple (if configured)

### Email Infrastructure
- **SES Domain Identity** - Email sending capabilities
- **Route53 Records** - SES verification and DKIM records
- **Email Templates** - User verification emails

### Application Infrastructure
- **Vercel Project** - Frontend deployment (if configured)
- **CodeDeploy** - Backend microservice deployment
- **Load Balancer** - Traffic distribution
- **EC2 Instances** - Application servers

## Troubleshooting

### Common Issues

1. **SES Domain Not Verified**
   ```
   Error: Email address is not verified
   ```
   **Solution**: Run `setup_ses_email_identity.sh` first

2. **Route53 Hosted Zone Not Found**
   ```
   Error: Could not find Route53 hosted zone
   ```
   **Solution**: Ensure the domain has a Route53 hosted zone

3. **Missing Variables**
   ```
   Error: Required variable not set
   ```
   **Solution**: Check `terraform.tfvars` and ensure all required variables are set

### Verification Steps

1. **Check SES Status**:
   ```bash
   aws ses get-identity-verification-attributes \
     --identities "yourdomain.com" \
     --region us-west-1
   ```

2. **Check Route53 Records**:
   ```bash
   aws route53 list-resource-record-sets \
     --hosted-zone-id YOUR_ZONE_ID
   ```

3. **Check Terraform State**:
   ```bash
   terraform show
   ```

## Security Notes

- **Vercel API Token**: Stored as sensitive variable, never commit to version control
- **Social Provider Secrets**: Store securely, consider using AWS Secrets Manager
- **Route53 Permissions**: Ensure Terraform has permissions to create/modify DNS records

## Next Steps

After successful deployment:

1. **Configure Application Secrets**: Use `scripts/deployment/setup-secrets.sh`
2. **Deploy Microservices**: Use CodeDeploy workflows
3. **Set up Monitoring**: Configure CloudWatch alarms and dashboards
4. **SSL Certificates**: Set up automatic certificate renewal with certbot

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Terraform logs: `terraform logs`
3. Check AWS CloudTrail for API call failures
4. Verify IAM permissions and policies