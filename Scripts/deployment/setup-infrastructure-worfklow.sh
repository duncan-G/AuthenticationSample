#!/bin/bash

#########################################
# Github Actions workflow setup for Terraform and CodeDeploy.
# Provides github actions with the ability to run terraform plans/apply and deploy to AWS CodeDeploy.
#########################################

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"
source "$UTILS_DIR/github-utils.sh"

print_header "🚀 Terraform Github Actions Workflow Setup Script"

# Function to get Route53 hosted zone ID from domain
get_route53_hosted_zone_id() {
    local domain_name="$1"
    
    print_info "Looking up Route53 hosted zone for domain: $domain_name"
    
    # Find the hosted zone for the exact domain name
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --profile "$AWS_PROFILE" --query "HostedZones[?Name=='${domain_name}.'].Id" --output text 2>/dev/null)
    
    if [ -z "$HOSTED_ZONE_ID" ]; then
        print_error "Could not find Route53 hosted zone for domain: $domain_name"
        print_error "Please ensure the hosted zone exists in Route53 before running this script"
        exit 1
    else
        # Remove the /hostedzone/ prefix if present
        HOSTED_ZONE_ID=$(echo "$HOSTED_ZONE_ID" | sed 's|/hostedzone/||')
        ROUTE53_HOSTED_ZONE_ID="$HOSTED_ZONE_ID"
        print_success "Found Route53 hosted zone ID: $ROUTE53_HOSTED_ZONE_ID"
    fi
}

# Function to get user input
get_user_input() {
    print_info "Please provide the following information:"
    
    prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "terraform-setup"
        
    AWS_ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    prompt_user "Enter application name (used for Terraform resource naming)" "APP_NAME"
    prompt_user "Enter AWS region" "AWS_REGION" "us-west-1"
    prompt_user "Enter terraform staging environment name" "STAGING_ENVIRONMENT" "terraform-staging"
    prompt_user "Enter terraform production environment name" "PRODUCTION_ENVIRONMENT" "terraform-production"
    prompt_user "Enter staging environment name" "CODEDEPLOY_STAGING_ENVIRONMENT" "staging"
    prompt_user "Enter production environment name" "CODEDEPLOY_PRODUCTION_ENVIRONMENT" "production"
    
    prompt_user "Enter domain name (e.g., example.com)" "DOMAIN_NAME"
    prompt_user "Enter API subdomains (comma-separated, e.g., api,admin,portal)" "SUBDOMAINS" "api,internal"
    prompt_user "Enter email address for domain verification" "ACME_EMAIL"
    
    # Get Route53 hosted zone ID automatically
    get_route53_hosted_zone_id "$DOMAIN_NAME"
    
    # Calculate bucket suffix using the same logic as elsewhere
    BUCKET_SUFFIX=$(echo "${AWS_ACCOUNT_ID}-${GITHUB_REPO_FULL}" | md5sum | cut -c1-8)

    print_info "Calculated bucket suffix: $BUCKET_SUFFIX"
    
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo "  Terraform App Name: $APP_NAME"
    echo "  AWS Region: $AWS_REGION"
    echo "  Terraform Staging Environment: $STAGING_ENVIRONMENT"
    echo "  Terraform Production Environment: $PRODUCTION_ENVIRONMENT"
    echo "  CodeDeploy Staging Environment: $CODEDEPLOY_STAGING_ENVIRONMENT"
    echo "  CodeDeploy Production Environment: $CODEDEPLOY_PRODUCTION_ENVIRONMENT"
    echo "  Domain Name: $DOMAIN_NAME"
    echo "  Route53 Hosted Zone ID: $ROUTE53_HOSTED_ZONE_ID"
    echo "  API Subdomains: $SUBDOMAINS"
    echo "  Email Address: $ACME_EMAIL"
    
    if ! prompt_confirmation "Do you want to proceed?" "y/N"; then
        print_info "Setup cancelled."
        exit 0
    fi
}

