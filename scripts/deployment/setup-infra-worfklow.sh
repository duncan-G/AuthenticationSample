#!/bin/bash

#########################################
# Github Actions workflow setup for Terraform and CodeDeploy.
# Provides github actions with the ability to run terraform plans/apply and deploy to AWS CodeDeploy.
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/github-utils.sh"

print_header "🚀 Terraform Github Actions Workflow Setup Script"

# Hosted zone lookup uses shared utils

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    
    prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "infra-setup"
        
    AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    prompt_user "Enter project name (used for Terraform resource naming)" "PROJECT_NAME"
    prompt_user "Enter AWS region" "AWS_REGION" "us-west-1"
    prompt_user "Enter Terraform stage workspace name" "STAGE_WORKSPACE" "terraform-stage"
    prompt_user "Enter Terraform prod workspace name" "PROD_WORKSPACE" "terraform-prod"
    prompt_user "Enter Terraform dev workspace name" "DEV_WORKSPACE" "terraform-dev"
    prompt_user "Enter runtime stage environment label" "RUNTIME_STAGE_ENV" "stage"
    prompt_user "Enter runtime prod environment label" "RUNTIME_PROD_ENV" "prod"
    prompt_user "Enter runtime dev environment label" "RUNTIME_DEV_ENV" "dev"
    
    prompt_user "Enter backend domain name (e.g., example.com)" "DOMAIN_NAME"
    
    # Prompt for Vercel API key for frontend deployments (optional)
    prompt_user_optional "Enter Vercel API key (for frontend deployments, leave blank to skip)" "VERCEL_API_KEY"
    
    # Get Route53 hosted zone ID automatically
    if ! ROUTE53_HOSTED_ZONE_ID=$(get_route53_hosted_zone_id "$DOMAIN_NAME" "$AWS_PROFILE"); then
        exit 1
    fi
    
    # Calculate bucket suffix using the same logic as elsewhere
    BUCKET_SUFFIX=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)

    print_info "Calculated bucket suffix: $BUCKET_SUFFIX"
    
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo "  Terraform Project Name: $PROJECT_NAME"
    echo "  AWS Region: $AWS_REGION"
    echo "  Terraform Stage Workspace: $STAGE_WORKSPACE"
    echo "  Terraform Prod Workspace: $PROD_WORKSPACE"
    echo "  Runtime Stage Env: $RUNTIME_STAGE_ENV"
    echo "  Runtime Prod Env: $RUNTIME_PROD_ENV"
    echo "  Domain Name: $DOMAIN_NAME"
    echo "  Route53 Hosted Zone ID: $ROUTE53_HOSTED_ZONE_ID"
    if [ -n "${VERCEL_API_KEY}" ]; then
        echo "  Vercel API Key: ${VERCEL_API_KEY:0:8}..."
    else
        echo "  Vercel API Key: (not provided)"
    fi
    
    if ! prompt_confirmation "Do you want to proceed?" "y/N"; then
        print_info "Setup cancelled."
        exit 0
    fi
}

# Function to create S3 bucket for Terraform state
create_terraform_state_bucket() {
    local tf_state_bucket="$1"
    
    print_info "Creating S3 bucket for Terraform state bucket: $tf_state_bucket"

    if ! aws s3api head-bucket --bucket "$tf_state_bucket" --profile "$AWS_PROFILE" 2>/dev/null; then
        aws s3api create-bucket --bucket "$tf_state_bucket" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" --profile "$AWS_PROFILE"
        print_success "S3 bucket $tf_state_bucket created."
    else
        print_warning "S3 bucket $tf_state_bucket already exists."
    fi

    aws s3api put-bucket-versioning --bucket "$tf_state_bucket" --versioning-configuration Status=Enabled --profile "$AWS_PROFILE"
}

# Function to create S3 bucket for CodeDeploy
create_codedeploy_bucket() {
    DEPLOYMENT_BUCKET="${PROJECT_NAME}-codedeploy-${BUCKET_SUFFIX}"
    
    # CodeDeploy bucket lifecycle configuration
    local codedeploy_lifecycle='{
      "Rules": [
        {
          "ID": "deployment_cleanup",
          "Status": "Enabled",
          "Filter": {},
          "NoncurrentVersionExpiration": {
            "NoncurrentDays": 30
          },
          "Expiration": {
            "Days": 90
          }
        }
      ]
    }'
    
    print_info "Creating CodeDeploy bucket..."
    create_s3_bucket_with_lifecycle "$DEPLOYMENT_BUCKET" "$AWS_REGION" "$AWS_PROFILE" "production" "${PROJECT_NAME}-codedeploy" "$codedeploy_lifecycle"
    print_success "CodeDeploy bucket created successfully."
}

setup_oidc_infrastructure() {
    print_info "Setting up OIDC infrastructure (delegated script)..."
    "$SCRIPT_DIR/setup-oidc-infra.sh" \
        --aws-profile "$AWS_PROFILE" \
        --project-name "$PROJECT_NAME" \
        --github-repo "$GITHUB_REPO_FULL" \
        --tf-state-bucket "$TF_STATE_BUCKET" \
        --stage-workspace "$STAGE_WORKSPACE" \
        --prod-workspace "$PROD_WORKSPACE" \
        --dev-workspace "$DEV_WORKSPACE" \
        --bucket-suffix "$BUCKET_SUFFIX"
}

