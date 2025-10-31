#!/bin/bash

#########################################
# Setup GitHub Actions OIDC infrastructure in AWS
# - Creates OIDC provider (token.actions.githubusercontent.com)
# - Creates IAM policy for Terraform + CodeDeploy buckets
# - Creates/updates IAM role trust policy for GitHub Actions (stage/prod)
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/common.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/prompt.sh"

print_header "🔐 Setting up GitHub Actions OIDC infrastructure"

# -----------------------------------------------------------------------------
# Args & defaults
# -----------------------------------------------------------------------------
AWS_PROFILE=""
AWS_ACCOUNT_ID=""
PROJECT_NAME=""
GITHUB_REPO_FULL=""
TF_STATE_BUCKET=""
TERRAFORM_DEV_ENV=""
TERRAFORM_STAGE_ENV=""
TERRAFORM_PROD_ENV=""
RUNTIME_STAGE_ENV=""
RUNTIME_PROD_ENV=""
BUCKET_SUFFIX=""

usage() {
    cat <<USAGE
Usage: $0 \
  --aws-profile PROFILE \
  --project-name NAME \
  --github-repo OWNER/REPO \
  --tf-state-bucket BUCKET \
  [--aws-account-id ACCOUNT_ID] \
  [--stage-workspace NAME] \
  [--prod-workspace NAME] \
  [--bucket-suffix SUFFIX]

Notes:
- If --aws-account-id is omitted, it will be resolved from the provided profile
- If --bucket-suffix is omitted, it will be derived from ACCOUNT_ID and OWNER/REPO
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --aws-profile) AWS_PROFILE="$2"; shift 2 ;;
        --aws-account-id) AWS_ACCOUNT_ID="$2"; shift 2 ;;
        --project-name) PROJECT_NAME="$2"; shift 2 ;;
        --github-repo) GITHUB_REPO_FULL="$2"; shift 2 ;;
        --tf-state-bucket) TF_STATE_BUCKET="$2"; shift 2 ;;
        --terraform-dev-env) TERRAFORM_DEV_ENV="$2"; shift 2 ;;
        --terraform-stage-env) TERRAFORM_STAGE_ENV="$2"; shift 2 ;;
        --terraform-prod-env) TERRAFORM_PROD_ENV="$2"; shift 2 ;;
        --runtime-stage-env) RUNTIME_STAGE_ENV="$2"; shift 2 ;;
        --runtime-prod-env) RUNTIME_PROD_ENV="$2"; shift 2 ;;
        --bucket-suffix) BUCKET_SUFFIX="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) print_error "Unknown argument: $1"; usage ;;
    esac
done

# -----------------------------------------------------------------------------
# Prompt for missing inputs and derive values
# -----------------------------------------------------------------------------
prompt_for_missing() {
    if [ -z "$AWS_PROFILE" ]; then
        prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "infra-setup"
    fi

    if [ -z "$PROJECT_NAME" ]; then
        prompt_user "Enter project name (used for resource naming)" "PROJECT_NAME"
    fi

    if [ -z "$GITHUB_REPO_FULL" ]; then
        if command_exists gh && gh auth status &> /dev/null; then
            GITHUB_REPO_FULL=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
        fi
        if [ -z "$GITHUB_REPO_FULL" ]; then
            prompt_user "Enter GitHub repository (owner/repo)" "GITHUB_REPO_FULL"
        else
            print_info "Detected GitHub repository: $GITHUB_REPO_FULL"
        fi
    fi

    if [ -z "$AWS_ACCOUNT_ID" ]; then
        AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    fi

    if [ -z "$TERRAFORM_DEV_ENV" ]; then TERRAFORM_DEV_ENV="terraform-dev"; fi
    if [ -z "$TERRAFORM_STAGE_ENV" ]; then TERRAFORM_STAGE_ENV="terraform-stage"; fi
    if [ -z "$TERRAFORM_PROD_ENV" ]; then TERRAFORM_PROD_ENV="terraform-prod"; fi
    if [ -z "$RUNTIME_STAGE_ENV" ]; then RUNTIME_STAGE_ENV="stage"; fi
    if [ -z "$RUNTIME_PROD_ENV" ]; then RUNTIME_PROD_ENV="prod"; fi

    if [ -z "$BUCKET_SUFFIX" ]; then
        BUCKET_SUFFIX=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
    fi

    if [ -z "$TF_STATE_BUCKET" ]; then
        local default_tf_bucket="terraform-state-${BUCKET_SUFFIX}"
        prompt_user "Enter Terraform state S3 bucket" "TF_STATE_BUCKET" "$default_tf_bucket"
    fi
}

prompt_for_missing

DEPLOYMENT_BUCKET="${PROJECT_NAME}-codedeploy-${BUCKET_SUFFIX}"

ORIGINAL_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../infrastructure/terraform" && pwd)/terraform-policy.json"
ORIGINAL_TRUST_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../infrastructure/terraform" && pwd)/terraform-github-trust-policy.json"

PROCESSED_POLICY_FILE_PATH=$(mktemp)
PROCESSED_TRUST_POLICY_FILE_PATH=$(mktemp)

# -----------------------------------------------------------------------------
# Impl
# -----------------------------------------------------------------------------
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

process_policy_files() {
    print_info "Processing policy files with variable substitution..."

    sed \
        -e "s|\${PROJECT_NAME}|$PROJECT_NAME|g" \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${TF_STATE_BUCKET}|$TF_STATE_BUCKET|g" \
        -e "s|\${DEPLOYMENT_BUCKET}|$DEPLOYMENT_BUCKET|g" \
        "$ORIGINAL_POLICY_FILE_PATH" > "$PROCESSED_POLICY_FILE_PATH"

    sed \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${GITHUB_REPO_FULL}|$GITHUB_REPO_FULL|g" \
        -e "s|\${TERRAFORM_DEV_ENV}|$TERRAFORM_DEV_ENV|g" \
        -e "s|\${TERRAFORM_STAGE_ENV}|$TERRAFORM_STAGE_ENV|g" \
        -e "s|\${TERRAFORM_PROD_ENV}|$TERRAFORM_PROD_ENV|g" \
        -e "s|\${RUNTIME_STAGE_ENV}|$RUNTIME_STAGE_ENV|g" \
        -e "s|\${RUNTIME_PROD_ENV}|$RUNTIME_PROD_ENV|g" \
        "$ORIGINAL_TRUST_POLICY_FILE_PATH" > "$PROCESSED_TRUST_POLICY_FILE_PATH"
}

cleanup() {
    rm -f "$PROCESSED_POLICY_FILE_PATH" "$PROCESSED_TRUST_POLICY_FILE_PATH" || true
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------

check_aws_cli
if ! check_aws_profile "$AWS_PROFILE"; then exit 1; fi
if ! check_aws_authentication "$AWS_PROFILE"; then exit 1; fi

process_policy_files
create_oidc_provider
create_iam_policy "$PROCESSED_POLICY_FILE_PATH"
create_iam_role "$PROCESSED_TRUST_POLICY_FILE_PATH"

print_success "✅ OIDC infrastructure setup completed"


