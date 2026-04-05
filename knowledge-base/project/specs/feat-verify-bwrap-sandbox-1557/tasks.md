# Tasks: Verify bwrap sandbox in production Docker container

## Phase 1: Diagnosis

- [ ] 1.1 SSH into production server for read-only bwrap diagnosis
- [ ] 1.2 Run `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id` and document output
- [ ] 1.3 Check Sentry for bwrap-related errors to understand SDK failure behavior

## Phase 2: Create seccomp profile

- [ ] 2.1 Get Docker Engine version from production server (`docker version`)
- [ ] 2.2 Download Docker's default seccomp profile matching that version
- [ ] 2.3 Add ALLOW rules for clone+CLONE_NEWUSER and unshare+CLONE_NEWUSER
- [ ] 2.4 Save as `apps/web-platform/infra/seccomp-bwrap.json`
- [ ] 2.5 Test locally: run container with custom profile, verify bwrap works
- [ ] 2.6 Negative test: verify `unshare --net` still fails with custom profile

## Phase 3: Update deploy infrastructure

- [ ] 3.1 Add `terraform_data.seccomp_profile_install` to `server.tf`
- [ ] 3.2 Add `terraform_data.ci_deploy_update` to `server.tf`
- [ ] 3.3 Update ci-deploy.sh: graceful seccomp detection + `--security-opt` for canary and production
- [ ] 3.4 Update ci-deploy.sh: add bwrap canary check after health check
- [ ] 3.5 Update cloud-init.yml: add seccomp profile to `write_files`
- [ ] 3.6 Update cloud-init.yml: add `--security-opt` to initial `docker run`
- [ ] 3.7 Update server.tf `templatefile()` call with seccomp profile variable
- [ ] 3.8 Update ci-deploy.test.sh with mock expectations for `--security-opt` and bwrap check

## Phase 4: Deploy and verify

- [ ] 4.1 Run `terraform apply` to deploy seccomp profile + updated ci-deploy.sh
- [ ] 4.2 Trigger deploy or wait for PR merge release
- [ ] 4.3 Verify bwrap works inside container post-deploy
- [ ] 4.4 Verify negative test: `unshare --net` still blocked
- [ ] 4.5 Create tracking issue for periodic seccomp profile review (Docker version drift)
