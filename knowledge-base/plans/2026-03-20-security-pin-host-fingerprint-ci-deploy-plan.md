---
title: "security: pin server host key fingerprint in CI deploy workflow"
type: feat
date: 2026-03-20
semver: patch
---

# security: pin server host key fingerprint in CI deploy workflow

## Overview

The CI deploy steps in `web-platform-release.yml` and `telegram-bridge-release.yml` use `appleboy/ssh-action` with default `StrictHostKeyChecking=no`. This accepts any host key, making the deploy vulnerable to MITM attacks. Pin the server's SSH host key fingerprint using the action's `fingerprint` input so that CI verifies it is connecting to the real server before executing deployment commands.

## Problem Statement

Both deploy workflows (`web-platform-release.yml` line 46, `telegram-bridge-release.yml` lines 41 and 59) SSH into the Hetzner server without host key verification. An attacker who intercepts the connection (DNS poisoning, BGP hijack, compromised network hop) could impersonate the server and receive the deployment commands -- including access to `WEB_PLATFORM_SSH_KEY` and any env vars passed via `envs`.

This is a defense-in-depth gap identified as a follow-up to #738 (CI deploy SSH key fix).

## Proposed Solution

1. **Obtain the server's SSH host key fingerprint** by running `ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub` on the server (via existing SSH access) and extracting the SHA256 fingerprint
2. **Store the fingerprint** as a GitHub Actions secret named `WEB_PLATFORM_HOST_FINGERPRINT`
3. **Add the `fingerprint` input** to all three `appleboy/ssh-action` invocations across both workflows

## Technical Considerations

- **Fingerprint format**: `appleboy/ssh-action` expects the SHA256 fingerprint (e.g., `SHA256:AAAA...`). The `ssh-keygen -l` command outputs this format by default. The `cut -d ' ' -f2` extracts just the fingerprint hash.
- **Key type**: Ed25519 is preferred (`ssh_host_ed25519_key.pub`). The server was set up with Ed25519 keys per the SSH hardening plan.
- **Three ssh-action invocations**: `web-platform-release.yml` has 1, `telegram-bridge-release.yml` has 2 (env setup + deploy). All three must be updated.
- **Same host**: Both workflows deploy to the same server (`WEB_PLATFORM_HOST`), so a single `WEB_PLATFORM_HOST_FINGERPRINT` secret covers all invocations.
- **Fingerprint rotation**: If the server is reprovisioned, the host key changes and the secret must be updated. This is a manual step but is acceptable -- server reprovisioning is rare and already requires updating `WEB_PLATFORM_HOST` and `WEB_PLATFORM_SSH_KEY`.
- **No Terraform involvement**: The fingerprint is a read-only property of the existing server's SSH host key. It does not require infrastructure changes.

## Acceptance Criteria

- [ ] `WEB_PLATFORM_HOST_FINGERPRINT` GitHub secret is set with the server's Ed25519 host key SHA256 fingerprint
- [ ] `web-platform-release.yml` deploy step passes `fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}` to `appleboy/ssh-action`
- [ ] `telegram-bridge-release.yml` both ssh-action steps pass `fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}` to `appleboy/ssh-action`
- [ ] Deploy succeeds end-to-end with fingerprint verification enabled (verified via workflow run)

## Test Scenarios

- Given a correct fingerprint secret, when the deploy workflow runs, then the SSH connection succeeds and deployment completes normally
- Given an incorrect fingerprint secret, when the deploy workflow runs, then the SSH connection is rejected (MITM protection working)
- Given the fingerprint secret is missing/empty, when the deploy workflow runs, then the action falls back to default behavior (no verification) -- this is undesirable but is the action's default; the mitigation is ensuring the secret exists

## SpecFlow Analysis

**Edge cases identified:**

1. **Secret not set before first deploy**: If the workflow runs before the secret is created, `${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}` resolves to empty string. `appleboy/ssh-action` with an empty `fingerprint` input skips verification (same as omitting it). This means the change is backward-compatible -- deploys will not break if the secret is not yet set. However, the security benefit is absent until the secret is populated.
2. **Server reprovisioning**: A new server gets a new host key. The deploy will fail with a fingerprint mismatch. This is the desired behavior -- it prevents deploying to the wrong server. The operator must update the secret.
3. **Key type mismatch**: If the server presents an RSA key but the fingerprint is from Ed25519, verification fails. The server's `sshd_config` should present Ed25519 preferentially (standard on modern Ubuntu).

## MVP

### `.github/workflows/web-platform-release.yml` (deploy step, line 45-78)

```yaml
      - name: Deploy to server
        uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
        with:
          host: ${{ secrets.WEB_PLATFORM_HOST }}
          username: root
          key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}
          fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}
          script: |
            # ... existing script unchanged ...
```

### `.github/workflows/telegram-bridge-release.yml` (both ssh-action steps)

```yaml
      - name: Ensure telegram env vars on server
        uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
        with:
          host: ${{ secrets.WEB_PLATFORM_HOST }}
          username: root
          key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}
          fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}
          # ... rest unchanged ...

      - name: Deploy to server
        uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
        with:
          host: ${{ secrets.WEB_PLATFORM_HOST }}
          username: root
          key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}
          fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}
          # ... rest unchanged ...
```

### Obtaining the fingerprint (one-time manual step)

```bash
ssh <server> ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub | cut -d ' ' -f2
# Output: SHA256:AAAA...
# Then: gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "<fingerprint>"
```

## References

- Issue: #748
- Parent issue: #738 (CI deploy SSH key fix)
- [appleboy/ssh-action README](https://github.com/appleboy/ssh-action) -- `fingerprint` input documentation
- Learning: [CI SSH deploy firewall hidden dependency](../learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md)
- Workflow: `.github/workflows/web-platform-release.yml:45-78`
- Workflow: `.github/workflows/telegram-bridge-release.yml:40-91`
