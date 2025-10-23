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
Usage: $(basename "$0") [--action deploy|destroy]

Options:
  -a, --action    Action to perform (deploy|destroy). Default: deploy
  -h, --help      Show this help message
EOF
}

ACTION="deploy"

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
    deploy|destroy) ;;
    *)
      print_error "Invalid --action: $ACTION (expected deploy or destroy)"
      usage
      exit 1
      ;;
  esac
}

get_user_input() {
  prompt_user "Enter AWS profile" "AWS_PROFILE" "infra-setup"
  prompt_user "Enter project name" "PROJECT_NAME"
  prompt_user "Enter AWS region" "AWS_REGION" "us-west-1"
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
  check_github_cli
}

########################################
# State bucket naming
########################################
compute_tf_state_bucket() {
  local account_id="$1"
  local repo_full
  repo_full=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  local bucket_suffix
  bucket_suffix=$(echo "${account_id}-${repo_full}" | md5sum | cut -c1-8)
  TF_STATE_BUCKET="terraform-state-${bucket_suffix}-dev"
}

########################################
# S3 backend bucket
########################################
bucket_exists() {
  local bucket="$1"
  aws s3api head-bucket --bucket "$bucket" --profile "$AWS_PROFILE" 2>/dev/null
}

create_bucket() {
  local bucket="$1"
  local region="$2"

  print_info "Creating S3 bucket $bucket in $region"

  if [ "$region" = "us-east-1" ]; then
    # us-east-1 does not accept a LocationConstraint
    aws s3api create-bucket \
      --bucket "$bucket" \
      --profile "$AWS_PROFILE"
  else
    aws s3api create-bucket \
      --bucket "$bucket" \
      --region "$region" \
      --create-bucket-configuration LocationConstraint="$region" \
      --profile "$AWS_PROFILE"
  fi
}

configure_bucket_baseline() {
  local bucket="$1"
  aws s3api put-bucket-versioning \
    --bucket "$bucket" \
    --versioning-configuration Status=Enabled \
    --profile "$AWS_PROFILE"

  aws s3api put-bucket-encryption \
    --bucket "$bucket" \
    --profile "$AWS_PROFILE" \
    --server-side-encryption-configuration '{
      "Rules": [
        {"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}
      ]
    }'

  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --profile "$AWS_PROFILE" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  aws s3api put-bucket-tagging \
    --bucket "$bucket" \
    --profile "$AWS_PROFILE" \
    --tagging "TagSet=[{Key=Name,Value=${PROJECT_NAME}-tf-state-dev},{Key=Environment,Value=dev}]"

  print_success "Terraform state bucket configured"
}

ensure_backend_bucket() {
  print_info "Ensuring Terraform state bucket exists: $TF_STATE_BUCKET"
  if ! bucket_exists "$TF_STATE_BUCKET"; then
    create_bucket "$TF_STATE_BUCKET" "$AWS_REGION"
  else
    print_warning "S3 bucket $TF_STATE_BUCKET already exists"
  fi
  configure_bucket_baseline "$TF_STATE_BUCKET"
}

########################################
# Terraform
########################################
export_tf_vars() {
  export TF_VAR_region="$AWS_REGION"
  export TF_VAR_project_name="$PROJECT_NAME"
  export TF_VAR_env="dev"
  export TF_VAR_auth_callback='["https://localhost:3000/auth/callback"]'
  export TF_VAR_auth_logout='["https://localhost:3000/auth/logout-complete"]'
  export TF_STATE_BUCKET="$TF_STATE_BUCKET"
  # Ensure Terraform (including the S3 backend) can load the selected profile
  export AWS_PROFILE="github-terraform"
  export AWS_SDK_LOAD_CONFIG=1
}

terraform_init() {
  print_info "Initializing Terraform backend"
  terraform init \
    -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="workspace_key_prefix=${PROJECT_NAME}"
}

terraform_workspace_dev() {
  print_info "Selecting/creating workspace: dev"
  if ! terraform workspace select dev 2>/dev/null; then
    terraform workspace new dev
  fi
}

terraform_plan_apply() {
  print_info "Planning Terraform changes"
  terraform plan -out=tfplan

  if prompt_confirmation "Apply Terraform changes?" "Y/n"; then
    terraform apply -auto-approve tfplan
    print_success "Dev infrastructure deployed successfully"
  else
    print_info "Skipped apply"
  fi
}

run_terraform_pipeline() {
  cd "$PROJECT_ROOT/infrastructure/terraform/dev"
  export_tf_vars
  terraform_init
  terraform_workspace_dev
  terraform_plan_apply
}

terraform_destroy() {
  print_warning "This will destroy all dev infrastructure managed by Terraform."
  terraform destroy -auto-approve
  print_success "Dev infrastructure destroyed successfully"
}

run_terraform_destroy() {
  # If the backend bucket doesn't exist, there's nothing to destroy
  if ! bucket_exists "$TF_STATE_BUCKET"; then
    print_warning "Terraform state bucket $TF_STATE_BUCKET not found. Nothing to destroy."
    return 0
  fi
  cd "$PROJECT_ROOT/infrastructure/terraform/dev"
  export_tf_vars
  terraform_init
  terraform_workspace_dev
  terraform_destroy
}

########################################
# Main
########################################
main() {
  parse_args "$@"
  print_header "🛠️ Dev AWS Infrastructure ($ACTION)"

  get_user_input
  validate_environment
  AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
  compute_tf_state_bucket "$AWS_ACCOUNT_ID"

  if [[ "$ACTION" = "deploy" ]]; then
    ensure_backend_bucket
    run_terraform_pipeline
  else
    run_terraform_destroy
  fi
}

main "$@"
