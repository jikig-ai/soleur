# Tasks: fix release CI SSH deploy user

## Phase 1: Server Preparation (Manual -- SSH as root)

- [ ] 1.1 SSH into production server as root using admin key
- [ ] 1.2 Create `deploy` user: `useradd -m -s /bin/bash -G docker deploy`
- [ ] 1.3 Derive CI public key: `ssh-keygen -y -f <WEB_PLATFORM_SSH_KEY_file>` (or retrieve from existing root authorized_keys)
- [ ] 1.4 Create deploy SSH directory: `mkdir -p /home/deploy/.ssh && chmod 700 /home/deploy/.ssh`
- [ ] 1.5 Install authorized_keys with forced command: `echo 'restrict,command="/usr/local/bin/ci-deploy.sh" <CI_PUBLIC_KEY>' > /home/deploy/.ssh/authorized_keys`
- [ ] 1.6 Set permissions: `chmod 600 /home/deploy/.ssh/authorized_keys && chown -R deploy:deploy /home/deploy/.ssh`
- [ ] 1.7 Verify `/usr/local/bin/ci-deploy.sh` exists (should be there from PR #825); if not, install from `apps/web-platform/infra/cloud-init.yml` lines 42-172
- [ ] 1.8 Create sudoers rule: `/etc/sudoers.d/deploy-chown` with `deploy ALL=(root) NOPASSWD: /usr/bin/chown 1001\:1001 /mnt/data/workspaces`
- [ ] 1.9 Set sudoers permissions: `chmod 0440 /etc/sudoers.d/deploy-chown && chown root:root /etc/sudoers.d/deploy-chown`
- [ ] 1.10 Validate sudoers syntax: `visudo -c -f /etc/sudoers.d/deploy-chown`
- [ ] 1.11 Transfer data ownership: `chown -R deploy:deploy /mnt/data && chown 1001:1001 /mnt/data/workspaces`
- [ ] 1.12 Update SSH config if needed: ensure `AllowUsers root deploy` in `/etc/ssh/sshd_config.d/01-hardening.conf`, then `systemctl restart sshd`
- [ ] 1.13 Verify deploy user access: SSH as deploy, run `docker ps`, `ls /mnt/data/.env`, `sudo chown 1001:1001 /mnt/data/workspaces`

## Phase 2: Fix Fingerprint Secret

- [ ] 2.1 Retrieve correct server host key fingerprint: `ssh-keyscan -t ed25519 <host> 2>/dev/null | ssh-keygen -lf -`
- [ ] 2.2 Update GitHub secret: `gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "<fingerprint>"`

## Phase 3: Verify CI Deploys

- [ ] 3.1 Trigger web-platform-release: `gh workflow run web-platform-release.yml -f bump_type=patch`
- [ ] 3.2 Poll and verify web-platform deploy succeeds with health check
- [ ] 3.3 Trigger telegram-bridge-release: `gh workflow run telegram-bridge-release.yml -f bump_type=patch`
- [ ] 3.4 Poll and verify telegram-bridge deploy succeeds with health check
- [ ] 3.5 Verify root SSH still works via admin key for maintenance
