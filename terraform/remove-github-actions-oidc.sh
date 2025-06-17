#!/bin/bash

#########################################
# Cleanup Terraform Pipeline Resources
# Deletes all AWS resources created by setup-pipeline.sh
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
    echo "   🗑️  Terraform Pipeline Cleanup Script"
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
    
    echo
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo
    
    print_warning "This will DELETE the following resources:"
    echo "  • IAM Role: GitHubActionsTerraform"
    echo "  • IAM Policy: TerraformGitHubActionsOIDCPolicy"
    echo "  • OIDC Provider: token.actions.githubusercontent.com"
    echo
    
    read -p "$(echo -e ${RED}Are you sure you want to delete these resources? ${NC}[y/N]: )" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled."
        exit 0
    fi
    
    echo
    read -p "$(echo -e ${RED}Type 'DELETE' to confirm: ${NC})" confirm_delete
    if [[ "$confirm_delete" != "DELETE" ]]; then
        print_info "Cleanup cancelled. You must type 'DELETE' to confirm."
        exit 0
    fi
}

# Function to detach policy from role
detach_policy_from_role() {
    print_info "Detaching policy from IAM role..."
    
    ROLE_NAME="GitHubActionsTerraform"
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/TerraformGitHubActionsOIDCPolicy"
    
    # Check if role exists and has policy attached
    if aws iam get-role --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" &> /dev/null; then
        if aws iam list-attached-role-policies --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" | grep -q "TerraformGitHubActionsOIDCPolicy"; then
            aws iam detach-role-policy \
                --profile "$AWS_PROFILE" \
                --role-name "$ROLE_NAME" \
                --policy-arn "$POLICY_ARN"
            print_success "Policy detached from role"
        else
            print_warning "Policy not attached to role, skipping detach"
        fi
    else
        print_warning "Role does not exist, skipping policy detach"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    print_info "Deleting IAM role..."
    
    ROLE_NAME="GitHubActionsTerraform"
    
    if aws iam get-role --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" &> /dev/null; then
        aws iam delete-role \
            --profile "$AWS_PROFILE" \
            --role-name "$ROLE_NAME"
        print_success "IAM role deleted"
    else
        print_warning "IAM role does not exist, skipping deletion"
    fi
}

# Function to delete IAM policy
delete_iam_policy() {
    print_info "Deleting IAM policy..."
    
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/TerraformGitHubActionsOIDCPolicy"
    
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "$POLICY_ARN" &> /dev/null; then
        aws iam delete-policy \
            --profile "$AWS_PROFILE" \
            --policy-arn "$POLICY_ARN"
        print_success "IAM policy deleted"
    else
        print_warning "IAM policy does not exist, skipping deletion"
    fi
}

# Function to delete OIDC provider
delete_oidc_provider() {
    print_info "Deleting OIDC provider..."
    
    OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    
    # Check if OIDC provider exists
    if aws iam list-open-id-connect-providers --profile "$AWS_PROFILE" | grep -q "token.actions.githubusercontent.com"; then
        aws iam delete-open-id-connect-provider \
            --profile "$AWS_PROFILE" \
            --open-id-connect-provider-arn "$OIDC_ARN"
        print_success "OIDC provider deleted"
    else
        print_warning "OIDC provider does not exist, skipping deletion"
    fi
}

# Function to display final summary
display_final_summary() {
    echo
    print_success "🎉 Pipeline cleanup completed successfully!"
    echo
    print_info "Resources that were processed:"
    echo "  ✅ IAM Role: GitHubActionsTerraform"
    echo "  ✅ IAM Policy: TerraformGitHubActionsOIDCPolicy"
    echo "  ✅ OIDC Provider: token.actions.githubusercontent.com"
    echo
    print_info "Additional cleanup steps:"
    echo "1. Remove the AWS_ACCOUNT_ID secret from your GitHub repository:"
    echo "   Settings → Secrets and variables → Actions → Delete 'AWS_ACCOUNT_ID'"
    echo
    echo "2. Your GitHub Actions workflow will no longer work until you:"
    echo "   • Run setup-pipeline.sh again, OR"
    echo "   • Set up alternative AWS credentials"
    echo
    print_warning "Note: This cleanup does NOT delete your terraform infrastructure."
    print_info "To delete infrastructure, run: terraform destroy"
    echo
}

# Main execution
main() {
    print_header
    
    check_aws_cli
    get_user_input
    get_aws_account_id
    
    echo
    print_info "Starting pipeline cleanup..."
    
    detach_policy_from_role
    delete_iam_role
    delete_iam_policy
    delete_oidc_provider
    
    display_final_summary
}

# Run main function
main "$@" 