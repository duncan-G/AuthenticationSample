#!/bin/bash

#########################################
# Interactive Terraform Pipeline Setup
# Automated OIDC authentication setup for GitHub Actions
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/print-utils.sh"
source "$SCRIPT_DIR/prompt-utils.sh"
source "$SCRIPT_DIR/aws-utils.sh"
source "$SCRIPT_DIR/github-utils.sh"

print_header "🚀 Terraform Pipeline Setup Script"

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    
    # Get AWS profile
    prompt_user "Enter AWS profile name" "AWS_PROFILE" "terraform-setup"
    
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

# Function to create OIDC provider
create_oidc_provider() {
    print_info "Creating OIDC provider..."
    
    # Check if OIDC provider already exists
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

# Function to create S3 bucket for Terraform state
create_terraform_state_backend() {
    print_info "Creating S3 bucket for Terraform state backend..."

    # Generate a unique bucket name using a hash of account ID and repo
    BUCKET_HASH=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    BUCKET_NAME="terraform-state-${BUCKET_HASH}"
    
    print_info "Generated bucket name: $BUCKET_NAME"

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

# Function to create IAM policy
create_iam_policy() {
    print_info "Creating IAM policy..."
    
    # Check if policy already exists
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/terraform-github-actions-oidc-policy" &> /dev/null; then
        print_warning "IAM policy already exists, skipping creation"
    else
        # Substitute variables in terraform-policy.json and write to a temp file
        sed \
            -e "s|\${APP_NAME}|$TF_APP_NAME|g" \
            -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
            -e "s|\${BUCKET_NAME}|$BUCKET_NAME|g" \
            terraform-policy.json > terraform-policy-temp.json
        
        aws iam create-policy \
            --profile "$AWS_PROFILE" \
            --policy-name terraform-github-actions-oidc-policy \
            --policy-document file://terraform-policy-temp.json
        print_success "IAM policy created"
    fi
}

# Function to create trust policy
create_trust_policy() {
    print_info "Creating trust policy..."
    
    # Substitute variables in github-trust-policy.json and write to the final file
    sed \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${GITHUB_REPO_FULL}|$GITHUB_REPO_FULL|g" \
        -e "s|\${STAGING_ENVIRONMENT}|$STAGING_ENVIRONMENT|g" \
        -e "s|\${PRODUCTION_ENVIRONMENT}|$PRODUCTION_ENVIRONMENT|g" \
        github-trust-policy.json > github-trust-policy-temp.json
    print_success "Trust policy created"
}

# Function to create IAM role
create_iam_role() {
    print_info "Creating IAM role..."
    
    # Get absolute path to the trust policy file
    TRUST_POLICY_PATH="$(pwd)/github-trust-policy-temp.json"
    
    # Check if role already exists
    if aws iam get-role --profile "$AWS_PROFILE" --role-name github-actions-terraform &> /dev/null; then
        print_warning "IAM role already exists, updating trust policy"
        aws iam update-assume-role-policy \
            --profile "$AWS_PROFILE" \
            --role-name github-actions-terraform \
            --policy-document "file://$TRUST_POLICY_PATH" \
            --no-cli-pager
    else
        aws iam create-role \
            --profile "$AWS_PROFILE" \
            --role-name github-actions-terraform \
            --assume-role-policy-document "file://$TRUST_POLICY_PATH" \
            --no-cli-pager
        print_success "IAM role created"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --profile "$AWS_PROFILE" \
        --role-name github-actions-terraform \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/terraform-github-actions-oidc-policy"
    
    print_success "Policy attached to role"
}

# Function to cleanup temporary files
cleanup() {
    print_info "Cleaning up temporary files..."
    rm -f github-trust-policy-temp.json terraform-policy-temp.json
    print_success "Cleanup completed"
}

# Function to display final instructions
display_final_instructions() {
    echo
    print_success "🎉 Pipeline setup completed successfully!"
    echo
    
    echo
    print_info "Your setup is complete and ready to use!"
    
    echo "Your IAM Role ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-terraform${NC}"
    echo
    echo "Your Terraform State Bucket:"
    echo -e "${GREEN}   $BUCKET_NAME${NC}"
    echo
    print_info "You can now use the GitHub Actions workflow!"
    echo "   • Manual: Actions → 'Terraform Infrastructure' → Run workflow"
    echo "   • Automatic: Pull requests will show terraform plans"
    echo
}

# Main execution
main() {
    check_aws_cli
    check_github_cli

    GITHUB_REPO_FULL=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    validate_repo "$GITHUB_REPO_FULL"

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
    print_info "Starting pipeline setup..."
    
    create_oidc_provider
    create_terraform_state_backend
    create_iam_policy
    create_trust_policy
    create_iam_role
    
    # Create GitHub secrets and environments
    add_github_secrets "$GITHUB_REPO_FULL" \
        "AWS_ACCOUNT_ID:$AWS_ACCOUNT_ID" \
        "TF_STATE_BUCKET:$BUCKET_NAME" \
        "TF_APP_NAME:$TF_APP_NAME"
    
    add_github_variables "$GITHUB_REPO_FULL" \
        "AWS_DEFAULT_REGION:$AWS_REGION"
    
    create_github_environments "$GITHUB_REPO_FULL" \
        "$STAGING_ENVIRONMENT" \
        "$PRODUCTION_ENVIRONMENT"
    
    cleanup
    display_final_instructions
}

# Run main function
main "$@" 