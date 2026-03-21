# Learning: Premature SSH user migration breaks CI deploys

## Problem

PR #834 changed CI release workflows from `username: root` to `username: deploy` for SSH deployments, but the server-side prerequisites (creating the deploy user, installing SSH keys, configuring forced commands, sudoers rules) were never completed. This caused immediate SSH authentication failures on the next release deploy. A secondary failure was a host key fingerprint mismatch caused by the wrong key-type algorithm.

Two distinct failure modes:

1. **SSH auth failure** (08:35 UTC): deploy user doesn't exist on server, no authorized_keys configured
2. **Fingerprint mismatch** (08:39 UTC): appleboy/ssh-action negotiated ed25519 but the stored fingerprint was for a different algorithm

## Solution

Two-commit fix:

1. **Revert to root** (deb334c): Restore `username: root` in both `web-platform-release.yml` and `telegram-bridge-release.yml`. This unblocks immediate deploys while the full migration is tracked in issue #857.

2. **Harden version passing** (20338c4): Move `${{ needs.release.outputs.version }}` from inline script interpolation to the `envs:` parameter of appleboy/ssh-action, eliminating expression injection surface:

```yaml
# Before (injection surface)
script: |
  TAG="v${{ needs.release.outputs.version }}"

# After (safe)
env:
  DEPLOY_VERSION: ${{ needs.release.outputs.version }}
with:
  envs: DEPLOY_VERSION
script: |
  TAG="v$DEPLOY_VERSION"
```

Additional improvements retained from prior PRs: host key fingerprint pinning (#824), version format validation with regex (#836).

## Key Insight

Infrastructure migrations that span server-side setup and CI workflow changes require explicit phase gates, not just code review. A technically correct PR that assumes server-side prerequisites will fail in production if those prerequisites are incomplete. The two phases must be:

1. **Phase 1**: Complete and manually verify all server-side changes (user creation, SSH keys, forced commands, sudoers, directory ownership)
2. **Phase 2**: Only then update CI workflows to reference the new infrastructure

Merging Phase 2 before Phase 1 is complete creates a "migration gap" that breaks deployments.

Secondary insight: SSH host key fingerprints are algorithm-specific. When using `appleboy/ssh-action`, the stored fingerprint must match the algorithm that the SSH client negotiates (typically ed25519), not just any valid server key.

## Prevention

- Never merge CI workflow changes that depend on server-side infrastructure without verifying prerequisites are deployed
- For SSH user migrations: add a pre-deploy validation step that checks `id <user>` before attempting deployment
- Always pass dynamic values via `envs:` parameter in appleboy/ssh-action, never inline `${{ }}` in script bodies
- Store fingerprints for all host key algorithms (ed25519, ecdsa, rsa) and document which one is actively used

## Related

- Issue #857: Complete deploy user migration (Phase 1 server-side setup)
- Issue #858: Verify WEB_PLATFORM_HOST_FINGERPRINT secret
- Issue #846: Refactor deploy scripts to use env indirection
- PR #834: The premature migration that caused this
- PR #824: SSH host key fingerprint pinning
- Learning: `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Learning: `2026-03-20-ssh-forced-command-workflow-refactoring-drops-parameters.md`
- Learning: `2026-03-19-github-actions-env-indirection-for-context-values.md`

## Tags

category: integration-issues
module: CI/CD release workflows
