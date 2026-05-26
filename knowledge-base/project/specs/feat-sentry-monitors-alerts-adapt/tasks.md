---
feature: sentry-monitors-alerts-adapt
date: 2026-05-15
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
issue: 3814
closes_review_issues: [3236]
---

# Tasks: Sentry Monitors/Alerts adaptation

Phase order respects the contract-before-consumer rule: monitors before check-ins (Phase 5.5 auto-apply closes the window). Legal corpus is independent of audit output (Phase 3 references audit path declaratively, not output contents).

## Phase 0: Preconditions

- [x] 0.1 Verify `jianyuan/terraform-provider-sentry` v0.15.0-beta2 latest via `gh api`. Pin in `versions.tf`.
- [ ] 0.1.5 DE-region smoke test against scratch project per Phase 0.1.5 of plan. If fails, abort Phase 5 and switch to DHH escape hatch. (OPERATOR — requires real Sentry org + SENTRY_AUTH_TOKEN)
- [x] 0.2 Capture 4 dashboard-keyed alert rule names byte-for-byte from `configure-sentry-alerts.sh`. Persist to audit report.
- [x] 0.3 Verify 9 scheduled-workflow filenames exist on main. Capture observed median duration per workflow via `gh run list` (feeds R3 grace-period table).
- [x] 0.4 Document Doppler vs GitHub-secret split in ADR-031 (Sentry secrets in repo secrets, R2 creds in Doppler).
- [x] 0.5 Grep operator-keyed message strings; record current invariant.
- [x] 0.6 Verify Eleventy mirror 3-file presence.
- [x] 0.7 Confirm `sentry-scrub.ts` untouched.
- [ ] 0.8 Provision 3 new repo secrets: `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`. Derive from existing DSN. (OPERATOR — requires DSN value; check-in steps degrade gracefully when secrets are missing so wiring lands first.)
- [x] 0.9 Document local `SENTRY_AUTH_TOKEN` source for operator runs (user token vs internal integration).

## Phase 1: Audit script

- [x] 1.1 Create `apps/web-platform/scripts/sentry-monitors-audit.sh` (modeled on `configure-sentry-alerts.sh`).
- [x] 1.2 Create `apps/web-platform/scripts/sentry-monitors-audit.test.sh` with T1-T5 cases (env-var missing, region probe, orphan join logic, idempotency, match-by-id).
- [x] 1.3 Script emits rule IDs as machine-readable JSON array at end of report.

## Phase 2: Run audit

- [ ] 2.1 Operator runs audit locally; report committed to `knowledge-base/legal/audits/2026-05-15-sentry-migration-audit.md`. (OPERATOR — requires SENTRY_AUTH_TOKEN; script + tests landed in Phase 1.)
- [ ] 2.1.5 If non-zero orphans: classify each (monitor-no-alert / alert-no-monitor / pre-2026-auto-migration-orphan) and remediate per Phase 2.1.5 runbook. Document each in audit report. (OPERATOR — depends on 2.1 output)
- [x] 2.2 Add CI step to `reusable-release.yml` to re-run audit on PR-A merge and upload artifact.

## Phase 3: Legal corpus (8 files)

- [x] 3.1 Edit `docs/legal/data-protection-disclosure.md` §2.3(m) + bump Last Updated.
- [x] 3.2 Edit `docs/legal/privacy-policy.md` §5.10 + bump Last Updated.
- [x] 3.3 Edit `docs/legal/gdpr-policy.md` operational-telemetry + bump Last Updated.
- [x] 3.4 Mirror 3.1 edits to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.
- [x] 3.5 Mirror 3.2 edits to `plugins/soleur/docs/pages/legal/privacy-policy.md`.
- [x] 3.6 Mirror 3.3 edits to `plugins/soleur/docs/pages/legal/gdpr-policy.md`.
- [x] 3.7 Edit `knowledge-base/legal/article-30-register.md` PA8 §(c) + bump YAML `last_reviewed`.
- [x] 3.8 Edit `knowledge-base/legal/compliance-posture.md` Active Compliance Items row.
- [x] 3.9 Run source/mirror diff verification (Phase 3 verification block).

## Phase 4: Cron monitor wiring (9 workflows)

- [x] 4.1 `scheduled-terraform-drift.yml` — add 3 check-in steps.
- [x] 4.2 `scheduled-oauth-probe.yml` — add 3 check-in steps.
- [x] 4.3 `scheduled-cf-token-expiry-check.yml` — add 3 check-in steps.
- [x] 4.4 `scheduled-github-app-drift-guard.yml` — add 3 check-in steps.
- [x] 4.5 `scheduled-daily-triage.yml` — add 3 check-in steps.
- [x] 4.6 `scheduled-realtime-probe.yml` — add 3 check-in steps.
- [x] 4.7 `scheduled-skill-freshness.yml` — add 3 check-in steps.
- [x] 4.8 `scheduled-content-vendor-drift.yml` — add 3 check-in steps.
- [x] 4.9 `scheduled-community-monitor.yml` — add 3 check-in steps.

## Phase 5: Terraform onramp

- [x] 5.1 Create `apps/web-platform/infra/sentry/` root: `versions.tf`, `main.tf`, `variables.tf`, `issue-alerts.tf`, `cron-monitors.tf`, `README.md`.
- [x] 5.2 Fill `cron-monitors.tf` per-workflow grace-period table (Phase 0.3 outputs).
- [x] 5.3 Document import rollback in `README.md` (terraform state rm matrix).
- [x] 5.4 Write ADR-031 at `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`.
- [x] 5.5 Create `.github/workflows/apply-sentry-infra.yml` (auto-applies cron-monitor resources on push-to-main).
- [ ] 5.6 File Phase 7 deprecation tracking issue at commit time with `blocked-on:next-release-cycle` label. (OPERATOR — `gh issue create`)

## Phase 6: GDPR-gate

- [x] 6.1 Run `/soleur:gdpr-gate` on full PR diff. Capture outcome in audit artifact.
- [x] 6.2 Address any Critical findings inline.

## Pre-merge ACs

- [x] AC1: Phase 0 artifacts captured.
- [x] AC2: Audit script test suite passes.
- [ ] AC3: Audit report committed with zero open orphans. (Blocks on 2.1 OPERATOR step; ship-ready after operator runs the script.)
- [x] AC4: Legal corpus grep counts match (all 1s, plus YAML last_reviewed).
- [x] AC5: 9 workflows have curl-pattern check-in steps.
- [ ] AC6: 3 new repo secrets exist. (Blocks on 0.8 OPERATOR step.)
- [x] AC7: Terraform fmt + validate pass.
- [x] AC8: ADR-031 committed.
- [x] AC9: sentry-scrub.ts unchanged.
- [x] AC10: GDPR-gate PASS.
- [ ] AC11: PR body uses `Ref #3814` + `Closes #3236`. (Done at /ship time.)
- [x] AC12: operator-keyed grep invariant preserved.

## Post-merge operator ACs

- [ ] AC13: terraform import 4 issue-alert rules; plan no-op. (OPERATOR)
- [ ] AC14: auto-apply workflow (Phase 5.5) creates 9 cron monitors. Verify via API GET. (OPERATOR — first push-to-main triggers)
- [ ] AC15: first scheduled run of each workflow produces recognized check-in. (OPERATOR — natural cron firing post-merge)
- [ ] AC16: one full production release cycle ships under Terraform management. (OPERATOR)
- [ ] AC17: manually `gh issue close 3814`; proceed to Phase 7 PR-B. (OPERATOR)
