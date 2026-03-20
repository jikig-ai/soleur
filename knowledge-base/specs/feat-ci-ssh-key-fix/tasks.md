# Tasks: fix CI deploy SSH key passphrase

## Phase 1: Key Generation and Server Installation

- [ ] 1.1 Generate new Ed25519 keypair without passphrase: `ssh-keygen -t ed25519 -C "ci-deploy@soleur-web-platform" -f ci_deploy_key -N ""`
- [ ] 1.2 Verify key format: `head -1 ci_deploy_key` outputs `-----BEGIN OPENSSH PRIVATE KEY-----`
- [ ] 1.3 SSH into web-platform server using existing manual access
- [ ] 1.4 Append new public key to `/root/.ssh/authorized_keys` on server: `ssh root@<host> 'cat >> /root/.ssh/authorized_keys' < ci_deploy_key.pub`
- [ ] 1.5 Verify file permissions: `ssh root@<host> 'stat -c "%a %U:%G" /root/.ssh/authorized_keys'` (expect `600 root:root`)
- [ ] 1.6 Verify SSH access with new key: `ssh -i ci_deploy_key root@<host> 'echo ok'`
- [ ] 1.7 Update GitHub secret: `gh secret set WEB_PLATFORM_SSH_KEY < ci_deploy_key`
- [ ] 1.8 Securely delete both local key files: `shred -u ci_deploy_key ci_deploy_key.pub`

## Phase 2: Verification

- [ ] 2.1 Trigger deploy workflow: `gh workflow run build-web-platform.yml -f deploy=true`
- [ ] 2.2 Poll workflow run until completion: `gh run view <id> --json status,conclusion`
- [ ] 2.3 Verify deploy job succeeded (no `ssh.ParsePrivateKey` errors in logs)
- [ ] 2.4 Verify health endpoint responds: `curl -sf https://app.soleur.ai/health`

## Phase 3: Cleanup and Follow-up

- [ ] 3.1 Remove old public key from `/root/.ssh/authorized_keys` on server (optional -- orphaned key authenticates nothing)
- [ ] 3.2 File follow-up issue: restrict CI key with `command=` in `authorized_keys`
- [ ] 3.3 File follow-up issue: add host key fingerprint verification via `fingerprint` input
- [ ] 3.4 File follow-up issue: evaluate Watchtower/webhook-based deploy to eliminate SSH dependency
