#!/usr/bin/env bash
###############################################################################
# setup-secrets.sh — Discover *.env.template files and either
#   • create .env / files for client apps (dev) or push to Vercel
#   • create / update an AWS Secrets Manager secret for backend apps
#
# Usage:   ./setup-secrets.sh [-a PROJECT_NAME] [-p AWS_PROFILE] [-P] [-f] [-h]
# Flags:
#   -P   production mode                  (default: development)
#   -f   force prompting for *all* keys   (even those already stored)
#   -h   show help and exit
#
# Prerequisites: AWS CLI, jq, utils/{print,prompt,aws,common}.sh
###############################################################################
set -Eeuo pipefail
IFS=$'\n\t'

## ----------------------------------------------------------------------------
## Shared paths & utils
## ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$SCRIPT_DIR/../utils"

# shellcheck source=utils/print-utils.sh
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/common.sh"

print_header "🔐 Environment Secrets Setup"

## ----------------------------------------------------------------------------
## Globals (minimal — prefer locals inside functions)
## ----------------------------------------------------------------------------
PROJECT_NAME=""
AWS_PROFILE=""
PROD_MODE=false
FORCE_ALL=false
SECRET_NAME=""

# Associative arrays declared globally so they can be filled by sub‑functions
# and read afterwards.
declare -Ag BACKEND_DEFAULTS=()   # key ➜ default value from template
declare -Ag BACKEND_COMMENTS=()   # key ➜ comment above key
declare -Ag BACKEND_VALUES=()     # key ➜ final value to be stored

## ----------------------------------------------------------------------------
## Helper functions
## ----------------------------------------------------------------------------
usage() {
  sed -n '2,32p' "$0"
  exit "${1:-0}"
}

parse_args() {
  while getopts ':a:p:Pfh' flag; do
    case "$flag" in
      a) PROJECT_NAME="$OPTARG" ;;
      p) AWS_PROFILE="$OPTARG" ;;
      P) PROD_MODE=true       ;;
      f) FORCE_ALL=true       ;;
      h) usage 0              ;;
      :) print_error "Option -$OPTARG requires an argument" ; usage 1 ;;
      *) print_error "Unknown option: -$OPTARG"             ; usage 1 ;;
    esac
  done
  shift $((OPTIND-1))
}

prompt_for_missing() {
  if [[ -z $PROJECT_NAME ]];  then prompt_user "Project name" PROJECT_NAME ; fi
  if [[ -z $AWS_PROFILE ]];   then prompt_user "AWS profile"      AWS_PROFILE "developer" ; fi
  print_success "Project: $PROJECT_NAME"
  print_success "AWS profile: $AWS_PROFILE"
}

determine_secret_name() {
  SECRET_NAME="${PROJECT_NAME}-secrets"
  if [[ $PROD_MODE == true ]]; then
    SECRET_NAME+="-prod"
  else
    SECRET_NAME+="-dev"
  fi
  print_info "Secret name: $SECRET_NAME"
}

## -----------------------------------------------------------------------------
## Template discovery
## -----------------------------------------------------------------------------
discover_templates() {
  readarray -d '' TEMPLATE_FILES < <(
    if [[ $PROD_MODE == true ]]; then
      find "$PROJECT_ROOT" -type f \( -name '*.env.template' -o -name '*.env.template.prod' \) -print0
    else
      find "$PROJECT_ROOT" -type f \( -name '*.env.template' -o -name '*.env.template.dev' \) -print0
    fi
  )
}

