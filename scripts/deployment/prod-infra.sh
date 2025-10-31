#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$SCRIPT_DIR/../utils"

source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/common.sh"
source "$UTILS_DIR/github-utils.sh"

########################################
# Args & usage
########################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [--action plan|deploy|destroy] [--env prod|stage] [--multi-az]

Options:
  -a, --action    Action to perform (plan|deploy|destroy). Default: plan
  -e, --env       Target environment for variables (prod|stage). Default: stage
      --multi-az  Enable multi-az state/workspace prefix. Default: single-az
  -h, --help      Show this help message
EOF
}

ACTION="plan"
ENVIRONMENT="stage"   # maps to TF_VAR_env and workspace suffix
MULTI_AZ="false"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--action)
        if [[ $# -lt 2 ]]; then
          print_error "Missing value for $1"
          usage
          exit 1
        fi
        ACTION="$2"
        shift 2
        ;;
      --action=*)
        ACTION="${1#*=}"
        shift 1
        ;;
      -e|--env)
        if [[ $# -lt 2 ]]; then
          print_error "Missing value for $1"
          usage
          exit 1
        fi
        ENVIRONMENT="$2"
        shift 2
        ;;
      --env=*)
        ENVIRONMENT="${1#*=}"
        shift 1
        ;;
      --multi-az)
        MULTI_AZ="true"
        shift 1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        print_error "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  case "$ACTION" in
    plan|deploy|destroy) ;;
    *)
      print_error "Invalid --action: $ACTION (expected plan|deploy|destroy)"
      usage
      exit 1
      ;;
  esac

  case "$ENVIRONMENT" in
    prod|stage) ;;
    *)
      print_error "Invalid --env: $ENVIRONMENT (expected prod|stage)"
      usage
      exit 1
      ;;
  esac
}

