#!/bin/bash
# Ensure SSM agent is running for script execution
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Decode and install SSH helper script
# The script is passed as a base64-encoded string for robustness

echo "${ssh_helper_script}" | base64 -d > /usr/local/bin/ssh-to-private
chmod +x /usr/local/bin/ssh-to-private

# Set private instance ID as environment variable
echo "export PRIVATE_INSTANCE_ID=${private_instance_id}" >> /home/ec2-user/.bashrc

# Create a simple alias for convenience
echo 'alias ssh-private="ssh-to-private"' >> /home/ec2-user/.bashrc

echo "✅ SSH helper script installed at /usr/local/bin/ssh-to-private"
echo "Usage: ssh-to-private [instance-id]"
echo "Or use alias: ssh-private" 