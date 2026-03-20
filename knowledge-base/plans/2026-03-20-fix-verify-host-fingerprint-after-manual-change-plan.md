---
title: "fix: verify WEB_PLATFORM_HOST_FINGERPRINT secret after manual change"
type: fix
date: 2026-03-20
---

# fix: verify WEB_PLATFORM_HOST_FINGERPRINT secret after manual change

## Overview

During the deploy failure incident on 2026-03-20, the `WEB_PLATFORM_HOST_FINGERPRINT` GitHub secret was manually updated at 08:44 UTC. The previous value (set by PR #824 and verified working) may have been replaced with an incorrect fingerprint. This issue tracks verifying the current secret value against the actual server host key and correcting it if mismatched.

## Problem Statement

The `WEB_PLATFORM_HOST_FINGERPRINT` secret gates SSH host key verification for all CI deploys (web-platform and telegram-bridge). If the manually-set value is wrong, every deploy will fail with `ssh: host key fingerprint mismatch`. The most recent deploy (PR #859 at 09:54 UTC) failed with `ssh: unable to authenticate` -- an auth failure that precedes fingerprint verification in the SSH handshake. This means the fingerprint has not been tested end-to-end since the manual change.

Issue #857 (deploy user migration) is now CLOSED, meaning the `deploy` user and forced command infrastructure should be in place on the server. The next deploy attempt will reach the fingerprint verification step, and if the secret is wrong, it will fail there.

## Proposed Solution

1. **SSH into the web platform server** and retrieve fingerprints for all key types
2. **Identify the correct fingerprint** -- ed25519 is preferred (matches `appleboy/ssh-action` negotiation behavior)
3. **Compare against the current secret** -- the secret value is not readable via `gh secret list`, so the comparison requires either:
   - Setting the known-good value via `gh secret set` (idempotent if already correct)
   - Or triggering a deploy and checking whether it succeeds
4. **Set the correct fingerprint** via `gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:<hash>"`
5. **Verify end-to-end** by triggering a deploy workflow and confirming success

## Technical Considerations

- **Fingerprint format**: Must be `SHA256:<unpadded_base64>` (exact match, no normalization). This is the output format of `ssh-keygen -l -f <keyfile> | cut -d ' ' -f2`. See the existing plan (`2026-03-20-security-pin-host-fingerprint-ci-deploy-plan.md`) for the full call chain analysis through easyssh-proxy.
- **Key type negotiation**: `appleboy/ssh-action` (via `drone-ssh` and `easyssh-proxy`) uses Go's `ssh` library which negotiates the key type with the server. Modern Ubuntu servers present ed25519 first. The fingerprint in the secret must match whichever key type is actually negotiated.
- **Server access**: The server IP is stored in `WEB_PLATFORM_HOST` GitHub secret. It can also be obtained via `hcloud server list` (if the Hetzner token is configured) or from Terraform state. The learning from `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` notes the Hetzner API token was previously found in `settings.local.json`.
- **No code changes needed**: This is a secrets-only fix. No workflow files need modification -- the `fingerprint:` input is already wired in both release workflows (PR #824).
- **Both workflows affected**: `web-platform-release.yml` and `telegram-bridge-release.yml` both reference `WEB_PLATFORM_HOST_FINGERPRINT` and deploy to the same server.
- **Deploy user readiness**: PR #859 completed the deploy user migration. Workflows now use `username: deploy` with forced commands. The next deploy should work if both auth and fingerprint are correct.

## Acceptance Criteria

- [ ] SSH into web platform server and retrieve ed25519 host key fingerprint
- [ ] Set `WEB_PLATFORM_HOST_FINGERPRINT` GitHub secret to the verified correct `SHA256:<hash>` value
- [ ] Trigger a web-platform deploy and confirm SSH connection succeeds with fingerprint verification
- [ ] Trigger a telegram-bridge deploy and confirm SSH connection succeeds with fingerprint verification (or verify both share the same host and one test suffices)

## Test Scenarios

- Given the correct fingerprint in the GitHub secret, when a deploy workflow runs, then SSH connects successfully and the deploy command executes
- Given the server was reprovisioned since the secret was last set, when the fingerprint is retrieved, then it differs from the stored value (indicating the secret is stale)
- Given an incorrect fingerprint was set manually during the incident, when the correct fingerprint replaces it, then deploys resume working

## Context

- **Incident timeline**: PR #834 broke deploys at 08:31 UTC by switching to `username: deploy` before server-side setup. The fingerprint was manually updated at 08:44 UTC during triage. PR #847 reverted to `username: root` at 09:40 UTC. PR #859 completed the proper deploy user migration at 09:54 UTC.
- **Related learning**: `2026-03-20-premature-ssh-user-migration-breaks-ci-deploys.md` documents the full incident and notes the fingerprint mismatch as a secondary failure mode.
- **Key algorithm note**: The learning states "appleboy/ssh-action negotiated ed25519 but the stored fingerprint was for a different algorithm" -- this suggests the manual update may have used the wrong key type's fingerprint.

## MVP

### Retrieve fingerprints from server

```bash
# SSH into the server (replace <server-ip> with WEB_PLATFORM_HOST value)
ssh root@<server-ip>

# Get fingerprints for all key types
for f in /etc/ssh/ssh_host_*_key.pub; do
  echo "--- $f ---"
  ssh-keygen -l -f "$f"
done
```

### Set the correct fingerprint

```bash
# Use the ed25519 fingerprint (most likely negotiated)
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:<ed25519-hash>"
```

### Alternative: Remote fingerprint retrieval (no SSH needed)

```bash
# Get ed25519 fingerprint via ssh-keyscan
ssh-keyscan -t ed25519 <server-ip> 2>/dev/null | ssh-keygen -lf - | cut -d ' ' -f2
```

Note: `ssh-keyscan` fetches the key over the network. If the connection is already compromised, the fetched key could be the attacker's. Direct server access (Option A) is more trustworthy.

### Verify via deploy

```bash
# Trigger a manual web-platform release
gh workflow run web-platform-release.yml -f bump_type=patch

# Monitor the run
gh run list --workflow=web-platform-release.yml --limit 1 --json databaseId,status,conclusion
```

## References

- Issue: [#858](https://github.com/jikig-ai/soleur/issues/858)
- PR #824: Original fingerprint pinning setup
- PR #834: Premature deploy user migration (caused incident)
- PR #847: Revert to root user
- PR #859: Complete deploy user migration with forced commands
- Existing plan: `knowledge-base/plans/2026-03-20-security-pin-host-fingerprint-ci-deploy-plan.md`
- Learning: `knowledge-base/learnings/2026-03-20-premature-ssh-user-migration-breaks-ci-deploys.md`
- Learning: `knowledge-base/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Workflow: `.github/workflows/web-platform-release.yml:46-52`
- Workflow: `.github/workflows/telegram-bridge-release.yml:40-47`
- [appleboy/ssh-action fingerprint issue #275](https://github.com/appleboy/ssh-action/issues/275)