# Function to create S3 bucket for Terraform state
create_terraform_state_backend() {
    TF_STATE_BUCKET="terraform-state-${BUCKET_SUFFIX}"
    
    print_info "Creating S3 bucket for Terraform state backend: $TF_STATE_BUCKET"

    if ! aws s3api head-bucket --bucket "$TF_STATE_BUCKET" --profile "$AWS_PROFILE" 2>/dev/null; then
        aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" --profile "$AWS_PROFILE"
        print_success "S3 bucket $TF_STATE_BUCKET created."
    else
        print_warning "S3 bucket $TF_STATE_BUCKET already exists."
    fi

    aws s3api put-bucket-versioning --bucket "$TF_STATE_BUCKET" --versioning-configuration Status=Enabled --profile "$AWS_PROFILE"
}

# Function to create S3 bucket for SSL certificates
create_certificate_bucket() {
    CERTIFICATE_BUCKET="${APP_NAME}-certificate-store-${BUCKET_SUFFIX}"
    
    # Certificate bucket lifecycle configuration
    local certificate_lifecycle='{
      "Rules": [
        {
          "ID": "ssl_certificate_cleanup",
          "Status": "Enabled",
          "Filter": {},
          "NoncurrentVersionExpiration": {
            "NoncurrentDays": 30
          },
          "Expiration": {
            "Days": 365
          }
        }
      ]
    }'
    
    print_info "Creating certificate bucket..."
    create_s3_bucket_with_lifecycle "$CERTIFICATE_BUCKET" "$AWS_REGION" "$AWS_PROFILE" "production" "${APP_NAME}-certificate-store" "$certificate_lifecycle"
    print_success "Certificate bucket created successfully."
}

# Function to create S3 bucket for CodeDeploy
create_codedeploy_bucket() {
    DEPLOYMENT_BUCKET="${APP_NAME}-codedeploy-${BUCKET_SUFFIX}"
    
    # CodeDeploy bucket lifecycle configuration
    local codedeploy_lifecycle='{
      "Rules": [
        {
          "ID": "deployment_cleanup",
          "Status": "Enabled",
          "Filter": {},
          "NoncurrentVersionExpiration": {
            "NoncurrentDays": 30
          },
          "Expiration": {
            "Days": 90
          }
        }
      ]
    }'
    
    print_info "Creating CodeDeploy bucket..."
    create_s3_bucket_with_lifecycle "$DEPLOYMENT_BUCKET" "$AWS_REGION" "$AWS_PROFILE" "production" "${APP_NAME}-codedeploy" "$codedeploy_lifecycle"
    print_success "CodeDeploy bucket created successfully."
}

# Function to create OIDC provider
create_oidc_provider() {
    print_info "Creating OIDC provider..."
    
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
    local policy_file_path="$1"
    
    print_info "Creating IAM policy for Terraform..."
    
    if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-terraform" &> /dev/null; then
        print_warning "IAM policy already exists, skipping creation"
    else
        aws iam create-policy \
            --profile "$AWS_PROFILE" \
            --policy-name "github-actions-oidc-policy-terraform" \
            --policy-document "file://$policy_file_path"
        print_success "IAM policy created"
    fi
}

# Function to create IAM role
create_iam_role() {
    local trust_policy_file_path="$1"
    
    print_info "Creating IAM role for Terraform..."
    
    if aws iam get-role --profile "$AWS_PROFILE" --role-name "github-actions-terraform" &> /dev/null; then
        print_warning "IAM role already exists, updating trust policy"
        aws iam update-assume-role-policy \
            --profile "$AWS_PROFILE" \
            --role-name "github-actions-terraform" \
            --policy-document "file://$trust_policy_file_path" \
            --no-cli-pager
    else
        aws iam create-role \
            --profile "$AWS_PROFILE" \
            --role-name "github-actions-terraform" \
            --assume-role-policy-document "file://$trust_policy_file_path" \
            --no-cli-pager
        print_success "IAM role created"
    fi
    
    aws iam attach-role-policy \
        --profile "$AWS_PROFILE" \
        --role-name "github-actions-terraform" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/github-actions-oidc-policy-terraform"
    
    print_success "Policy attached to role"
}

