# Tasks: security: add ClientAliveInterval/ClientAliveCountMax to SSH hardening

## Phase 1: Web-Platform Update

- [x] 1.1 Add `ClientAliveInterval 300` and `ClientAliveCountMax 2` to `apps/web-platform/infra/cloud-init.yml` `write_files` block for `01-hardening.conf`

## Phase 2: Telegram-Bridge Migration and Update

- [x] 2.1 Add `write_files` section to `apps/telegram-bridge/infra/cloud-init.yml` with `01-hardening.conf` containing all hardening directives (matching web-platform) plus keepalive directives
- [x] 2.2 Remove `sed` commands from telegram-bridge `runcmd` section (lines 43-46)
- [x] 2.3 Add `systemctl restart sshd` as first `runcmd` entry in telegram-bridge cloud-init

## Phase 3: Verification

- [x] 3.1 Verify both cloud-init files produce identical `01-hardening.conf` content
- [x] 3.2 Verify telegram-bridge `runcmd` no longer contains `sed` commands for sshd_config
- [x] 3.3 Verify `systemctl restart sshd` ordering is consistent between both files
