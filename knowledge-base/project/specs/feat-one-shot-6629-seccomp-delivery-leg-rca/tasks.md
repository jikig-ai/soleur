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

- [ ] 1.1 `gh run view 29450562340 --log` — confirm it is the ADR-079 item-4
  redeploy; capture the pre-redeploy `host_present=false` baseline + timestamp.
- [ ] 1.2 Read `/hooks/deploy-status` HISTORY around 2026-07-16T21:03Z (HMAC +
  CF-Access via Doppler `prd_terraform`, read-only) — establish host_present
  true→false→true edges. Historical data only (no fresh probe).
- [ ] 1.3 Query Better Stack logs API for web-1 SOLEUR_* boot markers in
  [last-known-true … 21:03]. Boot marker in-window ⟹ replacement (H1/H2).
- [ ] 1.4 `gh run list` for apply-web-platform-infra / apply-deploy-pipeline-fix /
  scheduled-terraform-drift (2026-07-14…16) — find any web-1 replace/apply, its
  executed `-target` set, and the SSH-leg (docker_seccomp_config) job status.
- [ ] 1.5 Read R2 tfstate (canonical triplet: AWS creds + `--name-transformer
  tf-var`); `terraform state show terraform_data.docker_seccomp_config` — compare
  recorded `triggers.server_id` vs live `hcloud_server.web["web-1"].id`.
- [ ] 1.6 Read `cat-deploy-state.sh:326-368` + hook wiring — confirm host-side
  `test -f` (eliminate H5 namespace-visibility).
- [ ] 1.7 Write the RCA post-mortem with a per-hypothesis verdict table (each row
  CONFIRMED/REFUTED/UNKNOWN + cited discriminator datum) + the explicit
  non-merge-path YES/NO determination.
- [ ] 1.8 COMMIT Phase 1 alone. If H1/H2 REFUTED, STOP and re-scope Phases 2–3.

## Phase 2 — Fix (only if Phase 1 confirms an in-repo defect)

- [ ] 2.1 Bake seccomp profile + userns sysctl unit + drop-in into `cloud-init.yml`
  `write_files:`/`runcmd:` (mirror `daemon.json` at `:441-444`); pin the cloud-init
  copy to `seccomp-bwrap.json` via `file()`/templatefile + a drift-guard test.
- [ ] 2.2 Add `server_id` to `apparmor_bwrap_profile.triggers_replace`
  (`server.tf`); bake apparmor into cloud-init too if the same boot-gap applies.
- [ ] 2.3 (Conditional H2/H3) Make the SSH-apply leg FAIL LOUD (non-zero + Sentry)
  when docker_seccomp_config/apparmor_bwrap_profile do not apply.
- [ ] 2.4 Amend ADR-079 delivery contract (dual-delivery). Re-read the 3 `.c4`
  files; edit only if a description is falsified (expected no-op).
- [ ] 2.5 `tsc --noEmit` (if TS touched); infra shell tests; `terraform validate` /
  infra-config gate green.

## Phase 3 — Non-merge-path determination (#6628 build-gate)

- [ ] 3.1 State the YES/NO in the RCA with the confirming datum.
- [ ] 3.2 Comment on #6628 (build trigger fired / stays deferred, with reason).
- [ ] 3.3 PR body `Ref #6629`; `gh issue close 6629` post-merge.