#######################################################################
# create_application_secrets
# --------------------------
# Build a JSON payload (static + existing secrets) and create or
# update an AWS Secrets Manager secret named "<APP_NAME>-secrets".
#######################################################################
create_application_secrets() {
  local -r secret_name="${APP_NAME:?}-secrets"
  local -r aws_opts=(--profile "${AWS_PROFILE:?}")
  local secret_json

  print_info "Creating/updating AWS secret: $secret_name"

  # ------------------------------------------------------------------
  # 1. Static JSON – safest to let jq assemble it for proper escaping
  # ------------------------------------------------------------------
  local static_json
  local subdomain_json="{}"

  # --------------------------------------------------------------
  # 1a. Build flat SUBDOMAIN_<n> entries if SUBDOMAINS is provided
  # --------------------------------------------------------------
  if [[ -n "$SUBDOMAINS" ]]; then
    print_info "Processing subdomains: $SUBDOMAINS"
    # shellcheck disable=SC2016
    subdomain_json=$(echo "$SUBDOMAINS" | tr ',' '\n' | jq -Rn --arg DOMAIN_NAME "$DOMAIN_NAME" '
      # Read each line (sub-domain) into an array
      [inputs] as $subs
      # Reduce into {"SUBDOMAIN_NAME_1": "foo.example.com", ...}
      | reduce range(0; $subs|length) as $i ({}; 
          . + {("SUBDOMAIN_NAME_" + ($i + 1 | tostring)) : 
               ($subs[$i] + ( $DOMAIN_NAME    # append ".<domain>" only if set
                               | if length>0 then "." + . else "" end ))}
        )
    ')
  fi

  # ----------------------------------------------------------------
  # 1b. Assemble static JSON with sub-domain pairs
  # ----------------------------------------------------------------
  secret_json=$(jq -n \
      --arg APP_NAME "$APP_NAME" \
      --arg CERTIFICATE_STORE "${APP_NAME}-certificate-store-${BUCKET_SUFFIX}" \
      --arg ACME_EMAIL "$ACME_EMAIL" \
      --arg DOMAIN_NAME "$DOMAIN_NAME" \
      --argjson SUBDOMAIN_PAIRS "$subdomain_json" \
      '{
         APP_NAME:         $APP_NAME,
         CERTIFICATE_STORE:$CERTIFICATE_STORE,
         DOMAIN_NAME:      $DOMAIN_NAME,
         ACME_EMAIL:       $ACME_EMAIL
       } + $SUBDOMAIN_PAIRS')

  # ------------------------------------------------------------------
  # 2. Create or update the secret
  # ------------------------------------------------------------------
  if aws secretsmanager describe-secret --secret-id "$secret_name" "${aws_opts[@]}" &>/dev/null; then
    print_warning "Secret exists – updating"
    aws secretsmanager update-secret \
        --secret-id "$secret_name" \
        --secret-string "$secret_json" \
        "${aws_opts[@]}"
    print_success "Secret $secret_name updated ✔"
  else
    print_info "Secret not found – creating"
    aws secretsmanager create-secret \
        --name "$secret_name" \
        --description "Application configuration for $APP_NAME" \
        --secret-string "$secret_json" \
        "${aws_opts[@]}"
    print_success "Secret $secret_name created ✔"
  fi
}

# Function to build and push certbot image to ECR
build_and_push_certbot_image() {
    print_info "Building and pushing certbot image to ECR..."
    
    # Get ECR login token
    print_info "Getting ECR login token..."
    aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | \
        docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    # Create ECR repository if it doesn't exist
    local ecr_repo_name="${APP_NAME}/certbot"
    local ecr_repo_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ecr_repo_name}"
    
    print_info "Creating ECR repository: $ecr_repo_name"
    if ! aws ecr describe-repositories --repository-names "$ecr_repo_name" --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
        aws ecr create-repository \
            --repository-name "$ecr_repo_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"
        print_success "ECR repository $ecr_repo_name created"
    else
        print_warning "ECR repository $ecr_repo_name already exists"
    fi
    
    # Build the certbot image
    print_info "Building certbot Docker image..."
    local certbot_dir="$(cd "$SCRIPT_DIR/../../Infrastructure/certbot" && pwd)"
    
    cd "$certbot_dir"
    docker build -t "$ecr_repo_name:latest" .
    
    if [ $? -eq 0 ]; then
        print_success "Certbot image built successfully"
    else
        print_error "Failed to build certbot image"
        exit 1
    fi
    
    # Tag the image for ECR
    docker tag "$ecr_repo_name:latest" "$ecr_repo_uri:latest"
    
    # Push the image to ECR
    print_info "Pushing certbot image to ECR..."
    docker push "$ecr_repo_uri:latest"
    
    if [ $? -eq 0 ]; then
        print_success "Certbot image pushed to ECR successfully"
        print_info "ECR Image URI: $ecr_repo_uri:latest"
    else
        print_error "Failed to push certbot image to ECR"
        exit 1
    fi
    
    # Return to original directory
    cd - > /dev/null
}

