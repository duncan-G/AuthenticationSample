#!/bin/bash

#########################################
# Terraform and CodeDeploy Workflow Cleanup Script
# Provides a user-friendly interface for cleaning up Terraform and CodeDeploy workflow resources
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/github-utils.sh"

print_header "🗑️  Terraform and CodeDeploy Github Actions Workflow Cleanup Script"

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    
    prompt_user "Enter your AWS SSO profile name" "AWS_PROFILE" "infra-setup"

    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    
    print_warning "This will DELETE the following resources:"
    echo "  • IAM Role: github-actions-terraform"
    echo "  • IAM Policy: terraform-github-actions-oidc-policy"
    echo "  • OIDC Provider: token.actions.githubusercontent.com"
    print_warning "S3 Bucket: Terraform state backend (manual deletion required)"
    print_warning "S3 Bucket: CodeDeploy deployment bucket (manual deletion required)"
    print_warning "Github Secrets, Variables and Environments: (manual deletion required)"
    
    if ! prompt_confirmation "Are you sure you want to delete these resources?" "y/N"; then
        print_info "Cleanup cancelled."
        exit 0
    fi
    
    if ! prompt_required_confirmation "Type 'DELETE' to confirm" "DELETE" "This action cannot be undone. Please type 'DELETE' to confirm the deletion of all pipeline resources."; then
        exit 0
    fi
}

# Function to detach policy from role
detach_policy_from_role() {
    local role_name_suffix="$1"
    
    print_info "Detaching policy from IAM role for $role_name_suffix..."
    
    ROLE_NAME="github-actions-${role_name_suffix}"
    POLICY_NAME="github-actions-oidc-policy-${role_name_suffix}"
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    if aws iam get-role --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" &> /dev/null; then
        if aws iam list-attached-role-policies --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" | grep -q "$POLICY_NAME"; then
            aws iam detach-role-policy \
                --profile "$AWS_PROFILE" \
                --role-name "$ROLE_NAME" \
                --policy-arn "$POLICY_ARN"
            print_success "Policy detached from role"
        else
            print_warning "Policy not attached to role, skipping detach"
        fi
    else
        print_warning "Role does not exist, skipping policy detach"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    local role_name_suffix="$1"
    
    print_info "Deleting IAM role for $role_name_suffix..."
    
    ROLE_NAME="github-actions-${role_name_suffix}"
    
    if aws iam get-role --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" &> /dev/null; then
        aws iam delete-role \
            --profile "$AWS_PROFILE" \
            --role-name "$ROLE_NAME"
        print_success "IAM role deleted"
    else
        print_warning "IAM role does not exist, skipping deletion"
    fi
}

# Function to delete IAM policy
delete_iam_policy() {
    local role_name_suffix="$1"
    
    print_info "Deleting IAM policy for $role_name_suffix..."
    
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-${role_name_suffix}"
    
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "$POLICY_ARN" &> /dev/null; then
        print_info "Checking for policy versions..."
        POLICY_VERSIONS=$(aws iam list-policy-versions \
            --profile "$AWS_PROFILE" \
            --policy-arn "$POLICY_ARN" \
            --query 'Versions[?IsDefaultVersion==`false`].VersionId' \
            --output text 2>/dev/null)
        
        if [ -n "$POLICY_VERSIONS" ]; then
            print_info "Found non-default policy versions. Deleting them..."
            for version in $POLICY_VERSIONS; do
                print_info "Deleting policy version: $version"
                aws iam delete-policy-version \
                    --profile "$AWS_PROFILE" \
                    --policy-arn "$POLICY_ARN" \
                    --version-id "$version"
            done
            print_success "All non-default policy versions deleted"
        else
            print_info "No non-default policy versions found"
        fi
        
        aws iam delete-policy \
            --profile "$AWS_PROFILE" \
            --policy-arn "$POLICY_ARN"
        print_success "IAM policy deleted"
    else
        print_warning "IAM policy does not exist, skipping deletion"
    fi
}

