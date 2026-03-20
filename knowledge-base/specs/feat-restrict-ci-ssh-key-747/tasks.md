# Tasks: Restrict CI deploy SSH key with command=

## Phase 1: Create deploy script

- [x] 1.1 Create `apps/web-platform/infra/ci-deploy.sh` with deploy logic for both web-platform and telegram-bridge
  - [x] 1.1.1 Parse `SSH_ORIGINAL_COMMAND` for structured `deploy <component> <image> <tag>` format
  - [x] 1.1.2 Validate action, component, image pattern (`ghcr.io/jikig-ai/soleur-*`), and tag format (`vX.Y.Z`)
  - [x] 1.1.3 Implement web-platform deploy case (docker pull/stop/rm/run + health check)
  - [x] 1.1.4 Implement telegram-bridge deploy case (docker pull/stop/rm/run + health check)
  - [x] 1.1.5 Log all attempts (accepted and rejected) via `logger -t ci-deploy`
  - [x] 1.1.6 Reject unrecognized commands with error message and exit 1

## Phase 2: Update cloud-init

- [x] 2.1 Update `apps/web-platform/infra/cloud-init.yml`
  - [x] 2.1.1 Add `write_files` entry for `/usr/local/bin/ci-deploy.sh` with mode 0755
  - [x] 2.1.2 Add comments documenting the `authorized_keys` `restrict,command=` format for the CI key

## Phase 3: Update CI workflows

- [x] 3.1 Update `.github/workflows/web-platform-release.yml` deploy step
  - [x] 3.1.1 Replace inline multi-line script with single-line `deploy web-platform <image> <tag>` command
- [x] 3.2 Update `.github/workflows/telegram-bridge-release.yml` deploy steps
  - [x] 3.2.1 Remove "Ensure telegram env vars on server" SSH step (env managed separately)
  - [x] 3.2.2 Replace inline multi-line script with single-line `deploy telegram-bridge <image> <tag>` command

## Phase 4: Server-side provisioning (manual)

- [ ] 4.1 SSH into server and create `/usr/local/bin/ci-deploy.sh` with contents from `apps/web-platform/infra/ci-deploy.sh`
- [ ] 4.2 Set permissions: `chmod 755 /usr/local/bin/ci-deploy.sh`
- [ ] 4.3 Update `/root/.ssh/authorized_keys` -- add `restrict,command="/usr/local/bin/ci-deploy.sh"` prefix to CI key
- [ ] 4.4 Verify admin key remains unrestricted
- [ ] 4.5 Test deploy manually: `ssh -i <ci-key> root@<host> "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"`
- [ ] 4.6 Test rejection: `ssh -i <ci-key> root@<host> "whoami"` (should fail)

## Phase 5: Verify CI deploy

- [ ] 5.1 Merge workflow changes to main
- [ ] 5.2 Run `gh workflow run web-platform-release.yml -f bump_type=patch` and verify deploy succeeds
- [ ] 5.3 Run `gh workflow run telegram-bridge-release.yml -f bump_type=patch` and verify deploy succeeds
