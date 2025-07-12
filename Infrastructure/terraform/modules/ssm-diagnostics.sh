#!/bin/bash
# SSM Agent Diagnostic Script
# This script runs on EC2 instance startup to diagnose SSM Agent connectivity issues
# Results are logged to CloudWatch and SSM Parameter Store for remote inspection

set -e

# Template variables from Terraform
APP_NAME="${app_name}"
REGION="${region}"
INSTANCE_ID="${instance_id}"
SUBNET_TYPE="${subnet_type}"

# Logging setup
LOGFILE="/var/log/ssm-diagnostics.log"
exec > >(tee -a $LOGFILE) 2>&1

echo "========================================="
echo "SSM Agent Diagnostics Started: $(date)"
echo "App: $APP_NAME"
echo "Region: $REGION"
echo "Instance: $INSTANCE_ID"
echo "Subnet Type: $SUBNET_TYPE"
echo "========================================="

# Function to log and store diagnostic results
log_diagnostic() {
    local key="$1"
    local value="$2"
    echo "DIAGNOSTIC: $key = $value"
    
    # Store in SSM Parameter Store for remote access
    aws ssm put-parameter \
        --region "$REGION" \
        --name "/diagnostics/$APP_NAME/$INSTANCE_ID/$key" \
        --value "$value" \
        --type "String" \
        --overwrite \
        --no-cli-pager 2>/dev/null || echo "Failed to store parameter $key"
}

# Function to test network connectivity
test_connectivity() {
    local endpoint="$1"
    local port="$2"
    local timeout=5
    
    if timeout $timeout bash -c "cat < /dev/null > /dev/tcp/$endpoint/$port" 2>/dev/null; then
        echo "SUCCESS"
    else
        echo "FAILED"
    fi
}

# Wait for instance to be ready
sleep 30

# Install required packages
yum update -y
yum install -y jq curl

# 1. Check Instance Metadata Service
echo "1. Testing Instance Metadata Service..."
METADATA_TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    --connect-timeout 5 --max-time 10 -s 2>/dev/null || echo "FAILED")

if [ "$METADATA_TOKEN" != "FAILED" ]; then
    INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $METADATA_TOKEN" \
        -s "http://169.254.169.254/latest/dynamic/instance-identity/document" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "FAILED")
    
    if [ "$INSTANCE_IDENTITY" != "FAILED" ]; then
        log_diagnostic "metadata_service" "SUCCESS"
        ACTUAL_REGION=$(echo "$INSTANCE_IDENTITY" | jq -r '.region' 2>/dev/null || echo "UNKNOWN")
        log_diagnostic "detected_region" "$ACTUAL_REGION"
        ACTUAL_INSTANCE_ID=$(echo "$INSTANCE_IDENTITY" | jq -r '.instanceId' 2>/dev/null || echo "UNKNOWN")
        log_diagnostic "actual_instance_id" "$ACTUAL_INSTANCE_ID"
    else
        log_diagnostic "metadata_service" "FAILED_IDENTITY"
    fi
else
    log_diagnostic "metadata_service" "FAILED_TOKEN"
fi

# 2. Check IAM Role
echo "2. Checking IAM Role..."
IAM_ROLE=$(curl -H "X-aws-ec2-metadata-token: $METADATA_TOKEN" \
    -s "http://169.254.169.254/latest/meta-data/iam/security-credentials/" \
    --connect-timeout 5 --max-time 10 2>/dev/null || echo "FAILED")

if [ "$IAM_ROLE" != "FAILED" ] && [ -n "$IAM_ROLE" ]; then
    log_diagnostic "iam_role" "$IAM_ROLE"
    
    # Test IAM credentials
    IAM_CREDS=$(curl -H "X-aws-ec2-metadata-token: $METADATA_TOKEN" \
        -s "http://169.254.169.254/latest/meta-data/iam/security-credentials/$IAM_ROLE" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "FAILED")
    
    if [ "$IAM_CREDS" != "FAILED" ]; then
        log_diagnostic "iam_credentials" "SUCCESS"
    else
        log_diagnostic "iam_credentials" "FAILED"
    fi
