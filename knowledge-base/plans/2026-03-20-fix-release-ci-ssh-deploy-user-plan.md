---
title: "fix: repair release CI deploy after SSH user migration"
type: fix
date: 2026-03-20
---

# fix: repair release CI deploy after SSH user migration

## Overview

Both Telegram Bridge and Web Platform release CI deploy jobs are failing with SSH authentication/fingerprint errors after PR #834 migrated workflows from `username: root` to `username: deploy`. The server-side preparation (Phase 1 of #834's tasks) was not completed before the workflow changes were merged, leaving CI unable to authenticate as the `deploy` user.

## Problem Statement

PR #834 (`fix(security): replace root SSH with deploy user in CI workflows`) changed both release workflows to SSH as `deploy` instead of `root`. However, the prerequisite Phase 1 manual steps -- creating the `deploy` user on the production server, installing SSH authorized_keys, and setting up the forced command -- were never completed.

**Two distinct failure modes observed:**

1. **Run 23335135290 / 23335135287** (08:35 UTC): `ssh: unable to authenticate, attempted methods [none publickey]` -- the `deploy` user either does not exist on the server or has no authorized_keys entry matching `WEB_PLATFORM_SSH_KEY`
2. **Run 23335268807** (08:39 UTC): `ssh: host key fingerprint mismatch` -- the `WEB_PLATFORM_HOST_FINGERPRINT` secret was updated at 08:38 UTC but with an incorrect value

