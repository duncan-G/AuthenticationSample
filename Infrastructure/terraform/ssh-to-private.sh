#!/bin/bash

# SSH helper script to connect to private instance
# Usage: ssh-to-private [private-instance-id]

set -e

# Default private instance ID (you can override by passing as argument)
PRIVATE_INSTANCE_ID="${PRIVATE_INSTANCE_ID}"

# Use provided instance ID if specified
if [ $# -eq 1 ]; then
    PRIVATE_INSTANCE_ID="$1"
fi

# Check if instance ID is set
if [ -z "$PRIVATE_INSTANCE_ID" ]; then
    echo "❌ Error: No private instance ID specified"
    echo "Usage: ssh-to-private [instance-id]"
    echo "Or set PRIVATE_INSTANCE_ID environment variable"
    exit 1
fi

# Get private IP of the instance
PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$PRIVATE_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

if [ "$PRIVATE_IP" = "None" ] || [ -z "$PRIVATE_IP" ]; then
    echo "❌ Error: Could not get private IP for instance $PRIVATE_INSTANCE_ID"
    exit 1
fi

echo "🔑 Retrieving SSH key from Parameter Store..."

# Create a unique temporary file for the private key in ~/.ssh
tmp_key_file=$(mktemp "$HOME/.ssh/private-key-XXXXXX.pem")

# Get SSH key from Parameter Store
aws ssm get-parameter \
    --name "/ssh/private-key" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text > "$tmp_key_file"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to retrieve SSH key from Parameter Store"
    echo "Make sure the key is stored at /ssh/private-key"
    rm -f "$tmp_key_file"
    exit 1
fi

# Set proper permissions
chmod 400 "$tmp_key_file"

echo "🔗 Connecting to private instance at $PRIVATE_IP..."
echo "Instance ID: $PRIVATE_INSTANCE_ID"
echo ""
echo "To connect manually: ssh -i $tmp_key_file ec2-user@$PRIVATE_IP"
echo ""

# Fetch and add the host key to known_hosts
ssh-keyscan -H "$PRIVATE_IP" >> ~/.ssh/known_hosts

# Connect to private instance
ssh -i "$tmp_key_file" ec2-user@"$PRIVATE_IP"

# Clean up key file
rm -f "$tmp_key_file" 