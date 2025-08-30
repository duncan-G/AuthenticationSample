#!/bin/bash

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"

print_header "📧 SES Domain Identity Setup Script"

# Resolve Route53 hosted zone id for an exact domain
get_route53_hosted_zone_id() {
    local domain_name="$1"
    print_info "Looking up Route53 hosted zone for domain: $domain_name"
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --profile "$AWS_PROFILE" --query "HostedZones[?Name=='${domain_name}.'].Id" --output text 2>/dev/null)
    if [ -z "$HOSTED_ZONE_ID" ]; then
        print_error "Could not find Route53 hosted zone for domain: $domain_name"
        print_error "Please ensure the hosted zone exists in Route53 before running this script"
        exit 1
    fi
    HOSTED_ZONE_ID=$(echo "$HOSTED_ZONE_ID" | sed 's|/hostedzone/||')
    ROUTE53_HOSTED_ZONE_ID="$HOSTED_ZONE_ID"
    print_success "Found Route53 hosted zone ID: $ROUTE53_HOSTED_ZONE_ID"
}

get_user_input() {
    print_info "Please provide the following information:"
    prompt_user "Enter AWS SSO profile name" "AWS_PROFILE" "infra-setup"
    prompt_user "Enter SES region" "AWS_REGION" "us-west-1"
    prompt_user "Enter root domain (e.g., example.com)" "DOMAIN_NAME"
    if ! prompt_confirmation "Wait for SES and DKIM verification to complete?" "Y/n"; then
        NO_WAIT=1
    else
        NO_WAIT=0
    fi
    get_route53_hosted_zone_id "$DOMAIN_NAME"

    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  SES Region: $AWS_REGION"
    echo "  Domain: $DOMAIN_NAME"
    echo "  Route53 Hosted Zone ID: $ROUTE53_HOSTED_ZONE_ID"
    echo "  Wait for verification: $([[ ${NO_WAIT:-0} -eq 0 ]] && echo yes || echo no)"

    if ! prompt_confirmation "Do you want to proceed?" "y/N"; then
        print_info "Setup cancelled."
        exit 0
    fi
}

main() {
    check_aws_cli

    get_user_input

    if ! check_aws_profile "$AWS_PROFILE"; then exit 1; fi
    if ! check_aws_authentication "$AWS_PROFILE"; then exit 1; fi
    validate_aws_region "$AWS_REGION"

    print_info "[1/6] Ensuring SES domain identity for $DOMAIN_NAME in $AWS_REGION"
    VERIFY_TOKEN=$(aws ses verify-domain-identity \
        --domain "$DOMAIN_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'VerificationToken' --output text || true)
    if [[ "$VERIFY_TOKEN" == "None" || -z "$VERIFY_TOKEN" ]]; then
        print_warning "SES verify-domain-identity returned no token; proceeding (identity may already exist)."
    else
        print_success "Obtained domain verification token."
        print_info "[2/6] Upserting Route53 TXT record for domain verification"
        CHANGE_BATCH_FILE=$(mktemp)
        cat > "$CHANGE_BATCH_FILE" <<EOF
{
  "Comment": "Upsert SES domain verification for $DOMAIN_NAME",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "_amazonses.$DOMAIN_NAME",
        "Type": "TXT",
        "TTL": 600,
        "ResourceRecords": [ { "Value": "\\"$VERIFY_TOKEN\\"" } ]
      }
    }
  ]
}
EOF
        aws route53 change-resource-record-sets \
          --hosted-zone-id "$ROUTE53_HOSTED_ZONE_ID" \
          --change-batch file://"$CHANGE_BATCH_FILE" \
          --profile "$AWS_PROFILE" >/dev/null || print_warning "Failed to upsert TXT record (it may already exist)"
        rm -f "$CHANGE_BATCH_FILE"
    fi

    print_info "[3/6] Requesting DKIM verification tokens"
    read -r T1 T2 T3 < <(aws ses verify-domain-dkim \
      --domain "$DOMAIN_NAME" \
      --region "$AWS_REGION" \
      --profile "$AWS_PROFILE" \
      --query 'DkimTokens' --output text)

    print_info "[4/6] Upserting Route53 CNAME records for DKIM"
    CHANGE_BATCH_FILE=$(mktemp)
    cat > "$CHANGE_BATCH_FILE" <<EOF
{
  "Comment": "Upsert SES DKIM records for $DOMAIN_NAME",
  "Changes": [
    {"Action": "UPSERT", "ResourceRecordSet": {"Name": "$T1._domainkey.$DOMAIN_NAME", "Type": "CNAME", "TTL": 600, "ResourceRecords": [{"Value": "$T1.dkim.amazonses.com"}] }},
    {"Action": "UPSERT", "ResourceRecordSet": {"Name": "$T2._domainkey.$DOMAIN_NAME", "Type": "CNAME", "TTL": 600, "ResourceRecords": [{"Value": "$T2.dkim.amazonses.com"}] }},
    {"Action": "UPSERT", "ResourceRecordSet": {"Name": "$T3._domainkey.$DOMAIN_NAME", "Type": "CNAME", "TTL": 600, "ResourceRecords": [{"Value": "$T3.dkim.amazonses.com"}] }}
  ]
}
EOF
    aws route53 change-resource-record-sets \
      --hosted-zone-id "$ROUTE53_HOSTED_ZONE_ID" \
      --change-batch file://"$CHANGE_BATCH_FILE" \
      --profile "$AWS_PROFILE" >/dev/null
    rm -f "$CHANGE_BATCH_FILE"

    if [[ ${NO_WAIT:-0} -eq 0 ]]; then
        print_info "[5/6] Waiting for SES domain verification to complete..."
        for attempt in {1..40}; do
            STATUS=$(aws ses get-identity-verification-attributes \
              --identities "$DOMAIN_NAME" \
              --region "$AWS_REGION" \
              --profile "$AWS_PROFILE" \
              --query 'VerificationAttributes["'"$DOMAIN_NAME"'"]'.VerificationStatus --output text)
            echo "  Attempt $attempt: status=$STATUS"
            [[ "$STATUS" == "Success" ]] && break
            sleep 30
        done

        print_info "[5/6] Waiting for DKIM verification to complete..."
        for attempt in {1..40}; do
            DSTATUS=$(aws ses get-identity-dkim-attributes \
              --identities "$DOMAIN_NAME" \
              --region "$AWS_REGION" \
              --profile "$AWS_PROFILE" \
              --query 'DkimAttributes["'"$DOMAIN_NAME"'"]'.DkimVerificationStatus --output text)
            echo "  Attempt $attempt: dkim_status=$DSTATUS"
            [[ "$DSTATUS" == "Success" ]] && break
            sleep 30
        done
    fi

    ACCOUNT_ID=$(get_aws_account_id "$AWS_PROFILE")
    SES_IDENTITY_ARN="arn:aws:ses:$AWS_REGION:$ACCOUNT_ID:identity/$DOMAIN_NAME"

    print_success "[6/6] SES setup complete"
    echo "Your SES identity ARN:"
    echo -e "${GREEN}  $SES_IDENTITY_ARN${NC}"
    echo
    print_info "Export this as a Terraform variable:"
    echo -e "${GREEN}  export TF_VAR_ses_identity_arn=$SES_IDENTITY_ARN${NC}"
}

main "$@"