# Function to setup GitHub secrets and environments
setup_github_workflow() {
    print_info "Setting up GitHub secrets and environments..."

    # Base secrets
    add_github_secrets "$GITHUB_REPO_FULL" \
        "AWS_ACCOUNT_ID:$AWS_ACCOUNT_ID" \
        "TF_STATE_BUCKET:$TF_STATE_BUCKET" \
        "ROUTE53_HOSTED_ZONE_ID:$ROUTE53_HOSTED_ZONE_ID" \
        "BUCKET_SUFFIX:$BUCKET_SUFFIX" \
        "EDGE_SHARED_SECRET:$(openssl rand -hex 16)" \
        "DEPLOYMENT_BUCKET:$DEPLOYMENT_BUCKET"

    # Conditionally add Vercel secret only if provided
    if [ -n "${VERCEL_API_KEY}" ]; then
        add_github_secrets "$GITHUB_REPO_FULL" \
            "VERCEL_API_KEY:$VERCEL_API_KEY"
    else
        print_info "Skipping VERCEL_API_KEY secret (not provided)"
    fi
    
    add_github_variables "$GITHUB_REPO_FULL" \
        "AWS_REGION:$AWS_REGION" \
        "PROJECT_NAME:$PROJECT_NAME" \
        "DOMAIN_NAME:$DOMAIN_NAME" \
        "TF_STAGE_WORKSPACE:$STAGE_WORKSPACE" \
        "TF_PROD_WORKSPACE:$PROD_WORKSPACE" \
        "TF_DEV_WORKSPACE:$DEV_WORKSPACE" \
        "RUNTIME_STAGE_ENV:$RUNTIME_STAGE_ENV" \
        "RUNTIME_PROD_ENV:$RUNTIME_PROD_ENV" \
        "RUNTIME_DEV_ENV:$RUNTIME_DEV_ENV"

    create_github_environments "$GITHUB_REPO_FULL" \
        "$STAGE_WORKSPACE" \
        "$PROD_WORKSPACE" \
        "$DEV_WORKSPACE"

    create_github_environments "$GITHUB_REPO_FULL" \
        "$RUNTIME_STAGE_ENV" \
        "$RUNTIME_PROD_ENV" \
        "$RUNTIME_DEV_ENV"
}

# Function to display final instructions
display_final_instructions() {
    print_success "🎉 Terraform and CodeDeploy workflow setup completed successfully!"
    
    print_info "Your setup is complete and ready to use!"
    
    # Calculate ECR repository information
    local ecr_repo_name="${PROJECT_NAME}/certbot"
    local ecr_repo_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ecr_repo_name}"
    
    echo "Your Terraform State Bucket:"
    echo -e "${GREEN}   $TF_STATE_BUCKET${NC}"
    echo "Your Terraform IAM Role ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-terraform${NC}"

    echo "Your ECR Certbot Repository:"
    echo -e "${GREEN}   $ecr_repo_uri${NC}"
    echo "Your Domain Configuration:"
    echo -e "${GREEN}   Domain: $DOMAIN_NAME${NC}"
    echo -e "${GREEN}   Route53 Zone ID: $ROUTE53_HOSTED_ZONE_ID${NC}"
    
    print_info "You can now use the GitHub Actions workflows!"
    echo "   • Terraform: Actions → 'Infrastructure (Release|Debug)' → Run workflow"
    echo "   • CodeDeploy: Actions → 'Authentication Service Deployment' → Run workflow"
    echo "   • Automatic: Pull requests will show terraform plans"
    
    print_info "Next steps:"
    echo "   1. Set up application secrets using setup-secrets.sh"
    echo "   2. Deploy infrastructure using Terraform workflow"
    echo "   3. Use CodeDeploy workflows for application deployments"
}

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo
    echo "This script sets up the complete Terraform and CodeDeploy workflow infrastructure including:"
    echo "  - Variable substitution in policy files"
    echo "  - OIDC provider and IAM roles/policies for Terraform and CodeDeploy"
    echo "  - S3 bucket for Terraform state backend"
    echo "  - ECR repository creation and certbot image building/pushing"
    echo "  - GitHub repository secrets and variables"
    echo "  - GitHub environments for Terraform and CodeDeploy"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate profile"
    echo "  - GitHub CLI authenticated"
    exit 1
}

# Main execution
main() {
    if [ $# -ne 0 ]; then
        show_usage
    fi
    
    check_aws_cli
    check_github_cli

    GITHUB_REPO_FULL=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    if ! validate_repo "$GITHUB_REPO_FULL"; then
        exit 1
    fi

    get_user_input

    if ! check_aws_profile "$AWS_PROFILE"; then
        exit 1
    fi
    
    if ! check_aws_authentication "$AWS_PROFILE"; then
        exit 1
    fi

    validate_aws_region "$AWS_REGION"
    
    print_info "Setting up AWS permissions for Terraform and CodeDeploy deployments..."
    
    TF_STATE_BUCKET="terraform-state-${BUCKET_SUFFIX}"
    create_terraform_state_bucket "$TF_STATE_BUCKET"-dev
    create_terraform_state_bucket "$TF_STATE_BUCKET"-prod
    create_codedeploy_bucket
    setup_oidc_infrastructure
    setup_github_workflow
    
    display_final_instructions
}

# Run main function
main "$@"
