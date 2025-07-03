#!/usr/bin/env bash
###############################################################################
# setup-ebs-volume.sh – First‑boot bootstrap for an EBS volume that stores
# Let's Encrypt material. Idempotent: safe to re‑run.
#
#  1. Waits for the device to appear (with user‑configurable timeout).
#  2. Formats the volume **iff** no filesystem is present.
#  3. Mounts it, creates LE sub‑dirs, fixes perms, and persists the mount in
#     /etc/fstab using UUID for reliability.
#  4. Logs to both stderr and /var/log/certificate-manager/ebs-volume-setup.log.
#
# Requires: bash 4+, util-linux (lsblk, blkid, mount), coreutils, grep, sed.
###############################################################################
set -Eeuo pipefail
shopt -s inherit_errexit nullglob

# ── User‑tunable knobs ───────────────────────────────────────────────────────
DEVICE_NAME="${DEVICE_NAME:-/dev/sdf}"
MOUNT_POINT="${MOUNT_POINT:-/etc/letsencrypt}"
FILESYSTEM_TYPE="${FILESYSTEM_TYPE:-ext4}"
WAIT_SECONDS="${WAIT_SECONDS:-30}"
LOG_FILE="/var/log/certificate-manager/ebs-volume-setup.log"

# ── Simple logger ────────────────────────────────────────────────────────────
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[ %s ] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
fatal() { log "\e[31mERROR:\e[0m $*"; exit 1; }
trap 'fatal "line $LINENO: command failed with exit code $?"' ERR

# ── Helpers ──────────────────────────────────────────────────────────────────
wait_for_device() {
  local end=$((SECONDS+WAIT_SECONDS))
  while [[ ! -b $DEVICE_NAME ]]; do
    ((SECONDS < end)) || fatal "Device $DEVICE_NAME did not appear within ${WAIT_SECONDS}s"
    sleep 1
  done
}

has_fs() { blkid -o value -s TYPE "$DEVICE_NAME" &>/dev/null; }

get_uuid() {
  local uuid
  uuid=$(blkid -o value -s UUID "$DEVICE_NAME" 2>/dev/null)
  [[ -n "$uuid" ]] || fatal "Could not get UUID for device $DEVICE_NAME"
  echo "$uuid"
}

mount_opts="defaults,nofail"

###############################################################################
log "📀 EBS‑volume bootstrap starting (device=$DEVICE_NAME, mount=$MOUNT_POINT)"
mkdir -p "$(dirname "$LOG_FILE")"

wait_for_device

# Guard: already mounted? – idempotent early‑exit
if mountpoint -q "$MOUNT_POINT"; then
  log "Volume already mounted at $MOUNT_POINT – nothing to do ✅"
  exit 0
fi

mkdir -p "$MOUNT_POINT"

if has_fs; then
  log "Device already contains a filesystem ($(blkid -o value -s TYPE "$DEVICE_NAME")) – skipping format"
else
  log "Formatting $DEVICE_NAME with $FILESYSTEM_TYPE"
  mkfs -t "$FILESYSTEM_TYPE" -F "$DEVICE_NAME"
fi

# Get UUID for reliable mounting
UUID=$(get_uuid)
log "Using UUID: $UUID for device $DEVICE_NAME"

log "Mounting $DEVICE_NAME to $MOUNT_POINT"
mount -o "$mount_opts" "$DEVICE_NAME" "$MOUNT_POINT"

# Sub‑directories for certbot
for d in live renewal archive; do
  mkdir -p "$MOUNT_POINT/$d"
done

chown -R root:root "$MOUNT_POINT"
chmod 700 "$MOUNT_POINT" "$MOUNT_POINT"/{live,renewal,archive}

# Persist across reboots using UUID for reliability
if ! grep -qs "[[:space:]]$MOUNT_POINT[[:space:]]" /etc/fstab; then
  echo "UUID=$UUID $MOUNT_POINT $FILESYSTEM_TYPE $mount_opts 0 2" >> /etc/fstab
  log "Added UUID-based entry to /etc/fstab"
fi

log "🎉 EBS volume setup finished successfully"
