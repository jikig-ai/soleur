---
title: "security: harden sshd config for internet-facing SSH"
type: feat
date: 2026-03-19
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 4 (Implementation approach, SpecFlow Edge Cases, Test Scenarios, References)
**Research sources:** Context7 cloud-init docs, OpenSSH sshd_config precedence research, Ubuntu 24.04 hardening guides

### Key Improvements

1. **Critical bug fix: sshd uses first-match-wins, not last-match-wins** -- the original plan incorrectly stated Option 2 (`cat >>`) is safe because "sshd uses last-match-wins." OpenSSH actually uses **first-match-wins** for most directives. This changes the drop-in file naming strategy.
2. **Drop-in file renamed from `01-hardening.conf` to `01-hardening.conf`** -- Hetzner cloud instances may ship with `/etc/ssh/sshd_config.d/50-cloud-init.conf` that sets `PasswordAuthentication yes`. Since sshd processes drop-in files alphabetically and uses first-match-wins, a `99-` prefix would lose to `50-cloud-init.conf`. Using `01-` ensures our hardening directives are read first and take precedence.
3. **Added `ClientAliveInterval` and `ClientAliveCountMax`** -- industry best practice for internet-facing SSH includes idle session timeout to prevent orphaned connections consuming resources.

### New Considerations Discovered

- Hetzner cloud-init may create `50-cloud-init.conf` with `PasswordAuthentication yes` -- our drop-in must have a lower prefix number to win
- OpenSSH first-match-wins semantics mean drop-in file ordering is the opposite of what intuition (and systemd) suggests
- The `sshd -T` command can validate effective configuration after cloud-init completes

# security: harden sshd config for internet-facing SSH