categorise_templates() {
  CLIENT_TEMPLATES=()
  BACKEND_TEMPLATES=()
  for f in "${TEMPLATE_FILES[@]}"; do
    if [[ $f == */clients/* ]]; then CLIENT_TEMPLATES+=("$f") ; else BACKEND_TEMPLATES+=("$f") ; fi
  done
  print_info  "Found ${#CLIENT_TEMPLATES[@]} client template(s)"
  print_info  "Found ${#BACKEND_TEMPLATES[@]} backend template(s)"
}

## -----------------------------------------------------------------------------
## Generic parser (used by both client & backend)
##   Args:   $1 – path to template file
##   Prints: key\tdefault\tcomment   to stdout
## -----------------------------------------------------------------------------
parse_template() {
  local file="$1"; local prev_comment=""; local prev_is_comment=false
  while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in
      \#*)   prev_comment="${line#\# }"; prev_is_comment=true ;;
      "")    prev_comment=""; prev_is_comment=false           ;;
      *)
        if [[ $line =~ ^[[:space:]]*([^=[:space:]]+)=[[:space:]]*(.*)$ ]]; then
          local k="${BASH_REMATCH[1]}"; local v="${BASH_REMATCH[2]}"
          # Remove trailing/leading whitespace and carriage returns, then remove quotes
          v="$(echo "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"  # Trim whitespace
          v="${v%$'\r'}"                  # Remove carriage return  
          v="${v#\"}"                     # Remove leading quote
          v="${v%\"}"                     # Remove trailing quote
          local c=""
          [[ $prev_is_comment == true ]] && c="$prev_comment"
          printf '%s\t%s\t%s\n' "$k" "$v" "$c"
        fi
        prev_comment=""; prev_is_comment=false
      ;;
    esac
  done < "$file"
}

## -----------------------------------------------------------------------------
## Client processing (dev only)
## -----------------------------------------------------------------------------
process_client_templates() {
  [[ ${#CLIENT_TEMPLATES[@]} -eq 0 ]] && return 0
  if [[ $PROD_MODE == true ]]; then
    print_warning "Production client secrets via Vercel not implemented yet – skipping"
    return 0
  fi

  for tmpl in "${CLIENT_TEMPLATES[@]}"; do
    [[ ! -r "$tmpl" ]] && { print_error "Cannot read template: $tmpl"; continue; }
    
    declare -A values=();
    
    # Use process substitution with exec to avoid subshell
    exec 3< <(parse_template "$tmpl")
    while IFS=$'\t' read -r key def comment <&3; do
      local prompt="$key(${comment:+$comment }):"
      local temp_value
      prompt_user "$prompt" temp_value "$def"
      values["$key"]="$temp_value"
    done
    exec 3<&-  # Close the file descriptor

    if [[ ${#values[@]} -eq 0 ]]; then
      print_warning "No valid key=value pairs found in $tmpl"
      continue
    fi

    # Remove .template from filename while preserving environment suffix
    local basename_tmpl="$(basename "$tmpl")"
    local out_name="${basename_tmpl/.template/}"
    local out_file="$(dirname "$tmpl")/$out_name"
    : > "$out_file"
    for k in $(printf '%s\n' "${!values[@]}" | sort); do
      echo "$k=${values[$k]}" >> "$out_file"
    done
    print_success "Created ${out_file#$PROJECT_ROOT/}"
  done
}

## -----------------------------------------------------------------------------
## Backend processing (AWS Secrets Manager)
## -----------------------------------------------------------------------------
collect_backend_defaults() {
  [[ ${#BACKEND_TEMPLATES[@]} -eq 0 ]] && return 0
  for tmpl in "${BACKEND_TEMPLATES[@]}"; do
    [[ ! -r "$tmpl" ]] && { print_error "Cannot read template: $tmpl"; continue; }
    
    # Properly establish file descriptor first, then read from it
    exec 3< <(parse_template "$tmpl")
    while IFS=$'\t' read -r key def comment <&3; do
      BACKEND_DEFAULTS["$key"]="$def"
      [[ -n $comment ]] && BACKEND_COMMENTS["$key"]="$comment"
    done
    exec 3<&-  # Close the file descriptor
  done
}

load_existing_secret() {
  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
    # Temporarily disable 'set -e' to handle errors gracefully
    set +e
    EXISTING_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text --profile "$AWS_PROFILE" 2>&1)
    local get_secret_exit_code=$?
    set -e
    
    if [[ $get_secret_exit_code -ne 0 ]]; then
      print_error "Failed to retrieve secret value: $EXISTING_JSON"
      print_error "Please check your AWS credentials and permissions"
      exit 1
    fi
    
    if [[ -n "$EXISTING_JSON" ]] && jq -e . <<<"$EXISTING_JSON" >/dev/null 2>&1; then
      mapfile -t EXISTING_KEYS < <(jq -r 'keys[]' <<<"$EXISTING_JSON" 2>/dev/null)
      for k in "${EXISTING_KEYS[@]}"; do 
        BACKEND_VALUES["$k"]=$(jq -r --arg k "$k" '.[$k]' <<<"$EXISTING_JSON" 2>/dev/null)
      done
      print_info "Found ${#EXISTING_KEYS[@]} existing backend key(s)"
    else
      print_warning "Existing secret found but contains invalid JSON"
    fi
  fi
}

prompt_backend_values() {
  [[ ${#BACKEND_DEFAULTS[@]} -eq 0 ]] && { print_warning "No backend keys found to process"; return; }
  for k in $(printf '%s\n' "${!BACKEND_DEFAULTS[@]}" | sort); do
    if [[ $FORCE_ALL == false && -n ${BACKEND_VALUES[$k]:-} ]]; then
      print_info "⏭ $k already present"
      continue
    fi
    local def="${BACKEND_VALUES[$k]:-${BACKEND_DEFAULTS[$k]}}"
    local prompt="$k${BACKEND_COMMENTS[$k]+(${BACKEND_COMMENTS[$k]} )}"
    local temp_value
    prompt_user "$prompt" temp_value "$def"
    BACKEND_VALUES["$k"]="$temp_value"
  done
}

store_secret() {
  [[ ${#BACKEND_DEFAULTS[@]} -eq 0 ]] && { print_warning "No backend secrets to store"; return; }
  print_info "Storing ${#BACKEND_DEFAULTS[@]} key(s) to AWS Secrets Manager"
  local jq_args=(); local jq_entries=();
  for k in "${!BACKEND_DEFAULTS[@]}"; do jq_args+=(--arg "$k" "${BACKEND_VALUES[$k]}"); jq_entries+=("\"$k\": \$$k"); done
  
  # Join array elements with commas for proper JSON syntax
  local IFS=','
  SECRETS_JSON=$(jq -n "${jq_args[@]}" "{${jq_entries[*]}}")

  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
    # Update existing secret
    set +e
    local update_output
    update_output=$(aws secretsmanager update-secret --secret-id "$SECRET_NAME" --secret-string "$SECRETS_JSON" --profile "$AWS_PROFILE" 2>&1)
    local update_exit_code=$?
    set -e
    
    if [[ $update_exit_code -ne 0 ]]; then
      print_error "Failed to update secret: $update_output"
      print_error "Please check your AWS credentials and permissions"
      exit 1
    fi
    print_success "Secret updated"
  else
    # Create new secret
    set +e
    local create_output
    create_output=$(aws secretsmanager create-secret --name "$SECRET_NAME" --secret-string "$SECRETS_JSON" \
      --description "Secrets for $PROJECT_NAME $([[ $PROD_MODE == true ]] && echo prod || echo dev)" --profile "$AWS_PROFILE" 2>&1)
    local create_exit_code=$?
    set -e
    
    if [[ $create_exit_code -ne 0 ]]; then
      print_error "Failed to create secret: $create_output"
      print_error "Please check your AWS credentials and permissions"
      exit 1
    fi
    print_success "Secret created"
  fi
}

display_prod_warning() {
  if [[ $PROD_MODE == true ]]; then
    print_warning "These changes will be applied to the production environment"
    print_warning "Please be careful when making changes"
    print_warning "You should probably manage secrets in the AWS console"
    echo
    if ! prompt_confirmation "Are you sure you want to continue?" "y/N"; then
      print_info "Operation cancelled by user"
      exit 0
    fi
  fi
}

## -----------------------------------------------------------------------------
## Main flow
## -----------------------------------------------------------------------------
main() {
  parse_args "$@"

  display_prod_warning
  prompt_for_missing
  discover_templates

  if ! check_jq; then
    exit 1
  fi
  if ! check_aws_cli; then
    exit 1
  fi
  if ! check_aws_profile "$AWS_PROFILE"; then
    exit 1
  fi
  if ! check_aws_authentication "$AWS_PROFILE"; then
    exit 1
  fi

  determine_secret_name
  categorise_templates
  process_client_templates

  collect_backend_defaults
  load_existing_secret
  prompt_backend_values
  store_secret

  print_success "🎉 Environment setup completed"
}

main "$@"
