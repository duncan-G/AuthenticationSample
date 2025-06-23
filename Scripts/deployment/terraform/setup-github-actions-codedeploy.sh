#!/bin/bash

# Setup GitHub Actions CodeDeploy Role
# This script creates the IAM role and policy for GitHub Actions CodeDeploy deployments
# and updates GitHub repository secrets

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/common.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/github-utils.sh"

# Configuration
APP_NAME="authentication-sample"
ENVIRONMENT="staging"
GITHUB_REPOSITORY=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header "GitHub Actions CodeDeploy Role Setup"
echo "This script will:"
echo "  1. Create IAM role and policy for GitHub Actions CodeDeploy deployments"
echo "  2. Update GitHub repository secrets"
echo "  3. Configure OIDC trust relationship"
echo ""

# Get AWS profile
AWS_PROFILE=$(prompt_aws_profile)
export AWS_PROFILE

# Get GitHub repository
GITHUB_REPOSITORY=$(prompt_github_repository)
if [ -z "$GITHUB_REPOSITORY" ]; then
    print_error "GitHub repository is required"
    exit 1
fi

# Get AWS account ID
AWS_ACCOUNT_ID=$(get_aws_account_id)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    print_error "Failed to get AWS account ID"
    exit 1
fi

print_info "AWS Account ID: $AWS_ACCOUNT_ID"
print_info "GitHub Repository: $GITHUB_REPOSITORY"
print_info "App Name: $APP_NAME"
print_info "Environment: $ENVIRONMENT"
echo ""

# Check if GitHub CLI is installed
if ! command_exists gh; then
    print_error "GitHub CLI (gh) is not installed. Please install it first."
    echo "Visit: https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated with GitHub
if ! gh auth status &> /dev/null; then
    print_error "Not authenticated with GitHub CLI. Please run 'gh auth login' first."
    exit 1
fi

# Check if user has access to the repository
if ! gh repo view "$GITHUB_REPOSITORY" &> /dev/null; then
    print_error "No access to repository: $GITHUB_REPOSITORY"
    exit 1
fi

print_success "GitHub authentication verified"
echo ""

# Create Terraform configuration
print_info "Creating Terraform configuration..."

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
# AWS Configuration
region = "$(aws configure get region --profile $AWS_PROFILE)"

# Application Configuration
app_name = "$APP_NAME"
environment = "$ENVIRONMENT"
github_repository = "$GITHUB_REPOSITORY"

# Instance Configuration
public_instance_type = "t4g.micro"
private_instance_type = "t4g.small"
EOF

print_success "Created terraform.tfvars"
echo ""

# Initialize Terraform
print_info "Initializing Terraform..."
terraform init
print_success "Terraform initialized"
echo ""

# Plan Terraform changes
print_info "Planning Terraform changes..."
terraform plan -var-file="terraform.tfvars" -out=tfplan
print_success "Terraform plan created"
echo ""

# Ask for confirmation
echo -e "${YELLOW}Review the plan above and confirm to proceed with creating the resources.${NC}"
read -p "Do you want to apply the Terraform plan? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Operation cancelled"
    exit 0
fi

# Apply Terraform changes
print_info "Applying Terraform changes..."
terraform apply tfplan
print_success "Terraform changes applied"
echo ""

# Get the role ARN
ROLE_ARN=$(terraform output -raw github_actions_codedeploy_role_arn 2>/dev/null || echo "")
if [ -z "$ROLE_ARN" ]; then
    print_error "Failed to get role ARN from Terraform output"
    exit 1
fi

print_info "Role ARN: $ROLE_ARN"
echo ""

# Update GitHub secrets
print_info "Updating GitHub repository secrets..."

# Check existing secrets
existing_secrets=$(gh secret list 2>/dev/null | grep -E "(AWS_ACCOUNT_ID|ECR_REPOSITORY_PREFIX|DEPLOYMENT_BUCKET)" || true)

# Set AWS Account ID secret
if echo "$existing_secrets" | grep -q "AWS_ACCOUNT_ID"; then
    print_info "AWS_ACCOUNT_ID secret already exists, updating..."
    gh secret set AWS_ACCOUNT_ID --body "$AWS_ACCOUNT_ID" 2>/dev/null || true
