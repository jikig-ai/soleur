---
module: System
date: 2026-04-06
problem_type: integration_issue
component: tooling
symptoms:
  - "FATAL: Doppler secrets download failed on all webhook-triggered deploys"
  - "Doppler token works when tested directly via SSH but fails under systemd service"
  - "2>/dev/null swallows actual error message making diagnosis opaque"
root_cause: config_error
resolution_type: config_change
severity: critical
tags: [doppler, systemd, protecthome, deploy-pipeline, infrastructure]
---

# Troubleshooting: Doppler CLI fails under systemd ProtectHome=read-only

## Problem

Since v0.13.41, all webhook-triggered deploys failed with `FATAL: Doppler secrets download failed`. The Doppler CLI's `configuration.Setup()` runs `os.Mkdir(~/.doppler, 0700)` before every subcommand, which fails when systemd's `ProtectHome=read-only` makes the deploy user's home directory read-only.

## Environment

- Module: web-platform infra (ci-deploy.sh, webhook.service)
- Affected Component: Deploy pipeline (systemd webhook service)
- Date: 2026-04-06
- systemd directives: ProtectHome=read-only, PrivateTmp=true, ProtectSystem=strict

## Symptoms

- `FATAL: Doppler secrets download failed` in journalctl for every webhook-triggered deploy since v0.13.41
- Doppler token works when tested directly via SSH as root
- The actual error (`mkdir /home/deploy/.doppler: read-only file system`) was invisible because `2>/dev/null` swallowed stderr
- Three consecutive deploy failures (v0.13.41, v0.13.42, v0.13.43) before diagnosis

## What Didn't Work

**Direct solution:** The root cause was identified through SSH diagnosis using `systemd-run --pipe` to reproduce the exact systemd sandbox restrictions. The fix was applied on the first attempt after diagnosis.

## Solution

Three changes fix the issue:

**1. Redirect Doppler config directory to /tmp (writable under PrivateTmp):**

Add `DOPPLER_CONFIG_DIR=/tmp/.doppler` to `/etc/default/webhook-deploy`. This redirects the CLI's config directory from `~/.doppler` (blocked by ProtectHome) to `/tmp` (isolated by PrivateTmp=true).

**2. Replace stderr suppression with combined output capture:**

```bash
# Before (broken -- swallows actual error):
if doppler secrets download ... > "$tmpenv" 2>/dev/null; then

# After (fixed -- captures and logs the error):
if ! doppler_output=$(doppler secrets download ... 2>&1); then
    logger -t "$LOG_TAG" "FATAL: Doppler secrets download failed: $doppler_output"
    rm -f "$tmpenv"
    echo "Error: Failed to download secrets from Doppler: $doppler_output" >&2
    exit 1
fi
echo "$doppler_output" > "$tmpenv"
```

**3. Disable Doppler version check (defense-in-depth):**

Add `DOPPLER_ENABLE_VERSION_CHECK=false` to the env file. The version check also writes to `~/.doppler` and contacts the Doppler API unnecessarily in production.

**Terraform provisioner for existing server:**

```bash
# Idempotent append (grep guard prevents duplicates)
grep -q DOPPLER_CONFIG_DIR /etc/default/webhook-deploy || \
  printf 'DOPPLER_CONFIG_DIR=/tmp/.doppler\nDOPPLER_ENABLE_VERSION_CHECK=false\n' \
  >> /etc/default/webhook-deploy
```

## Why This Works

1. **Root cause:** Doppler CLI v3.75.3 calls `configuration.Setup()` in its `PersistentPreRun` hook, which runs `os.Mkdir(~/.doppler, 0700)` before every subcommand. Under systemd's `ProtectHome=read-only`, the home directory is mounted read-only, causing the mkdir to fail before the CLI reaches the `secrets download` command.
2. **Why /tmp works:** `PrivateTmp=true` gives each systemd service its own private `/tmp` namespace. Writing to `/tmp/.doppler` is equivalent to writing to a private ephemeral directory -- no other service can see it, and it's cleaned on service restart.
3. **Why not ReadWritePaths:** Adding `ReadWritePaths=/home/deploy/.doppler` would punch a write hole through the ProtectHome sandbox, persist sensitive metadata on disk, and require pre-creating the directory.

## Prevention

- When adding systemd sandbox directives (`ProtectHome`, `ProtectSystem`, `PrivateDevices`), audit all CLI tools the service invokes for home-directory writes. Common offenders: Doppler (`~/.doppler`), Docker (`~/.docker`), npm (`~/.npm`), AWS CLI (`~/.aws`).
- Never use `2>/dev/null` on CLI commands in deploy scripts. Capture stderr in a variable and log it on failure. Opaque errors multiply debugging time.
- Use `systemd-run --pipe` with matching sandbox directives to reproduce issues locally before deploying fixes.

## Related Issues

- See also: [stale-env-deploy-pipeline-terraform-bridge-20260405.md](./stale-env-deploy-pipeline-terraform-bridge-20260405.md) -- Previous deploy pipeline fix that removed .env fallback and hardened ci-deploy.sh
- See also: [2026-04-03-doppler-not-installed-env-fallback-outage.md](./2026-04-03-doppler-not-installed-env-fallback-outage.md) -- Earlier Doppler CLI availability issue
