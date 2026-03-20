# Learning: OpenSSH first-match-wins and sshd_config.d drop-in precedence

## Problem

Hardening SSH on an internet-facing Hetzner server (Ubuntu 24.04) required disabling password authentication and enforcing key-only access. The initial approach used `sed` commands in cloud-init `runcmd` to patch `/etc/ssh/sshd_config` in place. This is fragile: `sed` patterns silently no-op when the target line is commented out, absent, or formatted differently than expected. Worse, Hetzner ships a cloud-init drop-in at `/etc/ssh/sshd_config.d/50-cloud-init.conf` that may contain `PasswordAuthentication yes` — even a correct `sed` on the main config file would be overridden by the drop-in.

## Solution

Replace `sed` commands with a declarative cloud-init `write_files` drop-in at `/etc/ssh/sshd_config.d/01-hardening.conf` containing all hardening directives:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
X11Forwarding no
```

The `01-` prefix is critical — it ensures the hardening file is read before Hetzner's `50-cloud-init.conf`. Combined with `systemctl restart sshd` as the first `runcmd` entry, the unhardened window is minimized.

`KbdInteractiveAuthentication no` was added during review to close a PAM bypass vector: without it, PAM-based keyboard-interactive auth could still accept passwords even when `PasswordAuthentication no` is set.

## Key Insight

OpenSSH uses **first-match-wins** for most directives — the opposite of systemd's last-wins convention. When Ubuntu 24.04's `sshd_config` includes `/etc/ssh/sshd_config.d/*.conf` at the top of the file (before the main directives), drop-ins are processed first. A `99-hardening.conf` file would lose to `50-cloud-init.conf` because the `50-` file is read first and its value sticks. The correct prefix is `01-` to guarantee the hardening directives are the first match.

This first-match-wins behavior also means the main `sshd_config` defaults are effectively fallbacks — they only apply for directives not already set by any drop-in. This is safe and intentional, but violates the mental model developers bring from systemd, nginx, or CSS where later declarations override earlier ones.

General rule for SSH hardening via cloud-init: use `write_files` (which runs before `runcmd`) to place a low-numbered drop-in, not `sed` to patch the main config. This is idempotent, auditable, and immune to vendor-specific config file formatting.

## Tags

category: integration-issues
module: infrastructure