else
    print_info "Creating AWS_ACCOUNT_ID secret..."
    gh secret set AWS_ACCOUNT_ID --body "$AWS_ACCOUNT_ID"
fi

# Get ECR repository prefix
ECR_REPOSITORY_PREFIX=$(terraform output -raw ecr_repository_prefix 2>/dev/null || echo "${AWS_ACCOUNT_ID}.dkr.ecr.$(aws configure get region --profile $AWS_PROFILE).amazonaws.com")
if [ -n "$ECR_REPOSITORY_PREFIX" ]; then
    if echo "$existing_secrets" | grep -q "ECR_REPOSITORY_PREFIX"; then
        print_info "ECR_REPOSITORY_PREFIX secret already exists, updating..."
        gh secret set ECR_REPOSITORY_PREFIX --body "$ECR_REPOSITORY_PREFIX" 2>/dev/null || true
    else
        print_info "Creating ECR_REPOSITORY_PREFIX secret..."
        gh secret set ECR_REPOSITORY_PREFIX --body "$ECR_REPOSITORY_PREFIX"
    fi
fi

# Get deployment bucket name
DEPLOYMENT_BUCKET=$(terraform output -raw deployment_bucket_name 2>/dev/null || echo "")
if [ -n "$DEPLOYMENT_BUCKET" ]; then
    if echo "$existing_secrets" | grep -q "DEPLOYMENT_BUCKET"; then
        print_info "DEPLOYMENT_BUCKET secret already exists, updating..."
        gh secret set DEPLOYMENT_BUCKET --body "$DEPLOYMENT_BUCKET" 2>/dev/null || true
    else
        print_info "Creating DEPLOYMENT_BUCKET secret..."
        gh secret set DEPLOYMENT_BUCKET --body "$DEPLOYMENT_BUCKET"
    fi
fi

# Set GitHub variables
print_info "Setting GitHub repository variables..."

# Set APP_NAME variable
if gh variable list 2>/dev/null | grep -q "APP_NAME"; then
    print_info "APP_NAME variable already exists, updating..."
    gh variable set APP_NAME --body "$APP_NAME" 2>/dev/null || true
else
    print_info "Creating APP_NAME variable..."
    gh variable set APP_NAME --body "$APP_NAME"
fi

# Set AWS_DEFAULT_REGION variable
AWS_REGION=$(aws configure get region --profile $AWS_PROFILE)
if gh variable list 2>/dev/null | grep -q "AWS_DEFAULT_REGION"; then
    print_info "AWS_DEFAULT_REGION variable already exists, updating..."
    gh variable set AWS_DEFAULT_REGION --body "$AWS_REGION" 2>/dev/null || true
else
    print_info "Creating AWS_DEFAULT_REGION variable..."
    gh variable set AWS_DEFAULT_REGION --body "$AWS_REGION"
fi

print_success "GitHub secrets and variables updated"
echo ""

# Clean up
rm -f tfplan
rm -f terraform.tfvars

# Summary
print_header "Setup Complete"
echo -e "${GREEN}✅ GitHub Actions CodeDeploy Role Setup Complete${NC}"
echo ""
echo "Created Resources:"
echo -e "  ${BLUE}• IAM Role:${NC} $ROLE_ARN"
echo -e "  ${BLUE}• IAM Policy:${NC} ${APP_NAME}-github-actions-codedeploy-policy"
echo -e "  ${BLUE}• OIDC Provider:${NC} ${APP_NAME}-github-actions-codedeploy-oidc"
echo ""
echo "Updated GitHub Repository:"
echo -e "  ${BLUE}• Secrets:${NC} AWS_ACCOUNT_ID, ECR_REPOSITORY_PREFIX, DEPLOYMENT_BUCKET"
echo -e "  ${BLUE}• Variables:${NC} APP_NAME, AWS_DEFAULT_REGION"
echo ""
echo "Next Steps:"
echo "  1. Your GitHub Actions workflows will now use the new CodeDeploy role"
echo "  2. The role has minimal permissions required for CodeDeploy deployments"
echo "  3. Test a deployment to ensure everything works correctly"
echo ""
echo -e "${YELLOW}Note:${NC} The role is scoped to your GitHub repository: $GITHUB_REPOSITORY" 