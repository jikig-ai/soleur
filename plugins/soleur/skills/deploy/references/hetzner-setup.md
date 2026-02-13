# Hetzner VM Setup Guide

First-time setup for deploying containerized applications to a Hetzner Cloud VM.

## 1. Provision a VM

Create a Hetzner Cloud server:
- **Type**: CX22 (2 vCPU, 4 GB RAM) or larger depending on application
- **Image**: Ubuntu 24.04
- **Location**: Choose nearest to target users
- **SSH Key**: Add a public key during creation

## 2. Install Docker

SSH into the server and install Docker:

```bash
ssh root@<server-ip>
apt update && apt install -y docker.io
systemctl enable --now docker
```

## 3. Authenticate with GHCR

Create a GitHub Personal Access Token (classic) with `read:packages` scope, then log in on the server:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-username> --password-stdin
```

Pipe the token via stdin -- do not pass it as a command-line argument.

## 4. SSH Key Setup

On the local machine, generate a deploy key and copy it to the server:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -N ""
ssh-copy-id -i ~/.ssh/deploy_key.pub root@<server-ip>
```

Verify passwordless access:

```bash
ssh -o BatchMode=yes -i ~/.ssh/deploy_key root@<server-ip> "echo OK"
```

Set restrictive permissions on the key file:

```bash
chmod 600 ~/.ssh/deploy_key
```

## 5. Firewall Rules

Configure `ufw` to allow only necessary traffic:

```bash
ufw allow 22/tcp       # SSH
ufw allow 80/tcp       # HTTP (if needed)
ufw allow 443/tcp      # HTTPS (if needed)
ufw allow <app-port>/tcp  # Application port
ufw enable
```

## 6. Volume Mounting (Optional)

If the application needs persistent storage, attach a Hetzner volume and mount it.

Use idempotent mounting -- `mount` with a fallback, not `mkfs.ext4 -F` which is destructive:

```bash
# Format only if not already formatted
blkid /dev/sdb || mkfs.ext4 /dev/sdb

# Mount idempotently
mkdir -p /mnt/data
mount /dev/sdb /mnt/data || true

# Add to fstab for persistence across reboots
grep -q '/dev/sdb /mnt/data' /etc/fstab || echo "/dev/sdb /mnt/data ext4 defaults 0 2" >> /etc/fstab
```

## 7. Health Endpoint

Add a `/health` endpoint to the application that returns HTTP 200 when the service is ready. The deploy skill checks this endpoint after deployment.

Example (Node.js):

```javascript
app.get("/health", (req, res) => res.sendStatus(200));
```

Set the `DEPLOY_HEALTH_URL` environment variable to enable automated health verification:

```bash
export DEPLOY_HEALTH_URL="http://<server-ip>:<app-port>/health"
```