# Function to create EBS volume for Let's Encrypt certificates
create_certbot_ebs_volume() {
    print_info "Creating EBS volume for Let's Encrypt certificates..."
    
    local volume_name="${APP_NAME}-letsencrypt-persistent"
    local availability_zone
    
    # Get availability zone from the region
    availability_zone=$(aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'AvailabilityZones[0].ZoneName' \
        --output text)
    
    print_info "Using availability zone: $availability_zone"
    
    # Check if volume already exists
    local existing_volume_id
    existing_volume_id=$(aws ec2 describe-volumes \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --filters "Name=tag:Name,Values=$volume_name" \
        --query 'Volumes[0].VolumeId' \
        --output text 2>/dev/null)
    
    if [ "$existing_volume_id" != "None" ] && [ -n "$existing_volume_id" ]; then
        print_warning "EBS volume already exists: $existing_volume_id"
        print_info "Volume name: $volume_name"
        print_info "Volume ID: $existing_volume_id"
        return 0
    fi
    
    # Create the EBS volume
    print_info "Creating new EBS volume..."
    local volume_id
    volume_id=$(aws ec2 create-volume \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --size 1 \
        --volume-type gp3 \
        --encrypted \
        --availability-zone "$availability_zone" \
        --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=$volume_name},{Key=Purpose,Value='Let\'s Encrypt certificates'},{Key=Environment,Value='production'},{Key=ManagedBy,Value='manual'}]" \
        --query 'VolumeId' \
        --output text)
    
    if [ $? -eq 0 ] && [ -n "$volume_id" ]; then
        print_success "EBS volume created successfully"
        print_info "Volume ID: $volume_id"
        print_info "Volume name: $volume_name"
        print_info "Size: 1 GB"
        print_info "Type: gp3"
        print_info "Encrypted: Yes"
        print_info "Availability Zone: $availability_zone"
        
        # Wait for volume to be available
        print_info "Waiting for volume to become available..."
        aws ec2 wait volume-available \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --volume-ids "$volume_id"
        
        print_success "EBS volume is ready for use"
        print_warning "Note: This volume will need to be manually attached to your EC2 instance after infrastructure deployment"
        print_info "The volume will be attached to the public instance at device /dev/sdf"
    else
        print_error "Failed to create EBS volume"
        exit 1
    fi
}

