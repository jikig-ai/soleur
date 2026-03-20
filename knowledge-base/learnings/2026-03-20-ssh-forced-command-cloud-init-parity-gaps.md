# Learning: SSH forced command and cloud-init parity gaps break CI deploys

## Problem

After PR #834 switched CI workflows to `username: deploy` with forced command syntax (`deploy <component> <image> <tag>`), all deploys failed with `ssh: unable to authenticate`. Four independent bugs compounded:

1. **Missing `restrict,command=` prefix**: Cloud-init added the deploy SSH key as a plain key (`${deploy_ssh_public_key}`) instead of `restrict,command="/usr/local/bin/ci-deploy.sh" ${deploy_ssh_public_key}`. A comment on line 39 documented the expected format, but the actual key on line 18 didn't match.

2. **Missing `sudo` in standalone ci-deploy.sh**: The standalone `ci-deploy.sh` used `chown 1001:1001 /mnt/data/workspaces` (no sudo), while the cloud-init embedded copy correctly used `sudo chown`. The deploy user can't chown without sudo, but the test suite passed because it mocked `chown` directly — the mock didn't cover `sudo chown`.

3. **Multi-line SSH scripts break forced commands**: Workflows sent 3-line scripts (TAG assignment + validation + deploy command). With SSH forced commands, `SSH_ORIGINAL_COMMAND` captures the entire client request as a single string. `ci-deploy.sh` expects exactly 4 whitespace-separated fields, so multi-line input causes immediate rejection with "expected 4 fields, got N".

4. **Telegram-bridge cloud-init missing parity**: Web-platform cloud-init had ci-deploy.sh and sudoers; telegram-bridge didn't. Both apps deploy to the same server via `WEB_PLATFORM_HOST`, but a server reprovision from telegram-bridge's cloud-init would lack the forced command infrastructure.

## Solution

### Fix 1: Add forced command prefix to deploy SSH key

```yaml
# Before (cloud-init.yml)
ssh_authorized_keys:
  - ${deploy_ssh_public_key}

# After
ssh_authorized_keys:
  - restrict,command="/usr/local/bin/ci-deploy.sh" ${deploy_ssh_public_key}
```

Applied to both web-platform and telegram-bridge cloud-init files.

### Fix 2: Add sudo to standalone ci-deploy.sh

```bash
# Before (ci-deploy.sh line 76)
chown 1001:1001 /mnt/data/workspaces

# After
sudo chown 1001:1001 /mnt/data/workspaces
```

Also added a `sudo` mock to `ci-deploy.test.sh` so tests exercise the real command path.

### Fix 3: Simplify workflow scripts to single-line deploy commands

```yaml
# Before (web-platform-release.yml)
script: |
  TAG="v${{ needs.release.outputs.version }}"
  [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: ..."; exit 1; }
  deploy web-platform ghcr.io/jikig-ai/soleur-web-platform "$TAG"

# After
script: deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v${{ needs.release.outputs.version }}
```

Client-side validation removed — ci-deploy.sh validates tag format, component, and image server-side.

### Fix 4: Add ci-deploy.sh and sudoers to telegram-bridge cloud-init

Added the full ci-deploy.sh `write_files` block and sudoers rule to telegram-bridge's cloud-init for parity with web-platform.

## Key Insight

SSH forced commands fundamentally change how SSH command execution works: the server ignores whatever command the client requests and runs the forced command instead. `SSH_ORIGINAL_COMMAND` is set to the raw client text — including variable assignments, conditionals, and newlines if the client sent a multi-line script. Any validation in the forced command script that assumes structured single-line input will reject multi-line scripts.

When adopting forced commands, every SSH action step must send only the final command — no wrappers, no pre-validation, no variable expansion. The forced command IS the validation layer.

Additionally, comments documenting expected format don't prevent implementation drift. The web-platform cloud-init had a comment on line 39 showing `restrict,command="..." ssh-ed25519 ...`, but the actual key on line 18 was plain. Comments adjacent to implementation are not substitutes for tests.

## Session Errors

None detected.

## Tags
category: integration-issues
module: infrastructure
