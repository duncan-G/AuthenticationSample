#!/bin/bash

#########################################
# Create Service Workflow Script
# Creates GitHub Actions workflow for a new service
#########################################

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/common.sh"

# Script to create a new service workflow from template
# Usage: ./scripts/create-service-github-action.sh <service-name>

set -e

validate_service_name() {
    local service_name="$1"
    
    if [ -z "$service_name" ]; then
        print_error "Service name is required"
        return 1
    fi
    
    if [[ ! "$service_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        print_error "Service name can only contain letters, numbers, and hyphens"
        return 1
    fi
    
    return 0
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
    local debug_workflow=".github/workflows/${service_name}-service-debug.yml"
    local release_workflow=".github/workflows/${service_name}-service-release.yml"
    
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
    
    local debug_template=".github/workflows/templates/service-dotnet-debug-template.yml"
    local release_template=".github/workflows/templates/service-dotnet-release-template.yml"
    local debug_output=".github/workflows/${service_name}-service-debug.yml"
    local release_output=".github/workflows/${service_name}-service-release.yml"
    
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
    echo "  - .github/workflows/${service_name}-service-debug.yml (PR builds)"
    echo "  - .github/workflows/${service_name}-service-release.yml (deployments)"
    echo
    print_info "Created GitHub environments:"
    echo "  - service-stage"
    echo "  - service-prod"
    echo
    print_info "Required secrets and variables:"
    echo "  - AWS_ACCOUNT_ID (secret) - Your AWS account ID"
    echo "  - ECR_REPOSITORY_PREFIX (secret) - ECR repository prefix"
    echo "  - DEPLOYMENT_BUCKET (secret) - S3 bucket for deployment artifacts"
    echo
    print_info "Next steps:"
    echo "1. Review the generated workflow files:"
    echo "   .github/workflows/${service_name}-service-debug.yml"
    echo "   .github/workflows/${service_name}-service-release.yml"
    echo
    echo "2. Verify secrets and variables are set correctly:"
    echo "   - Go to Settings → Secrets and variables → Actions"
    echo "   - Check that all required secrets and variables exist"
    echo
    echo "3. Update Terraform configuration if needed:"
    echo "   infrastructure/terraform/modules/codedeploy.tf"
    echo
    echo "4. Deploy the Terraform changes:"
    echo "   cd infrastructure/terraform/modules"
    echo "   terraform plan -var='project_name=your-project' -var='env=stage'"
    echo "   terraform apply -var='project_name=your-project' -var='env=stage'"
    echo
    echo "5. Test the workflows:"
    echo "   - Create a PR with changes to microservices/$pascal_case_name/"
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
    
    # Get service name from command line
    SERVICE_NAME="$1"
    
    validate_service_name_with_checks "$SERVICE_NAME"
    create_service_workflow "$SERVICE_NAME"
    
    # Display next steps
    display_next_steps "$SERVICE_NAME"
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 