**Root cause:** The deploy user migration was a two-phase operation (server prep + workflow change). The workflow changes were merged without completing server preparation. The `ci-deploy.sh` forced command script is embedded in cloud-init for new server provisioning but was previously installed on the running server only for the `root` user (PR #825 / issue #747). The `deploy` user needs equivalent setup.

## Proposed Solution

A hybrid fix with two tracks:

### Track 1: Server-side preparation (manual SSH commands)

Execute the Phase 1 steps from `knowledge-base/specs/feat-deploy-ssh-user/tasks.md` that were skipped:

1. SSH into the web platform server as `root` (admin key)
2. Create the `deploy` user with docker group membership
3. Install SSH authorized_keys for `deploy` with the CI public key + forced command restriction
4. Configure sudoers for the `chown` command
5. Transfer `/mnt/data` ownership to `deploy`
6. Update `AllowUsers` in sshd config
7. Verify: SSH as `deploy`, run `docker ps`, check data access

### Track 2: Fix the fingerprint secret

Retrieve the correct server host key fingerprint and update `WEB_PLATFORM_HOST_FINGERPRINT`:

```bash
# From a machine that can SSH to the server:
ssh-keyscan -H <WEB_PLATFORM_HOST> 2>/dev/null | ssh-keygen -lf - | grep SHA256
```

Then update via `gh secret set WEB_PLATFORM_HOST_FINGERPRINT`.

### Track 3: Workflow validation

After server-side setup, trigger manual runs to verify both workflows:

1. `gh workflow run telegram-bridge-release.yml -f bump_type=patch`
2. `gh workflow run web-platform-release.yml -f bump_type=patch`
3. Poll until complete and verify deploy success with health checks

## Technical Considerations

### Forced command compatibility

The `ci-deploy.sh` script was originally installed for the `root` user's authorized_keys (PR #825). The `deploy` user needs the same forced command restriction in its authorized_keys. The cloud-init template already writes `ci-deploy.sh` to `/usr/local/bin/ci-deploy.sh` (line 42-172 of `apps/web-platform/infra/cloud-init.yml`), but this only applies to **new** server provisioning, not the existing running server.

For the existing server, the script must be manually installed and the `deploy` user's `authorized_keys` must include the `restrict,command="/usr/local/bin/ci-deploy.sh"` prefix.

### Telegram Bridge shares the web platform server

Despite having separate Terraform infra definitions (`apps/telegram-bridge/infra/` with `hcloud_server.bridge` in `fsn1`), both release workflows deploy to `WEB_PLATFORM_HOST`. The `ci-deploy.sh` forced command script handles both `web-platform` and `telegram-bridge` components. The `TELEGRAM_BRIDGE_HOST` secret exists but is not used by the release workflow.

This is by design -- both apps are co-located on the web platform server. The separate Telegram Bridge Terraform is for future separation.

### SSH key reuse

The same `WEB_PLATFORM_SSH_KEY` private key is used for both workflows. The corresponding public key must be added to the `deploy` user's `~/.ssh/authorized_keys`. The public key can be derived from the private key: `ssh-keygen -y -f <private_key_file>`.

### Rollback option

If server-side setup cannot be completed immediately, the workflows can be temporarily reverted to `username: root` to restore deploys while the deploy user is set up properly. This is a revert of the username change only (not the full PR #834).

## Acceptance Criteria

- [ ] `deploy` user exists on the web platform server with docker group membership
- [ ] `deploy` user's `~/.ssh/authorized_keys` contains the CI public key with `restrict,command="/usr/local/bin/ci-deploy.sh"` prefix
- [ ] `/usr/local/bin/ci-deploy.sh` is installed on the server with mode 0755
- [ ] `/etc/sudoers.d/deploy-chown` exists with correct permissions (0440, root:root)
- [ ] `/mnt/data` is owned by `deploy:deploy`
- [ ] `/mnt/data/workspaces` is owned by `1001:1001`
- [ ] `AllowUsers root deploy` is active in sshd config
- [ ] `WEB_PLATFORM_HOST_FINGERPRINT` secret contains the correct server host key fingerprint
- [ ] Web Platform Release workflow deploys successfully (health check passes)
- [ ] Telegram Bridge Release workflow deploys successfully (health check passes)
- [ ] Root SSH still works via admin key for maintenance

## Test Scenarios

- Given the deploy user is created and configured, when web-platform-release.yml runs with `bump_type=patch`, then the deploy step succeeds and health check returns 200
- Given the deploy user is configured, when telegram-bridge-release.yml runs with `bump_type=patch`, then the deploy step succeeds and health endpoint responds
- Given the deploy user has the forced command, when CI tries `deploy web-platform <image> <tag>`, then the command is accepted and executed
- Given the deploy user has the forced command, when CI tries any non-deploy command, then the command is rejected with exit 1
- Given an incorrect fingerprint secret, when the deploy step runs, then it fails with "fingerprint mismatch" (not silently proceeding)

## Dependencies and Risks

### Dependencies

- SSH access to the production server as root (admin key)
- The `WEB_PLATFORM_SSH_KEY` private key to derive the public key for authorized_keys
- Server host key fingerprint (retrievable via `ssh-keyscan`)

### Risks

- **Deploy user may break existing docker containers** -- The `deploy` user needs docker group membership to run `docker pull/stop/rm/run`. If docker group doesn't exist yet (unlikely on a server already running docker), `usermod -aG docker deploy` will fail.
- **Forced command interaction with sudo** -- The `ci-deploy.sh` script uses `sudo chown` for the web-platform component. The sudoers rule must exactly match: `deploy ALL=(root) NOPASSWD: /usr/bin/chown 1001\:1001 /mnt/data/workspaces`
- **Race condition during setup** -- If a release CI job triggers while the deploy user is being set up, it will fail. The server setup should be done during a quiet period or after temporarily pausing auto-merge.

## References

- PR #834: `fix(security): replace root SSH with deploy user in CI workflows` (merged, caused the failures)
- PR #825: `security: restrict CI deploy SSH key with command= forced command` (original forced command setup)
- Issue #832: Original tracking issue for deploy user migration
- Tasks: `knowledge-base/specs/feat-deploy-ssh-user/tasks.md` (Phase 1 manual steps not completed)
- Learning: `knowledge-base/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Learning: `knowledge-base/learnings/2026-03-20-ssh-forced-command-workflow-refactoring-drops-parameters.md`
- Workflow: `.github/workflows/telegram-bridge-release.yml`
- Workflow: `.github/workflows/web-platform-release.yml`
- Cloud-init: `apps/web-platform/infra/cloud-init.yml` (lines 12-18 for deploy user, 42-172 for ci-deploy.sh)

## MVP

### Server-side commands (run as root via SSH)

```bash
# 1. Create deploy user with docker group
useradd -m -s /bin/bash -G docker deploy

# 2. Set up SSH directory
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

# 3. Derive public key from CI private key and install with forced command
# (public key content must come from: ssh-keygen -y -f <WEB_PLATFORM_SSH_KEY>)
echo 'restrict,command="/usr/local/bin/ci-deploy.sh" <CI_PUBLIC_KEY>' > /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

# 4. Install ci-deploy.sh (if not already present from cloud-init)
# Copy content from apps/web-platform/infra/cloud-init.yml lines 42-172
chmod 755 /usr/local/bin/ci-deploy.sh

# 5. Sudoers rule
echo 'deploy ALL=(root) NOPASSWD: /usr/bin/chown 1001\:1001 /mnt/data/workspaces' > /etc/sudoers.d/deploy-chown
chmod 0440 /etc/sudoers.d/deploy-chown
chown root:root /etc/sudoers.d/deploy-chown
visudo -c -f /etc/sudoers.d/deploy-chown

# 6. Transfer data ownership
chown -R deploy:deploy /mnt/data
chown 1001:1001 /mnt/data/workspaces

# 7. Update sshd AllowUsers (if not already including deploy)
grep -q 'AllowUsers.*deploy' /etc/ssh/sshd_config.d/01-hardening.conf || \
  sed -i 's/AllowUsers root/AllowUsers root deploy/' /etc/ssh/sshd_config.d/01-hardening.conf
systemctl restart sshd
```

### Fingerprint fix (run locally or from CI machine)

```bash
# Get correct fingerprint
FINGERPRINT=$(ssh-keyscan -t ed25519 <WEB_PLATFORM_HOST> 2>/dev/null | ssh-keygen -lf - | awk '{print $2}')
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "$FINGERPRINT"
```

### Verification (run after server setup)

```bash
# Trigger both release workflows
gh workflow run web-platform-release.yml -f bump_type=patch
gh workflow run telegram-bridge-release.yml -f bump_type=patch

# Poll for completion
gh run list --workflow=web-platform-release.yml --limit 1 --json status,conclusion
gh run list --workflow=telegram-bridge-release.yml --limit 1 --json status,conclusion
```
