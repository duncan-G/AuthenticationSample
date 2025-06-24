#!/bin/bash

#########################################
# Terraform Workflow Cleanup Script
# Provides a user-friendly interface for cleaning up Terraform workflow resources
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/github-utils.sh"

print_header "🗑️  Terraform Github Actions Workflow Cleanup Script"

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    echo
    
    # Get AWS profile name
    prompt_user "Enter your AWS SSO profile name" "AWS_PROFILE" "terraform-setup"

    echo
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo
    
    print_warning "This will DELETE the following resources:"
    echo "  • IAM Role: github-actions-terraform"
    echo "  • IAM Policy: terraform-github-actions-oidc-policy"
    echo "  • OIDC Provider: token.actions.githubusercontent.com"
    echo
    print_warning "S3 Bucket: Terraform state backend (manual deletion required)"
    print_warning "Github Secrets, Variables and Environments: (manual deletion required)"
    echo
    
    if ! prompt_confirmation "Are you sure you want to delete these resources?" "y/N"; then
        print_info "Cleanup cancelled."
        exit 0
    fi
    
    if ! prompt_required_confirmation "Type 'DELETE' to confirm" "DELETE" "This action cannot be undone. Please type 'DELETE' to confirm the deletion of all pipeline resources."; then
        exit 0
    fi
}

# Function to provide instructions for S3 bucket cleanup
display_state_bucket_cleanup_instructions() {
    # Recalculate the bucket name using the same logic as setup script
    BUCKET_HASH=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    BUCKET_NAME="terraform-state-${BUCKET_HASH}"

    echo
    print_warning "S3 bucket cleanup is not automated for safety reasons."
    echo
    print_info "To manually delete the S3 bucket, run these commands:"
    echo
    echo -e "${YELLOW}# Delete all objects in the bucket:${NC}"
    echo -e "${GREEN}aws s3 rm s3://$BUCKET_NAME --recursive --profile $AWS_PROFILE${NC}"
    echo
    echo -e "${YELLOW}# Delete the bucket:${NC}"
    echo -e "${GREEN}aws s3api delete-bucket --bucket $BUCKET_NAME --profile $AWS_PROFILE${NC}"
    echo
    print_warning "⚠️  WARNING: This will permanently delete your Terraform state!"
    print_info "Make sure you have backed up your state or are certain you want to delete it."
    echo
}

# Function to display final summary
display_final_summary() {
    echo
    print_success "🎉 Pipeline cleanup completed successfully!"
    echo
    print_info "Resources that were processed:"
    echo "  ✅ IAM Role: github-actions-terraform"
    echo "  ✅ IAM Policy: terraform-github-actions-oidc-policy"
    echo "  ✅ OIDC Provider: token.actions.githubusercontent.com"
    echo "  ℹ️  S3 Bucket: Manual deletion required (see instructions above)"
    echo
    print_info "Additional cleanup steps:"
    echo "1. Remove the AWS_ACCOUNT_ID secret from your GitHub repository:"
    echo "   Settings → Secrets and variables → Actions → Delete 'AWS_ACCOUNT_ID'"
    echo
    echo "2. Remove the TF_STATE_BUCKET secret from your GitHub repository:"
    echo "   Settings → Secrets and variables → Actions → Delete 'TF_STATE_BUCKET'"
    echo
    echo "3. Remove the TF_APP_NAME secret from your GitHub repository:"
    echo "   Settings → Secrets and variables → Actions → Delete 'TF_APP_NAME'"
    echo
    echo "4. Remove the AWS_DEFAULT_REGION variable from your GitHub repository:"
    echo "   Settings → Secrets and variables → Actions → Variables → Delete 'AWS_DEFAULT_REGION'"
    echo
    echo "5. Remove the Staging and Production environments from your GitHub repository:"
    echo "   Settings → Environments → Staging → Delete"
    echo "   Settings → Environments → Production → Delete"
    echo
    echo "6. Your GitHub Actions workflow will no longer work until you:"
    echo "   • Run setup-github-actions-oidc.sh again, OR"
    echo "   • Set up AWS permissions in AWS Dashboard"
    echo
    print_warning "Note: This cleanup does NOT delete your terraform infrastructure."
    print_info "To delete infrastructure, run: terraform destroy"
    echo
}

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo
    echo "This script cleans up the complete Terraform workflow infrastructure including:"
    echo "  - OIDC provider and IAM roles/policies"
    echo "  - S3 bucket cleanup instructions"
    echo "  - GitHub repository cleanup instructions"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate profile"
    echo "  - GitHub CLI authenticated"
    exit 1
}

# Main execution
main() {
    # Check arguments
    if [ $# -ne 0 ]; then
        show_usage
    fi
    
    check_github_cli

    GITHUB_REPO_FULL=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    validate_repo "$GITHUB_REPO_FULL"

    get_user_input

    # Check AWS profile and authentication
    check_aws_cli
    
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
    print_info "Starting pipeline cleanup..."
    
    # Call the shared cleanup script with skip_aws_check=true since we already did the checks
    "$SCRIPT_DIR/remove-github-actions-oidc.sh" "$AWS_PROFILE" "terraform" "$AWS_ACCOUNT_ID" "true"
    
    display_final_summary
    display_state_bucket_cleanup_instructions
}

# Run main function
main "$@" 