# Tasks: fix deploy pipeline Doppler secrets download

## Phase 1: Fix ci-deploy.sh observability

- [ ] 1.1 Update `resolve_env_file()` in `apps/web-platform/infra/ci-deploy.sh`: replace `2>/dev/null` with combined output capture pattern (capture stdout+stderr in variable, log on failure, write to tmpenv on success)
- [ ] 1.2 Update `apps/web-platform/infra/ci-deploy.test.sh`: add test for Doppler error logging, ensure mock environment includes `DOPPLER_CONFIG_DIR`
- [ ] 1.3 Run `bash apps/web-platform/infra/ci-deploy.test.sh` and verify all tests pass

## Phase 2: Fix cloud-init and Terraform for DOPPLER_CONFIG_DIR

- [ ] 2.1 Update `apps/web-platform/infra/cloud-init.yml`: add `DOPPLER_CONFIG_DIR=/tmp/.doppler` and `DOPPLER_ENABLE_VERSION_CHECK=false` to the runcmd that writes `/etc/default/webhook-deploy`
- [ ] 2.2 Extend `terraform_data.deploy_pipeline_fix` in `apps/web-platform/infra/server.tf`: add idempotent `remote-exec` to append `DOPPLER_CONFIG_DIR` and `DOPPLER_ENABLE_VERSION_CHECK` to `/etc/default/webhook-deploy` (grep guard, do NOT rewrite DOPPLER_TOKEN)

## Phase 3: Apply and verify

- [ ] 3.1 Taint and apply: `terraform taint terraform_data.deploy_pipeline_fix` then `doppler run -p soleur -c prd_terraform -- terraform apply -target=terraform_data.deploy_pipeline_fix`
- [ ] 3.2 Verify env file on server contains all three vars
- [ ] 3.3 Trigger a deploy and verify via `journalctl -t ci-deploy` that secrets download succeeds
- [ ] 3.4 Verify container has Doppler secrets: `docker exec soleur-web-platform printenv DOPPLER_CONFIG` returns `prd`
