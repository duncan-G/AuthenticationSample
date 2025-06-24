#!/bin/bash

#########################################
# Github Actions workflow setup for CodeDeploy.
# Provides github actions with the ability to deploy to AWS Codedeploy.
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/github-utils.sh"

print_header "🚀 CodeDeploy Workflow Setup Script"

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    
    # Get AWS profile
    prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "terraform-setup"
    
    # Get app name for resource naming
    prompt_user "Enter application name (used for image repository and resource naming)" "APP_NAME"
    
    # Get environment names
    prompt_user "Enter staging environment name" "STAGING_ENVIRONMENT" "codedeploy-staging"
    prompt_user "Enter production environment name" "PRODUCTION_ENVIRONMENT" "codedeploy-production"
    
    echo
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo "  App Name: $APP_NAME"
    echo "  Staging Environment: $STAGING_ENVIRONMENT"
    echo "  Production Environment: $PRODUCTION_ENVIRONMENT"
    echo
    
    if ! prompt_confirmation "Do you want to proceed?" "y/N"; then
        print_info "Setup cancelled."
        exit 0
    fi
}

# Function to setup OIDC infrastructure
setup_oidc_infrastructure() {
    print_info "Setting up OIDC infrastructure..."
    
    # Get the paths to the original policy files
    ORIGINAL_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/codedeploy-policy.json"
    ORIGINAL_TRUST_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/github-trust-policy.json"
    
    # Create processed policy files with variables substituted
    PROCESSED_POLICY_FILE_PATH="$(pwd)/codedeploy-policy-processed.json"
    PROCESSED_TRUST_POLICY_FILE_PATH="$(pwd)/github-trust-policy-processed.json"
    
    print_info "Processing policy files with variable substitution..."
    
    # Substitute variables in codedeploy-policy.json
    local hash
    hash=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    BUCKET_NAME="codedeploy-${hash}"
    sed \
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
    "$SCRIPT_DIR/setup-github-actions-oidc.sh" "$PROCESSED_POLICY_FILE_PATH" "$PROCESSED_TRUST_POLICY_FILE_PATH" "$AWS_PROFILE" "codedeploy" "true"
    
    # Clean up processed files
    rm -f "$PROCESSED_POLICY_FILE_PATH" "$PROCESSED_TRUST_POLICY_FILE_PATH"
}

# Function to setup GitHub secrets and environments
setup_github_workflow() {
    print_info "Setting up GitHub secrets and environments..."
    
    # Create GitHub secrets
    add_github_secrets "$GITHUB_REPO_FULL" \
        "AWS_ACCOUNT_ID:$AWS_ACCOUNT_ID" \
        "ECR_REPOSITORY_PREFIX:$APP_NAME" \
        "DEPLOYMENT_BUCKET:$BUCKET_NAME"
    
    # Create GitHub environments
    create_github_environments "$GITHUB_REPO_FULL" \
        "$STAGING_ENVIRONMENT" \
        "$PRODUCTION_ENVIRONMENT"
}

# Function to display final instructions
display_final_instructions() {
    echo
    print_success "🎉 CodeDeploy workflow setup completed successfully!"
    echo
    
    echo
    print_info "Your setup is complete and ready to use!"
    
    echo "Your IAM Role ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-${APP_NAME}${NC}"
    echo
    echo "Your IAM Policy ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-${APP_NAME}${NC}"
    echo
    print_info "You can now use the GitHub Actions workflow for CodeDeploy deployments!"
    echo "   • Manual: Actions → 'CodeDeploy Deployment' → Run workflow"
    echo "   • Automatic: Push to main branch or create releases"
    echo
    print_info "Example GitHub Actions usage:"
    echo "  - name: Configure AWS credentials"
    echo "    uses: aws-actions/configure-aws-credentials@v4"
    echo "    with:"
    echo "      role-to-assume: \${{ secrets.AWS_ROLE_ARN }}"
    echo "      aws-region: \${{ vars.AWS_DEFAULT_REGION }}"
    echo
}

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo
    echo "This script sets up the complete CodeDeploy workflow infrastructure including:"
    echo "  - Variable substitution in policy files"
    echo "  - OIDC provider and IAM roles/policies for CodeDeploy"
    echo "  - GitHub repository secrets and variables"
    echo "  - GitHub environments for staging and production"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate profile"
    echo "  - GitHub CLI authenticated"
    echo
    echo "Note: This script processes the original JSON files with variable substitution"
    echo "and then calls the CodeDeploy OIDC setup script with the processed files."
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
    
    echo
    print_info "Starting CodeDeploy workflow setup..."
    
    setup_oidc_infrastructure
    setup_github_workflow
    display_final_instructions
}

# Run main function
main "$@"