########################################
# Inputs & helpers
########################################
detect_github_repo() {
  # Try gh first
  if command_exists gh && gh auth status &>/dev/null; then
    local name
    if name=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); then
      printf '%s\n' "$name"
      return 0
    fi
  fi
  # Fallback to git remote
  if command_exists git; then
    local remote
    if remote=$(git config --get remote.origin.url 2>/dev/null); then
      # Handle https and ssh forms
      remote=${remote%.git}
      if [[ "$remote" =~ ^https?://[^/]+/(.+/.+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
      elif [[ "$remote" =~ ^git@[^:]+:(.+/.+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
      fi
    fi
  fi
  return 1
}

get_user_input() {
  prompt_user "Enter AWS profile" "AWS_PROFILE" "github-terraform"
  prompt_user "Enter project name" "PROJECT_NAME"
  prompt_user "Enter AWS region" "AWS_REGION" "us-west-1"

  # Auto-detect GitHub repo (no override)
  if command_exists gh && gh auth status &>/dev/null; then
    GITHUB_REPO_FULL=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  else
    if ! GITHUB_REPO_FULL=$(detect_github_repo 2>/dev/null); then
      print_error "Unable to determine GitHub repository. Ensure GitHub CLI is authenticated or 'git remote origin' is configured."
      exit 1
    fi
  fi

  # Validate repository access
  if ! validate_repo "$GITHUB_REPO_FULL"; then
    exit 1
  fi

  prompt_user "Enter domain name (e.g. example.com)" "DOMAIN_NAME"
  prompt_user "Enter Vercel API token" "VERCEL_API_KEY"
}

bucket_exists() {
  local bucket="$1"
  aws s3api head-bucket --bucket "$bucket" --profile "$AWS_PROFILE" 2>/dev/null
}

########################################
# Validation
########################################
check_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    print_error "Terraform is not installed or not on PATH."
    exit 1
  fi
}

validate_environment() {
  check_aws_cli
  if ! check_aws_profile "$AWS_PROFILE"; then exit 1; fi
  if ! check_aws_authentication "$AWS_PROFILE"; then exit 1; fi
  validate_aws_region "$AWS_REGION"
  check_terraform
  check_github_cli || true
}

get_tf_state_bucket() {
  local account_id="$1"
  local repo_full="$2"
  local bucket_suffix
  bucket_suffix=$(echo "${account_id}-${repo_full}" | md5sum | cut -c1-8)
  echo "terraform-state-${bucket_suffix}"
}

########################################
# Terraform
########################################
export_tf_vars() {
  export TF_VAR_region="$AWS_REGION"
  export TF_VAR_project_name="$PROJECT_NAME"
  export TF_VAR_env="$ENVIRONMENT"
  export TF_VAR_github_repository="$GITHUB_REPO_FULL"
  export TF_VAR_codedeploy_bucket_name="$DEPLOYMENT_BUCKET"
  export TF_VAR_certificate_manager_s3_key="${CERT_MANAGER_S3_KEY:-infrastructure/certificate-manager.sh}"
  export TF_VAR_domain_name="$DOMAIN_NAME"
  export TF_VAR_route53_hosted_zone_id="$ROUTE53_HOSTED_ZONE_ID"
  export TF_VAR_bucket_suffix="${BUCKET_SUFFIX:-}"
  export TF_VAR_vercel_api_token="${VERCEL_API_KEY:-}"
  export TF_VAR_vercel_root_directory="clients/auth-sample"
  export TF_VAR_microservices='["auth", "envoy", "otel-collector"]'
  export TF_VAR_microservices_with_logs='["auth", "envoy"]'
  export TF_VAR_api_subdomain='api'
  export TF_VAR_auth_subdomain='auth'
  export TF_VAR_auth_callback="[\"https://auth.${DOMAIN_NAME}/auth/callback\"]"
  export TF_VAR_auth_logout="[\"https://auth.${DOMAIN_NAME}/auth/logout-complete\"]"

  export TF_STATE_BUCKET="$TF_STATE_BUCKET"
  # Ensure Terraform (including the S3 backend) can load the selected profile
  export AWS_PROFILE="github-terraform"
  export AWS_SDK_LOAD_CONFIG=1
}

upload_certificate_manager_to_codedeploy() {
  local src_file
  src_file="$PROJECT_ROOT/infrastructure/terraform/modules-single-az/compute/userdata/certificate-manager.sh"
  local s3_key
  s3_key="${CERT_MANAGER_S3_KEY:-infrastructure/certificate-manager.sh}"

  if [[ ! -f "$src_file" ]]; then
    print_warning "certificate-manager.sh not found at $src_file; skipping upload"
    return 0
  fi

  print_info "Uploading certificate-manager.sh to s3://${DEPLOYMENT_BUCKET}/${s3_key}"
  if aws s3 cp "$src_file" "s3://${DEPLOYMENT_BUCKET}/${s3_key}" \
       --profile "$AWS_PROFILE" \
       --region "$AWS_REGION" \
       --only-show-errors; then
    print_success "Uploaded certificate-manager.sh to CodeDeploy bucket"
  else
    print_warning "Failed to upload certificate-manager.sh to s3://${DEPLOYMENT_BUCKET}/${s3_key}"
  fi
}

terraform_init() {
  print_info "Initializing Terraform backend"
  local az_prefix
  if [[ "$MULTI_AZ" == "true" ]]; then
    az_prefix="multi-az"
  else
    az_prefix="single-az"
  fi

  terraform init \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="workspace_key_prefix=${PROJECT_NAME}/${az_prefix}"
}

terraform_workspace() {
  local ws="terraform-${ENVIRONMENT}"
  print_info "Selecting/creating workspace: $ws"
  if ! terraform workspace select "$ws" 2>/dev/null; then
    terraform workspace new "$ws"
  fi
}

terraform_plan_only() {
  print_info "Planning Terraform changes ($ACTION)"
  local plan_file
  plan_file="tfplan-${ACTION}"

  if [[ "$ACTION" == "destroy" ]]; then
    terraform plan -destroy -out="$plan_file"
  else
    terraform plan -out="$plan_file"
  fi
  print_success "Plan complete: $plan_file"
}

terraform_apply_or_destroy() {
  case "$ACTION" in
    deploy)
      if prompt_confirmation "Apply Terraform changes?" "Y/n"; then
        terraform apply -auto-approve "tfplan-deploy" || terraform apply -auto-approve
        print_success "Infrastructure deployed successfully ($ENVIRONMENT)"
      else
        print_info "Skipped apply"
      fi
      ;;
    destroy)
      print_warning "This will destroy all $ENVIRONMENT infrastructure managed by Terraform."
      terraform destroy -auto-approve
      print_success "Infrastructure destroyed successfully ($ENVIRONMENT)"
      ;;
  esac
}

run_terraform_pipeline() {
  cd "$PROJECT_ROOT/infrastructure/terraform/prod"
  export_tf_vars
  terraform_init
  terraform_workspace
  terraform_plan_only
  terraform_apply_or_destroy || true
}

run_terraform_destroy() {
  # If the backend bucket doesn't exist, there's nothing to destroy
  if ! bucket_exists "$TF_STATE_BUCKET"; then
    print_warning "Terraform state bucket $TF_STATE_BUCKET not found. Nothing to destroy."
    return 0
  fi
  cd "$PROJECT_ROOT/infrastructure/terraform/prod"
  export_tf_vars
  terraform_init
  terraform_workspace
  terraform destroy -auto-approve
  print_success "Infrastructure destroyed successfully ($ENVIRONMENT)"
}

########################################
# Main
########################################
main() {
  parse_args "$@"
  print_header "🏗️ Prod/Stage AWS Infrastructure ($ACTION)"

  get_user_input
  validate_environment

  # Resolve supporting values using the selected AWS profile
  AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
  ROUTE53_HOSTED_ZONE_ID=$(get_route53_hosted_zone_id "$DOMAIN_NAME" "$AWS_PROFILE")
  TF_STATE_BUCKET=$(get_tf_state_bucket "$AWS_ACCOUNT_ID" "$GITHUB_REPO_FULL")

  # Derive bucket suffix and deployment bucket (no prompts)
  BUCKET_SUFFIX=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
  DEPLOYMENT_BUCKET="${PROJECT_NAME}-codedeploy-${BUCKET_SUFFIX}"

  case "$ACTION" in
    plan|deploy)
      upload_certificate_manager_to_codedeploy
      run_terraform_pipeline
      ;;
    destroy)
      run_terraform_destroy
      ;;
  esac
}

main "$@"


