# Tasks: harden sshd config for internet-facing SSH

## Phase 1: Core Implementation

### 1.1 Add `write_files` section to cloud-init.yml

- [ ] 1.1.1 Add `write_files` block before `runcmd` in `apps/web-platform/infra/cloud-init.yml`
- [ ] 1.1.2 Create `/etc/ssh/sshd_config.d/99-hardening.conf` drop-in with all five directives: `PasswordAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `PermitRootLogin prohibit-password`, `AllowUsers root`
- [ ] 1.1.3 Set owner `root:root` and permissions `0644`

### 1.2 Remove redundant sed commands

- [ ] 1.2.1 Remove the two `sed -i` commands for `PasswordAuthentication` from the `runcmd` SSH hardening section
- [ ] 1.2.2 Update the SSH hardening comment to reference the `write_files` drop-in
- [ ] 1.2.3 Keep `systemctl restart sshd` in `runcmd`

## Phase 2: Verification

### 2.1 Validate cloud-init YAML

- [ ] 2.1.1 Verify YAML is syntactically valid (no indentation errors)
- [ ] 2.1.2 Verify `write_files` section is at the top level (sibling of `runcmd`, not nested inside it)
- [ ] 2.1.3 Verify `${image_name}` Terraform template variable is preserved

### 2.2 Validate CI compatibility

- [ ] 2.2.1 Confirm `PermitRootLogin prohibit-password` allows key-based root login (CI uses `username: root`)
- [ ] 2.2.2 Confirm `AllowUsers root` permits the CI deploy user

## Phase 3: Follow-up

### 3.1 File follow-up issue for telegram-bridge

- [ ] 3.1.1 Create GitHub issue to apply same hardening to `apps/telegram-bridge/infra/cloud-init.yml`
