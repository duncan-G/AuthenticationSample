#!/usr/bin/env bash
# Gets the number of CONFIRMED users in an AWS Cognito User Pool.
# Prints the count to stdout and exits 0 on success; prints an error to stderr and exits non-zero on failure.

set -o pipefail

# Ensure aws cli is available
if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI is not installed or not in PATH." >&2
  exit 1
fi

# Validate required environment variables
if [[ -z "${USER_POOL_ID:-}" ]]; then
  echo "Error: USER_POOL_ID is not set in the environment." >&2
  exit 1
fi

if [[ -z "${AWS_PROFILE:-}" ]]; then
  echo "Error: AWS_PROFILE is not set in the environment." >&2
  exit 1
fi

get_confirmed_users_count() {
  local count
  local err_file err

  # Capture count; handle AWS CLI errors cleanly and echo underlying error
  err_file=$(mktemp)
  count=$(
    aws cognito-idp list-users \
      --user-pool-id "${USER_POOL_ID}" \
      --profile "${AWS_PROFILE}" \
      --query "Users[?UserStatus=='CONFIRMED'] | length(@)" \
      --output text 2>"${err_file}"
  )
  if [[ $? -ne 0 ]]; then
    err=$(cat "${err_file}")
    rm -f "${err_file}"
    echo "Error: Failed to retrieve confirmed user count from Cognito. AWS CLI error: ${err}" >&2
    return 1
  fi
  rm -f "${err_file}"

  # Normalize whitespace
  count="${count//$'\r'/}"
  count="${count//$'\n'/}"

  # Validate the result is a non-negative integer (handles 0, 1, etc.)
  if [[ -z "$count" || "$count" == "None" || ! $count =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid confirmed user count received: '$count'" >&2
    return 1
  fi

  echo "$count"
  return 0
}

get_confirmed_users_count
exit $?