else
    log_diagnostic "iam_role" "MISSING"
fi

# 3. Test Network Connectivity to SSM Endpoints
echo "3. Testing Network Connectivity..."
SSM_ENDPOINT="ssm.$REGION.amazonaws.com"
SSM_MSG_ENDPOINT="ssmmessages.$REGION.amazonaws.com"
EC2_MSG_ENDPOINT="ec2messages.$REGION.amazonaws.com"

log_diagnostic "ssm_endpoint_connectivity" "$(test_connectivity $SSM_ENDPOINT 443)"
log_diagnostic "ssmmessages_endpoint_connectivity" "$(test_connectivity $SSM_MSG_ENDPOINT 443)"
log_diagnostic "ec2messages_endpoint_connectivity" "$(test_connectivity $EC2_MSG_ENDPOINT 443)"

# Test DNS resolution
nslookup $SSM_ENDPOINT > /dev/null 2>&1 && log_diagnostic "dns_resolution" "SUCCESS" || log_diagnostic "dns_resolution" "FAILED"

# 4. Check SSM Agent Status
echo "4. Checking SSM Agent Status..."
if systemctl is-active --quiet amazon-ssm-agent; then
    log_diagnostic "ssm_agent_status" "ACTIVE"
    log_diagnostic "ssm_agent_enabled" "$(systemctl is-enabled amazon-ssm-agent 2>/dev/null || echo 'UNKNOWN')"
else
    log_diagnostic "ssm_agent_status" "INACTIVE"
    # Try to start it
    systemctl start amazon-ssm-agent || true
    sleep 5
    if systemctl is-active --quiet amazon-ssm-agent; then
        log_diagnostic "ssm_agent_restart" "SUCCESS"
    else
        log_diagnostic "ssm_agent_restart" "FAILED"
    fi
fi

# 5. Check SSM Agent Logs
echo "5. Checking SSM Agent Logs..."
if [ -f /var/log/amazon/ssm/amazon-ssm-agent.log ]; then
    # Get last 10 lines of SSM agent log
    LAST_LOG_LINES=$(tail -n 10 /var/log/amazon/ssm/amazon-ssm-agent.log 2>/dev/null || echo "NO_LOGS")
    log_diagnostic "ssm_agent_last_logs" "$LAST_LOG_LINES"
    
    # Check for specific error patterns
    if grep -q "registration failed" /var/log/amazon/ssm/amazon-ssm-agent.log 2>/dev/null; then
        log_diagnostic "ssm_registration_error" "FOUND"
    else
        log_diagnostic "ssm_registration_error" "NOT_FOUND"
    fi
else
    log_diagnostic "ssm_agent_logs" "NO_LOG_FILE"
fi

# 6. Test AWS CLI Access
echo "6. Testing AWS CLI Access..."
if command -v aws >/dev/null 2>&1; then
    # Test basic AWS CLI functionality
    AWS_IDENTITY=$(aws sts get-caller-identity --region $REGION --no-cli-pager 2>/dev/null || echo "FAILED")
    if [ "$AWS_IDENTITY" != "FAILED" ]; then
        log_diagnostic "aws_cli_access" "SUCCESS"
        AWS_ARN=$(echo "$AWS_IDENTITY" | jq -r '.Arn' 2>/dev/null || echo "UNKNOWN")
        log_diagnostic "aws_identity_arn" "$AWS_ARN"
    else
        log_diagnostic "aws_cli_access" "FAILED"
    fi
else
    log_diagnostic "aws_cli_installed" "NOT_INSTALLED"
fi

