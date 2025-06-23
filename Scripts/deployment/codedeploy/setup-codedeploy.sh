#!/bin/bash

#########################################
# CodeDeploy Setup Script
# Sets up CodeDeploy infrastructure and GitHub Actions
#########################################

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/common.sh"

# Setup script for CodeDeploy infrastructure
# This script sets up the necessary AWS resources and GitHub Actions for CodeDeploy

set -e

# Configuration
APP_NAME="authentication-sample"
ENVIRONMENT="staging"
ECR_REPOSITORY_PREFIX=""

# Function to get user input with default
get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        eval "$var_name=\${input:-$default}"
    else
        read -p "$prompt: " input
        eval "$var_name=\$input"
    fi
}

# Function to validate AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        print_info "Please run 'aws configure' or set up AWS SSO"
        exit 1
    fi
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "us-west-1")
    
    print_success "AWS credentials validated"
    print_info "Account ID: $AWS_ACCOUNT_ID"
    print_info "Region: $AWS_REGION"
}

# Function to validate GitHub CLI
check_github_cli() {
    if ! command_exists gh; then
        print_error "GitHub CLI (gh) is not installed"
        print_info "Please install it from: https://cli.github.com/"
        exit 1
    fi
    
    if ! gh auth status >/dev/null 2>&1; then
        print_error "GitHub CLI not authenticated"
        print_info "Please run 'gh auth login'"
        exit 1
    fi
    
    GITHUB_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    print_success "GitHub CLI authenticated"
    print_info "Repository: $GITHUB_REPO"
}

# Function to deploy Terraform infrastructure
deploy_infrastructure() {
    print_header "Deploying CodeDeploy Infrastructure"
    
    cd Infrastructure/terraform/modules
    
    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        print_info "Initializing Terraform..."
        terraform init
    fi
    
    # Select workspace
    print_info "Selecting Terraform workspace: $ENVIRONMENT"
    terraform workspace select -or-create "$ENVIRONMENT"
    
    # Plan deployment
    print_info "Planning infrastructure deployment..."
    terraform plan -var="app_name=$APP_NAME" -var="environment=$ENVIRONMENT" -var="region=$AWS_REGION"
    
    # Confirm deployment
    read -p "Do you want to apply these changes? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "Applying infrastructure changes..."
        terraform apply -var="app_name=$APP_NAME" -var="environment=$ENVIRONMENT" -var="region=$AWS_REGION" -auto-approve
        
        # Get deployment bucket name
        DEPLOYMENT_BUCKET=$(terraform output -raw deployment_bucket_name 2>/dev/null || echo "")
        print_success "Infrastructure deployed successfully"
    else
        print_warning "Infrastructure deployment cancelled"
        exit 0
    fi
    
    cd ../../..
}

# Function to configure GitHub secrets
configure_github_secrets() {
    print_header "Configuring GitHub Secrets"
    
    # Check if secrets already exist
    existing_secrets=$(gh secret list 2>/dev/null | grep -E "(AWS_ACCOUNT_ID|ECR_REPOSITORY_PREFIX|DEPLOYMENT_BUCKET)" || true)
    
    if [ -n "$existing_secrets" ]; then
        print_warning "Some secrets already exist:"
        echo "$existing_secrets"
        read -p "Do you want to update them? (y/N): " update_secrets
        if [[ ! $update_secrets =~ ^[Yy]$ ]]; then
            print_info "Skipping GitHub secrets configuration"
            return
        fi
    fi
    
    # Set secrets
    print_info "Setting GitHub secrets..."
    
    gh secret set AWS_ACCOUNT_ID --body "$AWS_ACCOUNT_ID" 2>/dev/null || true
    gh secret set ECR_REPOSITORY_PREFIX --body "$ECR_REPOSITORY_PREFIX" 2>/dev/null || true
    
    if [ -n "$DEPLOYMENT_BUCKET" ]; then
        gh secret set DEPLOYMENT_BUCKET --body "$DEPLOYMENT_BUCKET" 2>/dev/null || true
    fi
    
    print_success "GitHub secrets configured"
}

# Function to create ECR repositories
create_ecr_repositories() {
    print_header "Creating ECR Repositories"
    
    for service in authentication; do
        repo_name="$ECR_REPOSITORY_PREFIX/$service"
        
        if aws ecr describe-repositories --repository-names "$repo_name" >/dev/null 2>&1; then
            print_info "ECR repository $repo_name already exists"
        else
            print_info "Creating ECR repository: $repo_name"
            aws ecr create-repository --repository-name "$repo_name" --region "$AWS_REGION"
            print_success "Created ECR repository: $repo_name"
        fi
    done
}

# Function to display next steps
display_next_steps() {
    print_header "Setup Complete!"
    
    echo
    print_success "CodeDeploy infrastructure has been configured successfully!"
    echo
    print_info "Next steps:"
    echo "1. Install CodeDeploy agent on your EC2 instances:"
    echo "   #!/bin/bash"
    echo "   yum update -y"
    echo "   yum install -y ruby wget"
    echo "   cd /home/ec2-user"
    echo "   wget https://aws-codedeploy-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/install"
    echo "   chmod +x ./install"
    echo "   ./install auto"
    echo "   service codedeploy-agent start"
    echo
    echo "2. Ensure Docker Swarm is running on your instances:"
    echo "   docker swarm init  # On manager node"
    echo "   docker swarm join  # On worker nodes"
    echo
    echo "3. Create required Docker secrets:"
    echo "   docker secret create aspnetapp.pfx /path/to/certificate.pfx"
    echo
    echo "4. Create overlay network:"
    echo "   docker network create -d overlay --attachable net"
    echo
    echo "5. Test the deployment:"
    echo "   - Make changes to Microservices/Authentication/"
    echo "   - Push to main branch"
    echo "   - Check GitHub Actions for deployment status"
    echo
    print_info "Configuration Summary:"
    echo "  - AWS Account ID: $AWS_ACCOUNT_ID"
    echo "  - AWS Region: $AWS_REGION"
    echo "  - App Name: $APP_NAME"
    echo "  - Environment: $ENVIRONMENT"
    echo "  - ECR Repository Prefix: $ECR_REPOSITORY_PREFIX"
    echo "  - Deployment Bucket: $DEPLOYMENT_BUCKET"
    echo "  - GitHub Repository: $GITHUB_REPO"
    echo
}

# Main execution
main() {
    print_header "CodeDeploy Setup Script"
    
    # Check prerequisites
    print_info "Checking prerequisites..."
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed"
        print_info "Please install it from: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    if ! command_exists terraform; then
        print_error "Terraform is not installed"
        print_info "Please install it from: https://www.terraform.io/downloads.html"
        exit 1
    fi
    
    if ! command_exists gh; then
        print_error "GitHub CLI is not installed"
        print_info "Please install it from: https://cli.github.com/"
        exit 1
    fi
    
    print_success "All prerequisites are installed"
    
    # Validate credentials
    check_aws_credentials
    check_github_cli
    
    # Get configuration
    print_header "Configuration"
    
    get_input "Enter application name" "authentication-sample" "APP_NAME"
    get_input "Enter environment" "staging" "ENVIRONMENT"
    get_input "Enter ECR repository prefix" "authentication-sample" "ECR_REPOSITORY_PREFIX"
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Create ECR repositories
    create_ecr_repositories
    
    # Configure GitHub secrets
    configure_github_secrets
    
    # Display next steps
    display_next_steps
}

# Run main function
main "$@" 