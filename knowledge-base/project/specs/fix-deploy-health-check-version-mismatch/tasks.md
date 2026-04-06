# Tasks: fix(infra) deploy health check version mismatch

Source: `knowledge-base/project/plans/2026-04-06-fix-deploy-health-check-version-mismatch-plan.md`

## Phase 1: Apply Doppler ProtectHome fix via Terraform

- [x] 1.1 SSH diagnosis: DOPPLER_CONFIG_DIR IS set (terraform was already applied)
- [x] 1.2 SSH diagnosis: found real error — Doppler stderr warning leaks into env file via `2>&1`
- [x] 1.3 SSH diagnosis: container stuck at v0.13.44
- [x] 1.4 Fixed ci-deploy.sh (stderr separation), ran `terraform apply` to push fix
- [x] 1.5 Verified fix on server (grep confirms doppler_stderr_file pattern in ci-deploy.sh)
- [x] 1.6 Deploy verified: v0.13.51 running (run 24031175406 succeeded)
- [x] 1.7 Root cause identified: Doppler CLI stderr warning contaminating env file, not ProtectHome

## Phase 2: Fix polling window and improve diagnostics

- [x] 2.1 Update `.github/workflows/web-platform-release.yml` -- increase poll from 12 to 30 attempts
- [x] 2.2 Replace `grep -q "ok"` with `jq -r '.status'` for robust status check
- [x] 2.3 Add uptime to version mismatch log messages
- [x] 2.4 Verify workflow YAML is valid (no heredoc/indentation issues per AGENTS.md)

## Phase 3: Verification

- [x] 3.1 Deploy verified: v0.13.51 running after terraform apply (run 24031175406 succeeded). Workflow YAML changes (300s polling) will be verified on merge.
- [x] 3.2 Deploy notification uses existing email pattern (no changes needed)
