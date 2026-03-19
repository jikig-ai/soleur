# Tasks: fix CI deploy SSH key passphrase

## Phase 1: Key Generation and Server Installation

- [ ] 1.1 Generate new Ed25519 keypair without passphrase: `ssh-keygen -t ed25519 -C "ci-deploy@soleur-web-platform" -f ci_deploy_key -N ""`
- [ ] 1.2 SSH into web-platform server using existing manual access
- [ ] 1.3 Append new public key to `/root/.ssh/authorized_keys` on server
- [ ] 1.4 Verify SSH access with new key: `ssh -i ci_deploy_key root@<host> 'echo ok'`
- [ ] 1.5 Update GitHub secret: `gh secret set WEB_PLATFORM_SSH_KEY < ci_deploy_key`
- [ ] 1.6 Securely delete local private key: `shred -u ci_deploy_key`

## Phase 2: Verification

- [ ] 2.1 Trigger deploy workflow: `gh workflow run build-web-platform.yml -f deploy=true`
- [ ] 2.2 Poll workflow run until completion: `gh run view <id> --json status,conclusion`
- [ ] 2.3 Verify deploy job succeeded (no `ssh.ParsePrivateKey` errors in logs)
- [ ] 2.4 Verify health endpoint responds: `curl -sf https://app.soleur.ai/health`

## Phase 3: Cleanup and Follow-up

- [ ] 3.1 Remove old public key from `/root/.ssh/authorized_keys` on server (optional)
- [ ] 3.2 File follow-up issue: restrict CI key with `command=` in `authorized_keys`
- [ ] 3.3 File follow-up issue: evaluate Watchtower/webhook-based deploy to eliminate SSH dependency
