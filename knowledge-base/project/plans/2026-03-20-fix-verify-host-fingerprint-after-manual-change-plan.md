---
title: "fix: verify WEB_PLATFORM_HOST_FINGERPRINT secret after manual change"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

# fix: verify WEB_PLATFORM_HOST_FINGERPRINT secret after manual change

## Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Technical Considerations, Proposed Solution, MVP, Test Scenarios)
**Research sources:** appleboy/ssh-action issue #275, appleboy/easyssh-proxy source code, SSH host key best practices for CI/CD

### Key Improvements

1. **Key type negotiation is unreliable** -- appleboy/ssh-action issue #275 reveals multiple users found ed25519 fingerprints fail while ecdsa works. The Go SSH library negotiates key type at runtime based on server/client algorithm preference ordering, which may not match ed25519 even on modern servers. The plan must retrieve and try ALL key types, not assume ed25519.
2. **Systematic fallback procedure** added -- try ed25519 first, fall back to ecdsa, then rsa. Each attempt requires a deploy trigger to verify because the secret value is write-only (not readable via API).
3. **Automation-first approach** -- direct SSH command execution via `ssh root@<host> <command>` avoids interactive sessions. The `ssh-keyscan` alternative provides a non-SSH fallback for fingerprint retrieval.
4. **Post-fix hardening** -- document the working key type in a learning file so future reprovisioning knows which algorithm to pin.

### New Considerations Discovered

- The `easyssh-proxy` fingerprint comparison is an exact string match against `ssh.FingerprintSHA256(publicKey)` with no normalization -- trailing `=` padding, case differences, or prefix omission all cause silent failures
- Multiple users in appleboy/ssh-action#275 report "I first tried rsa and ed25519, and finally switched to the ecdsa fingerprint, which successfully passed verification" -- the negotiated key type is server-configuration-dependent, not predictable
- The error message `ssh: host key fingerprint mismatch` is the only diagnostic -- it does not reveal which key type was negotiated or what fingerprint was expected vs received, making debugging blind without trying all types

## Overview

