---
title: "fix: pin Doppler CLI install with SHA-256 checksum verification"
type: fix
date: 2026-04-06
---

# fix: pin Doppler CLI install with SHA-256 checksum verification

## Overview

The Doppler CLI install in `apps/web-platform/infra/cloud-init.yml` pipes a remote
script to shell without checksum verification. This is a supply-chain risk -- a
compromised CDN or CA could serve a tampered binary. The webhook binary install in the
same file already demonstrates the correct pattern with version pinning and SHA-256
verification.

## Problem Statement

Line 171 of `cloud-init.yml`:

```bash
curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh
```

Problems:

1. **No version pin** -- always installs latest, which could introduce breaking changes
   during provisioning
2. **No integrity verification** -- TLS protects the transport but not against a
   compromised upstream (CDN, build pipeline, CA)
3. **Pipe-to-shell** -- executes arbitrary remote code; the script could change at any
   time

The issue (#1500) also references `server.tf` but that file only passes the
`doppler_token` variable to cloud-init -- the actual install command lives solely in
`cloud-init.yml`.

## Proposed Solution

Replace the `curl | sh` install with a pinned binary download + SHA-256 checksum
verification, matching the existing webhook binary install pattern at lines 222-229 of
`cloud-init.yml`.

### Target Version

- **Doppler CLI v3.75.3** (latest as of 2026-04-06)
- **SHA-256:** `9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db`
- **Source:** `doppler_3.75.3_linux_amd64.tar.gz` from
  [DopplerHQ/cli releases](https://github.com/DopplerHQ/cli/releases/tag/3.75.3)
- **Checksum verified against:**
  [checksums.txt](https://github.com/DopplerHQ/cli/releases/download/3.75.3/checksums.txt)

### Tarball Structure

The tarball contains the `doppler` binary at root level (not nested), along with
`LICENSE`, `README.md`, and `completions/` directory. Extract only the `doppler` binary.

### Existing Pattern to Match

The webhook binary install (lines 222-229) provides the exact template:

```yaml
- |
  WEBHOOK_VERSION="2.8.2"
  WEBHOOK_SHA256="7a190ec7b4c2ffbb4eb1e11755a2e7acd82f1ffe74f60f235a360441daf22fd2"
  curl -fsSL "https://github.com/adnanh/webhook/releases/download/$${WEBHOOK_VERSION}/webhook-linux-amd64.tar.gz" -o /tmp/webhook.tar.gz
  echo "$${WEBHOOK_SHA256}  /tmp/webhook.tar.gz" | sha256sum -c -
  tar xzf /tmp/webhook.tar.gz -C /usr/local/bin --strip-components=1 webhook-linux-amd64/webhook
  chmod +x /usr/local/bin/webhook
  rm /tmp/webhook.tar.gz
```

### Implementation

Replace `cloud-init.yml` line 171:

```yaml
# Before (lines 170-171):
  # Install Doppler CLI (for secrets injection)
  - curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh

# After:
  # Install Doppler CLI v3.75.3 (for secrets injection) with checksum verification
- |
  DOPPLER_VERSION="3.75.3"
  DOPPLER_SHA256="9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"
  curl -fsSL --retry 3 "https://github.com/DopplerHQ/cli/releases/download/$${DOPPLER_VERSION}/doppler_$${DOPPLER_VERSION}_linux_amd64.tar.gz" -o /tmp/doppler.tar.gz
  echo "$${DOPPLER_SHA256}  /tmp/doppler.tar.gz" | sha256sum -c -
  tar xzf /tmp/doppler.tar.gz -C /usr/local/bin doppler
  chmod +x /usr/local/bin/doppler
  rm /tmp/doppler.tar.gz
```

Key differences from the webhook pattern:

- **No `--strip-components`** -- the Doppler binary is at tarball root (`doppler`), not
  nested in a subdirectory
- **Extract target is `doppler`** -- not a path like `webhook-linux-amd64/webhook`
- **Download URL uses GitHub releases** -- not `cli.doppler.com`

### What Does NOT Change

- `server.tf` -- only passes `doppler_token` to cloud-init; no install logic
- The `doppler_token` environment setup (lines 173-176) -- unchanged
- The `doppler secrets download` usage later in cloud-init (lines 251-253) -- unchanged
- `ci-deploy.sh` -- uses `doppler` binary already on the server; unaffected

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| APT with GPG key (issue suggestion) | Auto-updates, OS-native | Adds apt repo dependency, GPG key rotation risk, slower | Rejected -- inconsistent with webhook pattern |
| Pin version in install.sh args | Simpler change | Still pipes script to shell, script itself unverified | Rejected -- doesn't fix core issue |
| Binary download + SHA-256 | Matches existing pattern, fully deterministic | Must manually update version/hash | **Chosen** -- consistency, security |

## Acceptance Criteria

- [x] `cloud-init.yml` Doppler CLI install uses pinned version `3.75.3` with SHA-256
  checksum `9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db`
- [x] Checksum verification fails loudly (non-zero exit) if hash mismatches
- [x] No `curl | sh` pattern remains for Doppler install
- [x] `server.tf` is NOT modified (no install logic there)
- [x] Existing Doppler token setup and secrets download remain unchanged
- [x] The `$${VAR}` Terraform template escape syntax is used correctly (double `$$` to
  produce literal `$` in rendered cloud-init)
- [x] Comment updated to include version: `# Install Doppler CLI v3.75.3 (for secrets
  injection) with checksum verification`
- [x] `curl` includes `--retry 3` for resilience during provisioning

## Test Scenarios

- Given a fresh server provisioning, when cloud-init runs the Doppler install block,
  then the binary is downloaded, checksum verified, and installed to `/usr/local/bin/doppler`
- Given a tampered tarball (wrong checksum), when `sha256sum -c -` runs, then it exits
  non-zero and cloud-init halts the runcmd sequence
- Given the installed binary, when `doppler secrets download` runs later in cloud-init,
  then secrets are fetched correctly (no behavioral change)
- Given Terraform `templatefile()` rendering, when `$${DOPPLER_VERSION}` is processed,
  then it produces `${DOPPLER_VERSION}` in the rendered YAML (not an empty string)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- **Issue:** #1500
- **Source:** PR #1496 code review finding
- **Effort:** Small (single file, ~10 lines changed)
- **Existing pattern:** webhook binary install at `cloud-init.yml:222-229`
- **Learning:** `knowledge-base/project/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
  documents the Doppler binary download URL pattern (`cli.doppler.com/download?os=linux&arch=...`)
  but GitHub releases provide checksums; the `cli.doppler.com` URL does not

## Plan Review

All three reviewers approved. Applied two non-blocking suggestions:

1. Added `--retry 3` to the `curl` command for provisioning resilience
2. Added acceptance criterion for updated comment with version number

**Follow-up:** The Docker install at `cloud-init.yml:179` (`curl -fsSL https://get.docker.com | sh`)
has the same pipe-to-shell pattern. Out of scope for this PR but should be tracked as a
separate issue.

## References

- GitHub issue: #1500
- Doppler CLI releases: <https://github.com/DopplerHQ/cli/releases>
- Checksums file: <https://github.com/DopplerHQ/cli/releases/download/3.75.3/checksums.txt>
- Webhook install pattern: `apps/web-platform/infra/cloud-init.yml:222-229`
- Doppler learnings: `knowledge-base/project/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
