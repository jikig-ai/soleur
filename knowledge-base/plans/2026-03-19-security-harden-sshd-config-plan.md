---
title: "security: harden sshd config for internet-facing SSH"
type: feat
date: 2026-03-19
semver: patch
---

# security: harden sshd config for internet-facing SSH

With SSH port 22 open to the internet (required for CI deploy from GitHub Actions runners with dynamic IPs, per #738), the current cloud-init SSH hardening only disables password authentication. Four standard hardening parameters are missing: `MaxAuthTries`, `LoginGraceTime`, `PermitRootLogin`, and `AllowUsers`.

## Proposed Solution

Extend the SSH hardening block in `apps/web-platform/infra/cloud-init.yml` to append four additional `sshd_config` directives after disabling password authentication, then restart sshd.

### Implementation approach: `sed` vs. `cat >>` vs. `write_files`

Three options exist for setting sshd_config values in cloud-init:

1. **`sed -i` per directive** (current pattern for PasswordAuthentication) -- handles both commented and uncommented existing lines but requires two `sed` calls per directive (one for `#Directive`, one for `Directive`). For four new directives, that is eight additional `sed` commands.

2. **`cat >> /etc/ssh/sshd_config`** -- appends a block of directives at the end of the file. Later directives in sshd_config override earlier ones (sshd uses last-match-wins), so appending is safe even if a directive already exists commented out elsewhere. Single command, clean, idempotent by sshd semantics.

3. **cloud-init `write_files` directive** -- writes a drop-in file to `/etc/ssh/sshd_config.d/`. Cleaner separation but Ubuntu 24.04's default sshd_config must include `Include /etc/ssh/sshd_config.d/*.conf` (it does since Ubuntu 22.04+). This is the most modern approach.

**Recommendation: Option 3 (`write_files` with sshd_config.d drop-in).** It is the cleanest approach for Ubuntu 24.04, avoids sed fragility, and separates hardening config from the distro default. If the existing PasswordAuthentication `sed` commands are migrated into the same drop-in, the SSH hardening section becomes a single declarative block.

### Target file: `apps/web-platform/infra/cloud-init.yml`

Add a `write_files` section (before `runcmd`) that creates `/etc/ssh/sshd_config.d/99-hardening.conf`:

```yaml
# In cloud-init.yml, add write_files section:
write_files:
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    content: |
      PasswordAuthentication no
      MaxAuthTries 3
      LoginGraceTime 30
      PermitRootLogin prohibit-password
      AllowUsers root
    owner: root:root
    permissions: '0644'
```

Then simplify the existing `runcmd` SSH hardening section -- remove the two `sed` commands (now redundant since the drop-in handles `PasswordAuthentication no`) and keep only `systemctl restart sshd`.

### Parameter rationale

| Directive | Value | Why |
|-----------|-------|-----|
| `PasswordAuthentication no` | `no` | Existing hardening, moved to drop-in |
| `MaxAuthTries` | `3` | Limits brute-force key guessing per connection (default is 6) |
| `LoginGraceTime` | `30` | Seconds before unauthenticated connection is dropped (default is 120) |
| `PermitRootLogin` | `prohibit-password` | Allows key-based root login (needed for CI deploy via `appleboy/ssh-action` with `username: root`), blocks password login |
| `AllowUsers` | `root` | Restricts SSH to only the `root` user -- no other accounts can SSH in |

### CI deploy compatibility

The CI deploy workflow (`build-web-platform.yml`) uses `appleboy/ssh-action` with `username: root` and key-based auth (`secrets.WEB_PLATFORM_SSH_KEY`). All four hardening parameters are compatible:

- `PermitRootLogin prohibit-password` -- allows key-based root login (what CI uses)
- `AllowUsers root` -- CI connects as root (allowed)
- `MaxAuthTries 3` -- CI presents one key (well within limit)
- `LoginGraceTime 30` -- CI authenticates in <1 second (well within limit)

## Pre-existing issue: telegram-bridge has identical gap

The `apps/telegram-bridge/infra/cloud-init.yml` has the exact same SSH hardening section (password auth only). The same four parameters should be added there too, but that is out of scope for this issue. A follow-up issue should be filed.

## Non-goals

- Changing firewall rules (SSH is already open to `0.0.0.0/0` per #738)
- Changing the SSH key type or rotation schedule
- Adding fail2ban or other intrusion detection (separate concern)
- Hardening the telegram-bridge server (separate issue)

## Acceptance Criteria

- [ ] `apps/web-platform/infra/cloud-init.yml` includes a `write_files` section creating `/etc/ssh/sshd_config.d/99-hardening.conf`
- [ ] Drop-in file sets: `PasswordAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `PermitRootLogin prohibit-password`, `AllowUsers root`
- [ ] Existing `sed` commands for PasswordAuthentication are removed from `runcmd` (now redundant)
- [ ] `systemctl restart sshd` remains in `runcmd` after Docker setup
- [ ] CI deploy via `appleboy/ssh-action` with `username: root` and key auth is unaffected

## Test Scenarios

- Given the cloud-init applies on a fresh Ubuntu 24.04 server, when sshd starts, then `/etc/ssh/sshd_config.d/99-hardening.conf` exists with all five directives
- Given a CI deploy runs after cloud-init, when `appleboy/ssh-action` connects as root with key auth, then SSH authentication succeeds (MaxAuthTries, LoginGraceTime, AllowUsers all permit this)
- Given an attacker tries password-based root login, when sshd evaluates the connection, then it is rejected (PasswordAuthentication no + PermitRootLogin prohibit-password)
- Given an attacker tries to SSH as a non-root user, when sshd evaluates the connection, then it is rejected (AllowUsers root)

## SpecFlow Edge Cases

- **cloud-init ordering**: `write_files` runs before `runcmd` in cloud-init's module ordering. The drop-in file will exist before `systemctl restart sshd` executes. No ordering risk.
- **sshd_config.d Include directive**: Ubuntu 24.04 ships with `Include /etc/ssh/sshd_config.d/*.conf` at the top of `/etc/ssh/sshd_config`. The drop-in is picked up automatically. The `99-` prefix ensures it loads last, so its directives take precedence over any earlier config.
- **Idempotency**: If cloud-init runs again (server rebuild), `write_files` overwrites the file with identical content. No accumulation or duplication.

## MVP

### `apps/web-platform/infra/cloud-init.yml`

```yaml
#cloud-config
package_update: true
packages:
  - curl
  - jq

write_files:
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    content: |
      PasswordAuthentication no
      MaxAuthTries 3
      LoginGraceTime 30
      PermitRootLogin prohibit-password
      AllowUsers root
    owner: root:root
    permissions: '0644'

runcmd:
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

  # Mount volume for workspaces (Hetzner pre-formats with ext4 via Terraform)
  - mkdir -p /mnt/data
  - mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/data || true
  - echo '/dev/disk/by-id/scsi-0HC_Volume_* /mnt/data ext4 defaults 0 2' >> /etc/fstab

  # Create workspace and plugin directories
  - mkdir -p /mnt/data/workspaces
  - mkdir -p /mnt/data/plugins/soleur

  # Create .env placeholder
  - touch /mnt/data/.env

  # Pull and run container
  - docker pull ${image_name}
  - |
    docker run -d \
      --name soleur-web-platform \
      --restart unless-stopped \
      --env-file /mnt/data/.env \
      -v /mnt/data/workspaces:/workspaces \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 0.0.0.0:80:3000 \
      -p 0.0.0.0:3000:3000 \
      ${image_name}

  # Restart sshd to apply hardening from write_files
  - systemctl restart sshd
```

## References

- Issue: #765
- SSH opened to internet: #738
- CI deploy workflow: `.github/workflows/build-web-platform.yml`
- Firewall config: `apps/web-platform/infra/firewall.tf`
- Learning: [CI SSH deploy requires firewall rule](../learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md)
- Telegram-bridge cloud-init (same gap): `apps/telegram-bridge/infra/cloud-init.yml`
