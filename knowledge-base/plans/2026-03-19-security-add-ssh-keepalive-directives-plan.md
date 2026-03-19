---
title: "security: add ClientAliveInterval/ClientAliveCountMax to SSH hardening"
type: feat
date: 2026-03-19
semver: patch
---

# security: add ClientAliveInterval/ClientAliveCountMax to SSH hardening

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 4 (Parameter Rationale, SpecFlow Edge Cases, Test Scenarios, References)
**Research sources:** Context7 cloud-init docs, OpenSSH sshd_config man pages, SSH hardening guides (2025-2026), CI workflow analysis

### Key Improvements

1. **Resolved `AllowUsers root` concern for telegram-bridge** -- CI workflow (`telegram-bridge-release.yml`) confirmed to use `username: root` via `appleboy/ssh-action`, so `AllowUsers root` is correct for both servers
2. **Documented `ClientAliveCountMax 0` gotcha** -- Setting to 0 disables termination entirely (OpenSSH man page), not what intuition suggests. Our value of 2 is the industry-standard choice
3. **Added TCPKeepAlive interaction note** -- ClientAlive messages use the encrypted SSH channel (non-spoofable), complementing the OS-level TCPKeepAlive which defaults to `yes`
4. **Confirmed cloud-init ordering** -- Context7 docs confirm `write_files` executes before `runcmd`, so the drop-in file exists before `systemctl restart sshd` runs

### New Considerations Discovered

- `ClientAliveCountMax 0` disables connection termination entirely -- counterintuitive but documented in the OpenSSH man page
- ClientAlive messages are sent through the encrypted channel and cannot be spoofed, unlike TCPKeepAlive
- The `defer: true` option in cloud-init `write_files` could delay file creation until after package install, but is NOT needed here since sshd is already installed on Ubuntu 24.04

---

Add `ClientAliveInterval 300` and `ClientAliveCountMax 2` to the SSH hardening drop-in on both web-platform and telegram-bridge servers. This drops idle SSH sessions after ~10 minutes (2 missed keepalives at 5-minute intervals), preventing resource exhaustion from orphaned connections on internet-facing servers.

## Context

- Identified during security review of #765
- Explicitly documented as out-of-scope in the #765 plan (line 97-98 of the prior plan)
- Filed as #778 to track separately
- `apps/web-platform/infra/cloud-init.yml` already uses the `write_files` + `01-hardening.conf` pattern -- just needs two lines added
- `apps/telegram-bridge/infra/cloud-init.yml` still uses the fragile `sed` pattern from pre-#765 era -- needs migration to `write_files` + `01-hardening.conf` (matching web-platform) plus the keepalive directives

## Proposed Solution

### 1. `apps/web-platform/infra/cloud-init.yml`

Add two lines to the existing `write_files` block for `/etc/ssh/sshd_config.d/01-hardening.conf`:

```yaml
write_files:
  - path: /etc/ssh/sshd_config.d/01-hardening.conf
    content: |
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      MaxAuthTries 3
      LoginGraceTime 30
      PermitRootLogin prohibit-password
      AllowUsers root
      ClientAliveInterval 300
      ClientAliveCountMax 2
    owner: root:root
    permissions: '0644'
```

### 2. `apps/telegram-bridge/infra/cloud-init.yml`

Replace the fragile `sed` commands in `runcmd` with a `write_files` drop-in matching the web-platform pattern. This brings telegram-bridge to parity with web-platform's hardening approach (per the learning in `knowledge-base/learnings/2026-03-19-openssh-first-match-wins-drop-in-precedence.md`).

```yaml
write_files:
  - path: /etc/ssh/sshd_config.d/01-hardening.conf
    content: |
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      MaxAuthTries 3
      LoginGraceTime 30
      PermitRootLogin prohibit-password
      AllowUsers root
      ClientAliveInterval 300
      ClientAliveCountMax 2
    owner: root:root
    permissions: '0644'
```

Remove the three `sed`/`sshd restart` lines from `runcmd` and add `systemctl restart sshd` as the first `runcmd` entry (same pattern as web-platform).

### Parameter Rationale

| Directive | Value | Effect |
|-----------|-------|--------|
| `ClientAliveInterval` | `300` | Server sends a keepalive packet every 300 seconds (5 minutes) through the encrypted SSH channel to check if the client is alive |
| `ClientAliveCountMax` | `2` | After 2 missed keepalives, the server terminates the session |

Net effect: idle sessions are dropped after ~10 minutes (5 min interval x 2 missed = 10 min).

### Research Insights: ClientAlive vs TCPKeepAlive

ClientAlive messages are sent through the **encrypted SSH channel** and cannot be spoofed, unlike TCP keepalives (`TCPKeepAlive yes`, which is the OpenSSH default). Both mechanisms are complementary:

- **ClientAlive** (what we are adding): Application-layer, encrypted, non-spoofable. Detects idle sessions even when the network path is healthy but the client is unresponsive.
- **TCPKeepAlive** (already enabled by default): OS-layer, spoofable. Detects dead TCP connections (network failures, crashed hosts). Prevents "ghost" sessions that consume server resources.

Both should remain enabled. There is no conflict between them.

### Research Insights: `ClientAliveCountMax 0` gotcha

Per the [OpenSSH man page](https://man.openbsd.org/sshd_config), setting `ClientAliveCountMax` to `0` **disables connection termination entirely** -- it does not mean "disconnect after first missed keepalive." This is counterintuitive and a common misconfiguration. Our value of `2` is the [most commonly recommended](https://linuxize.com/post/ssh-hardening-best-practices/) setting across hardening guides.

### CI Deploy Compatibility

Both CI deploy workflows use `appleboy/ssh-action` with `username: root` for short-lived, non-interactive SSH sessions:

- **web-platform**: `build-web-platform.yml` -- uses `secrets.WEB_PLATFORM_SSH_KEY`
- **telegram-bridge**: `telegram-bridge-release.yml` -- also uses `secrets.WEB_PLATFORM_SSH_KEY` and `username: root`

These sessions complete in seconds and never hit the 10-minute idle timeout. The `AllowUsers root` directive is confirmed safe for both servers.

## Non-goals

- Changing existing hardening directives (PasswordAuthentication, MaxAuthTries, etc.)
- Adding fail2ban or other intrusion detection
- Changing firewall rules
- Applying keepalive settings to live servers (cloud-init runs on server creation only; applying to existing servers requires a separate deployment step)

## Acceptance Criteria

- [x] `apps/web-platform/infra/cloud-init.yml` `01-hardening.conf` includes `ClientAliveInterval 300` and `ClientAliveCountMax 2`
- [x] `apps/telegram-bridge/infra/cloud-init.yml` migrated from `sed` to `write_files` with `01-hardening.conf` matching web-platform
- [x] `apps/telegram-bridge/infra/cloud-init.yml` `01-hardening.conf` includes `ClientAliveInterval 300` and `ClientAliveCountMax 2`
- [x] Telegram-bridge `runcmd` sed commands removed and replaced with `systemctl restart sshd` as first entry
- [x] Both cloud-init files produce identical SSH hardening configuration

## Test Scenarios

- Given web-platform cloud-init applies on a fresh server, when `sshd -T` is run, then `clientaliveinterval 300` and `clientalivecountmax 2` appear in the effective config
- Given telegram-bridge cloud-init applies on a fresh server, when `sshd -T` is run, then `clientaliveinterval 300` and `clientalivecountmax 2` appear in the effective config
- Given telegram-bridge cloud-init applies, when checking `/etc/ssh/sshd_config.d/`, then `01-hardening.conf` exists and no `sed` modifications were applied to `/etc/ssh/sshd_config`
- Given an SSH session is idle for 11 minutes, when the server evaluates the connection, then the session is terminated (2 missed keepalives at 5-minute intervals)
- Given a CI deploy runs, when `appleboy/ssh-action` executes commands, then the session completes successfully (active session, well within keepalive window)

## SpecFlow Edge Cases

- **First-match-wins ordering**: `ClientAliveInterval` and `ClientAliveCountMax` are not typically set in the Ubuntu 24.04 defaults or Hetzner's `50-cloud-init.conf`, so the `01-` prefix is not strictly necessary for precedence -- but placing them in the same drop-in file maintains a single source of truth for all hardening directives
- **Idempotency**: `write_files` overwrites the entire file on each cloud-init run (confirmed via [Context7 cloud-init docs](https://cloudinit.readthedocs.io/en/latest/reference/examples)). Adding two lines does not change the idempotency behavior
- **cloud-init module ordering**: `write_files` is a config module that runs before `runcmd` (a final module) in cloud-init's boot sequence. The drop-in file is guaranteed to exist on disk before `systemctl restart sshd` executes. No race condition.
- **Telegram-bridge migration scope**: Migrating telegram-bridge from `sed` to `write_files` is a prerequisite for adding keepalive directives cleanly. The alternative (adding more `sed` commands) would compound the fragility documented in the OpenSSH learning. The migration is low-risk because it produces the same effective sshd configuration, just via a more reliable mechanism
- **`AllowUsers root` on telegram-bridge**: **Resolved** -- `telegram-bridge-release.yml` uses `appleboy/ssh-action` with `username: root` and `secrets.WEB_PLATFORM_SSH_KEY`. The server is provisioned with `hcloud_ssh_key.default` (root access only). `AllowUsers root` is correct.
- **`ClientAliveCountMax 0` trap**: If anyone later changes the value to 0 thinking it means "disconnect immediately," it actually disables termination entirely. A code comment in the drop-in content would be inappropriate (sshd_config does not support inline comments after directives), but this gotcha is documented in this plan and the OpenSSH man page.
- **Existing servers**: cloud-init only runs on first boot. The keepalive directives will apply to newly provisioned servers. To apply to existing live servers, a manual `sshd_config.d/01-hardening.conf` update + `systemctl restart sshd` is required -- this is explicitly out of scope (see Non-goals)

## MVP

### `apps/web-platform/infra/cloud-init.yml` (diff)

```yaml
# Add to existing write_files 01-hardening.conf content block:
      ClientAliveInterval 300
      ClientAliveCountMax 2
```

### `apps/telegram-bridge/infra/cloud-init.yml` (full rewrite)

```yaml
#cloud-config
package_update: true
packages:
  - curl
  - jq

write_files:
  - path: /etc/ssh/sshd_config.d/01-hardening.conf
    content: |
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      MaxAuthTries 3
      LoginGraceTime 30
      PermitRootLogin prohibit-password
      AllowUsers root
      ClientAliveInterval 300
      ClientAliveCountMax 2
    owner: root:root
    permissions: '0644'

runcmd:
  # Apply SSH hardening immediately (drop-in written by write_files above)
  - systemctl restart sshd

  # Install Docker
  - curl -fsSL https://get.docker.com | sh

  # Configure Docker log rotation
  - |
    cat > /etc/docker/daemon.json << 'DOCKEREOF'
    {
      "log-driver": "json-file",
      "log-opts": {
        "max-size": "10m",
        "max-file": "3"
      }
    }
    DOCKEREOF
  - systemctl restart docker

  # Mount volume (Hetzner pre-formats with ext4 via Terraform)
  - mkdir -p /mnt/data
  - mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/data || true
  - echo '/dev/disk/by-id/scsi-0HC_Volume_* /mnt/data ext4 defaults 0 2' >> /etc/fstab

  # Create .env placeholder
  - touch /mnt/data/.env

  # Pull and run container
  - docker pull ${image_name}
  - |
    docker run -d \
      --name soleur-bridge \
      --restart unless-stopped \
      --env-file /mnt/data/.env \
      -v /mnt/data:/home/soleur/data \
      -p 127.0.0.1:8080:8080 \
      ${image_name}
```

## References

### Internal

- Issue: #778
- Parent security review: #765
- Prior hardening plan: `knowledge-base/plans/2026-03-19-security-harden-sshd-config-plan.md`
- Learning (first-match-wins): `knowledge-base/learnings/2026-03-19-openssh-first-match-wins-drop-in-precedence.md`
- Learning (CI SSH deploy): `knowledge-base/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Web-platform cloud-init: `apps/web-platform/infra/cloud-init.yml`
- Telegram-bridge cloud-init: `apps/telegram-bridge/infra/cloud-init.yml`
- Telegram-bridge CI deploy: `.github/workflows/telegram-bridge-release.yml` (confirms `username: root`)
- Telegram-bridge Terraform: `apps/telegram-bridge/infra/server.tf`

### External (from deepen-plan research)

- [OpenSSH sshd_config man page](https://man.openbsd.org/sshd_config) -- authoritative reference for ClientAliveInterval, ClientAliveCountMax, and TCPKeepAlive semantics
- [cloud-init write_files documentation](https://cloudinit.readthedocs.io/en/latest/reference/examples) -- Context7 verified syntax and module ordering
- [SSH Hardening Best Practices (Linuxize)](https://linuxize.com/post/ssh-hardening-best-practices/) -- recommends ClientAliveInterval 300, ClientAliveCountMax 2
- [SSH Security Best Practices (DevOps Knowledge Hub)](https://devops.aibit.im/article/ssh-security-best-practices-hardening) -- comprehensive hardening checklist
- [How to Set SSH Idle Timeout (OneUptime, 2026)](https://oneuptime.com/blog/post/2026-03-04-ssh-idle-timeout-maxauthtries-rhel-9/view) -- RHEL-focused but same OpenSSH semantics
- [Datadog STIG: SSH Client Alive Count Max](https://docs.datadoghq.com/security/default_rules/xccdf-org-ssgproject-content-rule-sshd-set-keepalive/) -- compliance rule documentation
- [CIS Benchmark: SSH Idle Timeout Interval](https://www.tenable.com/audits/items/CIS_Red_Hat_EL7_v3.0.1_Server_L1.audit:d69a16dedc2c8b68537bd8c9839e8da4) -- CIS Level 1 benchmark for SSH idle timeout