# Function to setup OIDC infrastructure
setup_oidc_infrastructure() {
    print_info "Setting up OIDC infrastructure..."
    
    ORIGINAL_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/terraform-policy.json"
    ORIGINAL_TRUST_POLICY_FILE_PATH="$(cd "$SCRIPT_DIR/../../Infrastructure/terraform" && pwd)/github-trust-policy.json"
    
    PROCESSED_POLICY_FILE_PATH="$(pwd)/terraform-policy-processed.json"
    PROCESSED_TRUST_POLICY_FILE_PATH="$(pwd)/github-trust-policy-processed.json"

    CERTIFICATE_BUCKET="${APP_NAME}-certificate-store-${BUCKET_SUFFIX}"
    DEPLOYMENT_BUCKET="${APP_NAME}-codedeploy-${BUCKET_SUFFIX}"
    
    print_info "Processing policy files with variable substitution..."
    
    sed \
        -e "s|\${APP_NAME}|$APP_NAME|g" \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${TF_STATE_BUCKET}|$TF_STATE_BUCKET|g" \
        -e "s|\${CERTIFICATE_BUCKET}|$CERTIFICATE_BUCKET|g" \
        -e "s|\${DEPLOYMENT_BUCKET}|$DEPLOYMENT_BUCKET|g" \
        "$ORIGINAL_POLICY_FILE_PATH" > "$PROCESSED_POLICY_FILE_PATH"
    
    sed \
        -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${GITHUB_REPO_FULL}|$GITHUB_REPO_FULL|g" \
        -e "s|\${STAGING_ENVIRONMENT}|$STAGING_ENVIRONMENT|g" \
        -e "s|\${PRODUCTION_ENVIRONMENT}|$PRODUCTION_ENVIRONMENT|g" \
        "$ORIGINAL_TRUST_POLICY_FILE_PATH" > "$PROCESSED_TRUST_POLICY_FILE_PATH"
    
    create_oidc_provider
    
    create_iam_policy "$PROCESSED_POLICY_FILE_PATH"
    create_iam_role "$PROCESSED_TRUST_POLICY_FILE_PATH"
    
    rm -f "$PROCESSED_POLICY_FILE_PATH" "$PROCESSED_TRUST_POLICY_FILE_PATH"
}

# Function to setup GitHub secrets and environments
setup_github_workflow() {
    print_info "Setting up GitHub secrets and environments..."

    # Convert comma-separated subdomains to Terraform list format
    # Terraform expects a JSON array like ["api", "admin", "portal"]
    # but we accept comma-separated input like "api,admin,portal"
    local subdomains_list
    if [[ -n "$SUBDOMAINS" ]]; then
        # Convert comma-separated string to JSON array format for Terraform
        # Example: "api,admin,portal" -> ["api", "admin", "portal"]
        subdomains_list=$(echo "$SUBDOMAINS" | tr ',' '\n' | jq -R . | jq -s .)
        print_info "Converted subdomains to Terraform list format: $subdomains_list"
    else
        subdomains_list='[]'
        print_warning "No subdomains provided, using empty list"
    fi

    add_github_secrets "$GITHUB_REPO_FULL" \
        "AWS_ACCOUNT_ID:$AWS_ACCOUNT_ID" \
        "TF_STATE_BUCKET:$TF_STATE_BUCKET" \
        "ROUTE53_HOSTED_ZONE_ID:$ROUTE53_HOSTED_ZONE_ID" \
        "BUCKET_SUFFIX:$BUCKET_SUFFIX" \
        "SUBDOMAINS:$subdomains_list"
    
    add_github_variables "$GITHUB_REPO_FULL" \
        "AWS_REGION:$AWS_REGION" \
        "APP_NAME:$APP_NAME" \
        "DOMAIN_NAME:$DOMAIN_NAME" \

    create_github_environments "$GITHUB_REPO_FULL" \
        "$STAGING_ENVIRONMENT" \
        "$PRODUCTION_ENVIRONMENT"
    
    create_github_environments "$GITHUB_REPO_FULL" \
        "$CODEDEPLOY_STAGING_ENVIRONMENT" \
        "$CODEDEPLOY_PRODUCTION_ENVIRONMENT"
}

