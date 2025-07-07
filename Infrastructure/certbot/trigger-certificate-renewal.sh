#!/usr/bin/env bash
###############################################################################
# trigger-certificate-renewal.sh — one-shot cert rotation for Docker Swarm
#
# 1. Launch a transient Swarm service that calls renew-certificate.sh
# 2. Download the artefacts from S3 and load / rotate them as Swarm secrets
# 3. Clean up everything on exit
###############################################################################

set -Eeuo pipefail
shopt -s inherit_errexit

###############################################################################
# Constants / defaults
###############################################################################
readonly RUN_ID=$(date +%Y%m%d%H%M%S)
readonly SERVICE_NAME="cert-renew-${RUN_ID}"
readonly STAGING_DIR=$(mktemp -d -p /var/lib/certificate-manager cert-renew.XXXXXXXX)
readonly LETSENCRYPT_DIR=${LETSENCRYPT_DIR:-/etc/letsencrypt}
readonly LETSENCRYPT_LOG_DIR=${LETSENCRYPT_LOG_DIR:-/var/log/letsencrypt}
readonly WORKER_LOG_DIR=${WORKER_LOG_DIR:-/var/log/certificate-manager}
readonly TIMEOUT=${TIMEOUT_SECONDS:-300}                # 5 min
readonly WORKER_CONSTRAINT=${WORKER_CONSTRAINT:-node.role==worker}
readonly RENEWAL_THRESHOLD_DAYS=${RENEWAL_THRESHOLD_DAYS:-10}

# Swarm-secret names created at runtime and removed on exit
SECRET_IDS=()

###############################################################################
# Logging helpers
###############################################################################
_ts()   { date '+%F %T'; }
log()   { printf '[ %s ] TRIGGER %s\n' "$(_ts)" "$*" >&2; }
fatal()   { log "ERROR: $*"; exit 1; }