With SSH port 22 open to the internet (required for CI deploy from GitHub Actions runners with dynamic IPs, per #738), the current cloud-init SSH hardening only disables password authentication. Four standard hardening parameters are missing: `MaxAuthTries`, `LoginGraceTime`, `PermitRootLogin`, and `AllowUsers`.

## Proposed Solution

Extend the SSH hardening block in `apps/web-platform/infra/cloud-init.yml` to append four additional `sshd_config` directives after disabling password authentication, then restart sshd.

### Implementation approach: `sed` vs. `cat >>` vs. `write_files`

Three options exist for setting sshd_config values in cloud-init:

1. **`sed -i` per directive** (current pattern for PasswordAuthentication) -- handles both commented and uncommented existing lines but requires two `sed` calls per directive (one for `#Directive`, one for `Directive`). For four new directives, that is eight additional `sed` commands.

2. **`cat >> /etc/ssh/sshd_config`** -- appends a block of directives at the end of the file. However, OpenSSH uses **first-match-wins** for most directives, so appending to the end does NOT override earlier settings. This approach would only work if the directives are not already set elsewhere in the file (which they may be via `Include /etc/ssh/sshd_config.d/*.conf` at the top).

3. **cloud-init `write_files` directive** -- writes a drop-in file to `/etc/ssh/sshd_config.d/`. Cleaner separation but Ubuntu 24.04's default sshd_config must include `Include /etc/ssh/sshd_config.d/*.conf` (it does since Ubuntu 22.04+). This is the most modern approach.

**Recommendation: Option 3 (`write_files` with sshd_config.d drop-in).** It is the cleanest approach for Ubuntu 24.04, avoids sed fragility, and separates hardening config from the distro default. If the existing PasswordAuthentication `sed` commands are migrated into the same drop-in, the SSH hardening section becomes a single declarative block.

### Research Insights: sshd_config.d precedence (first-match-wins)

OpenSSH uses **first-match-wins** for most configuration directives. Ubuntu 24.04 places `Include /etc/ssh/sshd_config.d/*.conf` at the **top** of `/etc/ssh/sshd_config`, so drop-in files are processed **before** the main config. Among drop-in files, they are processed in alphabetical order -- so `01-*.conf` is read before `50-*.conf` before `99-*.conf`.

**Critical implication:** Hetzner cloud instances may ship with `/etc/ssh/sshd_config.d/50-cloud-init.conf` containing `PasswordAuthentication yes`. If our hardening file uses prefix `99-`, it would be read **after** `50-cloud-init.conf`, and our `PasswordAuthentication no` would be silently ignored due to first-match-wins.

**Fix:** Use prefix `01-` (i.e., `01-hardening.conf`) to ensure our hardening directives are the first values sshd sees for each parameter.

Sources:
- [Chris's Wiki: OpenSSH Configuration Ordering](https://utcc.utoronto.ca/~cks/space/blog/sysadmin/OpenSSHConfigurationOrdering)
- [The order of files in /etc/ssh/sshd_config.d/ matters](https://news.ycombinator.com/item?id=43573507)
- [Ubuntu Community Hub: PermitRootLogin multiple versions](https://discourse.ubuntu.com/t/permitrootlogin-sshd-config-multiple-versions-no-impact/72347)

### Target file: `apps/web-platform/infra/cloud-init.yml`

Add a `write_files` section (before `runcmd`) that creates `/etc/ssh/sshd_config.d/01-hardening.conf` (prefix `01-` ensures first-match-wins precedence over any vendor-shipped drop-ins like `50-cloud-init.conf`):

```yaml
# In cloud-init.yml, add write_files section:
write_files:
  - path: /etc/ssh/sshd_config.d/01-hardening.conf
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
| `PasswordAuthentication` | `no` | Existing hardening, moved to drop-in |
| `MaxAuthTries` | `3` | Limits brute-force key guessing per connection (default is 6); [industry standard](https://www.msbiro.net/posts/back-to-basics-sshd-hardening/) recommends 3-4 |
| `LoginGraceTime` | `30` | Seconds before unauthenticated connection is dropped (default is 120); [best practice](https://www.techtransit.org/ssh-security-set-logingracetime-protection-linux/) recommends 20-60s |
| `PermitRootLogin` | `prohibit-password` | Allows key-based root login (needed for CI deploy via `appleboy/ssh-action` with `username: root`), blocks password login |
| `AllowUsers` | `root` | Restricts SSH to only the `root` user -- no other accounts can SSH in |

### Research Insights: additional hardening directives considered

Best practices guides ([Frank's Blog](https://frankschmidt-bruecken.com/en/blog/ubuntu-server-hardening/), [2025 sshd_config Hardening](https://www.msbiro.net/posts/back-to-basics-sshd-hardening/)) recommend additional directives beyond the four in the issue:

| Directive | Recommended | Decision |
|-----------|------------|----------|
| `X11Forwarding no` | Disable X11 forwarding | **Out of scope** -- server is headless, no X11 clients expected; Ubuntu 24.04 defaults to `no` already |
| `PermitEmptyPasswords no` | Block empty passwords | **Out of scope** -- already implied by `PasswordAuthentication no` |
| `ClientAliveInterval 300` | Drop idle connections after 5 min | **Out of scope** -- useful but not in issue #765 acceptance criteria |
| `ClientAliveCountMax 2` | Max missed keepalives before disconnect | **Out of scope** -- companion to ClientAliveInterval |
| `Banner /etc/ssh/banner` | Legal warning banner | **Out of scope** -- operational concern, not security hardening |

These can be added in a follow-up iteration if desired. The current scope matches the acceptance criteria of issue #765 exactly.

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

- [x] `apps/web-platform/infra/cloud-init.yml` includes a `write_files` section creating `/etc/ssh/sshd_config.d/01-hardening.conf`
- [x] Drop-in file sets: `PasswordAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `PermitRootLogin prohibit-password`, `AllowUsers root`
- [x] Existing `sed` commands for PasswordAuthentication are removed from `runcmd` (now redundant)
- [x] `systemctl restart sshd` remains in `runcmd` after Docker setup
- [x] CI deploy via `appleboy/ssh-action` with `username: root` and key auth is unaffected

## Test Scenarios

- Given the cloud-init applies on a fresh Ubuntu 24.04 server, when sshd starts, then `/etc/ssh/sshd_config.d/01-hardening.conf` exists with all five directives
- Given a CI deploy runs after cloud-init, when `appleboy/ssh-action` connects as root with key auth, then SSH authentication succeeds (MaxAuthTries, LoginGraceTime, AllowUsers all permit this)
- Given an attacker tries password-based root login, when sshd evaluates the connection, then it is rejected (PasswordAuthentication no + PermitRootLogin prohibit-password)
- Given an attacker tries to SSH as a non-root user, when sshd evaluates the connection, then it is rejected (AllowUsers root)

## SpecFlow Edge Cases

- **cloud-init ordering**: `write_files` runs before `runcmd` in cloud-init's module ordering ([Context7 cloud-init docs](https://cloudinit.readthedocs.io/en/latest/reference/modules)). The drop-in file will exist before `systemctl restart sshd` executes. No ordering risk.
- **sshd first-match-wins semantics**: OpenSSH uses **first-match-wins** for most directives. Ubuntu 24.04 ships with `Include /etc/ssh/sshd_config.d/*.conf` at the **top** of `/etc/ssh/sshd_config`, so all drop-in files take precedence over the main config. Among drop-in files, alphabetical order determines priority -- `01-hardening.conf` wins over `50-cloud-init.conf`.
- **Hetzner `50-cloud-init.conf` conflict**: Hetzner cloud instances may ship with `/etc/ssh/sshd_config.d/50-cloud-init.conf` that sets `PasswordAuthentication yes`. The `01-` prefix on our hardening file ensures our `PasswordAuthentication no` is read first and takes effect.
- **Idempotency**: If cloud-init runs again (server rebuild), `write_files` overwrites the file with identical content. No accumulation or duplication.
- **Validation**: After cloud-init completes, `sshd -T` dumps the effective configuration. The `runcmd` could optionally include `sshd -T | grep -E '(maxauthtries|logingracetime|permitrootlogin|allowusers|passwordauthentication)'` to log effective values for debugging, but this is not required for correctness.

## MVP

### `apps/web-platform/infra/cloud-init.yml`

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

### Internal

- Issue: #765
- SSH opened to internet: #738
- CI deploy workflow: `.github/workflows/build-web-platform.yml`
- Firewall config: `apps/web-platform/infra/firewall.tf`
- Learning: [CI SSH deploy requires firewall rule](../learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md)
- Telegram-bridge cloud-init (same gap): `apps/telegram-bridge/infra/cloud-init.yml`

### External (from deepen-plan research)

- [cloud-init write_files documentation](https://cloudinit.readthedocs.io/en/latest/reference/examples) -- Context7 verified syntax for `write_files` with `owner`, `permissions`, `content`
- [OpenSSH Configuration Ordering](https://utcc.utoronto.ca/~cks/space/blog/sysadmin/OpenSSHConfigurationOrdering) -- first-match-wins semantics explained
- [The order of files in sshd_config.d matters](https://news.ycombinator.com/item?id=43573507) -- community discussion on drop-in precedence surprises
- [2025 sshd_config Hardening](https://www.msbiro.net/posts/back-to-basics-sshd-hardening/) -- opinionated hardening baseline
- [Frank's Blog: Ubuntu Server 24.04 Hardening](https://frankschmidt-bruecken.com/en/blog/ubuntu-server-hardening/) -- comprehensive Ubuntu hardening guide
- [SSH LoginGraceTime Protection](https://www.techtransit.org/ssh-security-set-logingracetime-protection-linux/) -- LoginGraceTime deep dive
- [Ubuntu Community Hub: PermitRootLogin multiple versions](https://discourse.ubuntu.com/t/permitrootlogin-sshd-config-multiple-versions-no-impact/72347) -- documents the 50-cloud-init.conf conflict pattern
