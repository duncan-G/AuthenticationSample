#!/usr/bin/env bash
set -euo pipefail

log() { echo "[manager] $*"; }

dnf -y update || yum -y update
dnf -y install docker jq awscli || yum -y install docker jq awscli
systemctl enable --now docker
usermod -aG docker ec2-user || true

# Install CloudWatch Agent for logs
if ! command -v amazon-cloudwatch-agent >/dev/null 2>&1; then
  dnf -y install amazon-cloudwatch-agent || yum -y install amazon-cloudwatch-agent
fi
cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {"file_path": "/var/log/docker-manager-setup.log", "log_group_name": "/aws/ec2/${project_name}-docker-manager", "log_stream_name": "{instance_id}", "timestamp_format": "%Y-%m-%d %H:%M:%S"}
        ]
      }
    }
  }
}
EOF
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true

# IMDSv2 region
TOKEN=$(curl -XPUT -s "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

if ! docker info >/dev/null 2>&1; then
  log "Docker not ready"
  exit 1
fi

if [[ $(docker info --format '{{.Swarm.LocalNodeState}}') != "active" ]]; then
  docker swarm init --advertise-addr "$LOCAL_IP"
fi

MANAGER_ADDR="$LOCAL_IP:2377"
MANAGER_TOKEN=$(docker swarm join-token -q manager)
WORKER_TOKEN=$(docker swarm join-token -q worker)

aws --region "$REGION" ssm put-parameter --name "/swarm/manager-addr"   --type String --value "$MANAGER_ADDR" --overwrite
aws --region "$REGION" ssm put-parameter --name "/swarm/manager-token"  --type String --value "$MANAGER_TOKEN" --overwrite
aws --region "$REGION" ssm put-parameter --name "/swarm/worker-token"   --type String --value "$WORKER_TOKEN" --overwrite

AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
docker node update --label-add az="$AZ" "$(docker info -f '{{.Swarm.NodeID}}')" || true

log "Manager initialized at $MANAGER_ADDR"


