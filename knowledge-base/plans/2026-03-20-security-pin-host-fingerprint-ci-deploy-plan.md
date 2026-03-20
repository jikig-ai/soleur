---
title: "security: pin server host key fingerprint in CI deploy workflow"
type: feat
date: 2026-03-20
semver: patch
deepened: 2026-03-20
---

# security: pin server host key fingerprint in CI deploy workflow

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Technical Considerations, SpecFlow Analysis, Fingerprint Verification Internals, Obtaining the Fingerprint)
**Research sources:** appleboy/ssh-action action.yml, appleboy/drone-ssh plugin.go, appleboy/easyssh-proxy easyssh.go (fingerprint verification implementation), golang.org/x/crypto/ssh FingerprintSHA256 source code

### Key Improvements
1. Traced fingerprint verification through the full call chain (ssh-action -> drone-ssh -> easyssh-proxy -> golang.org/x/crypto/ssh) and documented the exact comparison logic and format requirement
2. Confirmed the `SHA256:<base64>` format requirement from Go source code -- the `ssh.FingerprintSHA256()` function prepends `SHA256:` to unpadded base64
3. Added `ssh-keyscan` alternative for obtaining the fingerprint remotely (no server SSH access needed)
4. Documented the silent fallback behavior when the fingerprint secret is empty -- the action defaults to `ssh.InsecureIgnoreHostKey()`, providing zero protection

### New Considerations Discovered
- The fingerprint comparison in easyssh-proxy is an exact string match against `ssh.FingerprintSHA256(publicKey)` return value -- no normalization, no case folding, no prefix stripping
- `ssh-keyscan -t ed25519 <host>` can obtain the host key remotely, which is then piped to `ssh-keygen -lf -` to get the SHA256 fingerprint -- this avoids needing SSH access to the server
- The `telegram-bridge-release.yml` env setup step (line 41) passes sensitive env vars (`TELEGRAM_BOT_TOKEN`, `ANTHROPIC_API_KEY`) via the `envs` input -- without fingerprint verification, these secrets could be intercepted by a MITM attacker

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

### Fingerprint Verification Internals (from source code review)

The `fingerprint` input flows through three layers:

1. **appleboy/ssh-action** (`action.yml`) -- passes `INPUT_FINGERPRINT` env var to `entrypoint.sh`, which downloads and runs the `drone-ssh` binary
2. **appleboy/drone-ssh** (`plugin.go`) -- maps `Config.Fingerprint` to `easyssh.MakeConfig.Fingerprint`
3. **appleboy/easyssh-proxy** (`easyssh.go`) -- the actual verification:

```go
// From easyssh.go - getSSHConfig function
hostKeyCallback := ssh.InsecureIgnoreHostKey()
if config.Fingerprint != "" {
    hostKeyCallback = func(hostname string, remote net.Addr, publicKey ssh.PublicKey) error {
        if ssh.FingerprintSHA256(publicKey) != config.Fingerprint {
            return fmt.Errorf("ssh: host key fingerprint mismatch")
        }
        return nil
    }
}
```

4. **golang.org/x/crypto/ssh** (`keys.go`) -- `FingerprintSHA256` implementation:

```go
func FingerprintSHA256(pubKey PublicKey) string {
    sha256sum := sha256.Sum256(pubKey.Marshal())
    hash := base64.RawStdEncoding.EncodeToString(sha256sum[:])
    return "SHA256:" + hash
}
```

**Critical format detail**: The comparison is an exact string match (`!=`). The secret value must include the `SHA256:` prefix and use unpadded base64 (no trailing `=`). This matches the output of `ssh-keygen -l -f <keyfile> | cut -d ' ' -f2`.

**Empty fingerprint behavior**: When the secret is empty or missing, `config.Fingerprint` is `""`, the `if` branch is skipped, and `ssh.InsecureIgnoreHostKey()` is used -- equivalent to `StrictHostKeyChecking=no`. The workflow will succeed but with zero MITM protection.

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

1. **Secret not set before first deploy**: If the workflow runs before the secret is created, `${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}` resolves to empty string. The easyssh-proxy library skips verification when `Fingerprint` is empty (falls through to `ssh.InsecureIgnoreHostKey()`). This means the change is backward-compatible -- deploys will not break if the secret is not yet set. However, the security benefit is absent until the secret is populated.
2. **Server reprovisioning**: A new server gets a new host key. The deploy will fail with `ssh: host key fingerprint mismatch`. This is the desired behavior -- it prevents deploying to the wrong server. The operator must update the secret.
3. **Key type mismatch**: If the server presents an RSA key but the fingerprint is from Ed25519, verification fails because `ssh.FingerprintSHA256()` is called on whatever key the server presents during the handshake. The server's `sshd_config` should present Ed25519 preferentially (standard on modern Ubuntu). The `HostKeyAlgorithms` directive or client-side key type preference is not configurable via `appleboy/ssh-action`.
4. **Fingerprint format sensitivity**: The comparison is an exact string match with no normalization. A fingerprint with trailing padding (`SHA256:abc123==`) will not match the Go output (`SHA256:abc123`). The `ssh-keygen -l` output uses the same unpadded format, so this is only a concern if the fingerprint is obtained from a different tool.
5. **Env var exposure in telegram-bridge**: The first ssh-action step in `telegram-bridge-release.yml` passes `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USER_ID`, and `ANTHROPIC_API_KEY` via the `envs` input. Without fingerprint verification, a MITM attacker could capture these secrets. This makes the telegram-bridge workflow the higher-risk target of the two.

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

### Obtaining the fingerprint (one-time step)

**Option A: Via SSH (requires existing server access)**

```bash
ssh <server> ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub | cut -d ' ' -f2
# Output: SHA256:AAAA...
```

**Option B: Via ssh-keyscan (remote, no server login needed)**

```bash
ssh-keyscan -t ed25519 <server> 2>/dev/null | ssh-keygen -lf - | cut -d ' ' -f2
# Output: SHA256:AAAA...
```

Note: Option B fetches the key over the network. If the first fetch is already MITM'd, the pinned fingerprint would be the attacker's. Option A is more trustworthy since it reads the key file directly on the server. Given the server is already deployed and in use, Option A is preferred.

**Store the secret:**

```bash
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:AAAA..."
```

**Verify format**: The value must include the `SHA256:` prefix and use unpadded base64 (no trailing `=`). The `ssh-keygen -l` output matches this format.

## References

- Issue: #748
- Parent issue: #738 (CI deploy SSH key fix)
- [appleboy/ssh-action README](https://github.com/appleboy/ssh-action) -- `fingerprint` input documentation
- [appleboy/easyssh-proxy easyssh.go](https://github.com/appleboy/easyssh-proxy/blob/master/easyssh.go) -- fingerprint verification implementation (`getSSHConfig` function)
- [golang.org/x/crypto/ssh keys.go](https://github.com/golang/crypto/blob/master/ssh/keys.go) -- `FingerprintSHA256` returns `"SHA256:" + unpadded_base64`
- Learning: [CI SSH deploy firewall hidden dependency](../learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md)
- Learning: [Docker base image digest pinning](../learnings/2026-03-19-docker-base-image-digest-pinning.md) -- analogous supply-chain pinning pattern
- Workflow: `.github/workflows/web-platform-release.yml:45-78`
- Workflow: `.github/workflows/telegram-bridge-release.yml:40-91`
