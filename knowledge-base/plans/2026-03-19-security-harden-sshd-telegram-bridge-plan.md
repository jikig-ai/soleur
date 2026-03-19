---
title: "security: harden sshd config for telegram-bridge server"
type: fix
date: 2026-03-19
semver: patch
---

# security: harden sshd config for telegram-bridge server

## Status: Already Resolved

Issue #777 has been fully resolved by PR #783 (merged 2026-03-19T17:22:36Z). The PR body referenced `Closes #778` but did not include `Closes #777`, so #777 remains open despite the work being complete.

## What Was Requested (Issue #777)

Apply the same `write_files` drop-in pattern from #765 to `apps/telegram-bridge/infra/cloud-init.yml`:

- Create `/etc/ssh/sshd_config.d/01-hardening.conf` with all hardening directives
- Remove redundant `sed` commands
- Keep `systemctl restart sshd`

## What PR #783 Delivered

PR #783 ("security: add SSH keepalive directives and migrate telegram-bridge hardening") completed all of the above plus:

1. **Migrated telegram-bridge** from `sed`-based SSH hardening to declarative `write_files` + `01-hardening.conf` drop-in
2. **Added 5 previously missing directives**: `KbdInteractiveAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `PermitRootLogin prohibit-password`, `AllowUsers root`
3. **Added keepalive directives** to both servers: `ClientAliveInterval 300`, `ClientAliveCountMax 2`
4. **Both servers now produce identical SSH hardening configuration**

## Verification

The `01-hardening.conf` drop-in on `origin/main` for telegram-bridge contains:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
LoginGraceTime 30
PermitRootLogin prohibit-password
AllowUsers root
ClientAliveInterval 300
ClientAliveCountMax 2
```

This matches the web-platform configuration exactly, fulfilling all acceptance criteria from #777.

## Remaining Action

- [ ] Close issue #777 with a comment referencing PR #783 as the resolution

## Non-goals

- No additional code changes required
- No new infrastructure provisioning
- No CI changes

## Acceptance Criteria

- [x] `apps/telegram-bridge/infra/cloud-init.yml` uses `write_files` with `01-hardening.conf` drop-in (done in PR #783)
- [x] Drop-in sets all hardening directives including `MaxAuthTries`, `LoginGraceTime`, `PermitRootLogin`, `AllowUsers` (done in PR #783)
- [x] Redundant `sed` commands removed (done in PR #783)
- [x] `systemctl restart sshd` in `runcmd` (done in PR #783)
- [ ] Issue #777 closed with proper cross-reference

## Test Scenarios

- Given PR #783 is merged, when checking `origin/main:apps/telegram-bridge/infra/cloud-init.yml`, then the `write_files` section contains all 8 hardening directives
- Given issue #777 is closed with a comment, when viewing the issue, then it links to PR #783 as the resolution

## References

### Internal

- Issue: #777
- Resolution PR: #783 (closed #778 but also resolved #777)
- Original web-platform issue: #765 (closed by PR #776)
- Keepalive issue: #778 (closed by PR #783)
- Learning: [OpenSSH first-match-wins drop-in precedence](../learnings/2026-03-19-openssh-first-match-wins-drop-in-precedence.md)
- Plan for web-platform hardening: [2026-03-19-security-harden-sshd-config-plan.md](./2026-03-19-security-harden-sshd-config-plan.md)
