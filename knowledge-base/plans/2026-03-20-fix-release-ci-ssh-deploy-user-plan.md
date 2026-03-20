---
title: "fix: repair release CI deploy after SSH user migration"
type: fix
date: 2026-03-20
---

# fix: repair release CI deploy after SSH user migration

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6
**Research sources:** appleboy/ssh-action issue tracker, SSH security best practices (2025-2026), project learnings (5 relevant), code review of cloud-init templates and workflow files

### Key Improvements
1. Fingerprint key-type mismatch identified as likely cause of second failure -- must match the negotiated algorithm (ed25519 vs ecdsa), not just any server key
2. Added idempotency guards to all server-side commands (safe to re-run if partially completed)
3. Added pre-flight verification step to confirm root SSH works before starting setup
4. Added explicit ordering constraint: verify `ci-deploy.sh` exists before configuring authorized_keys (the forced command will reject all connections if the script is missing)

### New Considerations Discovered
- appleboy/ssh-action (drone-ssh) may negotiate a different key algorithm than the one used to generate the fingerprint secret -- ed25519 fingerprint fails if the client negotiates ecdsa ([issue #275](https://github.com/appleboy/ssh-action/issues/275))
- The `restrict` keyword in authorized_keys disables port forwarding, X11 forwarding, and agent forwarding by default -- no need for separate `no-port-forwarding` etc. options
- Running containers will continue to run after `chown -R deploy:deploy /mnt/data` because Docker holds file descriptors, but any container restart will use the new ownership

## Overview

Both Telegram Bridge and Web Platform release CI deploy jobs are failing with SSH authentication/fingerprint errors after PR #834 migrated workflows from `username: root` to `username: deploy`. The server-side preparation (Phase 1 of #834's tasks) was not completed before the workflow changes were merged, leaving CI unable to authenticate as the `deploy` user.

## Problem Statement

PR #834 (`fix(security): replace root SSH with deploy user in CI workflows`) changed both release workflows to SSH as `deploy` instead of `root`. However, the prerequisite Phase 1 manual steps -- creating the `deploy` user on the production server, installing SSH authorized_keys, and setting up the forced command -- were never completed.

**Two distinct failure modes observed:**

1. **Run 23335135290 / 23335135287** (08:35 UTC): `ssh: unable to authenticate, attempted methods [none publickey]` -- the `deploy` user either does not exist on the server or has no authorized_keys entry matching `WEB_PLATFORM_SSH_KEY`
2. **Run 23335268807** (08:39 UTC): `ssh: host key fingerprint mismatch` -- the `WEB_PLATFORM_HOST_FINGERPRINT` secret was updated at 08:38 UTC but with an incorrect value

**Root cause:** The deploy user migration was a two-phase operation (server prep + workflow change). The workflow changes were merged without completing server preparation. The `ci-deploy.sh` forced command script is embedded in cloud-init for new server provisioning but was previously installed on the running server only for the `root` user (PR #825 / issue #747). The `deploy` user needs equivalent setup.

### Research Insights

**Fingerprint mismatch root cause:** The `appleboy/ssh-action` uses [drone-ssh](https://github.com/appleboy/drone-ssh) internally, which negotiates the SSH key algorithm with the server. If the server offers multiple host key types (RSA, ECDSA, ed25519), the negotiated type may differ from the one used to generate the fingerprint. Per [issue #275](https://github.com/appleboy/ssh-action/issues/275), users report that ed25519 fingerprints fail while ecdsa fingerprints work, or vice versa. The fix is to retrieve the fingerprint for ALL key types and test which one the action negotiates, or retrieve the fingerprint directly from the server's key file rather than via `ssh-keyscan`.

**Best practice for fingerprint retrieval:** SSH into the server and run `ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub` (or the relevant key type) to get the authoritative fingerprint. The `ssh-keyscan` approach can return different key types depending on client-server negotiation. Per the [appleboy/ssh-action README](https://github.com/appleboy/ssh-action/blob/master/README.md), the recommended command is:

```bash
ssh <host> ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub | cut -d ' ' -f2
```

## Proposed Solution

A hybrid fix with three tracks, executed in order:

### Track 0: Pre-flight verification

Before making any changes, verify baseline access:

```bash
# Verify root SSH works (admin key)
ssh root@<WEB_PLATFORM_HOST> "whoami && docker ps --format '{{.Names}}' && cat /etc/ssh/sshd_config.d/01-hardening.conf"
```

This confirms: (a) the server is reachable, (b) Docker is running, (c) the current sshd config.

### Track 1: Server-side preparation (manual SSH commands)

Execute the Phase 1 steps from `knowledge-base/specs/feat-deploy-ssh-user/tasks.md` that were skipped:

1. SSH into the web platform server as `root` (admin key)
2. Create the `deploy` user with docker group membership
3. Verify `/usr/local/bin/ci-deploy.sh` exists (installed by PR #825) -- if missing, install it first
4. Install SSH authorized_keys for `deploy` with the CI public key + forced command restriction
5. Configure sudoers for the `chown` command
6. Transfer `/mnt/data` ownership to `deploy` (broad-to-narrow: recursive first, then specific override for workspaces)
7. Update `AllowUsers` in sshd config
8. Verify: SSH as `deploy`, test forced command accepts `deploy` and rejects other commands

### Track 2: Fix the fingerprint secret

Retrieve the correct server host key fingerprint **directly from the server's key file** (not via ssh-keyscan, which may return a different key type):

```bash
# Get the fingerprint for each key type available on the server
ssh root@<WEB_PLATFORM_HOST> "for f in /etc/ssh/ssh_host_*_key.pub; do echo \"--- \$f ---\"; ssh-keygen -l -f \"\$f\"; done"
```

Then determine which key type `drone-ssh` negotiates (typically ed25519 if available) and set the corresponding fingerprint:

```bash
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:<correct_hash>"
```

### Track 3: Workflow validation

After server-side setup, trigger manual runs to verify both workflows:

1. `gh workflow run web-platform-release.yml -f bump_type=patch`
2. `gh workflow run telegram-bridge-release.yml -f bump_type=patch`
3. Poll until complete and verify deploy success with health checks

## Technical Considerations

### Forced command compatibility

The `ci-deploy.sh` script was originally installed for the `root` user's authorized_keys (PR #825). The `deploy` user needs the same forced command restriction in its authorized_keys. The cloud-init template already writes `ci-deploy.sh` to `/usr/local/bin/ci-deploy.sh` (line 42-172 of `apps/web-platform/infra/cloud-init.yml`), but this only applies to **new** server provisioning, not the existing running server.

For the existing server, the script must be manually installed and the `deploy` user's `authorized_keys` must include the `restrict,command="/usr/local/bin/ci-deploy.sh"` prefix.

#### Research Insights

**Forced command ordering dependency:** The `command=` directive in authorized_keys references `/usr/local/bin/ci-deploy.sh`. If this file does not exist or is not executable when the SSH connection is made, the connection will fail with a cryptic error (not a clear "script not found" message). Always verify the script exists and is executable BEFORE adding the authorized_keys entry.

**`restrict` keyword behavior:** The `restrict` keyword (OpenSSH 7.2+) is a shorthand that disables port forwarding, X11 forwarding, agent forwarding, PTY allocation, and user-rc execution. It is more maintainable than listing individual `no-*` options and automatically covers new restriction options added in future OpenSSH releases.

### Telegram Bridge shares the web platform server

Despite having separate Terraform infra definitions (`apps/telegram-bridge/infra/` with `hcloud_server.bridge` in `fsn1`), both release workflows deploy to `WEB_PLATFORM_HOST`. The `ci-deploy.sh` forced command script handles both `web-platform` and `telegram-bridge` components. The `TELEGRAM_BRIDGE_HOST` secret exists but is not used by the release workflow.

This is by design -- both apps are co-located on the web platform server. The separate Telegram Bridge Terraform is for future separation.

### SSH key reuse

The same `WEB_PLATFORM_SSH_KEY` private key is used for both workflows. The corresponding public key must be added to the `deploy` user's `~/.ssh/authorized_keys`. The public key can be derived from the private key: `ssh-keygen -y -f <private_key_file>`.

### Fingerprint key-type negotiation

The `appleboy/ssh-action` uses drone-ssh which negotiates the SSH host key algorithm during the handshake. If the server offers ed25519, ecdsa, and rsa host keys, and the client prefers ed25519, then the fingerprint secret MUST contain the ed25519 fingerprint. Using the ecdsa fingerprint will cause a mismatch even though both are valid fingerprints for the same server.

**Diagnostic approach:** If the fingerprint still mismatches after setting it from ed25519, try ecdsa:

```bash
# Get all fingerprints and try each
ssh root@<host> "ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub"
ssh root@<host> "ssh-keygen -l -f /etc/ssh/ssh_host_ecdsa_key.pub"
ssh root@<host> "ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub"
```

### Rollback option

If server-side setup cannot be completed immediately, the workflows can be temporarily reverted to `username: root` to restore deploys while the deploy user is set up properly. This is a revert of the username change only (not the full PR #834).

### Relevant institutional learnings

1. **chown ordering** (`2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md`): Apply ownership in broadest-to-narrowest order. The recursive `chown -R deploy:deploy /mnt/data` MUST come before the specific `chown 1001:1001 /mnt/data/workspaces`, otherwise the recursive sweep overwrites the specific permission. The plan's MVP commands already have the correct ordering.

2. **SSH firewall dependency** (`2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`): When CI SSH deploy fails, the root cause may involve multiple layers (key auth + network path). The Hetzner firewall was previously opened to `0.0.0.0/0` for port 22 to allow GitHub Actions runners -- verify this is still the case. A firewall regression would produce a `dial tcp: i/o timeout` error, not an auth error, so the current failures confirm network connectivity is fine.

3. **OpenSSH first-match-wins** (`2026-03-19-openssh-first-match-wins-drop-in-precedence.md`): The `01-hardening.conf` drop-in uses a low number prefix to be read before Hetzner's `50-cloud-init.conf`. When adding `AllowUsers root deploy`, this must be in the `01-hardening.conf` file (which is processed first), not in the main sshd_config.

4. **Workflow command annotations** (`2026-03-20-github-actions-error-annotations-require-runner.md`): The `ci-deploy.sh` script correctly uses plain `echo` for error messages instead of `::error::` workflow commands, since the script executes on the remote server, not on the Actions runner.

5. **Forced command refactoring risk** (`2026-03-20-ssh-forced-command-workflow-refactoring-drops-parameters.md`): When refactoring SSH workflow steps, parameters serving different concerns (key loading vs. fingerprint pinning) within the same block are easily dropped. The current workflows correctly have the `fingerprint` parameter -- verify it is preserved after any changes.

## Acceptance Criteria

- [ ] `deploy` user exists on the web platform server with docker group membership
- [ ] `deploy` user's `~/.ssh/authorized_keys` contains the CI public key with `restrict,command="/usr/local/bin/ci-deploy.sh"` prefix
- [ ] `/usr/local/bin/ci-deploy.sh` is installed on the server with mode 0755 and content matching `apps/web-platform/infra/cloud-init.yml`
- [ ] `/etc/sudoers.d/deploy-chown` exists with correct permissions (0440, root:root) and passes `visudo -c` validation
- [ ] `/mnt/data` is owned by `deploy:deploy`
- [ ] `/mnt/data/workspaces` is owned by `1001:1001` (set AFTER the recursive chown)
- [ ] `AllowUsers root deploy` is active in `/etc/ssh/sshd_config.d/01-hardening.conf`
- [ ] `WEB_PLATFORM_HOST_FINGERPRINT` secret contains the correct `SHA256:<hash>` fingerprint matching the key type drone-ssh negotiates
- [ ] Web Platform Release workflow deploys successfully (health check passes)
- [ ] Telegram Bridge Release workflow deploys successfully (health check passes)
- [ ] Root SSH still works via admin key for maintenance
- [ ] Deploy user's forced command rejects non-deploy commands (e.g., `whoami`)

## Test Scenarios

- Given the deploy user is created and configured, when web-platform-release.yml runs with `bump_type=patch`, then the deploy step succeeds and health check returns 200
- Given the deploy user is configured, when telegram-bridge-release.yml runs with `bump_type=patch`, then the deploy step succeeds and health endpoint responds
- Given the deploy user has the forced command, when CI tries `deploy web-platform <image> <tag>`, then the command is accepted and executed
- Given the deploy user has the forced command, when CI tries any non-deploy command, then the command is rejected with exit 1
- Given an incorrect fingerprint secret, when the deploy step runs, then it fails with "fingerprint mismatch" (not silently proceeding)
- Given the deploy user is configured, when running `ssh deploy@<host> "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v0.0.1"`, then the forced command parses and rejects "v0.0.1" as invalid (no matching image tag in GHCR) but the SSH auth and command parsing succeeds

### Edge Cases

- **User already exists:** If `useradd deploy` fails because the user exists, `usermod -aG docker deploy` adds docker group membership without recreating the user
- **ci-deploy.sh already exists:** If the script was installed by PR #825, verify its content matches the cloud-init template (may have been updated in PR #834 to add `sudo` prefix for chown)
- **Multiple SSH sessions during setup:** The `systemctl restart sshd` does NOT terminate existing SSH sessions (only affects new connections), so the setup can be done in a single session without losing access
- **Docker group requires re-login:** Adding deploy to the docker group via `usermod -aG` requires the user to log out and back in. For CI, this is not an issue because each SSH connection is a fresh login session

## Dependencies and Risks

### Dependencies

- SSH access to the production server as root (admin key)
- The `WEB_PLATFORM_SSH_KEY` private key to derive the public key for authorized_keys (can also be derived from the existing root authorized_keys on the server if the CI public key is already there)
- Server host key fingerprint (retrievable directly from `/etc/ssh/ssh_host_*_key.pub` files)

### Risks

- **Deploy user may break existing docker containers** -- The `deploy` user needs docker group membership to run `docker pull/stop/rm/run`. If docker group doesn't exist yet (unlikely on a server already running docker), `usermod -aG docker deploy` will fail. Mitigated: verify `getent group docker` before user creation.
- **Forced command interaction with sudo** -- The `ci-deploy.sh` script uses `sudo chown` for the web-platform component. The sudoers rule must exactly match: `deploy ALL=(root) NOPASSWD: /usr/bin/chown 1001\:1001 /mnt/data/workspaces`. The backslash-escaped colon is required because sudoers interprets unescaped colons as field separators.
- **Race condition during setup** -- If a release CI job triggers while the deploy user is being set up, it will fail. The server setup should be done during a quiet period or after temporarily pausing auto-merge.
- **Fingerprint key-type mismatch** -- Setting the fingerprint for the wrong key algorithm will cause mismatch errors even though the value is correct for that algorithm. Retrieve fingerprints for all available key types and test systematically.

## References

- PR #834: `fix(security): replace root SSH with deploy user in CI workflows` (merged, caused the failures)
- PR #825: `security: restrict CI deploy SSH key with command= forced command` (original forced command setup)
- Issue #832: Original tracking issue for deploy user migration
- Tasks: `knowledge-base/specs/feat-deploy-ssh-user/tasks.md` (Phase 1 manual steps not completed)
- Learning: `knowledge-base/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Learning: `knowledge-base/learnings/2026-03-20-ssh-forced-command-workflow-refactoring-drops-parameters.md`
- Learning: `knowledge-base/learnings/2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md`
- Learning: `knowledge-base/learnings/2026-03-19-openssh-first-match-wins-drop-in-precedence.md`
- Workflow: `.github/workflows/telegram-bridge-release.yml`
- Workflow: `.github/workflows/web-platform-release.yml`
- Cloud-init: `apps/web-platform/infra/cloud-init.yml` (lines 12-18 for deploy user, 42-172 for ci-deploy.sh)
- [appleboy/ssh-action fingerprint issue #275](https://github.com/appleboy/ssh-action/issues/275)
- [appleboy/ssh-action fingerprint syntax issue #81](https://github.com/appleboy/ssh-action/issues/81)
- [appleboy/ssh-action README](https://github.com/appleboy/ssh-action/blob/master/README.md)

## MVP

### Pre-flight (run from local machine)

```bash
# Verify root SSH access and current state
ssh root@<WEB_PLATFORM_HOST> "
  echo '=== System info ==='
  whoami
  echo '=== Docker status ==='
  docker ps --format '{{.Names}}: {{.Status}}'
  echo '=== SSH config ==='
  cat /etc/ssh/sshd_config.d/01-hardening.conf
  echo '=== Existing users ==='
  id deploy 2>/dev/null || echo 'deploy user does not exist'
  echo '=== ci-deploy.sh ==='
  ls -la /usr/local/bin/ci-deploy.sh 2>/dev/null || echo 'ci-deploy.sh not found'
  echo '=== Host keys ==='
  for f in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -l -f \"\$f\"; done
"
```

### Server-side commands (run as root via SSH)

```bash
# 0. Verify docker group exists
getent group docker || { echo "ERROR: docker group does not exist"; exit 1; }

# 1. Create deploy user with docker group (idempotent)
id deploy &>/dev/null && usermod -aG docker deploy || useradd -m -s /bin/bash -G docker deploy

# 2. Set up SSH directory
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

# 3. Verify ci-deploy.sh exists and is executable
test -x /usr/local/bin/ci-deploy.sh || { echo "ERROR: ci-deploy.sh not found or not executable -- install it first"; exit 1; }

# 4. Derive public key from CI private key and install with forced command
# Option A: derive from private key file (if available locally)
#   ssh-keygen -y -f <WEB_PLATFORM_SSH_KEY_FILE>
# Option B: copy from root's authorized_keys (the CI key with restrict,command= prefix)
#   grep 'ci-deploy' /root/.ssh/authorized_keys
# Then install (replace <CI_PUBLIC_KEY> with the actual key):
echo 'restrict,command="/usr/local/bin/ci-deploy.sh" <CI_PUBLIC_KEY>' > /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

# 5. Sudoers rule (idempotent -- overwrites if exists)
echo 'deploy ALL=(root) NOPASSWD: /usr/bin/chown 1001\:1001 /mnt/data/workspaces' > /etc/sudoers.d/deploy-chown
chmod 0440 /etc/sudoers.d/deploy-chown
chown root:root /etc/sudoers.d/deploy-chown
visudo -c -f /etc/sudoers.d/deploy-chown

# 6. Transfer data ownership (broad-to-narrow ordering per learning)
chown -R deploy:deploy /mnt/data
chown 1001:1001 /mnt/data/workspaces

# 7. Update sshd AllowUsers (idempotent -- only modifies if deploy not present)
grep -q 'AllowUsers.*deploy' /etc/ssh/sshd_config.d/01-hardening.conf || \
  sed -i 's/AllowUsers root/AllowUsers root deploy/' /etc/ssh/sshd_config.d/01-hardening.conf
systemctl restart sshd
```

### Server-side verification (still as root)

```bash
# Verify deploy user setup
echo "=== User ==="
id deploy
echo "=== Docker access ==="
su - deploy -c "docker ps" 2>&1 | head -5
echo "=== Data ownership ==="
ls -la /mnt/data/ | head -5
stat -c '%U:%G' /mnt/data/workspaces
echo "=== SSH config ==="
grep AllowUsers /etc/ssh/sshd_config.d/01-hardening.conf
echo "=== Sudoers ==="
visudo -c -f /etc/sudoers.d/deploy-chown
echo "=== Authorized keys ==="
cat /home/deploy/.ssh/authorized_keys | cut -c1-80
```

### Fingerprint fix (run from local machine with root SSH access)

```bash
# Get fingerprints for ALL key types from the server
ssh root@<WEB_PLATFORM_HOST> "for f in /etc/ssh/ssh_host_*_key.pub; do echo \"--- \$f ---\"; ssh-keygen -l -f \"\$f\"; done"

# Set the ed25519 fingerprint first (most likely to be negotiated)
# Format: SHA256:<base64_hash>
FINGERPRINT="SHA256:<hash_from_ed25519_output>"
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "$FINGERPRINT"

# If the first attempt still fails with fingerprint mismatch, try ecdsa fingerprint instead
```

### Deploy user SSH verification (run from local machine)

```bash
# Test SSH as deploy user with the CI key
ssh -i <path_to_ci_private_key> deploy@<WEB_PLATFORM_HOST> "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v0.0.0"
# Expected: REJECTED by ci-deploy.sh (v0.0.0 is valid format but image may not exist in GHCR)
# The key thing is that SSH auth succeeds and the forced command runs

# Test that non-deploy commands are rejected
ssh -i <path_to_ci_private_key> deploy@<WEB_PLATFORM_HOST> "whoami"
# Expected: REJECTED by ci-deploy.sh ("unknown action 'whoami'")
```

### Workflow verification (run after server setup + fingerprint fix)

```bash
# Trigger both release workflows
gh workflow run web-platform-release.yml -f bump_type=patch
gh workflow run telegram-bridge-release.yml -f bump_type=patch

# Poll for completion
while true; do
  WEB_STATUS=$(gh run list --workflow=web-platform-release.yml --limit 1 --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')
  TB_STATUS=$(gh run list --workflow=telegram-bridge-release.yml --limit 1 --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')
  echo "Web Platform: $WEB_STATUS | Telegram Bridge: $TB_STATUS"
  echo "$WEB_STATUS $TB_STATUS" | grep -q "completed" && echo "$WEB_STATUS $TB_STATUS" | grep -q "completed" && break
  sleep 30
done
```
