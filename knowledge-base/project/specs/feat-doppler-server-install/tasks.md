# Tasks: Install Doppler on Server and Remove .env Fallback

Issue: #1493

## Phase 1: Terraform Provisioner

- [ ] 1.1 Add `null_resource.doppler_install` to `apps/web-platform/infra/server.tf`
  - [ ] 1.1.1 SSH connection block targeting `hcloud_server.web.ipv4_address`
  - [ ] 1.1.2 `remote-exec` provisioner: install Doppler CLI, persist token, verify
  - [ ] 1.1.3 `triggers` block on `sha256(var.doppler_token)` for token rotation
  - [ ] 1.1.4 `depends_on = [hcloud_server.web]`
- [ ] 1.2 Run `terraform plan` to verify only `null_resource.doppler_install` is created (no server replacement)
- [ ] 1.3 Run `terraform apply` to install Doppler on the live server
- [ ] 1.4 Verify via SSH: `doppler --version` and `doppler secrets --only-names`

## Phase 2: Harden ci-deploy.sh

- [ ] 2.1 Rewrite `resolve_env_file()` in `apps/web-platform/infra/ci-deploy.sh`
  - [ ] 2.1.1 Fail with exit 1 if `command -v doppler` fails
  - [ ] 2.1.2 Fail with exit 1 if `DOPPLER_TOKEN` is empty
  - [ ] 2.1.3 Fail with exit 1 if `doppler secrets download` fails
  - [ ] 2.1.4 Remove `/mnt/data/.env` fallback path entirely
  - [ ] 2.1.5 Keep `cleanup_env_file()` for temp file cleanup (still needed)
- [ ] 2.2 Update `cleanup_env_file()` to remove the `/mnt/data/.env` guard (always delete temp file)

## Phase 3: Clean Up cloud-init.yml

- [ ] 3.1 Remove `.env` placeholder creation from `runcmd` section
  - [ ] 3.1.1 Remove `touch /mnt/data/.env` and `chmod 600 /mnt/data/.env`
  - [ ] 3.1.2 Remove comments about populating `.env` with secrets
- [ ] 3.2 Update initial `docker run` block to use Doppler-only (no `.env` fallback)
- [ ] 3.3 Update `.env.example` header to note production uses Doppler (remove "copy to /mnt/data/.env" instruction)

## Phase 4: Verification

- [ ] 4.1 Trigger a test deploy via webhook or `workflow_dispatch`
- [ ] 4.2 Verify health endpoint returns correct version
- [ ] 4.3 Verify container environment includes `GITHUB_APP_ID` (the secret that caused the outage)
- [ ] 4.4 Audit: compare `/mnt/data/.env` keys against Doppler prd secrets to ensure nothing is missing
