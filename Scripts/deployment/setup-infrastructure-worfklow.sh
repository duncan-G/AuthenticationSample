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

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    
    prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "terraform-setup"
    prompt_user "Enter application name (used for Terraform resource naming)" "TF_APP_NAME"
    prompt_user "Enter AWS region" "AWS_REGION" "us-west-1"
    prompt_user "Enter staging environment name" "STAGING_ENVIRONMENT" "terraform-staging"
    prompt_user "Enter production environment name" "PRODUCTION_ENVIRONMENT" "terraform-production"
    prompt_user "Enter CodeDeploy staging environment name" "CODEDEPLOY_STAGING_ENVIRONMENT" "codedeploy-staging"
    prompt_user "Enter CodeDeploy production environment name" "CODEDEPLOY_PRODUCTION_ENVIRONMENT" "codedeploy-production"
    
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo "  Terraform App Name: $TF_APP_NAME"
    echo "  AWS Region: $AWS_REGION"
    echo "  Terraform Staging Environment: $STAGING_ENVIRONMENT"
    echo "  Terraform Production Environment: $PRODUCTION_ENVIRONMENT"
    echo "  CodeDeploy Staging Environment: $CODEDEPLOY_STAGING_ENVIRONMENT"
    echo "  CodeDeploy Production Environment: $CODEDEPLOY_PRODUCTION_ENVIRONMENT"
    
    if ! prompt_confirmation "Do you want to proceed?" "y/N"; then
        print_info "Setup cancelled."
        exit 0
    fi
}

# Function to create S3 bucket for Terraform state
create_terraform_state_backend() {
    BUCKET_HASH=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    BUCKET_NAME="terraform-state-${BUCKET_HASH}"
    
    print_info "Creating S3 bucket for Terraform state backend: $BUCKET_NAME"

    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" --profile "$AWS_PROFILE"
        print_success "S3 bucket $BUCKET_NAME created."
    else
        print_warning "S3 bucket $BUCKET_NAME already exists."
    fi

    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled --profile "$AWS_PROFILE"
}

create_codedeploy_bucket() {
    BUCKET_HASH=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    BUCKET_NAME="codedeploy-${BUCKET_HASH}"
    
    print_info "Creating S3 bucket for CodeDeploy deployment: $BUCKET_NAME"

    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" --profile "$AWS_PROFILE"
        print_success "S3 bucket $BUCKET_NAME created."
    else
        print_warning "S3 bucket $BUCKET_NAME already exists."
    fi

    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled --profile "$AWS_PROFILE"
}

# Function to create OIDC provider
create_oidc_provider() {
    print_info "Creating OIDC provider..."
    
    if aws iam list-open-id-connect-providers --profile "$AWS_PROFILE" | grep -q "token.actions.githubusercontent.com"; then
        print_warning "OIDC provider already exists, skipping creation"
    else
        aws iam create-open-id-connect-provider \
            --profile "$AWS_PROFILE" \
            --url https://token.actions.githubusercontent.com \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
        print_success "OIDC provider created"
    fi
}

# Function to create IAM policy
create_iam_policy() {
    local policy_file_path="$1"
    
    print_info "Creating IAM policy for Terraform..."
    
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-terraform" &> /dev/null; then
        print_warning "IAM policy already exists, skipping creation"
    else
        aws iam create-policy \
            --profile "$AWS_PROFILE" \
            --policy-name "github-actions-oidc-policy-terraform" \
            --policy-document "file://$policy_file_path"
        print_success "IAM policy created"
    fi
}

# Function to create IAM role
create_iam_role() {
    local trust_policy_file_path="$1"
    
    print_info "Creating IAM role for Terraform..."
    
    if aws iam get-role --profile "$AWS_PROFILE" --role-name "github-actions-terraform" &> /dev/null; then
        print_warning "IAM role already exists, updating trust policy"
        aws iam update-assume-role-policy \
            --profile "$AWS_PROFILE" \
            --role-name "github-actions-terraform" \
            --policy-document "file://$trust_policy_file_path" \
            --no-cli-pager
    else
        aws iam create-role \
            --profile "$AWS_PROFILE" \
            --role-name "github-actions-terraform" \
            --assume-role-policy-document "file://$trust_policy_file_path" \
            --no-cli-pager
        print_success "IAM role created"
    fi
    
    aws iam attach-role-policy \
        --profile "$AWS_PROFILE" \
        --role-name "github-actions-terraform" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-terraform"
    
    print_success "Policy attached to role"
}

