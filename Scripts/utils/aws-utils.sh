#!/bin/bash

#########################################
# AWS Utilities Script
# Shared functions for AWS authentication and configuration
#########################################

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/print-utils.sh"
source "$SCRIPT_DIR/common.sh"

# Function to check if AWS CLI is configured
check_aws_cli() {
    print_info "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        print_error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    print_success "AWS CLI is available"
}

# Function to check if AWS profile exists
check_aws_profile() {
    local profile="$1"
    
    if [ -z "$profile" ]; then
        print_error "AWS profile is required"
        return 1
    fi
    
    if ! aws configure list-profiles | grep -q "^${profile}$"; then
        print_error "AWS profile '$profile' not found"
        print_info "Available profiles:"
        aws configure list-profiles
        return 1
    fi
    
    print_success "AWS profile '$profile' found"
    return 0
}

# Function to check if AWS SSO session is authenticated
check_aws_authentication() {
    local profile="$1"
    
    if [ -z "$profile" ]; then
        print_error "AWS profile is required for authentication check"
        return 1
    fi
    
    print_info "Checking AWS authentication for profile: $profile..."
    
    # Test authentication by getting caller identity
    local result
    result=$(aws sts get-caller-identity --profile "$profile" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        local account_id
        account_id=$(echo "$result" | jq -r '.Account' 2>/dev/null || echo "$result" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
        print_success "AWS authentication successful for profile '$profile'"
        print_info "Account ID: $account_id"
        return 0
    else
        # Check for specific error types
        if echo "$result" | grep -q "Token has expired and refresh failed"; then
            print_error "SSO token has expired for profile '$profile'"
            print_info "Please run the following command to refresh your SSO session:"
            echo -e "${GREEN}aws sso login --profile $profile${NC}"
            echo
            print_info "After logging in, run this script again."
            return 1
        elif echo "$result" | grep -q "ProfileNotFoundError"; then
            print_error "AWS profile '$profile' not found"
            print_info "Please check your AWS configuration:"
            print_info "1. Run 'aws configure list-profiles' to see available profiles"
            print_info "2. Run 'aws configure list --profile $profile' to check profile configuration"
            return 1
        elif echo "$result" | grep -q "SSOStartUrl"; then
            print_error "SSO session not started for profile '$profile'"
            print_info "Please run the following command to start your SSO session:"
            echo -e "${GREEN}aws sso login --profile $profile${NC}"
            echo
            print_info "After logging in, run this script again."
            return 1
        else
            print_error "AWS authentication failed for profile '$profile'"
            print_info "Error details: $result"
            print_info "Please ensure:"
            print_info "1. Profile '$profile' exists in your AWS config"
            print_info "2. You have run 'aws sso login --profile $profile'"
            print_info "3. Your SSO session is still valid"
            return 1
        fi
    fi
}

# Function to get AWS account ID with authentication check
get_aws_account_id() {
    local profile=$1

    if [[ -z $profile ]]; then
        print_error "AWS profile is required" >&2
        return 1
    fi

    # Credential check (no output wanted)
    if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
        print_error "AWS authentication failed for profile '$profile'" >&2
        return 1
    fi

    print_info "Getting AWS Account ID using profile: $profile..." >&2

    # Grab the account ID (stderr redirected so only stdout is captured)
    local account_id
    if ! account_id=$(aws sts get-caller-identity \
                        --profile "$profile" \
                        --query Account --output text 2>&1); then
        print_error "Failed to get AWS Account ID" >&2
        print_info  "Error details: $account_id" >&2
        return 1
    fi

    if [[ -z $account_id ]]; then
        print_error "Failed to get AWS Account ID – empty result" >&2
        return 1
    fi

    print_success "AWS Account ID: $account_id" >&2
    printf '%s\n' "$account_id"          # <-- only this goes to stdout
}

# Function to validate AWS region
validate_aws_region() {
    local region="$1"
    
    if [ -z "$region" ]; then
        print_error "AWS region is required"
        return 1
    fi
    
    # List of valid AWS regions (you can expand this list)
    local valid_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "af-south-1" "ap-east-1" "ap-south-1" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3"
        "ap-southeast-1" "ap-southeast-2" "ap-southeast-3" "ap-southeast-4"
        "ca-central-1" "eu-central-1" "eu-west-1" "eu-west-2" "eu-west-3"
        "eu-north-1" "eu-south-1" "eu-south-2" "me-south-1" "me-central-1"
        "sa-east-1" "us-gov-east-1" "us-gov-west-1"
    )
    
    for valid_region in "${valid_regions[@]}"; do
        if [ "$region" = "$valid_region" ]; then
            print_success "AWS region '$region' is valid"
            return 0
        fi
    done
    
    print_warning "AWS region '$region' may not be valid"
    print_info "Common regions: us-east-1, us-west-2, eu-west-1, ap-southeast-1"
    return 0  # Don't fail, just warn
}

# Function to check if jq is available (for JSON parsing)
check_jq() {
    if ! command_exists jq; then
        print_warning "jq not found. Some features may not work optimally."
        print_info "To install jq: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        return 1
    fi
    return 0
}

# Export functions so they can be used by other scripts
export -f check_aws_cli check_aws_profile check_aws_authentication
export -f get_aws_account_id validate_aws_region check_jq 