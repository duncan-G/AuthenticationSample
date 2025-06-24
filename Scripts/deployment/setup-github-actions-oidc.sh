#!/bin/bash

#########################################
# Creates OIDC provider and IAM role for Github Actions.
# Used by setup-terraform-workflow.sh and setup-codedeploy-workflow.sh.
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/aws-utils.sh"

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

# Function to create IAM policy
create_iam_policy() {
    print_info "Creating IAM policy..."
    
    # Check if policy already exists
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-${ROLE_NAME_SUFFIX}" &> /dev/null; then
        print_warning "IAM policy already exists, skipping creation"
    else
        aws iam create-policy \
            --profile "$AWS_PROFILE" \
            --policy-name "github-actions-oidc-policy-${ROLE_NAME_SUFFIX}" \
            --policy-document "file://$POLICY_FILE_PATH"
        print_success "IAM policy created"
    fi
}

# Function to create IAM role
create_iam_role() {
    print_info "Creating IAM role..."
    
    # Check if role already exists
    if aws iam get-role --profile "$AWS_PROFILE" --role-name "github-actions-${ROLE_NAME_SUFFIX}" &> /dev/null; then
        print_warning "IAM role already exists, updating trust policy"
        aws iam update-assume-role-policy \
            --profile "$AWS_PROFILE" \
            --role-name "github-actions-${ROLE_NAME_SUFFIX}" \
            --policy-document "file://$TRUST_POLICY_FILE_PATH" \
            --no-cli-pager
    else
        aws iam create-role \
            --profile "$AWS_PROFILE" \
            --role-name "github-actions-${ROLE_NAME_SUFFIX}" \
            --assume-role-policy-document "file://$TRUST_POLICY_FILE_PATH" \
            --no-cli-pager
        print_success "IAM role created"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --profile "$AWS_PROFILE" \
        --role-name "github-actions-${ROLE_NAME_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-${ROLE_NAME_SUFFIX}"
    
    print_success "Policy attached to role"
}

# Main execution
main() {
    # Check arguments
    if [ $# -lt 4 ] || [ $# -gt 5 ]; then
        echo "Usage: $0 <policy_file_path> <trust_policy_file_path> <aws_profile> <role_name_suffix> [skip_aws_check]"
        echo
        echo "Arguments:"
        echo "  policy_file_path      Path to the IAM policy JSON file (with variables already substituted)"
        echo "  trust_policy_file_path Path to the trust policy JSON file (with variables already substituted)"
        echo "  aws_profile           AWS profile name to use"
        echo "  role_name_suffix      Suffix for the IAM role and policy names (e.g., 'terraform' creates 'github-actions-terraform')"
        echo "  skip_aws_check        Optional: Set to 'true' to skip AWS CLI and authentication checks"
        exit 1
    fi
    
    POLICY_FILE_PATH="$1"
    TRUST_POLICY_FILE_PATH="$2"
    AWS_PROFILE="$3"
    ROLE_NAME_SUFFIX="$4"
    SKIP_AWS_CHECK="${5:-false}"
    
    # Validate file paths
    if [ ! -f "$POLICY_FILE_PATH" ]; then
        print_error "Policy file not found: $POLICY_FILE_PATH"
        exit 1
    fi
    
    if [ ! -f "$TRUST_POLICY_FILE_PATH" ]; then
        print_error "Trust policy file not found: $TRUST_POLICY_FILE_PATH"
        exit 1
    fi
    
    # Skip AWS checks if requested
    if [ "$SKIP_AWS_CHECK" != "true" ]; then
        check_aws_cli

        # Check AWS profile and authentication
        if ! check_aws_profile "$AWS_PROFILE"; then
            exit 1
        fi
        
        if ! check_aws_authentication "$AWS_PROFILE"; then
            exit 1
        fi
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    echo
    print_info "Starting OIDC setup..."
    
    create_oidc_provider
    create_iam_policy
    create_iam_role
}

# Run main function
main "$@" 