# Function to setup OIDC infrastructure
setup_oidc_infrastructure() {
    print_info "Setting up OIDC infrastructure..."
    
    ORIGINAL_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/terraform-policy.json"
    ORIGINAL_TRUST_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/github-trust-policy.json"
    
    PROCESSED_POLICY_FILE_PATH="$(pwd)/terraform-policy-processed.json"
    PROCESSED_TRUST_POLICY_FILE_PATH="$(pwd)/github-trust-policy-processed.json"
    
    print_info "Processing policy files with variable substitution..."
    
    sed \
        -e "s|\${APP_NAME}|$TF_APP_NAME|g" \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${TF_STATE_BUCKET}|$BUCKET_NAME|g" \
        -e "s|\${DEPLOYMENT_BUCKET}|$CODEDEPLOY_BUCKET_NAME|g" \
        "$ORIGINAL_POLICY_FILE_PATH" > "$PROCESSED_POLICY_FILE_PATH"
    
    sed \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${GITHUB_REPO_FULL}|$GITHUB_REPO_FULL|g" \
        -e "s|\${STAGING_ENVIRONMENT}|$STAGING_ENVIRONMENT|g" \
        -e "s|\${PRODUCTION_ENVIRONMENT}|$PRODUCTION_ENVIRONMENT|g" \
        "$ORIGINAL_TRUST_POLICY_FILE_PATH" > "$PROCESSED_TRUST_POLICY_FILE_PATH"
    
    create_oidc_provider
    
    create_iam_policy "$PROCESSED_POLICY_FILE_PATH"
    create_iam_role "$PROCESSED_TRUST_POLICY_FILE_PATH"
    
    rm -f "$PROCESSED_POLICY_FILE_PATH" "$PROCESSED_TRUST_POLICY_FILE_PATH"
}

# Function to setup GitHub secrets and environments
setup_github_workflow() {
    print_info "Setting up GitHub secrets and environments..."

    local hash
    hash=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    CODEDEPLOY_BUCKET_NAME="codedeploy-${hash}"

    add_github_secrets "$GITHUB_REPO_FULL" \
        "AWS_ACCOUNT_ID:$AWS_ACCOUNT_ID" \
        "TF_STATE_BUCKET:$BUCKET_NAME" \
        "TF_APP_NAME:$TF_APP_NAME" \
        "ECR_REPOSITORY_PREFIX:$TF_APP_NAME" \
        "DEPLOYMENT_BUCKET:$CODEDEPLOY_BUCKET_NAME"
    
    add_github_variables "$GITHUB_REPO_FULL" \
        "AWS_DEFAULT_REGION:$AWS_REGION"
    
    create_github_environments "$GITHUB_REPO_FULL" \
        "$STAGING_ENVIRONMENT" \
        "$PRODUCTION_ENVIRONMENT"
    
    create_github_environments "$GITHUB_REPO_FULL" \
        "$CODEDEPLOY_STAGING_ENVIRONMENT" \
        "$CODEDEPLOY_PRODUCTION_ENVIRONMENT"
}

# Function to display final instructions
display_final_instructions() {
    print_success "🎉 Terraform and CodeDeploy workflow setup completed successfully!"
    
    print_info "Your setup is complete and ready to use!"
    
    echo "Your Terraform State Bucket:"
    echo -e "${GREEN}   $BUCKET_NAME${NC}"
    echo "Your CodeDeploy Deployment Bucket:"
    echo -e "${GREEN}   $CODEDEPLOY_BUCKET_NAME${NC}"
    echo "Your Terraform IAM Role ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-terraform${NC}"
    
    print_info "You can now use the GitHub Actions workflows!"
    echo "   • Terraform: Actions → 'Infrastructure Release' → Run workflow"
    echo "   • CodeDeploy: Actions → 'Authentication Service Deployment' → Run workflow"
    echo "   • Automatic: Pull requests will show terraform plans"
    
    print_info "Next steps:"
    echo "   1. Deploy infrastructure using Terraform workflow"
    echo "   2. Use CodeDeploy workflows for application deployments"
}

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo
    echo "This script sets up the complete Terraform and CodeDeploy workflow infrastructure including:"
    echo "  - Variable substitution in policy files"
    echo "  - OIDC provider and IAM roles/policies for Terraform and CodeDeploy"
    echo "  - S3 bucket for Terraform state backend"
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
    
    AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    validate_aws_region "$AWS_REGION"
    
    print_info "Setting up AWS permissions for Terraform and CodeDeploy deployments..."
    
    create_terraform_state_backend
    create_codedeploy_bucket
    setup_oidc_infrastructure
    setup_github_workflow
    
    display_final_instructions
}

# Run main function
main "$@"
