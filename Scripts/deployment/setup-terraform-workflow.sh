#!/bin/bash

#########################################
# Github Actions workflow setup for Terraform.
# Provides github actions with the ability to run terraform plans and apply changes to AWS.
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
    
    # Get AWS profile
    prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "terraform-setup"
    
    # Get app name for Terraform resource naming
    prompt_user "Enter application name (used for Terraform resource naming)" "TF_APP_NAME"
    
    # Get AWS region
    prompt_user "Enter AWS region" "AWS_REGION" "us-west-1"
    
    # Get environment names
    prompt_user "Enter staging environment name" "STAGING_ENVIRONMENT" "terraform-staging"
    prompt_user "Enter production environment name" "PRODUCTION_ENVIRONMENT" "terraform-production"
    
    echo
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo "  Terraform App Name: $TF_APP_NAME"
    echo "  AWS Region: $AWS_REGION"
    echo "  Staging Environment: $STAGING_ENVIRONMENT"
    echo "  Production Environment: $PRODUCTION_ENVIRONMENT"
    echo
    
    if ! prompt_confirmation "Do you want to proceed?" "y/N"; then
        print_info "Setup cancelled."
        exit 0
    fi
}

# Function to create S3 bucket for Terraform state
create_terraform_state_backend() {
    # Generate a unique bucket name using a hash of account ID and repo
    BUCKET_HASH=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    BUCKET_NAME="terraform-state-${BUCKET_HASH}"
    
    print_info "Creating S3 bucket for Terraform state backend: $BUCKET_NAME"

    # Create S3 bucket if it doesn't exist
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" --profile "$AWS_PROFILE"
        print_success "S3 bucket $BUCKET_NAME created."
    else
        print_warning "S3 bucket $BUCKET_NAME already exists."
    fi

    # Enable versioning on the bucket
    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled --profile "$AWS_PROFILE"
}

# Function to setup OIDC infrastructure
setup_oidc_infrastructure() {
    print_info "Setting up OIDC infrastructure..."
    
    # Get the paths to the original policy files
    ORIGINAL_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/terraform-policy.json"
    ORIGINAL_TRUST_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/github-trust-policy.json"
    
    # Create processed policy files with variables substituted
    PROCESSED_POLICY_FILE_PATH="$(pwd)/terraform-policy-processed.json"
    PROCESSED_TRUST_POLICY_FILE_PATH="$(pwd)/github-trust-policy-processed.json"
    
    print_info "Processing policy files with variable substitution..."
    
    # Substitute variables in terraform-policy.json
    sed \
        -e "s|\${APP_NAME}|$TF_APP_NAME|g" \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${BUCKET_NAME}|$BUCKET_NAME|g" \
        "$ORIGINAL_POLICY_FILE_PATH" > "$PROCESSED_POLICY_FILE_PATH"
    
    # Substitute variables in github-trust-policy.json
    sed \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${GITHUB_REPO_FULL}|$GITHUB_REPO_FULL|g" \
        -e "s|\${STAGING_ENVIRONMENT}|$STAGING_ENVIRONMENT|g" \
        -e "s|\${PRODUCTION_ENVIRONMENT}|$PRODUCTION_ENVIRONMENT|g" \
        "$ORIGINAL_TRUST_POLICY_FILE_PATH" > "$PROCESSED_TRUST_POLICY_FILE_PATH"
    
    # Call the OIDC setup script with processed files and parameters
    "$SCRIPT_DIR/setup-github-actions-oidc.sh" "$PROCESSED_POLICY_FILE_PATH" "$PROCESSED_TRUST_POLICY_FILE_PATH" "$AWS_PROFILE" "terraform" "true"
    
    # Clean up processed files
    rm -f "$PROCESSED_POLICY_FILE_PATH" "$PROCESSED_TRUST_POLICY_FILE_PATH"
}

# Function to setup GitHub secrets and environments
setup_github_workflow() {
    print_info "Setting up GitHub secrets and environments..."

    # Create GitHub secrets
    add_github_secrets "$GITHUB_REPO_FULL" \
        "AWS_ACCOUNT_ID:$AWS_ACCOUNT_ID" \
        "TF_STATE_BUCKET:$BUCKET_NAME" \
        "TF_APP_NAME:$TF_APP_NAME"
    
    # Create GitHub variables
    add_github_variables "$GITHUB_REPO_FULL" \
        "AWS_DEFAULT_REGION:$AWS_REGION"
    
    # Create GitHub environments
    create_github_environments "$GITHUB_REPO_FULL" \
        "$STAGING_ENVIRONMENT" \
        "$PRODUCTION_ENVIRONMENT"
}

# Function to display final instructions
display_final_instructions() {
    echo
    print_success "🎉 Terraform workflow setup completed successfully!"
    echo
    
    echo
    print_info "Your setup is complete and ready to use!"
    
    echo "Your Terraform State Bucket:"
    echo -e "${GREEN}   $BUCKET_NAME${NC}"
    echo
    echo "Your IAM Role ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-terraform${NC}"
    echo
    echo "Your IAM Policy ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-terraform${NC}"
    echo
    print_info "You can now use the GitHub Actions workflow!"
    echo "   • Manual: Actions → 'Terraform Infrastructure' → Run workflow"
    echo "   • Automatic: Pull requests will show terraform plans"
    echo
}

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo
    echo "This script sets up the complete Terraform workflow infrastructure including:"
    echo "  - Variable substitution in policy files"
    echo "  - OIDC provider and IAM roles/policies"
    echo "  - S3 bucket for Terraform state backend"
    echo "  - GitHub repository secrets and variables"
    echo "  - GitHub environments for staging and production"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate profile"
    echo "  - GitHub CLI authenticated"
    echo
    echo "Note: This script processes the original JSON files with variable substitution"
    echo "and then calls the OIDC setup script with the processed files."
    exit 1
}

# Main execution
main() {
    # Check arguments
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

    # Check AWS profile and authentication
    if ! check_aws_profile "$AWS_PROFILE"; then
        exit 1
    fi
    
    if ! check_aws_authentication "$AWS_PROFILE"; then
        exit 1
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Validate AWS region
    validate_aws_region "$AWS_REGION"
    
    echo
    print_info "Setting up AWS permissions for Terraform deployments..."
    
    create_terraform_state_backend
    setup_oidc_infrastructure
    setup_github_workflow
    
    display_final_instructions
}

# Run main function
main "$@"
