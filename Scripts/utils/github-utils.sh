#!/bin/bash

#########################################
# GitHub Utilities Script
# Shared functions for GitHub CLI operations
#########################################

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/print-utils.sh"
source "$SCRIPT_DIR/common.sh"

# Function to check if GitHub CLI is configured
check_github_cli() {
    print_info "Checking GitHub CLI configuration..."
    
    if ! command_exists gh; then
        print_error "GitHub CLI not found. Please install GitHub CLI first."
        print_info "To install GitHub CLI: https://cli.github.com/"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI not authenticated. Please authenticate first."
        print_info "To authenticate: gh auth login"
        exit 1
    fi
    
    print_success "GitHub CLI is available and authenticated"
}

# Function to validate repository access
validate_repo() {
    local repo="$1"
    
    if [ -z "$repo" ]; then
        print_error "Repository is required"
        return 1
    fi
    
    if ! gh repo view "$repo" &> /dev/null; then
        print_error "Cannot access repository $repo"
        print_info "Please ensure you have access to the repository."
        return 1
    fi
    
    print_success "Repository access confirmed: $repo"
    return 0
}

# Function to check if GitHub repository secrets exist
# Usage: check_github_secret_exists "owner/repo" "SECRET_NAME"
check_github_secret_exists() {
    local repo="$1"
    local secret_name="$2"
    
    if [ -z "$repo" ] || [ -z "$secret_name" ]; then
        print_error "Repository and secret name are required"
        return 1
    fi
    
    # Check if secret exists (this will return 0 if exists, 1 if not)
    if gh secret list --repo "$repo" | grep -q "^${secret_name}$"; then
        return 0  # Secret exists
    else
        return 1  # Secret does not exist
    fi
}

# Function to add GitHub repository secrets
# Usage: add_github_secrets "owner/repo" "SECRET1:value1" "SECRET2:value2"
add_github_secrets() {
    local repo="$1"
    shift
    local secrets=("$@")
    
    if [ ${#secrets[@]} -eq 0 ]; then
        print_warning "No secrets provided"
        return 0
    fi
    
    print_info "Creating GitHub repository secrets (encrypted)..."
    
    # Validate repository access
    if ! validate_repo "$repo"; then
        return 1
    fi
    
    for secret in "${secrets[@]}"; do
        local name="${secret%%:*}"
        local value="${secret##*:}"
        
        if [ -z "$name" ] || [ -z "$value" ]; then
            print_warning "Invalid secret format: $secret (expected 'name:value')"
            continue
        fi
        
        print_info "Creating secret: $name"
        if gh secret set "$name" --body "$value" --repo "$repo" &> /dev/null; then
            print_success "Secret $name created successfully"
        else
            print_warning "Failed to create secret $name (may already exist)"
        fi
    done
}

# Function to add GitHub repository variables
# Usage: add_github_variables "owner/repo" "VAR1:value1" "VAR2:value2"
add_github_variables() {
    local repo="$1"
    shift
    local variables=("$@")
    
    if [ ${#variables[@]} -eq 0 ]; then
        print_warning "No variables provided"
        return 0
    fi
    
    print_info "Creating GitHub repository variables (visible)..."
    
    # Validate repository access
    if ! validate_repo "$repo"; then
        return 1
    fi
    
    for variable in "${variables[@]}"; do
        local name="${variable%%:*}"
        local value="${variable##*:}"
        
        if [ -z "$name" ] || [ -z "$value" ]; then
            print_warning "Invalid variable format: $variable (expected 'name:value')"
            continue
        fi
        
        print_info "Creating variable: $name"
        if gh variable set "$name" --body "$value" --repo "$repo" &> /dev/null; then
            print_success "Variable $name created successfully"
        else
            print_warning "Failed to create variable $name (may already exist)"
        fi
    done
}

# Function to create GitHub environments
# Usage: create_github_environments "owner/repo" "env1" "env2" "env3"
create_github_environments() {
    local repo="$1"
    shift
    local environments=("$@")
    
    if [ ${#environments[@]} -eq 0 ]; then
        print_warning "No environments provided"
        return 0
    fi
    
    print_info "Creating GitHub environments..."
    
    # Validate repository access
    if ! validate_repo "$repo"; then
        return 1
    fi
    
    for env in "${environments[@]}"; do
        if [ -z "$env" ]; then
            print_warning "Empty environment name provided, skipping"
            continue
        fi
        
        print_info "Creating environment: $env"
        if gh api repos/"$repo"/environments/"$env" &> /dev/null; then
            print_warning "Environment $env already exists"
        else
            if gh api \
                --method PUT \
                -H "Accept: application/vnd.github+json" \
                repos/"$repo"/environments/"$env" &> /dev/null; then
                print_success "Environment $env created/updated successfully"
            else
                print_error "Failed to create environment $env"
            fi
        fi
    done
}

# Export functions so they can be used by other scripts
export -f check_github_cli validate_repo check_github_secret_exists add_github_secrets add_github_variables create_github_environments 