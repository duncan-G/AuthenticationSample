#!/usr/bin/env bash
set -euo pipefail

# Get AWS credentials via IMDSv2
AWS_ROLE_NAME="auth-sample-ec2-public-instance-role"
token=$(curl -sSf -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token)
creds_json=$(curl -sSf -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/iam/security-credentials/$AWS_ROLE_NAME")

export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<< "$creds_json")
export AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<< "$creds_json")
export AWS_SESSION_TOKEN=$(jq -r .Token <<< "$creds_json")
export AWS_DEFAULT_REGION=$(curl -sSf -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/placement/region)

certbot certonly --dns-route53 \
  --dns-route53 \
  -m "ultramotiontech@gmail.com" \
  -d "api.ultramotiontech.com" \
  --agree-tos \
  --non-interactive \
  --dry-run