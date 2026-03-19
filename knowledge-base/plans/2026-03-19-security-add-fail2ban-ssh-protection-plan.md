---
title: "security: add fail2ban for SSH brute-force protection"
type: feat
date: 2026-03-19
semver: patch
---

# security: add fail2ban for SSH brute-force protection

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 5
**Research sources:** Ubuntu 24.04 fail2ban package docs, fail2ban GitHub issues, cloud-init documentation, DigitalOcean hardening guides, Server World Ubuntu 24.04 reference

### Key Improvements

1. Verified exact `defaults-debian.conf` contents on Ubuntu 24.04 -- confirmed sshd jail auto-enables with `nftables` ban action and `systemd` backend
2. Identified historical Python 3.12 compatibility bug (LP#2055114) -- fixed in current Ubuntu 24.04 repos, no workaround needed
3. Clarified `MaxAuthTries 3` vs fail2ban `maxretry 5` interaction -- fail2ban counts connection-level failures, not per-connection auth attempts, so these are complementary layers

### New Considerations Discovered

- The `python3-systemd` package is a dependency of fail2ban on Ubuntu 24.04, pulled in automatically by `apt install fail2ban`
- On Debian/Ubuntu, `apt install` auto-enables and auto-starts fail2ban via the systemd unit's `WantedBy=multi-user.target` -- no explicit `systemctl enable` in runcmd is needed
- fail2ban's `dbpurgeage` setting (default 24h) automatically cleans the ban database, preventing disk growth

## Overview

Add fail2ban to the web-platform cloud-init configuration to rate-limit SSH brute-force attempts. With SSH port 22 open to `0.0.0.0/0` (required for GitHub Actions CI deploys per #738), the server currently has no connection rate limiting, exposing it to brute-force attacks and pre-auth exploitation of future OpenSSH CVEs.

## Problem Statement

The web-platform firewall (`apps/web-platform/infra/firewall.tf`) opens SSH to all IPs because GitHub Actions runners use 5,000+ dynamic IPs that cannot be allowlisted (documented in learning `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`). While SSH hardening is in place (key-only auth via `01-hardening.conf` drop-in, `MaxAuthTries 3`, `LoginGraceTime 30`), there is no mechanism to ban IPs that repeatedly fail authentication. This means:

1. Attackers can retry indefinitely from the same IP after the grace period resets
2. Log noise from brute-force attempts obscures legitimate security events
3. Any future OpenSSH pre-auth CVE (like regresshion/CVE-2024-6387) has a wider attack surface without connection limiting

## Proposed Solution

Add `fail2ban` to the `packages:` list in `apps/web-platform/infra/cloud-init.yml`. Ubuntu 24.04 ships fail2ban with a default `sshd` jail that:

- Monitors the systemd journal via `backend = systemd` (not `/var/log/auth.log` -- Ubuntu 24.04 uses journald by default)
- Bans IPs after 5 failed attempts within 10 minutes
- Bans for 10 minutes (escalating on repeat offenders with default `bantime.increment`)
- Uses `nftables` as the ban action (Ubuntu 24.04 default via `banaction = nftables`)

No custom jail configuration, no `write_files` entries, no `runcmd` commands -- the package install alone activates protection.

### Research Insights

**Verified default configuration:** Ubuntu 24.04's `/etc/fail2ban/jail.d/defaults-debian.conf` contains:

```ini
[DEFAULT]
banaction = nftables
banaction_allports = nftables[type=allports]
backend = systemd

[sshd]
enabled = true
```

This means the sshd jail is enabled out of the box with modern defaults. The `nftables` ban action is the correct choice for Ubuntu 24.04 (iptables is deprecated). The `systemd` backend reads directly from the journal, which is more performant than polling log files.

**Package auto-start behavior:** On Debian/Ubuntu, `apt install fail2ban` enables and starts the service automatically because the package's systemd unit includes `WantedBy=multi-user.target`. Cloud-init's `packages:` directive triggers `apt install`, which triggers the systemd unit installation hooks. No explicit `systemctl enable fail2ban` in `runcmd` is needed.

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

### Research Insights

**Best Practices:**

- Never edit `jail.conf` directly -- use `.local` override files (`jail.local` or files in `jail.d/`) to prevent merge conflicts during package upgrades
- The `dbpurgeage` default (24 hours) automatically cleans stale ban entries from the SQLite database, preventing unbounded disk growth
- fail2ban's `bantime.increment` feature (enabled by default) progressively increases ban duration for repeat offenders -- first ban is 10 minutes, subsequent bans grow exponentially

**Edge Cases:**

- fail2ban counts connection-level authentication failures, not per-connection retries. With `MaxAuthTries 3` in sshd, a brute-force attacker gets 3 password guesses per connection before disconnect. After being disconnected 5 times (maxretry), fail2ban bans the IP. This means an attacker gets ~15 total guesses before ban (3 per connection x 5 connections)
- The `findtime` window (10 minutes) resets on each new failure, not from the first failure. This means slow-and-steady attacks (1 attempt every 11 minutes) evade fail2ban. This is acceptable for the current threat model -- such attacks are impractical against key-only auth

### Interaction with existing SSH hardening

The existing `01-hardening.conf` drop-in sets `MaxAuthTries 3`. This means SSH disconnects after 3 failed auth attempts per connection, but does not prevent reconnection. fail2ban complements this by banning the source IP after repeated connection-level failures, closing the retry loop.

The defense-in-depth stack after this change:

| Layer | Protection | Scope |
|-------|-----------|-------|
| Hetzner Firewall | Network-level access control | Limits SSH to admin IPs + CI (0.0.0.0/0) |
| `01-hardening.conf` | Key-only auth, `MaxAuthTries 3` | Per-connection limits |
| **fail2ban** | **IP ban after 5 failed connections** | **Host-level rate limiting** |

### Interaction with CI deploys

GitHub Actions CI deploys authenticate with a dedicated SSH key (`WEB_PLATFORM_SSH_KEY` secret). These connections succeed on first attempt and will never trigger fail2ban. The only risk is if CI begins rapid-fire SSH connections (unlikely given deploy cadence), which would require fail2ban `ignoreip` tuning -- not needed now.

### Why not the telegram-bridge server

The telegram-bridge firewall restricts SSH to `admin_ips` only (no `0.0.0.0/0` rule). Brute-force attempts from the internet never reach port 22. fail2ban would be defense-in-depth there but is not security-critical. A separate issue can track adding it to telegram-bridge if desired.

### Deployment consideration

This change only takes effect on server rebuild (`terraform apply` that recreates the server). Existing servers are unaffected. To protect the current running server before rebuild, fail2ban can be installed manually via SSH: `apt install -y fail2ban`.

### Historical bug: Python 3.12 compatibility (resolved)

Ubuntu 24.04 initially shipped fail2ban 1.0.2-3, which was incompatible with Python 3.12 due to the removal of the `asynchat` module ([LP#2055114](https://bugs.launchpad.net/ubuntu/+source/fail2ban/+bug/2055114)). This was fixed in `1.0.2-3ubuntu0.1` (noble-proposed, June 2024) and the fix has been in the stable repos since late 2024. No workaround is needed as of March 2026.

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
- Given fail2ban was previously running with bans in its database, when the server reboots, then fail2ban starts automatically and the sshd jail is re-enabled

### Post-Deploy Verification Commands

```bash
# Verify fail2ban is running
systemctl status fail2ban

# Verify sshd jail is active
fail2ban-client status sshd

# Check nftables rules include fail2ban chain
nft list ruleset | grep -A5 f2b

# Check ban database exists
ls -la /var/lib/fail2ban/fail2ban.sqlite3
```

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
- [Ubuntu 24.04 fail2ban reference](https://www.server-world.info/en/note?os=Ubuntu_24.04&p=fail2ban)
- [DigitalOcean: Hardening SSH with Fail2Ban, Nftables & Cloud Firewalls](https://www.digitalocean.com/community/tutorials/hardening-ssh-fail2ban)
- [fail2ban Python 3.12 bug fix (LP#2055114)](https://bugs.launchpad.net/ubuntu/+source/fail2ban/+bug/2055114)

Closes #764