During the deploy failure incident on 2026-03-20, the `WEB_PLATFORM_HOST_FINGERPRINT` GitHub secret was manually updated at 08:44 UTC. The previous value (set by PR #824 and verified working) may have been replaced with an incorrect fingerprint. This issue tracks verifying the current secret value against the actual server host key and correcting it if mismatched.

## Problem Statement

The `WEB_PLATFORM_HOST_FINGERPRINT` secret gates SSH host key verification for all CI deploys (web-platform and telegram-bridge). If the manually-set value is wrong, every deploy will fail with `ssh: host key fingerprint mismatch`. The most recent deploy (PR #859 at 09:54 UTC) failed with `ssh: unable to authenticate` -- an auth failure that precedes fingerprint verification in the SSH handshake. This means the fingerprint has not been tested end-to-end since the manual change.

Issue #857 (deploy user migration) is now CLOSED, meaning the `deploy` user and forced command infrastructure should be in place on the server. The next deploy attempt will reach the fingerprint verification step, and if the secret is wrong, it will fail there.

## Proposed Solution

1. **Retrieve fingerprints for ALL key types** from the server (ed25519, ecdsa, rsa) -- do not assume which type the SSH client will negotiate
2. **Try ed25519 first** via `gh secret set`, then trigger a deploy to verify
3. **If ed25519 fails with fingerprint mismatch**, try ecdsa fingerprint (most common fallback per appleboy/ssh-action#275)
4. **If ecdsa also fails**, try rsa fingerprint as last resort
5. **Verify end-to-end** with a successful deploy, then document the working key type

### Research Insights

**Why all key types must be tried:** The Go `crypto/ssh` library's key algorithm negotiation depends on the intersection of client-supported and server-offered algorithms, ordered by preference. The server's `sshd_config` `HostKeyAlgorithms` directive and the client's `Config.HostKeyAlgorithms` field both influence the outcome. The `appleboy/ssh-action` does not expose a way to force a specific algorithm, so the negotiated type is opaque to the workflow author.

**Automation strategy:** Since `gh secret list` shows metadata but not values, verification requires a write-then-test loop. Each fingerprint attempt is: `gh secret set` -> `gh workflow run` -> poll for result -> check if the deploy step passed or failed with fingerprint mismatch.

## Technical Considerations

- **Fingerprint format**: Must be `SHA256:<unpadded_base64>` (exact match, no normalization). The `easyssh-proxy` comparison is `ssh.FingerprintSHA256(publicKey) != config.Fingerprint` -- a direct string inequality check with no case folding, no prefix stripping, no padding normalization. The `ssh-keygen -l -f <keyfile> | cut -d ' ' -f2` output matches this format exactly.
- **Key type negotiation is unreliable**: Despite modern Ubuntu servers offering ed25519, the Go SSH library may negotiate ecdsa or even rsa depending on the server's `HostKeyAlgorithms` configuration and the client library's preference ordering. Multiple users in [appleboy/ssh-action#275](https://github.com/appleboy/ssh-action/issues/275) report ed25519 failing and ecdsa working. The plan must not assume ed25519.
- **Error message is opaque**: The fingerprint mismatch error (`ssh: host key fingerprint mismatch`) does not reveal which key type was negotiated or what the expected vs actual fingerprints were. Debugging requires trial-and-error across key types.
- **Server access**: The server IP is stored in `WEB_PLATFORM_HOST` GitHub secret. It can also be obtained via `hcloud server list` (if the Hetzner token is configured) or from Terraform state. SSH access as root is available (the `deploy` user is also available but forced-command-restricted).
- **No code changes needed**: This is a secrets-only fix. No workflow files need modification -- the `fingerprint:` input is already wired in both release workflows (PR #824).
- **Both workflows affected**: `web-platform-release.yml` and `telegram-bridge-release.yml` both reference `WEB_PLATFORM_HOST_FINGERPRINT` and deploy to the same server.
- **Deploy user readiness**: PR #859 completed the deploy user migration. Workflows now use `username: deploy` with forced commands. The next deploy should work if both auth and fingerprint are correct.
- **Empty fingerprint fallback**: If the secret is empty or missing, `easyssh-proxy` falls back to `ssh.InsecureIgnoreHostKey()` -- equivalent to `StrictHostKeyChecking=no`. As a temporary unblock, clearing the secret would bypass fingerprint verification entirely (but removes MITM protection).

### Fingerprint Verification Call Chain (from source code)

```text
appleboy/ssh-action (action.yml)
  -> INPUT_FINGERPRINT env var
  -> drone-ssh binary (plugin.go)
  -> Config.Fingerprint -> easyssh.MakeConfig.Fingerprint
  -> easyssh-proxy (easyssh.go:176-206)
  -> if config.Fingerprint != "" {
       hostKeyCallback = func(...) error {
         if ssh.FingerprintSHA256(publicKey) != config.Fingerprint {
           return fmt.Errorf("ssh: host key fingerprint mismatch")
         }
         return nil
       }
     }
```

The `publicKey` in the callback is whatever key the server presents during the SSH handshake -- its type depends on negotiation, not on the fingerprint value stored in the secret.

## Acceptance Criteria

- [x] SSH into web platform server and retrieve host key fingerprints for ALL key types (ed25519, ecdsa, rsa)
- [x] Identify which key type `appleboy/ssh-action` actually negotiates (by trial: set fingerprint, trigger deploy, check result)
- [x] Set `WEB_PLATFORM_HOST_FINGERPRINT` GitHub secret to the verified correct `SHA256:<hash>` value for the negotiated key type
- [x] Trigger a web-platform deploy and confirm SSH connection succeeds with fingerprint verification
- [x] Confirm telegram-bridge uses the same host (both reference `WEB_PLATFORM_HOST`) so a single fingerprint covers both workflows
- [x] Document the working key type in a learning file for future reprovisioning reference

## Test Scenarios

- Given the correct fingerprint for the negotiated key type in the GitHub secret, when a deploy workflow runs, then SSH connects successfully and the deploy command executes
- Given the fingerprint is for ed25519 but the server negotiates ecdsa, when a deploy workflow runs, then it fails with `ssh: host key fingerprint mismatch` (key type mismatch, not a wrong fingerprint per se)
- Given the server was reprovisioned since the secret was last set, when the fingerprint is retrieved, then it differs from the stored value (indicating the secret is stale)
- Given an incorrect fingerprint was set manually during the incident, when the correct fingerprint replaces it, then deploys resume working
- Given the fingerprint secret is cleared (empty string), when a deploy workflow runs, then SSH falls back to `InsecureIgnoreHostKey` and connects without verification (emergency unblock, not desired steady state)

## Context

- **Incident timeline**: PR #834 broke deploys at 08:31 UTC by switching to `username: deploy` before server-side setup. The fingerprint was manually updated at 08:44 UTC during triage. PR #847 reverted to `username: root` at 09:40 UTC. PR #859 completed the proper deploy user migration at 09:54 UTC.
- **Related learning**: `2026-03-20-premature-ssh-user-migration-breaks-ci-deploys.md` documents the full incident and notes the fingerprint mismatch as a secondary failure mode.
- **Key algorithm note**: The learning states "appleboy/ssh-action negotiated ed25519 but the stored fingerprint was for a different algorithm" -- this hypothesis was written during the incident before investigation. **Post-investigation correction:** ssh-action actually negotiates ECDSA, not ED25519. See `2026-03-20-ssh-action-negotiates-ecdsa-not-ed25519.md`.

## MVP

### Step 1: Retrieve ALL fingerprints from server

```bash
# Option A: Direct SSH (preferred -- reads key files on disk, no network MITM risk)
ssh root@<server-ip> 'for f in /etc/ssh/ssh_host_*_key.pub; do echo "--- $f ---"; ssh-keygen -l -f "$f"; done'
```

```bash
# Option B: Remote via ssh-keyscan (no SSH login needed, but trusts the network)
for type in ed25519 ecdsa rsa; do
  echo "--- $type ---"
  ssh-keyscan -t "$type" <server-ip> 2>/dev/null | ssh-keygen -lf - | cut -d ' ' -f2
done
```

Expected output format for each key type:

```text
--- /etc/ssh/ssh_host_ed25519_key.pub ---
256 SHA256:AAAA... root@server (ED25519)
--- /etc/ssh/ssh_host_ecdsa_key.pub ---
256 SHA256:BBBB... root@server (ECDSA)
--- /etc/ssh/ssh_host_rsa_key.pub ---
3072 SHA256:CCCC... root@server (RSA)
```

Record all three `SHA256:...` values.

### Step 2: Try ed25519 fingerprint first

```bash
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:<ed25519-hash>"
```

### Step 3: Trigger a deploy to verify

```bash
# Trigger a manual web-platform release
gh workflow run web-platform-release.yml -f bump_type=patch

# Poll for completion (deploy job starts after release job)
gh run list --workflow=web-platform-release.yml --limit 1 --json databaseId,status,conclusion
```

### Step 4: If fingerprint mismatch, try ecdsa

Check the deploy step logs for `ssh: host key fingerprint mismatch`. If present:

```bash
# Switch to ecdsa fingerprint
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:<ecdsa-hash>"

# Re-trigger (use skip_deploy=false or re-run the failed deploy job)
gh run rerun <run-id> --job deploy
```

### Step 5: If ecdsa also fails, try rsa

```bash
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:<rsa-hash>"
gh run rerun <run-id> --job deploy
```

### Step 6: Emergency fallback (temporary, removes MITM protection)

If all three fail (unlikely -- indicates a deeper issue):

```bash
# Clear the fingerprint to bypass verification entirely
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body ""
```

This falls back to `ssh.InsecureIgnoreHostKey()` and should be reverted once the correct fingerprint is identified.

### Step 7: Document the working key type

After a successful deploy, create a learning documenting which key type `appleboy/ssh-action` actually negotiated with this server. This prevents the same trial-and-error on future reprovisioning.

### Edge Cases

- **Server reprovisioned between secret set and deploy**: If `terraform apply -replace` ran between PR #824 and now, all host keys changed. The fingerprints retrieved in Step 1 are authoritative.
- **Multiple key types work**: If the server's `HostKeyAlgorithms` config changes (e.g., via cloud-init on reprovision), the negotiated type could change. Store all three fingerprints in the learning file.
- **Format gotcha**: `ssh-keygen -l` on some systems outputs MD5 by default. Use `ssh-keygen -l -E sha256 -f <keyfile>` to force SHA256 format if needed.

## References

### Internal

- Issue: [#858](https://github.com/jikig-ai/soleur/issues/858)
- PR #824: Original fingerprint pinning setup
- PR #834: Premature deploy user migration (caused incident)
- PR #847: Revert to root user
- PR #859: Complete deploy user migration with forced commands
- Existing plan: `knowledge-base/project/plans/2026-03-20-security-pin-host-fingerprint-ci-deploy-plan.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-premature-ssh-user-migration-breaks-ci-deploys.md`
- Learning: `knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Workflow: `.github/workflows/web-platform-release.yml:46-52`
- Workflow: `.github/workflows/telegram-bridge-release.yml:40-47`

### External

- [appleboy/ssh-action fingerprint issue #275](https://github.com/appleboy/ssh-action/issues/275) -- multiple users confirm ecdsa works when ed25519 fails
- [appleboy/ssh-action fingerprint format issue #81](https://github.com/appleboy/ssh-action/issues/81) -- fingerprint syntax documentation
- [appleboy/easyssh-proxy source (easyssh.go)](https://github.com/appleboy/easyssh-proxy/blob/master/easyssh.go) -- fingerprint verification implementation at lines 176-206
- [golang.org/x/crypto/ssh FingerprintSHA256](https://github.com/golang/crypto/blob/master/ssh/keys.go) -- returns `"SHA256:" + unpadded_base64`
- [Comparing SSH Fingerprint Formats (Baeldung)](https://www.baeldung.com/linux/ssh-compare-fingerprint-formats) -- MD5 vs SHA256 format reference
