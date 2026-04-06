---
module: web-platform-infra
date: 2026-04-06
problem_type: security_issue
component: tooling
symptoms:
  - "Doppler CLI installed via curl pipe-to-shell without checksum verification"
  - "No version pinning — always installs latest, risking breaking changes during provisioning"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [supply-chain, checksum, cloud-init, doppler, binary-verification]
---

# Troubleshooting: Doppler CLI pipe-to-shell install in cloud-init lacks checksum verification

## Problem

The Doppler CLI install in `apps/web-platform/infra/cloud-init.yml` used `curl | sh` to pipe a
remote install script directly to shell without version pinning or integrity verification, creating
a supply-chain attack surface during server provisioning.

## Environment

- Module: web-platform infra (cloud-init provisioning)
- Affected Component: `apps/web-platform/infra/cloud-init.yml` line 171
- Date: 2026-04-06

## Symptoms

- Doppler CLI installed via `curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh`
- No version pin — always installs latest, which could introduce breaking changes during provisioning
- No integrity verification — TLS protects transport but not against compromised upstream (CDN, build pipeline, CA)

## What Didn't Work

**Direct solution:** The problem was identified via PR #1496 code review and fixed on the first
attempt by matching the existing webhook binary install pattern.

## Session Errors

**Ralph Loop script path error** — Tried `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` which does not exist.

- **Recovery:** Used correct path `./plugins/soleur/scripts/setup-ralph-loop.sh`
- **Prevention:** One-shot skill should reference the correct script path in its instructions

**Shell failures (exit codes 1/134) after worktree cd** — Multiple basic Bash commands (`echo`, `ls`, `pwd`, `true`) returned exit codes 1 or 134 (SIGABRT) after changing to worktree directory.

- **Recovery:** Waited and retried; shell recovered on its own after ~2 minutes
- **Prevention:** Unknown root cause — may be related to shell state corruption during worktree creation. Use Read/Glob/Grep tools as fallback when Bash is unreliable.

**Plan file not immediately visible in worktree** — Planning subagent committed the plan file but it wasn't initially found by Glob in the worktree path.

- **Recovery:** Searched broader path patterns and found the file
- **Prevention:** After subagent completes, verify file existence with explicit absolute path before assuming it's missing

**Subagent output format mismatch** — Planning subagent did not return the exact `## Session Summary` format specified in its contract.

- **Recovery:** Manually extracted plan file path from the narrative output
- **Prevention:** Subagent return contracts should be simpler and more prominent in the prompt; consider adding a final instruction "Your last output MUST start with ## Session Summary"

## Solution

Replaced the `curl | sh` install with a pinned binary download + SHA-256 checksum verification,
matching the existing webhook binary install pattern at lines 222-229 of the same file.

**Config change:**

```yaml
# Before (insecure):
  # Install Doppler CLI (for secrets injection)
  - curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh

# After (secure):
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

Key details:

- SHA-256 verified against `checksums.txt` from GitHub releases
- `$${VAR}` is Terraform's template escape for literal `$` in rendered output
- No `--strip-components` needed — Doppler tarball has binary at root level
- Download URL uses GitHub releases (not `cli.doppler.com`) to match checksum source

## Why This Works

The root cause was using a pipe-to-shell pattern (`curl | sh`) that delegates trust entirely to
the download server. Even with TLS enforcement, a compromised CDN, build pipeline, or CA could
serve a tampered install script or binary. The fix introduces two trust boundaries:

1. **Version pinning** — locks to a specific release, preventing drift
2. **SHA-256 checksum** — embedded in source code (versioned in git, reviewed in PRs), verified
   against the downloaded tarball before extraction. A hash mismatch causes `sha256sum -c -` to
   exit non-zero, halting cloud-init's runcmd sequence.

This is the same principle as lock files (`package-lock.json`, `go.sum`) and the existing webhook
binary install pattern already in the same file.

## Prevention

- All binary installs in cloud-init should use version pin + SHA-256 checksum verification
- When adding new binary installs, copy the webhook/Doppler pattern (version var, checksum var,
  download, verify, extract, chmod, cleanup)
- Docker install at line 186 (`curl -fsSL https://get.docker.com | sh`) has the same pattern —
  tracked as #1615

## Related Issues

- See also: [checksum-verification-binary-downloads](2026-03-20-checksum-verification-binary-downloads.md)
  (same principle applied to ffmpeg and rclone in `check_deps.sh`)
- GitHub issue: #1500
- Follow-up: #1615 (Docker install checksum)
