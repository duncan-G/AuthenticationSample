AWS_REGION ?= us-east-1

.PHONY: bootstrap-manager publish-params deploy-swarm

bootstrap-manager:
	@echo "Initialize first manager on an instance via SSM (update INSTANCE_ID)"
	@[ -n "$$INSTANCE_ID" ] || (echo "Set INSTANCE_ID env var" && exit 1)
	aws ssm send-command \
	  --region $(AWS_REGION) \
	  --instance-ids $$INSTANCE_ID \
	  --document-name "AWS-RunShellScript" \
	  --parameters commands='#!/bin/bash
set -euo pipefail
dnf -y install docker jq awscli || yum -y install docker jq awscli
systemctl enable --now docker
IP=$$(curl -s -H "X-aws-ec2-metadata-token: $$(curl -XPUT -s http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")" http://169.254.169.254/latest/meta-data/local-ipv4)
docker swarm init --advertise-addr $$IP || true
aws ssm put-parameter --name /swarm/manager-addr --type String --value $$IP:2377 --overwrite --region $(AWS_REGION)
aws ssm put-parameter --name /swarm/worker-token --type String --value $$(docker swarm join-token -q worker) --overwrite --region $(AWS_REGION)
aws ssm put-parameter --name /swarm/manager-token --type String --value $$(docker swarm join-token -q manager) --overwrite --region $(AWS_REGION)'

publish-params:
	@echo "Manually publish/rotate join tokens to SSM from a manager"
	aws ssm put-parameter --name /swarm/worker-token --type String --value "$$(docker swarm join-token -q worker)" --overwrite --region $(AWS_REGION)
	aws ssm put-parameter --name /swarm/manager-token --type String --value "$$(docker swarm join-token -q manager)" --overwrite --region $(AWS_REGION)

deploy-swarm:
	@echo "Deploy Docker stack"
	docker stack deploy -c infrastructure/docker/stack.yml platform
	

// TODO: Use envoy config