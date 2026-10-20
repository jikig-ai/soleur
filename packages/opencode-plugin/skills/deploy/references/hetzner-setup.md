# Hetzner VM Setup Guide

First-time setup for deploying containerized applications to a Hetzner Cloud VM.

## Primary Path: Terraform

Always provision infrastructure via Terraform for reproducibility and cloud portability. See existing patterns:

- `apps/web-platform/infra/` — CPX21 server, 20GB volume, HTTP/HTTPS firewall

### Quick Start

```bash
cd apps/<app>/infra
terraform init
terraform apply \
  -var="hcloud_token=<your-token>" \
  -var='admin_ips=["<your-ip>/32"]'
```

Terraform handles: server creation, SSH key upload, volume attachment, firewall rules, and cloud-init (Docker install, volume mount, container start, SSH hardening).

### Post-Terraform Steps

1. Create `.env` with app secrets
2. SCP `.env` to `root@<server-ip>:/mnt/data/.env`
3. Authenticate Docker with GHCR on the server (see below)
4. Restart container: `ssh root@<ip> "docker restart <container>"`

## Manual Steps (only when Terraform doesn't cover them)

### Authenticate with GHCR

Create a GitHub Personal Access Token (classic) with `read:packages` scope, then log in on the server:

```bash
echo "<ghcr-token>" | docker login ghcr.io -u <github-username> --password-stdin
```

Pipe the token via stdin — do not pass it as a command-line argument.

### SSH Key Setup

On the local machine, generate a deploy key and copy it to the server:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -N ""
ssh-copy-id -i ~/.ssh/deploy_key.pub root@<server-ip>
```

Verify passwordless access:

```bash
ssh -o BatchMode=yes -i ~/.ssh/deploy_key root@<server-ip> "echo OK"
```

### Health Endpoint

Add a `/health` endpoint to the application that returns HTTP 200 when the service is ready. The deploy skill checks this endpoint after deployment.

Set the `DEPLOY_HEALTH_URL` environment variable to enable automated health verification:

```bash
export DEPLOY_HEALTH_URL="http://<server-ip>:<app-port>/health"
```
