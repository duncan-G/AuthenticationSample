#!/bin/bash

#########################################
# Interactive Terraform Pipeline Setup
# Automated OIDC authentication setup for GitHub Actions
#########################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${WHITE}"
    echo "================================================="
    echo "   🚀 Terraform Pipeline Setup Script"
    echo "================================================="
    echo -e "${NC}"
}

# Function to prompt user for input
prompt_user() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    
    if [ -n "$default_value" ]; then
        read -p "$(echo -e ${WHITE}$prompt ${NC}[${default_value}]: )" input
        if [ -z "$input" ]; then
            input="$default_value"
        fi
    else
        read -p "$(echo -e ${WHITE}$prompt: ${NC})" input
        while [ -z "$input" ]; do
            print_warning "This field is required!"
            read -p "$(echo -e ${WHITE}$prompt: ${NC})" input
        done
    fi
    
    eval "$var_name='$input'"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    print_info "Checking AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    print_success "AWS CLI is available"
}

# Function to get AWS account ID
get_aws_account_id() {
    print_info "Getting AWS Account ID using profile: $AWS_PROFILE..."
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text 2>/dev/null)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Failed to get AWS Account ID using profile '$AWS_PROFILE'"
        print_info "Please ensure:"
        print_info "1. Profile '$AWS_PROFILE' exists in your AWS config"
        print_info "2. You have run 'aws sso login --profile $AWS_PROFILE'"
        print_info "3. Your SSO session is still valid"
        exit 1
    fi
    print_success "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    echo
    
    # Get AWS profile name
    prompt_user "Enter your AWS SSO profile name" "AWS_PROFILE" "terraform-setup"
    
    # Get GitHub organization/username
    prompt_user "Enter your GitHub username/organization" "GITHUB_ORG"
    
    # Get repository name
    prompt_user "Enter your repository name" "GITHUB_REPO"
    
    # Get AWS region
    prompt_user "Enter AWS region" "AWS_REGION" "us-west-1"
    
    # Construct full repo name
    GITHUB_REPO_FULL="${GITHUB_ORG}/${GITHUB_REPO}"
    
    echo
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo "  AWS Region: $AWS_REGION"
    echo
    
    read -p "$(echo -e ${YELLOW}Do you want to proceed? ${NC}[y/N]: )" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Setup cancelled."
        exit 0
    fi
}

# Function to create OIDC provider
create_oidc_provider() {
    print_info "Creating OIDC provider..."
    
    # Check if OIDC provider already exists
    if aws iam list-open-id-connect-providers --profile "$AWS_PROFILE" | grep -q "token.actions.githubusercontent.com"; then
        print_warning "OIDC provider already exists, skipping creation"
    else
        aws iam create-open-id-connect-provider \
            --profile "$AWS_PROFILE" \
            --url https://token.actions.githubusercontent.com \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
        print_success "OIDC provider created"
    fi
}

# Function to create IAM policy
create_iam_policy() {
    print_info "Creating IAM policy..."
    
    # Check if policy already exists
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/TerraformGitHubActionsOIDCPolicy" &> /dev/null; then
        print_warning "IAM policy already exists, skipping creation"
    else
        # Substitute variables in terraform-policy.json and write to a temp file
        sed \
            -e "s|\\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
            terraform/terraform-policy.json > terraform-policy-temp.json
        
        aws iam create-policy \
            --profile "$AWS_PROFILE" \
            --policy-name TerraformGitHubActionsOIDCPolicy \
            --policy-document file://terraform-policy-temp.json
        print_success "IAM policy created"
    fi
}

# Function to create trust policy
create_trust_policy() {
    print_info "Creating trust policy..."
    
    # Substitute variables in trust-policy.json and write to a temp file
    sed \
        -e "s|\\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\\${GITHUB_REPO_FULL}|$GITHUB_REPO_FULL|g" \
        terraform/github-trust-policy.json > github-trust-policy.json
    print_success "Trust policy created"
}

# Function to create IAM role
create_iam_role() {
    print_info "Creating IAM role..."
    
    # Check if role already exists
    if aws iam get-role --profile "$AWS_PROFILE" --role-name GitHubActionsTerraform &> /dev/null; then
        print_warning "IAM role already exists, updating trust policy"
        aws iam update-assume-role-policy \
            --profile "$AWS_PROFILE" \
            --role-name GitHubActionsTerraform \
            --policy-document file://github-trust-policy.json
    else
        aws iam create-role \
            --profile "$AWS_PROFILE" \
            --role-name GitHubActionsTerraform \
            --assume-role-policy-document file://github-trust-policy.json
        print_success "IAM role created"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --profile "$AWS_PROFILE" \
        --role-name GitHubActionsTerraform \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/TerraformGitHubActionsOIDCPolicy"
    
    print_success "Policy attached to role"
}

# Function to cleanup temporary files
cleanup() {
    print_info "Cleaning up temporary files..."
    rm -f github-trust-policy.json terraform-policy-temp.json
    print_success "Cleanup completed"
}

# Function to display final instructions
display_final_instructions() {
    echo
    print_success "🎉 Pipeline setup completed successfully!"
    echo
    print_info "Next steps:"
    echo "1. Add this secret to your GitHub repository:"
    echo "   Settings → Secrets and variables → Actions → New repository secret"
    echo
    echo -e "${YELLOW}   Secret Name: ${NC}AWS_ACCOUNT_ID"
    echo -e "${YELLOW}   Secret Value: ${NC}$AWS_ACCOUNT_ID"
    echo
    echo "2. Your IAM Role ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:role/GitHubActionsTerraform${NC}"
    echo
    print_info "You can now use the GitHub Actions workflow!"
    echo "   • Manual: Actions → 'Terraform Infrastructure' → Run workflow"
    echo "   • Automatic: Pull requests will show terraform plans"
    echo
}

# Main execution
main() {
    print_header
    
    check_aws_cli
    get_user_input
    get_aws_account_id
    
    echo
    print_info "Starting pipeline setup..."
    
    create_oidc_provider
    create_iam_policy
    create_trust_policy
    create_iam_role
    cleanup
    
    display_final_instructions
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@" 