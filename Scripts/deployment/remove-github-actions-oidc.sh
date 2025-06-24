#!/bin/bash

#########################################
# Deletes permissions for GitHub Actions to access AWS resources
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/aws-utils.sh"

# Function to detach policy from role
detach_policy_from_role() {
    print_info "Detaching policy from IAM role..."
    
    ROLE_NAME="github-actions-${ROLE_NAME_SUFFIX}"
    POLICY_NAME="github-actions-oidc-policy-${ROLE_NAME_SUFFIX}"
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    echo
    
    # Check if role exists and has policy attached
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
    print_info "Deleting IAM role..."
    
    ROLE_NAME="github-actions-${ROLE_NAME_SUFFIX}"
    
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
    print_info "Deleting IAM policy..."
    
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-${ROLE_NAME_SUFFIX}"
    
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "$POLICY_ARN" &> /dev/null; then
        # Get all policy versions
        print_info "Checking for policy versions..."
        POLICY_VERSIONS=$(aws iam list-policy-versions \
            --profile "$AWS_PROFILE" \
            --policy-arn "$POLICY_ARN" \
            --query 'Versions[?IsDefaultVersion==`false`].VersionId' \
            --output text 2>/dev/null)
        
        # Delete non-default versions
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
        
        # Now delete the policy
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

# Main execution
main() {
    # Check arguments
    if [ $# -lt 3 ] || [ $# -gt 4 ]; then
        echo "Usage: $0 <aws_profile> <role_name_suffix> <aws_account_id> [skip_aws_check]"
        echo
        echo "Arguments:"
        echo "  aws_profile           AWS profile name to use"
        echo "  role_name_suffix      Suffix for the IAM role and policy names (e.g., 'terraform' creates 'github-actions-terraform')"
        echo "  aws_account_id        AWS account ID"
        echo "  skip_aws_check        Optional: Set to 'true' to skip AWS CLI and authentication checks"
        exit 1
    fi
    
    AWS_PROFILE="$1"
    ROLE_NAME_SUFFIX="$2"
    AWS_ACCOUNT_ID="$3"
    SKIP_AWS_CHECK="${4:-false}"
    
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
    
    echo
    print_info "Starting pipeline cleanup..."
    
    detach_policy_from_role
    delete_iam_role
    delete_iam_policy
    delete_oidc_provider
}

# Run main function
main "$@" 