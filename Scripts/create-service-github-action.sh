#!/bin/bash

#########################################
# Create Service Workflow Script
# Creates GitHub Actions workflow for a new service
#########################################

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/validation.sh"
source "$UTILS_DIR/common.sh"
source "$UTILS_DIR/github-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"

# Script to create a new service workflow from template
# Usage: ./Scripts/create-service-github-action.sh <service-name>

set -e

# Function to create GitHub environments for the service
create_service_github_environments() {
    local service_name="$1"
    local staging_env="service-staging"
    local production_env="service-production"
    
    print_info "Creating GitHub environments for service: $service_name"
    
    # Check if GitHub CLI is available and authenticated
    if ! check_github_cli; then
        print_warning "GitHub CLI not available. Skipping environment creation."
        print_info "Please manually create environments: $staging_env, $production_env"
        return 0
    fi
    
    # Get repository name
    local repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
    if [ -z "$repo" ]; then
        print_warning "Could not determine GitHub repository. Skipping environment creation."
        print_info "Please manually create environments: $staging_env, $production_env"
        return 0
    fi
    
    # Use the shared function to create environments
    create_github_environments "$repo" "$staging_env" "$production_env"
}

# Function to validate service name and additional checks
validate_service_name_with_checks() {
    local service_name="$1"
    
    # Use the utility function for basic validation
    if ! validate_service_name "$service_name"; then
        echo "Usage: $0 <service-name>"
        exit 1
    fi
    
    # Check if workflow files already exist
    local debug_workflow=".github/workflows/${service_name}-debug.yml"
    local release_workflow=".github/workflows/${service_name}-service.yml"
    
    if [ -f "$debug_workflow" ] || [ -f "$release_workflow" ]; then
        print_warning "Workflow files already exist:"
        [ -f "$debug_workflow" ] && echo "  - $debug_workflow"
        [ -f "$release_workflow" ] && echo "  - $release_workflow"
        read -p "Do you want to overwrite them? (y/N): " overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to convert service name to PascalCase
convert_to_pascal_case() {
    local service_name="$1"
    # Convert kebab-case or snake_case to PascalCase
    # First, replace hyphens and underscores with spaces, then capitalize each word
    echo "$service_name" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g' | sed 's/ //g'
}

# Function to create service workflow
create_service_workflow() {
    local service_name="$1"
    local pascal_case_name
    pascal_case_name=$(convert_to_pascal_case "$service_name")
    
    local debug_template=".github/workflows/templates/service-debug-template.yml"
    local release_template=".github/workflows/templates/service-release-template.yml"
    local debug_output=".github/workflows/${service_name}-debug.yml"
    local release_output=".github/workflows/${service_name}-service.yml"
    
    print_info "Creating workflows for service: $service_name (PascalCase: $pascal_case_name)"
    
    # Check if templates exist
    if [ ! -f "$debug_template" ]; then
        print_error "Debug template file $debug_template not found"
        exit 1
    fi
    
    if [ ! -f "$release_template" ]; then
        print_error "Release template file $release_template not found"
        exit 1
    fi
    
    # Create debug workflow file from template
    # Replace both SERVICE_NAME and PASCALCASE_SERVICE_NAME placeholders
    sed -e "s/{{ SERVICE_NAME }}/$service_name/g" \
        -e "s/{{ PASCALCASE_SERVICE_NAME }}/$pascal_case_name/g" \
        "$debug_template" > "$debug_output"
    print_success "Created debug workflow file: $debug_output"
    
    # Create release workflow file from template
    # Replace both SERVICE_NAME and PASCALCASE_SERVICE_NAME placeholders
    sed -e "s/{{ SERVICE_NAME }}/$service_name/g" \
        -e "s/{{ PASCALCASE_SERVICE_NAME }}/$pascal_case_name/g" \
        "$release_template" > "$release_output"
    print_success "Created release workflow file: $release_output"
}

# Function to update Terraform configuration
update_terraform_config() {
    local service_name="$1"
    local terraform_file="Infrastructure/terraform/modules/codedeploy.tf"
    
    print_info "Updating Terraform configuration for service: $service_name"
    
    # Check if service is already in the Terraform config
    if grep -q "\"$service_name\"" "$terraform_file"; then
        print_warning "Service $service_name is already configured in Terraform"
        return
    fi
    
    # Create backup
    cp "$terraform_file" "${terraform_file}.backup"
    
    # Add service to the for_each lists
    sed -i "s/for_each = toset(\[\"authentication\"\])/for_each = toset([\"authentication\", \"$service_name\"])/g" "$terraform_file"
    
    print_success "Updated Terraform configuration"
    print_warning "Please review the changes in $terraform_file"
}

prompt_and_add_secrets() {
    local repo
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || return
    validate_repo "$repo" || return

    local -a required_secrets=(AWS_ACCOUNT_ID ECR_REPOSITORY_PREFIX DEPLOYMENT_BUCKET)
    local -a missing=()

    printf "🔍  Checking existing GitHub secrets…\n"
    for s in "${required_secrets[@]}"; do
        if check_github_secret_exists "$repo" "$s"; then
            print_success "Secret $s already exists"
        else
            print_info    "Secret $s is missing and will be created"
            missing+=("$s")
        fi
    done

    (( ${#missing[@]} )) || { print_success "All required secrets already exist"; return; }
    printf "➕  Creating %d missing secret(s)…\n" "${#missing[@]}"

    # ---------------------------------------------------------------------
    # Helpers / shared state
    # ---------------------------------------------------------------------
    local aws_profile aws_account_id app_name deployment_bucket
    ensure_aws_details() {
        [[ $aws_account_id ]] && return 0        # already obtained
        prompt_user "Enter AWS profile name" "aws_profile" "terraform-setup"
        # aws_profile is set by prompt_user
        check_aws_profile "$aws_profile"        || return 1
        check_aws_authentication "$aws_profile" || return 1
        aws_account_id=$(get_aws_account_id "$aws_profile") || return 1
    }

    # ---------------------------------------------------------------------
    # Gather values for each missing secret
    # ---------------------------------------------------------------------
    for secret in "${missing[@]}"; do
        case $secret in
            AWS_ACCOUNT_ID)
                ensure_aws_details            || return 1
                ;;
            ECR_REPOSITORY_PREFIX)
                prompt_user "Enter application name (used for container repository naming)" \
                            "app_name"
                # app_name is set by prompt_user
                ;;
            DEPLOYMENT_BUCKET)
                ensure_aws_details            || return 1
                local hash
                hash=$(echo "${aws_account_id}-${repo}" | md5sum | cut -c1-8)
                deployment_bucket="code-deploy-${hash}"
                ;;
        esac
    done

    # ---------------------------------------------------------------------
    # Push secrets to GitHub
    # ---------------------------------------------------------------------
    local -a payload=()
    [[ " ${missing[*]} " == *" AWS_ACCOUNT_ID "*      ]] && payload+=("AWS_ACCOUNT_ID:$aws_account_id")
    [[ " ${missing[*]} " == *" ECR_REPOSITORY_PREFIX "* ]] && payload+=("ECR_REPOSITORY_PREFIX:$app_name")
    [[ " ${missing[*]} " == *" DEPLOYMENT_BUCKET "*     ]] && payload+=("DEPLOYMENT_BUCKET:$deployment_bucket")

    add_github_secrets "$repo" "${payload[@]}"
}

# Function to display next steps
display_next_steps() {
    local service_name="$1"
    local pascal_case_name
    pascal_case_name=$(convert_to_pascal_case "$service_name")
    
    print_header "Service Github Actions Workflows Created Successfully!"
    
    echo
    print_success "Workflows for $service_name have been created!"
    echo
    print_info "Created files:"
    echo "  - .github/workflows/${service_name}-debug.yml (PR builds)"
    echo "  - .github/workflows/${service_name}-service.yml (deployments)"
    echo
    print_info "Created GitHub environments:"
    echo "  - service-staging"
    echo "  - service-production"
    echo
    print_info "Required secrets and variables:"
    echo "  - AWS_ACCOUNT_ID (secret) - Your AWS account ID"
    echo "  - ECR_REPOSITORY_PREFIX (secret) - ECR repository prefix"
    echo "  - DEPLOYMENT_BUCKET (secret) - S3 bucket for deployment artifacts"
    echo "  - APP_NAME (variable) - Application name for IAM roles"
    echo
    print_info "Next steps:"
    echo "1. Review the generated workflow files:"
    echo "   .github/workflows/${service_name}-debug.yml"
    echo "   .github/workflows/${service_name}-service.yml"
    echo
    echo "2. Verify secrets and variables are set correctly:"
    echo "   - Go to Settings → Secrets and variables → Actions"
    echo "   - Check that all required secrets and variables exist"
    echo
    echo "3. Update Terraform configuration if needed:"
    echo "   Infrastructure/terraform/modules/codedeploy.tf"
    echo
    echo "4. Deploy the Terraform changes:"
    echo "   cd Infrastructure/terraform/modules"
    echo "   terraform plan -var='app_name=your-app-name' -var='environment=staging'"
    echo "   terraform apply -var='app_name=your-app-name' -var='environment=staging'"
    echo
    echo "5. Test the workflows:"
    echo "   - Create a PR with changes to Microservices/$pascal_case_name/"
    echo "   - Check GitHub Actions for debug build status"
    echo "   - Push to main branch to trigger deployment"
    echo
    echo "6. Or trigger manual deployment:"
    echo "   - Go to Actions → $pascal_case_name Service Deployment"
    echo "   - Click 'Run workflow'"
    echo "   - Choose staging or production environment"
}

# Main execution
main() {
    print_header "Create Service Workflow"

    check_aws_cli
    check_github_cli
    
    # Get service name from command line
    SERVICE_NAME="$1"
    
    validate_service_name_with_checks "$SERVICE_NAME"
    prompt_and_add_secrets "$SERVICE_NAME"
    create_service_github_environments "$SERVICE_NAME"
    create_service_workflow "$SERVICE_NAME"
    update_terraform_config "$SERVICE_NAME"
    
    # Display next steps
    display_next_steps "$SERVICE_NAME"
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 