# Function to delete OIDC provider
delete_oidc_provider() {
    print_info "Deleting OIDC provider..."
    
    OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    
    if aws iam get-open-id-connect-provider --profile "$AWS_PROFILE" --open-id-connect-provider-arn "$OIDC_ARN" &> /dev/null; then
        aws iam delete-open-id-connect-provider \
            --profile "$AWS_PROFILE" \
            --open-id-connect-provider-arn "$OIDC_ARN"
        print_success "OIDC provider deleted"
    else
        print_warning "OIDC provider does not exist, skipping deletion"
    fi
}

# Function to cleanup OIDC infrastructure
cleanup_oidc_infrastructure() {
    print_info "Cleaning up OIDC infrastructure (delegated script)..."
    "$SCRIPT_DIR/remove-oidc-infrastructure.sh" \
        --aws-profile "$AWS_PROFILE" \
        --aws-account-id "$AWS_ACCOUNT_ID"
}

# Function to provide instructions for S3 bucket cleanup
display_state_bucket_cleanup_instructions() {
    BUCKET_SUFFIX=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    TERRAFORM_BUCKET_NAME="terraform-state-${BUCKET_SUFFIX}"  
    CODE_DEPLOY_BUCKET_NAME="codedeploy-${BUCKET_SUFFIX}"

    print_warning "S3 bucket cleanup is not automated for safety reasons."
    
    print_info "To manually delete the S3 buckets, run these commands:"
    
    echo -e "${YELLOW}# Delete Terraform state bucket:${NC}"
    echo -e "${GREEN}aws s3 rm s3://$TERRAFORM_BUCKET_NAME --recursive --profile $AWS_PROFILE${NC}"
    echo -e "${GREEN}aws s3api delete-bucket --bucket $TERRAFORM_BUCKET_NAME --profile $AWS_PROFILE${NC}"
    
    echo -e "${YELLOW}# Delete CodeDeploy bucket:${NC}"
    echo -e "${GREEN}aws s3 rm s3://$CODE_DEPLOY_BUCKET_NAME --recursive --profile $AWS_PROFILE${NC}"
    echo -e "${GREEN}aws s3api delete-bucket --bucket $CODE_DEPLOY_BUCKET_NAME --profile $AWS_PROFILE${NC}"
    
    print_info "Make sure you have backed up your state or are certain you want to delete it."
    print_info "Note: CodeDeploy bucket is managed by Terraform and will be cleaned up with terraform destroy."
    
    # Certbot ECR and EBS no longer applicable
}

# Function to display final summary
display_final_summary() {
    print_success "🎉 Pipeline cleanup completed successfully!"
    
    print_info "Resources that were processed:"
    echo "  ✅ IAM Role: github-actions-terraform"
    echo "  ✅ IAM Policy: terraform-github-actions-oidc-policy" 
    echo "  ✅ OIDC Provider: token.actions.githubusercontent.com"
    echo "  ℹ️  S3 Buckets: Manual deletion required (see instructions above)"
    echo "     - Terraform state bucket"
    echo "  ℹ️  CodeDeploy bucket: Managed by Terraform"
    # Certbot/EBS resources removed
    
    print_info "Additional cleanup steps:"
    echo "1. Remove GitHub repository secrets:"
    echo "   AWS_ACCOUNT_ID, TF_STATE_BUCKET, PROJECT_NAME, GITHUB_REPOSITORY, EDGE_SHARED_SECRET"
    echo "2. Remove GitHub repository variables:"
    echo "   AWS_REGION"
    echo "3. Remove GitHub environments:"
    echo "   terraform-stage, terraform-prod,"
    echo "   stage, prod"
    
    print_warning "Note: This cleanup does NOT delete your terraform infrastructure."
    print_info "To delete infrastructure, run: terraform destroy"
}

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo
    echo "This script cleans up the complete Terraform and CodeDeploy workflow infrastructure including:"
    echo "  - OIDC provider and IAM roles/policies for Terraform and CodeDeploy"
    echo "  - S3 bucket cleanup instructions for Terraform state and CodeDeploy artifacts"
    echo "  - GitHub repository cleanup instructions for secrets, variables, and environments"
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
    
    check_github_cli

    GITHUB_REPO_FULL=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    validate_repo "$GITHUB_REPO_FULL"

    get_user_input

    check_aws_cli
    
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
    
    print_info "Starting pipeline cleanup..."
    
    cleanup_oidc_infrastructure
    
    display_final_summary
    display_state_bucket_cleanup_instructions
}

# Run main function
main "$@" 