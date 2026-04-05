# Tasks: fix deploy pipeline uses stale .env instead of Doppler secrets

Source: `knowledge-base/project/plans/2026-04-05-fix-deploy-stale-env-terraform-plan.md`
Issue: #1548

## Phase 1: Update cloud-init for new servers

- [ ] 1.1 Read `apps/web-platform/infra/cloud-init.yml`
- [ ] 1.2 Add `/var/lock` to `ReadWritePaths` in the webhook.service unit definition (line 150: `ReadWritePaths=/mnt/data` becomes `ReadWritePaths=/mnt/data /var/lock`)

## Phase 2: Add terraform_data provisioner to server.tf

- [ ] 2.1 Read `apps/web-platform/infra/server.tf` (use `disk_monitor_install` as template)
- [ ] 2.2 Add single `terraform_data.deploy_pipeline_fix` resource
  - [ ] 2.2.1 `triggers_replace` = `sha256(join(",", [file("ci-deploy.sh"), <systemd_unit_content>]))`
  - [ ] 2.2.2 `connection` block matching `disk_monitor_install` pattern
  - [ ] 2.2.3 `file` provisioner: source `ci-deploy.sh`, destination `/usr/local/bin/ci-deploy.sh`
  - [ ] 2.2.4 `remote-exec` inline sequence: chmod +x, write webhook.service unit (with EnvironmentFile and ReadWritePaths=/mnt/data /var/lock), daemon-reload, restart webhook, rm -f /mnt/data/.env
- [ ] 2.3 Add comments explaining CI drift report behavior (references #1409) and documenting the duplication with cloud-init.yml

## Phase 3: Terraform apply and verification

- [ ] 3.1 Run `doppler run --project soleur --config prd_terraform -- terraform plan` to preview changes
- [ ] 3.2 Run `terraform apply` to execute provisioners
- [ ] 3.3 Verify ci-deploy.sh on server matches repo version (md5sum comparison)
- [ ] 3.4 Verify webhook.service has correct EnvironmentFile and ReadWritePaths
- [ ] 3.5 Verify `/mnt/data/.env` is deleted
- [ ] 3.6 Trigger a deploy and verify container gets all Doppler prd secrets
- [ ] 3.7 Verify `curl https://app.soleur.ai/health | jq .sentry` returns `"configured"`
- [ ] 3.8 Run `terraform plan` again to confirm no unexpected drift
