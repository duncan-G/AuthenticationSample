#!/bin/bash

#########################################
# Remove GitHub Actions OIDC infrastructure in AWS
# - Detach and delete IAM policy and role used by GitHub Actions
# - Delete the OIDC provider for token.actions.githubusercontent.com
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/common.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/prompt.sh"

print_header "🧹 Removing GitHub Actions OIDC infrastructure"

# -----------------------------------------------------------------------------
# Args & defaults
# -----------------------------------------------------------------------------
AWS_PROFILE=""
AWS_ACCOUNT_ID=""
FORCE=false

usage() {
    cat <<USAGE
Usage: $0 \
  --aws-profile PROFILE \
  [--aws-account-id ACCOUNT_ID] \
  [--force]

Notes:
- If --aws-account-id is omitted, it will be resolved from the provided profile
- Use --force to skip interactive confirmation
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --aws-profile) AWS_PROFILE="$2"; shift 2 ;;
        --aws-account-id) AWS_ACCOUNT_ID="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        -h|--help) usage ;;
        *) print_error "Unknown argument: $1"; usage ;;
    esac
done

# -----------------------------------------------------------------------------
# Prompt for missing inputs and confirm
# -----------------------------------------------------------------------------
prompt_for_missing() {
    if [ -z "$AWS_PROFILE" ]; then
        prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "infra-setup"
    fi

    if [ -z "$AWS_ACCOUNT_ID" ]; then
        AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    fi

    if [ "$FORCE" != true ]; then
        print_warning "This will DELETE the following resources:"
        echo "  • IAM Role: github-actions-terraform"
        echo "  • IAM Policy: github-actions-oidc-policy-terraform"
        echo "  • OIDC Provider: token.actions.githubusercontent.com"
        if ! prompt_confirmation "Are you sure you want to proceed?" "y/N"; then
            print_info "Operation cancelled."
            exit 0
        fi
        if ! prompt_required_confirmation "Type 'DELETE' to confirm" "DELETE" "This action cannot be undone."; then
            exit 0
        fi
    fi
}

prompt_for_missing

# -----------------------------------------------------------------------------
# Impl
# -----------------------------------------------------------------------------
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

delete_iam_policy() {
    local role_name_suffix="$1"
    print_info "Deleting IAM policy for $role_name_suffix..."
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-${role_name_suffix}"
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "$POLICY_ARN" &> /dev/null; then
        POLICY_VERSIONS=$(aws iam list-policy-versions \
            --profile "$AWS_PROFILE" \
            --policy-arn "$POLICY_ARN" \
            --query 'Versions[?IsDefaultVersion==`false`].VersionId' \
            --output text 2>/dev/null)
        if [ -n "$POLICY_VERSIONS" ]; then
            for version in $POLICY_VERSIONS; do
                aws iam delete-policy-version \
                    --profile "$AWS_PROFILE" \
                    --policy-arn "$POLICY_ARN" \
                    --version-id "$version"
            done
        fi
        aws iam delete-policy \
            --profile "$AWS_PROFILE" \
            --policy-arn "$POLICY_ARN"
        print_success "IAM policy deleted"
    else
        print_warning "IAM policy does not exist, skipping deletion"
    fi
}

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

print_info "Cleaning up OIDC infrastructure..."
detach_policy_from_role "terraform"
delete_iam_role "terraform"
delete_iam_policy "terraform"
delete_oidc_provider

print_success "✅ OIDC infrastructure removal completed"


