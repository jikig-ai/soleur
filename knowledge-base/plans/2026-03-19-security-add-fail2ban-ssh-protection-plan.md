---
title: "security: add fail2ban for SSH brute-force protection"
type: feat
date: 2026-03-19
semver: patch
---

# security: add fail2ban for SSH brute-force protection

## Overview

Add fail2ban to the web-platform cloud-init configuration to rate-limit SSH brute-force attempts. With SSH port 22 open to `0.0.0.0/0` (required for GitHub Actions CI deploys per #738), the server currently has no connection rate limiting, exposing it to brute-force attacks and pre-auth exploitation of future OpenSSH CVEs.

## Problem Statement

The web-platform firewall (`apps/web-platform/infra/firewall.tf`) opens SSH to all IPs because GitHub Actions runners use 5,000+ dynamic IPs that cannot be allowlisted (documented in learning `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`). While SSH hardening is in place (key-only auth via `01-hardening.conf` drop-in, `MaxAuthTries 3`, `LoginGraceTime 30`), there is no mechanism to ban IPs that repeatedly fail authentication. This means:

1. Attackers can retry indefinitely from the same IP after the grace period resets
2. Log noise from brute-force attempts obscures legitimate security events
3. Any future OpenSSH pre-auth CVE (like regresshion/CVE-2024-6387) has a wider attack surface without connection limiting

## Proposed Solution

Add `fail2ban` to the `packages:` list in `apps/web-platform/infra/cloud-init.yml`. Ubuntu 24.04 ships fail2ban with a default `sshd` jail that:

- Monitors `/var/log/auth.log` (systemd journal on Ubuntu 24.04 via `backend = systemd`)
- Bans IPs after 5 failed attempts within 10 minutes
- Bans for 10 minutes (escalating on repeat offenders with default `bantime.increment`)
- Uses `nftables` as the ban action (Ubuntu 24.04 default)

No custom jail configuration, no `write_files` entries, no `runcmd` commands -- the package install alone activates protection.

### File change

**`apps/web-platform/infra/cloud-init.yml`** -- add `fail2ban` to the `packages:` list:

```yaml
packages:
  - curl
  - jq
  - fail2ban
```

## Technical Considerations

### Why no custom jail configuration is needed

Ubuntu 24.04's fail2ban package includes `/etc/fail2ban/jail.d/defaults-debian.conf` which enables the `[sshd]` jail by default. The jail uses sensible defaults (5 retries, 10m ban, systemd backend). Custom tuning can be added later if monitoring reveals the defaults are too lenient or too aggressive.

### Interaction with existing SSH hardening

The existing `01-hardening.conf` drop-in sets `MaxAuthTries 3`. This means SSH disconnects after 3 failed auth attempts per connection, but does not prevent reconnection. fail2ban complements this by banning the source IP after repeated connection-level failures, closing the retry loop.

### Interaction with CI deploys

GitHub Actions CI deploys authenticate with a dedicated SSH key (`WEB_PLATFORM_SSH_KEY` secret). These connections succeed on first attempt and will never trigger fail2ban. The only risk is if CI begins rapid-fire SSH connections (unlikely given deploy cadence), which would require fail2ban `ignoreip` tuning -- not needed now.

### Why not the telegram-bridge server

The telegram-bridge firewall restricts SSH to `admin_ips` only (no `0.0.0.0/0` rule). Brute-force attempts from the internet never reach port 22. fail2ban would be defense-in-depth there but is not security-critical. A separate issue can track adding it to telegram-bridge if desired.

### Deployment consideration

This change only takes effect on server rebuild (`terraform apply` that recreates the server). Existing servers are unaffected. To protect the current running server before rebuild, fail2ban can be installed manually via SSH: `apt install -y fail2ban`.

## Non-Goals

- Custom jail configuration (defaults are appropriate for the current threat model)
- fail2ban for non-SSH services (no other services exposed)
- fail2ban on telegram-bridge (SSH not exposed to internet)
- Monitoring/alerting integration for ban events (future enhancement)

## Acceptance Criteria

- [ ] `fail2ban` added to `packages:` list in `apps/web-platform/infra/cloud-init.yml`
- [ ] fail2ban installed and running on web-platform server after rebuild
- [ ] SSH brute-force attempts are rate-limited (IPs banned after repeated failures)

## Test Scenarios

- Given the cloud-init.yml has fail2ban in packages, when a new server is provisioned, then fail2ban is installed and the sshd jail is active (`fail2ban-client status sshd` returns "currently banned: 0")
- Given fail2ban is running with default sshd jail, when an IP fails SSH auth 5 times within 10 minutes, then that IP is banned for 10 minutes
- Given fail2ban is running, when a CI deploy connects with a valid SSH key, then the connection succeeds and the IP is not banned

## MVP

### apps/web-platform/infra/cloud-init.yml

```yaml
packages:
  - curl
  - jq
  - fail2ban
```

## References

- Issue: #764
- SSH hardening PR: #776
- Firewall open for CI: #738 (learning: `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`)
- OpenSSH drop-in precedence: learning `2026-03-19-openssh-first-match-wins-drop-in-precedence.md`
- Related security issues: #747 (command= restriction), #748 (host key pinning), #749 (Watchtower)

Closes #764
