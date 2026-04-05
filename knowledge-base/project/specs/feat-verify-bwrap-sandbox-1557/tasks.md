# Tasks: Verify bwrap sandbox in production Docker container

## Phase 1: Diagnosis

- [ ] 1.1 SSH into production server for read-only bwrap diagnosis
- [ ] 1.2 Run `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id` and document output
- [ ] 1.3 Check Sentry for bwrap-related errors to understand SDK failure behavior
- [ ] 1.4 Get Docker Engine version from server (`docker version --format '{{.Server.Version}}'`)

## Phase 2: Create seccomp profile

- [ ] 2.1 Download Docker's default seccomp profile matching server's Docker Engine version
- [ ] 2.2 Add ALLOW rules for clone+CLONE_NEWUSER and unshare+CLONE_NEWUSER (with `excludes: { caps: ["CAP_SYS_ADMIN"] }`)
- [ ] 2.3 Add header comment documenting source Docker Engine version and diff
- [ ] 2.4 Save as `apps/web-platform/infra/seccomp-bwrap.json`
- [ ] 2.5 Test locally: run container with custom profile, verify bwrap works
- [ ] 2.6 Negative test: verify `unshare --net` still fails with custom profile
- [ ] 2.7 Create tracking issue for periodic seccomp profile review (Docker version drift)

## Phase 3: Update deploy infrastructure

- [ ] 3.1 Add `terraform_data.docker_seccomp_config` to `server.tf` (copy profile, update daemon.json, restart Docker)
- [ ] 3.2 Update ci-deploy.sh: add bwrap canary check after health check (before swap)
- [ ] 3.3 Update ci-deploy.test.sh with bwrap canary test expectations

## Phase 4: Deploy and verify

- [ ] 4.1 Run `terraform apply` to deploy seccomp profile and update daemon.json
- [ ] 4.2 Verify bwrap works inside auto-recovered container
- [ ] 4.3 Verify negative test: `unshare --net` still blocked
- [ ] 4.4 Trigger a deploy to verify canary bwrap check works end-to-end
