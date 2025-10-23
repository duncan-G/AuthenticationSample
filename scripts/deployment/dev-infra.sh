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
  check_github_cli
}

get_tf_state_bucket() {
  local profile="$1"
  local bucket_suffix=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)
  echo "terraform-state-${bucket_suffix}"
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
  TF_STATE_BUCKET=$(get_tf_state_bucket "$AWS_PROFILE")

  if [[ "$ACTION" = "deploy" ]]; then
    run_terraform_pipeline
  else
    run_terraform_destroy
  fi
}

main "$@"
