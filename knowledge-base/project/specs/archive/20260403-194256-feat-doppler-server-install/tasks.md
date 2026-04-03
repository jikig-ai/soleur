# Tasks: Install Doppler on Server and Remove .env Fallback

Issue: #1493

## Phase 1: Terraform Provisioner + Systemd Environment

- [ ] 1.1 Add `terraform_data.doppler_install` to `apps/web-platform/infra/server.tf`
  - [ ] 1.1.1 SSH connection block targeting `hcloud_server.web.ipv4_address`
  - [ ] 1.1.2 `remote-exec` provisioner: install Doppler CLI, persist token to `/etc/environment` and `/etc/default/webhook-deploy`, verify
  - [ ] 1.1.3 `triggers_replace` on `sha256(var.doppler_token)` for token rotation
  - [ ] 1.1.4 `depends_on = [hcloud_server.web]`
  - [ ] 1.1.5 Restart webhook.service after writing environment file
- [ ] 1.2 Add `EnvironmentFile=/etc/default/webhook-deploy` to webhook.service in `cloud-init.yml`
- [ ] 1.3 Run `terraform plan` to verify only `terraform_data.doppler_install` is created (no server replacement)
- [ ] 1.4 Run `terraform apply` to install Doppler on the live server
- [ ] 1.5 Verify via SSH: `doppler --version` and `doppler secrets --only-names`
- [ ] 1.6 Verify `/etc/default/webhook-deploy` exists with correct ownership and permissions

## Phase 2: Harden ci-deploy.sh

- [ ] 2.1 Rewrite `resolve_env_file()` in `apps/web-platform/infra/ci-deploy.sh`
  - [ ] 2.1.1 Fail with exit 1 if `command -v doppler` fails
  - [ ] 2.1.2 Fail with exit 1 if `DOPPLER_TOKEN` is empty
  - [ ] 2.1.3 Fail with exit 1 if `doppler secrets download` fails
  - [ ] 2.1.4 Remove `/mnt/data/.env` fallback path entirely
- [ ] 2.2 Simplify `cleanup_env_file()` to always delete (remove `/mnt/data/.env` conditional)

## Phase 2b: Pre-Removal .env Audit

- [ ] 2b.1 SSH into server, extract `/mnt/data/.env` key names
- [ ] 2b.2 Compare against `doppler secrets --only-names -p soleur -c prd`
- [ ] 2b.3 Add any missing keys to Doppler `prd` config before proceeding

## Phase 3: Clean Up cloud-init.yml

- [ ] 3.1 Remove `.env` placeholder creation from `runcmd` section
  - [ ] 3.1.1 Remove `touch /mnt/data/.env` and `chmod 600 /mnt/data/.env`
  - [ ] 3.1.2 Remove comments about populating `.env` with secrets
- [ ] 3.2 Add `/etc/default/webhook-deploy` creation to `runcmd` (for new servers)
- [ ] 3.3 Update initial `docker run` block to use Doppler-only (no `.env` fallback)
- [ ] 3.4 Update `.env.example` header to note production uses Doppler (remove "copy to /mnt/data/.env" instruction)

## Phase 4: Verification

- [ ] 4.1 Trigger a test deploy via webhook or `workflow_dispatch`
- [ ] 4.2 Verify health endpoint returns correct version
- [ ] 4.3 Verify container environment includes `GITHUB_APP_ID` (the secret that caused the outage)
- [ ] 4.4 Verify `DOPPLER_TOKEN` is present in webhook process environment (`systemctl show webhook.service --property=Environment`)
