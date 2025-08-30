#!/bin/bash

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../utils" && pwd)"
source "$UTILS_DIR/print-utils.sh"
source "$UTILS_DIR/prompt.sh"
source "$UTILS_DIR/aws-utils.sh"

print_header "🧹 Remove SES Verification TXT Record"

get_route53_hosted_zone_id() {
    local domain_name="$1"
    print_info "Looking up Route53 hosted zone for domain: $domain_name"
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --profile "$AWS_PROFILE" --query "HostedZones[?Name=='${domain_name}.'].Id" --output text 2>/dev/null)
    if [ -z "$HOSTED_ZONE_ID" ]; then
        print_error "Could not find Route53 hosted zone for domain: $domain_name"
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
    get_route53_hosted_zone_id "$DOMAIN_NAME"
    print_info "Configuration Summary:"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  SES Region: $AWS_REGION"
    echo "  Domain: $DOMAIN_NAME"
    echo "  Route53 Hosted Zone ID: $ROUTE53_HOSTED_ZONE_ID"
    if ! prompt_confirmation "Proceed to delete _amazonses.$DOMAIN_NAME TXT record?" "y/N"; then
        print_info "Cleanup cancelled."
        exit 0
    fi
}

main() {
    check_aws_cli

    get_user_input

    if ! check_aws_profile "$AWS_PROFILE"; then exit 1; fi
    if ! check_aws_authentication "$AWS_PROFILE"; then exit 1; fi
    validate_aws_region "$AWS_REGION"

    print_info "Looking up existing TXT record for _amazonses.$DOMAIN_NAME"
    R53_JSON=$(aws route53 list-resource-record-sets \
      --hosted-zone-id "$ROUTE53_HOSTED_ZONE_ID" \
      --profile "$AWS_PROFILE" \
      --query 'ResourceRecordSets[?Name==`_amazonses.'"$DOMAIN_NAME"'.` && Type==`TXT`]' \
      --output json)

    COUNT=$(echo "$R53_JSON" | jq 'length')
    if [[ "$COUNT" -eq 0 ]]; then
      print_warning "No verification TXT record found; nothing to do."
      exit 0
    fi

    VALUE=$(echo "$R53_JSON" | jq -r '.[0].ResourceRecords[0].Value')

    print_info "Deleting _amazonses.$DOMAIN_NAME TXT record"
    CHANGE_BATCH_FILE=$(mktemp)
    cat > "$CHANGE_BATCH_FILE" <<EOF
{
  "Comment": "Delete SES domain verification for $DOMAIN_NAME",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "_amazonses.$DOMAIN_NAME",
        "Type": "TXT",
        "TTL": 600,
        "ResourceRecords": [ { "Value": $VALUE } ]
      }
    }
  ]
}
EOF
    aws route53 change-resource-record-sets \
      --hosted-zone-id "$ROUTE53_HOSTED_ZONE_ID" \
      --change-batch file://"$CHANGE_BATCH_FILE" \
      --profile "$AWS_PROFILE" >/dev/null
    rm -f "$CHANGE_BATCH_FILE"

    print_success "Deleted verification TXT record. DKIM CNAMEs and SES identity were left intact."
}

main "$@"