###############################################################################
# Cleanup ─ always
###############################################################################
cleanup() {
  local rc=$?
  log "clean-up (rc=$rc)…"
  docker service rm -f "$SERVICE_NAME" &>/dev/null || true
  ((${#SECRET_IDS[@]})) && docker secret rm "${SECRET_IDS[@]}" &>/dev/null || true
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
trap 'fatal "command failed on line $LINENO"' ERR

###############################################################################
# Dependency check
###############################################################################
for cmd in docker aws jq; do command -v "$cmd" &>/dev/null || fatal "$cmd missing"; done

###############################################################################
# Swarm must be initialised
###############################################################################
until docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | \
      grep -Eq 'active|pending'; do
  log "waiting for Docker Swarm…"
  sleep 5
done
log "Docker Swarm ready"

###############################################################################
# Pull runtime configuration from AWS Secrets Manager
###############################################################################
[[ -n ${AWS_SECRET_NAME:-} ]] || fatal "AWS_SECRET_NAME env var is required"

secret=$(aws secretsmanager get-secret-value \
           --secret-id "$AWS_SECRET_NAME" \
           --query SecretString --output text) || fatal "cannot fetch secret"

json() { jq -r "$1" <<<"$secret"; }

APP_NAME=${APP_NAME:-$(json .APP_NAME)}
CERTIFICATE_STORE=${CERTIFICATE_STORE:-$(json .CERTIFICATE_STORE)}
ACME_EMAIL=${ACME_EMAIL:-$(json .ACME_EMAIL)}
AWS_REGION=${AWS_REGION:-$(json .AWS_REGION)}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
AWS_ROLE_NAME=${AWS_ROLE_NAME:-${APP_NAME}-ec2-public-instance-role}
SUBDOMAIN_NAMES=$(jq -r '
   to_entries | map(select(.key|test("^SUBDOMAIN_NAME_"))) | sort_by(.key) | .[].value
' <<<"$secret" | paste -sd, -)

: "${APP_NAME:?} ${CERTIFICATE_STORE:?} ${ACME_EMAIL:?} ${SUBDOMAIN_NAMES:?}"

IFS=',' read -r -a DOMAINS <<<"$SUBDOMAIN_NAMES"

RENEW_IMAGE=${RENEWAL_IMAGE:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}/certbot:latest}

###############################################################################
# Swarm secret helper
###############################################################################
make_secret() {
  local name=$1 val=$2
  id=$(printf '%s' "$val" | docker secret create "$name" -) \
      || fatal "secret $name create failed"
  SECRET_IDS+=("$name")
  echo "$name"
}

aws_role_sec=$(make_secret aws_role_${RUN_ID}     "$AWS_ROLE_NAME")
cert_store_sec=$(make_secret cert_store_${RUN_ID} "$CERTIFICATE_STORE")
acme_sec=$(make_secret acme_email_${RUN_ID}       "$ACME_EMAIL")
domains_sec=$(make_secret domains_${RUN_ID}       "$SUBDOMAIN_NAMES")

###############################################################################
# Check for missing secrets to determine if force upload is needed
###############################################################################
FORCE_UPLOAD=false
for d in "${DOMAINS[@]}"; do
  slug=${d//./-}
  for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
    docker secret inspect "${slug}-${f}" &>/dev/null || { FORCE_UPLOAD=true; break 2; }
  done
done

###############################################################################
# Run the renewal task
###############################################################################
log "launching renewal service $SERVICE_NAME"
log "See service logs at cert-renew-${RUN_ID}"

service_id=$(docker service create --detach --quiet --with-registry-auth \
  --name "$SERVICE_NAME" \
  --constraint "$WORKER_CONSTRAINT" \
  --restart-condition none \
  --stop-grace-period 5m \
  --mount "type=bind,source=$WORKER_LOG_DIR,target=$WORKER_LOG_DIR" \
  --mount "type=bind,source=$LETSENCRYPT_DIR,target=$LETSENCRYPT_DIR" \
  --mount "type=bind,source=$LETSENCRYPT_LOG_DIR,target=$LETSENCRYPT_LOG_DIR" \
  --env RUN_ID="$RUN_ID" \
  --env CERT_PREFIX="$APP_NAME" \
  --env RENEWAL_THRESHOLD_DAYS="$RENEWAL_THRESHOLD_DAYS" \
  --secret "source=$aws_role_sec,target=AWS_ROLE_NAME" \
  --secret "source=$cert_store_sec,target=CERTIFICATE_STORE" \
  --secret "source=$acme_sec,target=ACME_EMAIL" \
  --secret "source=$domains_sec,target=DOMAINS_NAMES" \
  --env AWS_SECRET_NAME="$AWS_SECRET_NAME" \
  --env FORCE_UPLOAD="$FORCE_UPLOAD" \
  --log-driver awslogs \
  --log-opt awslogs-group="/aws/ec2/$APP_NAME-certificate-manager" \
  --log-opt awslogs-stream="$SERVICE_NAME" \
  --log-opt awslogs-region="$AWS_REGION" \
  "$RENEW_IMAGE") || fatal "service create failed"

###############################################################################
# Wait for completion (timeout $TIMEOUT s)
###############################################################################
log "Waiting for renewal task to complete…"
end=$((SECONDS+TIMEOUT))
while (( SECONDS < end )); do
  state=$(docker service ps --filter desired-state=shutdown \
          --format '{{.CurrentState}}' "$service_id" | head -n1)
  case $state in
    *running) ;;
    *Complete*) log "service completed OK"; break ;;
    *Failed*)  fatal "renewal task failed" ;;
  esac
  log "current state: $state"
  sleep 3
done
(( SECONDS < end )) || fatal "renewal task timed out"

###############################################################################
# Pull renewal status
###############################################################################
status_json="$STAGING_DIR/status.json"
aws s3 cp "s3://$CERTIFICATE_STORE/$APP_NAME/$RUN_ID/renewal-status.json" \
          "$status_json" --only-show-errors \
          || { log "no renewal-status.json found – nothing to rotate"; exit 0; }

renewed=$(jq -e '.renewal_occurred' "$status_json")
renew_domains=($(jq -r '.renewed_domains[]' "$status_json"))

[[ $renewed == true && ${#renew_domains[@]} -gt 0 && $FORCE_UPLOAD == false ]] || {
  log "no domains renewed or force upload enabled – exit"; exit 0; }

###############################################################################
# Fetch artefacts & create Swarm secrets
###############################################################################
log "downloading cert artefacts…"
for d in "${renew_domains[@]}"; do
  dest="$STAGING_DIR/$d"; mkdir -p "$dest"
  aws s3 cp "s3://$CERTIFICATE_STORE/$APP_NAME/$RUN_ID/$d/" "$dest/" \
            --recursive --only-show-errors \
            || fatal "download failed: $d"
  for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
    [[ -f $dest/$f ]] || continue
    sec="${d//./-}-$f-$RUN_ID"
    docker secret create "$sec" "$dest/$f" &>/dev/null \
      || fatal "secret create failed: $sec"
    NEW_SECRETS["$d/$f"]=$sec
    SECRET_IDS+=("$sec")
  done
done
log "artefacts ready as Swarm secrets"

###############################################################################
# (Optional) hot-swap secrets in target services
###############################################################################
if [[ -n ${SERVICES_BY_DOMAIN:-} && $SERVICES_BY_DOMAIN != "{}" ]]; then
  jq -e empty <<<"$SERVICES_BY_DOMAIN" \
    || fatal "SERVICES_BY_DOMAIN not valid JSON"
  log "rotating secrets in services…"
  for d in "${renew_domains[@]}"; do
    mapfile -t svcs < <(jq -r --arg d "$d" '.[$d][]?' <<<"$SERVICES_BY_DOMAIN")
    (( ${#svcs[@]} )) || continue
    for svc in "${svcs[@]}"; do
      docker service update --quiet \
        --secret-rm cert.pem --secret-rm privkey.pem \
        --secret-rm fullchain.pem --secret-rm cert.pfx \
        --secret-add source="${NEW_SECRETS[$d/cert.pem]}",target=cert.pem \
        --secret-add source="${NEW_SECRETS[$d/privkey.pem]}",target=privkey.pem \
        --secret-add source="${NEW_SECRETS[$d/fullchain.pem]}",target=fullchain.pem \
        --secret-add source="${NEW_SECRETS[$d/cert.pfx]}",target=cert.pfx \
        "$svc" || fatal "cannot update $svc"
      log " ↻ $svc updated"
    done
  done
fi

###############################################################################
# Done
###############################################################################
log "✅ certificate rotation complete (domains: ${renew_domains[*]})"
