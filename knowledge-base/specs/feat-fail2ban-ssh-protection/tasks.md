# Tasks: security: add fail2ban for SSH brute-force protection

## Phase 1: Implementation

- [ ] 1.1 Add `fail2ban` to `packages:` list in `apps/web-platform/infra/cloud-init.yml`
- [ ] 1.2 Run compound (`soleur:compound`)
- [ ] 1.3 Commit, push, and create PR (via `/ship`)

## Phase 2: Verification (post-deploy)

- [ ] 2.1 After server rebuild, verify fail2ban is running: `systemctl status fail2ban`
- [ ] 2.2 Verify sshd jail is active: `fail2ban-client status sshd`
- [ ] 2.3 Verify CI deploy still succeeds after fail2ban is active
