# Certificate Manager – Swarm‑native ACME Toolkit

> **Goal** — Issue & renew Let’s Encrypt certificates inside Docker **Swarm**, upload them to **S3**, and hot‑swap them into running services with **zero downtime**. All pieces are Bash 4, minimal Alpine base image, and pass ShellCheck.

---

## 1 · Repo contents

| File / Directory                 | Kind             | Purpose                                                                                                  |
| -------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------- |
| `Dockerfile`                     | container recipe | Produces the image that *only* runs `renew-certificate.sh`.                                              |
| `renew-certificate.sh`           | bash             | Inside‑container logic: certbot → S3 → `/app/certs`. Swarm secrets auto‑import.                          |
| `trigger-certificate-renewal.sh` | bash             | One‑shot orchestrator: creates runtime secrets, waits, downloads artefacts, swaps into consumer service. |
| `certificate-manager.sh`         | bash             | Runs trigger once or every *N* seconds (`--daemon`). Lock‑file prevents overlaps.                        |
| `certificate-manager.service`    | systemd          | Hardened unit file that executes `certificate-manager.sh --daemon` on classic hosts.                     |
| `setup-ebs-volume.sh`            | bash             | Formats + mounts EBS at `/etc/letsencrypt` (idempotent).                                                 |

---

## 2 · Overview

This certificate manager provides a complete solution for automated SSL certificate management in Docker Swarm environments. It handles certificate issuance, renewal, storage, and hot-swapping without service downtime.

---

## 3 · Building the renewer image

```bash
# Build & push once (or via CI)
docker build -t registry.example.com/cert-renewer:latest .
docker push registry.example.com/cert-renewer:latest
```

The image contains:

* `certbot/dns-route53:latest` base
* Bash, curl, jq, AWS CLI
* `/app/renew-certificate.sh` (ENTRYPOINT)

---

## 4 · Deploying on Swarm

### 4.1 Prepare storage (per worker)

```bash
sudo ./setup-ebs-volume.sh   # defaults: /dev/sdf → /etc/letsencrypt (ext4)
```

### 4.2 Create long‑lived secrets (once)

```bash
docker secret create s3_bucket       "cert-bucket"
docker secret create aws_role_name   "my‑app‑private-instance-role"
docker secret create acme_email      "admin@example.com"
docker secret create domains         "example.com,api.example.com"
printf 'SuperSecret' | docker secret create pfx_password -  # optional
```

### 4.3 Stack snippet

```yaml
services:
  cert-renewer:
    image: registry.example.com/cert-renewer:latest
    command: ["/app/certificate-manager.sh", "--daemon", "--interval", "43200"] # every 12 h
    secrets:
      - source: s3_bucket      ; target: S3_BUCKET
      - source: aws_role_name  ; target: AWS_ROLE_NAME
      - source: acme_email     ; target: EMAIL
      - source: domains        ; target: DOMAINS
      - source: pfx_password   ; target: PFX_PASSWORD
    deploy:
      placement:
        constraints: ["node.role==worker"]
      restart_policy:
        condition: on-failure
```

> The **image** runs `renew-certificate.sh`. The **command** overrides ENTRYPOINT to launch the manager/daemon inside the *same* container. This keeps the image list short.

---

## 5 · Using the systemd unit (bare metal / ECS‑Anywhere)

```bash
sudo cp extras/certificate-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now certificate-manager.service
```

*ExecStart* employs `flock` to avoid overlaps:

```
ExecStart=/usr/bin/flock -n %t/certificate-manager/instance.lock \
         /usr/local/bin/certificate-manager.sh --daemon
```

Logs go to **journal** *and* `/var/log/certificate-manager/certificate-manager.log`.

---

## 6 · Environment reference (superset)

| Variable                 | Default             | Consumed by | Description                               |
| ------------------------ | ------------------- | ----------- | ----------------------------------------- |
| `AWS_ROLE_NAME`          | *(secret)*          | renewer     | IAM role name for IMDSv2 creds.           |
| `S3_BUCKET`              | `certificate-store` | renewer     | Target bucket.                            |
| `CERT_PREFIX`            | `certificates`      | renewer     | Folder prefix before timestamp.           |
| `DOMAINS`                | *(secret)*          | renewer     | Comma‑separated FQDN list.                |
| `PFX_PASSWORD`           | *(secret)*          | renewer     | Password for `.pfx`. Empty = no password. |
| `RENEWAL_THRESHOLD_DAYS` | 30                  | renewer     | Renew if cert expires in ≤ N days.        |
| `CERT_OUTPUT_DIR`        | `/app/certs`        | renewer     | Mount this into consumer service.         |
| `CHECK_INTERVAL`         | 86400               | manager     | Sleep between cycles in daemon mode.      |
| `LOG_DIR` / `LOG_FILE`   | see scripts         | all         | Where logs land.                          |

---

## 7 · Flow in a nutshell

1. **Manager / systemd timer** decides it's time → runs *trigger*.
2. *Trigger* launches short‑lived **container built from Dockerfile** (runs `renew-certificate.sh`).
3. Container renews, uploads, and places certs under `/app/certs/<domain>`.
4. Trigger downloads artefacts, converts them into Swarm secrets, updates your Envoy/Nginx service with `docker service update --secret-add`, then exits.
5. Consumer reloads certs automatically on secret rotation (e.g., Envoy's SDS or via `envoy --restart-epoch`).

---

## 8 · Troubleshooting

| Symptom                                    | Fix                                                                                                                                          |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `IMDSv2 token fetch failed`                | Confirm EC2 metadata endpoint reachable & instance profile attached.                                                                         |
| `Another cycle is already running` in logs | Previous renewal still active; wait or increase interval.                                                                                    |
| Certificates not updating in Envoy         | Verify service has `secrets:` entries matching the new secret names and `envoy.reloadable_features.enable_deprecated_feature_false` not set. |

---

## 9 · License

MIT © 2025
