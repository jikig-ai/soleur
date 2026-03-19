---
title: "security: add ClientAliveInterval/ClientAliveCountMax to SSH hardening"
type: feat
date: 2026-03-19
semver: patch
---

# security: add ClientAliveInterval/ClientAliveCountMax to SSH hardening

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
| `ClientAliveInterval` | `300` | Server sends a keepalive packet every 300 seconds (5 minutes) to check if the client is alive |
| `ClientAliveCountMax` | `2` | After 2 missed keepalives, the server terminates the session |

Net effect: idle sessions are dropped after ~10 minutes (5 min interval x 2 missed = 10 min).

### CI Deploy Compatibility

The CI deploy workflow (`build-web-platform.yml`) uses `appleboy/ssh-action` for short-lived, non-interactive SSH sessions. These complete in seconds and never hit the 10-minute idle timeout. No CI impact.

## Non-goals

- Changing existing hardening directives (PasswordAuthentication, MaxAuthTries, etc.)
- Adding fail2ban or other intrusion detection
- Changing firewall rules
- Applying keepalive settings to live servers (cloud-init runs on server creation only; applying to existing servers requires a separate deployment step)

## Acceptance Criteria

- [ ] `apps/web-platform/infra/cloud-init.yml` `01-hardening.conf` includes `ClientAliveInterval 300` and `ClientAliveCountMax 2`
- [ ] `apps/telegram-bridge/infra/cloud-init.yml` migrated from `sed` to `write_files` with `01-hardening.conf` matching web-platform
- [ ] `apps/telegram-bridge/infra/cloud-init.yml` `01-hardening.conf` includes `ClientAliveInterval 300` and `ClientAliveCountMax 2`
- [ ] Telegram-bridge `runcmd` sed commands removed and replaced with `systemctl restart sshd` as first entry
- [ ] Both cloud-init files produce identical SSH hardening configuration

## Test Scenarios

- Given web-platform cloud-init applies on a fresh server, when `sshd -T` is run, then `clientaliveinterval 300` and `clientalivecountmax 2` appear in the effective config
- Given telegram-bridge cloud-init applies on a fresh server, when `sshd -T` is run, then `clientaliveinterval 300` and `clientalivecountmax 2` appear in the effective config
- Given telegram-bridge cloud-init applies, when checking `/etc/ssh/sshd_config.d/`, then `01-hardening.conf` exists and no `sed` modifications were applied to `/etc/ssh/sshd_config`
- Given an SSH session is idle for 11 minutes, when the server evaluates the connection, then the session is terminated (2 missed keepalives at 5-minute intervals)
- Given a CI deploy runs, when `appleboy/ssh-action` executes commands, then the session completes successfully (active session, well within keepalive window)

## SpecFlow Edge Cases

- **First-match-wins ordering**: `ClientAliveInterval` and `ClientAliveCountMax` are not typically set in the Ubuntu 24.04 defaults or Hetzner's `50-cloud-init.conf`, so the `01-` prefix is not strictly necessary for precedence -- but placing them in the same drop-in file maintains a single source of truth for all hardening directives
- **Idempotency**: `write_files` overwrites the entire file on each cloud-init run. Adding two lines does not change the idempotency behavior
- **Telegram-bridge migration scope**: Migrating telegram-bridge from `sed` to `write_files` is a prerequisite for adding keepalive directives cleanly. The alternative (adding more `sed` commands) would compound the fragility documented in the OpenSSH learning. The migration is low-risk because it produces the same effective sshd configuration, just via a more reliable mechanism
- **`AllowUsers root` on telegram-bridge**: The telegram-bridge server may use a different user configuration. Verify whether the existing server uses root-only access before applying the web-platform's `AllowUsers root` directive. If telegram-bridge needs additional users, adjust accordingly

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
