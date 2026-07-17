---
title: "Tasks: RCA seccomp delivery-leg (#6629)"
plan: knowledge-base/project/plans/2026-07-18-rca-seccomp-delivery-leg-host-present-false-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — RCA seccomp delivery-leg host_present=false (#6629)

> PROBE-FIRST. Phase 1 (RCA) ships ALONE before any fix. No hypothesis reads
> CONFIRMED/REFUTED until its discriminator datum is pulled (#6536). NO SSH —
> `hr-no-dashboard-eyeball-pull-data-yourself`.

## Phase 1 — Self-pull the diagnosis (RCA)

- [x] 1.0 **H0 FIRST** — which host answered `/hooks/deploy-status` at 21:03: web-1
  or the seccomp-less warm-standby web-2? Pull the payload host_id/marker + tunnel
  ingress state vs #6595 (2026-07-17 pin). web-2 ⟹ host_present=false is EXPECTED,
  H1/H2 REFUTED, RCA reframes (image-bake still closes the standby gap).
- [x] 1.1 `gh run view 29450562340 --log` — confirm it is the ADR-079 item-4
  redeploy; capture the pre-redeploy `host_present=false` baseline + timestamp.
- [x] 1.2 Read `/hooks/deploy-status` HISTORY around 2026-07-16T21:03Z (HMAC +
  CF-Access via Doppler `prd_terraform`, read-only) — establish host_present
  true→false→true edges. Historical data only (no fresh probe).
- [x] 1.3 Query Better Stack logs API for web-1 SOLEUR_* boot markers in
  [last-known-true … 21:03]. Boot marker in-window ⟹ replacement (H1/H2).
- [x] 1.4 (WINDOW-DECISIVE) `gh run list` for apply-web-platform-infra /
  apply-deploy-pipeline-fix / scheduled-terraform-drift (2026-07-14…16) — find any
  web-1 replace/apply, its executed `-target` set, and the SSH-leg step status
  (`success`/`skipped`/`failure`). Grep the silent-skip signatures:
  `CI_SSH_ACCESS_TOKEN_ID absent`, `cloudflared TCP forward did not open`, and the
  cloudflared-log block (`Unauthorized`/`403`/`connection reset`/`i/o timeout`).
- [x] 1.5 (CORROBORATING, not decisive) Read R2 tfstate (canonical triplet);
  `terraform state show terraform_data.docker_seccomp_config` — server_id vs live id.
  NOTE: plan-time snapshot may have self-healed post-window; window-decisive = 1.0+1.4+1.3.
- [x] 1.6 Read `cat-deploy-state.sh:326-368` + hook wiring — confirm host-side
  `test -f` (eliminate H5 namespace-visibility).
- [x] 1.7 Write the RCA post-mortem with a per-hypothesis verdict table (each row
  CONFIRMED/REFUTED/UNKNOWN + cited discriminator datum) + the explicit
  non-merge-path YES/NO determination.
- [x] 1.8 COMMIT Phase 1 alone. If H0 (web-2 probe) OR H1/H2 REFUTED, STOP and re-scope.

## Phase 2 — Fix (only if Phase 1 confirms an enforcement-delivery gap on the probed host)

- [ ] 2.1 IMAGE-BAKE (NOT write_files): add `seccomp-bwrap.json` + `apparmor-soleur-bwrap.profile`
  to Dockerfile `/opt/soleur/host-scripts/` (`:196-206`); extract at boot
  (`cloud-init.yml:139-140`); fold into `host_scripts_content_hash` (no separate
  drift-guard test — extend existing hash). Respects the `WEB_GZIP_BUDGET` cap.
- [ ] 2.2 Add `--security-opt seccomp=… --security-opt apparmor=soleur-bwrap` to the
  cloud-init boot `docker run` (`:773-785`) + fail-closed `poweroff -f` if absent;
  `apparmor_parser -r` + userns sysctl in `runcmd` BEFORE that run.
- [ ] 2.3 AppArmor HARD-required: `server_id` in `apparmor_bwrap_profile.triggers_replace`
  (`server.tf:1121`) + image-bake delivery + load + boot `--security-opt`.
- [ ] 2.4 Preserve ci-deploy's UNCONDITIONAL `--security-opt` (fail-closed) — forbid
  any conditional-seccomp "fix." (Cond. H2/H3) SSH-leg FAIL LOUD (non-zero + Sentry).
- [ ] 2.5 Track `seccomp_profile_loaded_matches_host` in ACs/Observability, not just
  host_present. Verify via `terraform plan -replace=hcloud_server.web["web-1"]` (no apply)
  that the fresh create carries the change (ignore_changes[user_data] caveat).
- [ ] 2.6 CREATE ADR-122 anchored to ADR-080 (bake-and-extract) — NOT amend ADR-079.
  Re-read the 3 `.c4` files; edit only if a description is falsified (expected no-op).
- [ ] 2.7 `tsc --noEmit` (if TS touched); infra shell tests; `cloud-init-user-data-size.test.ts`
  green; `terraform validate` / infra-config gate green.

## Phase 3 — Non-merge-path determination (#6628 build-gate)

- [ ] 3.1 State the YES/NO in the RCA with the confirming datum.
- [ ] 3.2 Comment on #6628 (build trigger fired / stays deferred, with reason).
- [ ] 3.3 PR body `Ref #6629`; `gh issue close 6629` post-merge.