# 7. Test SSM API Access
echo "7. Testing SSM API Access..."
if command -v aws >/dev/null 2>&1; then
    # Test SSM describe-instance-information (this is what SSM agent uses)
    SSM_TEST=$(aws ssm describe-instance-information \
        --region $REGION \
        --no-cli-pager 2>/dev/null || echo "FAILED")
    
    if [ "$SSM_TEST" != "FAILED" ]; then
        log_diagnostic "ssm_api_access" "SUCCESS"
    else
        log_diagnostic "ssm_api_access" "FAILED"
    fi
fi

# 8. Network Route Check
echo "8. Checking Network Routes..."
if [ "$SUBNET_TYPE" = "private" ]; then
    # Check if we can reach internet via NAT
    if curl -s --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com/ > /dev/null; then
        log_diagnostic "internet_access" "SUCCESS"
    else
        log_diagnostic "internet_access" "FAILED"
    fi
else
    log_diagnostic "internet_access" "PUBLIC_SUBNET"
fi

# 9. Security Group Check (indirect)
echo "9. Checking Security Groups..."
# Test outbound HTTPS (443) - required for SSM
if curl -s --connect-timeout 5 --max-time 10 https://aws.amazon.com > /dev/null; then
    log_diagnostic "outbound_https" "SUCCESS"
else
    log_diagnostic "outbound_https" "FAILED"
fi

# 10. Final Status Summary
echo "10. Final Status Check..."
sleep 10  # Give SSM agent time to register

if systemctl is-active --quiet amazon-ssm-agent; then
    log_diagnostic "final_ssm_status" "ACTIVE"
    
    # Check if instance is registered in SSM
    if command -v aws >/dev/null 2>&1; then
        SSM_INSTANCE_INFO=$(aws ssm describe-instance-information \
            --region $REGION \
            --filters "Key=InstanceIds,Values=$ACTUAL_INSTANCE_ID" \
            --no-cli-pager 2>/dev/null || echo "FAILED")
        
        if [ "$SSM_INSTANCE_INFO" != "FAILED" ]; then
            INSTANCE_COUNT=$(echo "$SSM_INSTANCE_INFO" | jq '.InstanceInformationList | length' 2>/dev/null || echo "0")
            if [ "$INSTANCE_COUNT" -gt 0 ]; then
                log_diagnostic "ssm_registration_status" "REGISTERED"
            else
                log_diagnostic "ssm_registration_status" "NOT_REGISTERED"
            fi
        else
            log_diagnostic "ssm_registration_status" "CANNOT_CHECK"
        fi
    fi
else
    log_diagnostic "final_ssm_status" "INACTIVE"
fi

# Summary diagnostic parameter
SUMMARY="Instance: $INSTANCE_ID, Type: $SUBNET_TYPE, Time: $(date), SSM: $(systemctl is-active amazon-ssm-agent 2>/dev/null || echo 'UNKNOWN')"
log_diagnostic "summary" "$SUMMARY"

echo "========================================="
echo "SSM Agent Diagnostics Completed: $(date)"
echo "Check SSM Parameter Store under /diagnostics/$APP_NAME/$INSTANCE_ID/ for results"
echo "========================================="

# Install CloudWatch agent for better logging
yum install -y amazon-cloudwatch-agent

# Send logs to CloudWatch
if [ -f /var/log/ssm-diagnostics.log ]; then
    aws logs create-log-group --log-group-name "/aws/ec2/$APP_NAME-ssm-diagnostics" --region $REGION 2>/dev/null || true
    aws logs create-log-stream --log-group-name "/aws/ec2/$APP_NAME-ssm-diagnostics" --log-stream-name "$INSTANCE_ID" --region $REGION 2>/dev/null || true
    aws logs put-log-events --log-group-name "/aws/ec2/$APP_NAME-ssm-diagnostics" --log-stream-name "$INSTANCE_ID" --region $REGION --log-events "timestamp=$(date +%s)000,message=$(cat /var/log/ssm-diagnostics.log | base64 -w 0)" 2>/dev/null || true
fi 