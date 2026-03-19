---
title: "fix: CI deploy fails -- SSH key is passphrase-protected"
type: fix
date: 2026-03-19
semver: patch
---

# fix: CI deploy fails -- SSH key is passphrase-protected

## Overview

The `build-web-platform.yml` deploy job fails because the `WEB_PLATFORM_SSH_KEY` GitHub secret contains a passphrase-protected private key. The `appleboy/ssh-action@v1.2.5` action requires the `passphrase` input to be explicitly set for passphrase-protected keys -- without it, Go's `ssh.ParsePrivateKey` returns `ssh: this private key is passphrase protected` and the connection falls through to a TCP timeout.

The build-and-push job succeeds (image lands in GHCR). Only the deploy step is broken. Manual SSH deploy from a local machine with agent-forwarded keys is the current workaround.

Discovered during #678. Tracked in #738.

## Problem Statement

```
ssh.ParsePrivateKey: ssh: this private key is passphrase protected
dial tcp ***:22: i/o timeout
```

**Root cause:** The SSH private key stored in `WEB_PLATFORM_SSH_KEY` was generated with a passphrase. The `appleboy/ssh-action` step at line 66 of `build-web-platform.yml` passes `key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}` but does not pass `passphrase:`. The action's Go SSH client calls `ssh.ParsePrivateKey`, which fails immediately on passphrase-protected keys without the decryption passphrase.

**Impact:** Every `workflow_dispatch` with `deploy: true` fails. Deployments require manual SSH access.

## Proposed Solution

**Option 1 (recommended): Generate a new passwordless SSH key and update the secret.**

Generate an Ed25519 key without a passphrase, add the public key to the server's `authorized_keys`, and replace the `WEB_PLATFORM_SSH_KEY` GitHub secret with the new private key.

This is the simplest, most maintainable option. CI SSH keys should not have passphrases -- there is no interactive agent to unlock them, and the passphrase would need to be stored as yet another secret (defeating the purpose).

## Alternative Approaches Considered

**Option 2: Add `passphrase` input to the `appleboy/ssh-action` step.**

```yaml
# .github/workflows/build-web-platform.yml (deploy step)
- name: Deploy to server
  uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
  with:
    host: ${{ secrets.WEB_PLATFORM_HOST }}
    username: root
    key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}
    passphrase: ${{ secrets.WEB_PLATFORM_SSH_PASSPHRASE }}
    script: |
      ...
```

**Rejected because:** Storing the passphrase as a separate secret adds complexity without security benefit. The passphrase protects the key at rest, but in CI the key is already in memory via the secret. A passphrase-protected key + passphrase secret is equivalent to a passwordless key -- both are compromised if the secret store is compromised. The second secret doubles the rotation surface area.

**Option 3: Replace SSH deploy with Watchtower or webhook-triggered deploy.**

**Deferred, not rejected:** Watchtower or a webhook listener on the server would eliminate SSH entirely. This is architecturally cleaner for the long term but is a larger scope change that should be tracked separately. The current fix should unblock deploys immediately.

## Non-goals

- Changing the deploy mechanism (Watchtower, webhook) -- separate issue for future consideration
- Rotating or changing the server's host SSH keys
- Modifying Terraform infrastructure (`apps/web-platform/infra/server.tf`) -- Terraform manages the Hetzner SSH key resource from `var.ssh_key_path` (default: `~/.ssh/id_ed25519.pub`), but the CI deploy key is a separate concern from the server provisioning key
- Restricting the CI key's capabilities via `authorized_keys` command restriction (worth doing but separate scope)

## Technical Considerations

### Key generation

Use Ed25519 (same algorithm as the Terraform default `~/.ssh/id_ed25519.pub`). Ed25519 is the current best practice: short keys, fast operations, no configuration pitfalls.

```bash
ssh-keygen -t ed25519 -C "ci-deploy@soleur-web-platform" -f ci_deploy_key -N ""
```

The `-N ""` flag explicitly sets an empty passphrase. The `-C` comment tag identifies the key's purpose in `authorized_keys` output.

### Server-side key installation

The public key must be appended to `/root/.ssh/authorized_keys` on the web-platform server. This can be done via the existing manual SSH access:

```bash
ssh root@<server-ip> 'cat >> /root/.ssh/authorized_keys' < ci_deploy_key.pub
```

Alternatively, if Terraform is re-applied, the `hcloud_ssh_key.default` resource would need updating -- but that resource controls the key injected at server creation time, not post-creation `authorized_keys`. Adding the CI key via `authorized_keys` is the correct approach for a deploy key that is separate from the provisioning key.