# Function to display final instructions
display_final_instructions() {
    print_success "🎉 Terraform and CodeDeploy workflow setup completed successfully!"
    
    print_info "Your setup is complete and ready to use!"
    
    # Calculate ECR repository information
    local ecr_repo_name="${APP_NAME}/certbot"
    local ecr_repo_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ecr_repo_name}"
    
    echo "Your Terraform State Bucket:"
    echo -e "${GREEN}   $TF_STATE_BUCKET${NC}"
    echo "Your Terraform IAM Role ARN:"
    echo -e "${GREEN}   arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-terraform${NC}"
    echo "Your Application Secrets Manager Secret:"
    echo -e "${GREEN}   ${APP_NAME}-secrets${NC}"
    echo "Your ECR Certbot Repository:"
    echo -e "${GREEN}   $ecr_repo_uri${NC}"
    echo "Your EBS Volume for Let's Encrypt:"
    echo -e "${GREEN}   Volume Name: ${APP_NAME}-letsencrypt-persistent${NC}"
    echo -e "${GREEN}   Device: /dev/sdf (will be attached to public instance)${NC}"
    echo "Your Domain Configuration:"
    echo -e "${GREEN}   Domain: $DOMAIN_NAME${NC}"
    echo -e "${GREEN}   API Subdomains: $SUBDOMAINS${NC}"
    echo -e "${GREEN}   Route53 Zone ID: $ROUTE53_HOSTED_ZONE_ID${NC}"
    
    print_info "You can now use the GitHub Actions workflows!"
    echo "   • Terraform: Actions → 'Infrastructure Release' → Run workflow"
    echo "   • CodeDeploy: Actions → 'Authentication Service Deployment' → Run workflow"
    echo "   • Automatic: Pull requests will show terraform plans"
    
    print_info "Next steps:"
    echo "   1. Deploy infrastructure using Terraform workflow"
    echo "   2. Use CodeDeploy workflows for application deployments"
    echo "   3. Application services will use the created Secrets Manager secret"
    echo "   4. Certificate renewal will use the ECR certbot image"
}

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo
    echo "This script sets up the complete Terraform and CodeDeploy workflow infrastructure including:"
    echo "  - Variable substitution in policy files"
    echo "  - OIDC provider and IAM roles/policies for Terraform and CodeDeploy"
    echo "  - S3 bucket for Terraform state backend"
    echo "  - AWS Secrets Manager secret for application configuration"
    echo "  - ECR repository creation and certbot image building/pushing"
    echo "  - GitHub repository secrets and variables"
    echo "  - GitHub environments for Terraform and CodeDeploy"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate profile"
    echo "  - GitHub CLI authenticated"
    echo "  - Docker installed and running"
    exit 1
}

# Function to check Docker availability
check_docker() {
    print_info "Checking Docker availability..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        print_error "Please install Docker and ensure it's running"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running or not accessible"
        print_error "Please start Docker and ensure you have permissions to run docker commands"
        exit 1
    fi
    
    print_success "Docker is available and running"
}

# Main execution
main() {
    if [ $# -ne 0 ]; then
        show_usage
    fi
    
    check_aws_cli
    check_github_cli
    check_docker

    GITHUB_REPO_FULL=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    if ! validate_repo "$GITHUB_REPO_FULL"; then
        exit 1
    fi

    get_user_input

    if ! check_aws_profile "$AWS_PROFILE"; then
        exit 1
    fi
    
    if ! check_aws_authentication "$AWS_PROFILE"; then
        exit 1
    fi

    validate_aws_region "$AWS_REGION"
    
    print_info "Setting up AWS permissions for Terraform and CodeDeploy deployments..."
    
    create_terraform_state_backend
    create_certificate_bucket
    create_codedeploy_bucket
    setup_oidc_infrastructure
    create_application_secrets
    build_and_push_certbot_image
    create_certbot_ebs_volume
    setup_github_workflow
    
    display_final_instructions
}

# Run main function
main "$@"