### Secret rotation

1. Generate key locally (never on CI)
2. Install public key on server
3. Verify SSH access: `ssh -i ci_deploy_key root@<server-ip> 'echo ok'`
4. Update GitHub secret: `gh secret set WEB_PLATFORM_SSH_KEY < ci_deploy_key`
5. Shred local private key: `shred -u ci_deploy_key`
6. Trigger deploy: `gh workflow run build-web-platform.yml -f deploy=true`
7. Verify workflow succeeds

### Security considerations

- The private key must never be committed to the repository
- The key should be generated on the operator's local machine and uploaded directly to GitHub secrets
- After uploading, the local private key should be securely deleted (`shred -u`)
- The old passphrase-protected key in the GitHub secret becomes inert once replaced -- no revocation needed since the public key on the server will be replaced
- Consider restricting the new key in `authorized_keys` with `command="..."` or `restrict` options in a follow-up issue

### SpecFlow edge cases

- **Server unreachable during key installation:** The manual SSH workaround from #738 confirms the server is reachable. If it becomes unreachable, the Hetzner console provides emergency access.
- **Old public key left in authorized_keys:** Non-harmful. The old private key (passphrase-protected) is being replaced in the GitHub secret, so the orphaned public key grants no access. Clean up in a follow-up.
- **Health check timing:** The existing health check in the workflow (10 retries, 3s apart = 30s window) is adequate. No changes needed.
- **Concurrent deploys:** The `workflow_dispatch` trigger does not have concurrency control. Two simultaneous deploys could race on `docker stop`/`docker run`. This is a pre-existing issue unrelated to the SSH key fix.

## Acceptance Criteria

- [ ] `gh workflow run build-web-platform.yml -f deploy=true` completes successfully
- [ ] Deploy job connects to server and restarts the container
- [ ] Health check passes after deploy (`curl -sf http://localhost:3000/health` returns 200)
- [ ] No passphrase-related errors in workflow logs
- [ ] `WEB_PLATFORM_SSH_KEY` secret contains a passwordless Ed25519 private key
- [ ] Old passphrase-protected key is no longer in the secret store

## Test Scenarios

- Given a passwordless Ed25519 key in `WEB_PLATFORM_SSH_KEY`, when `workflow_dispatch` triggers with `deploy: true`, then the deploy job SSH-connects to the server, pulls the latest image, restarts the container, and the health check passes.
- Given the new public key is in `/root/.ssh/authorized_keys` on the server, when connecting via `ssh -i <key> root@<host>`, then the connection succeeds without prompting for a passphrase.
- Given the deploy job completes, when inspecting the workflow run logs, then no `ssh.ParsePrivateKey` or `passphrase` errors appear.
- Given a `workflow_dispatch` with `deploy: false` (default), when the workflow runs, then only the `build-and-push` job executes and the deploy job is skipped.

## Implementation Steps

### Phase 1: Key Generation and Installation (manual -- requires SSH access)

1. Generate a new Ed25519 keypair without a passphrase
2. SSH into the web-platform server using existing access
3. Append the new public key to `/root/.ssh/authorized_keys`
4. Verify SSH access with the new key
5. Update the `WEB_PLATFORM_SSH_KEY` GitHub secret via `gh secret set`
6. Securely delete the local private key

### Phase 2: Verification (automated)

1. Trigger the workflow: `gh workflow run build-web-platform.yml -f deploy=true`
2. Poll the workflow run until completion
3. Verify the deploy job succeeded
4. Check health endpoint responds

### Phase 3: Cleanup

1. Remove the old public key from `/root/.ssh/authorized_keys` (optional, non-urgent)
2. Consider filing a follow-up issue for `command=` restriction on the CI key
3. Consider filing a follow-up issue for Watchtower/webhook-based deploy

## Context

- **Issue:** #738
- **Priority:** P1 (deploy pipeline broken, manual workaround only)
- **Discovered during:** #678
- **Related:** `apps/web-platform/infra/server.tf` (Terraform SSH key resource -- separate concern)
- **Workflow file:** `.github/workflows/build-web-platform.yml:66`
- **Action:** `appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2` (v1.2.5)

## References

- [appleboy/ssh-action README -- passphrase input](https://github.com/appleboy/ssh-action#input-variables)
- [GitHub Docs -- Using secrets in workflows](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)
- [SSH key types comparison](https://goteleport.com/blog/comparing-ssh-keys/)
