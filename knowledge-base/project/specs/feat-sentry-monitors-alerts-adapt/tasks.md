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

- [ ] 0.1 Verify `jianyuan/terraform-provider-sentry` v0.15.0-beta2 latest via `gh api`. Pin in `versions.tf`.
- [ ] 0.1.5 DE-region smoke test against scratch project per Phase 0.1.5 of plan. If fails, abort Phase 5 and switch to DHH escape hatch.
- [ ] 0.2 Capture 4 dashboard-keyed alert rule names byte-for-byte from `configure-sentry-alerts.sh`. Persist to audit report.
- [ ] 0.3 Verify 9 scheduled-workflow filenames exist on main. Capture observed median duration per workflow via `gh run list` (feeds R3 grace-period table).
- [ ] 0.4 Document Doppler vs GitHub-secret split in ADR-031 (Sentry secrets in repo secrets, R2 creds in Doppler).
- [ ] 0.5 Grep operator-keyed message strings; record current invariant.
- [ ] 0.6 Verify Eleventy mirror 3-file presence.
- [ ] 0.7 Confirm `sentry-scrub.ts` untouched.
- [ ] 0.8 Provision 3 new repo secrets: `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`. Derive from existing DSN.
- [ ] 0.9 Document local `SENTRY_AUTH_TOKEN` source for operator runs (user token vs internal integration).

## Phase 1: Audit script

- [ ] 1.1 Create `apps/web-platform/scripts/sentry-monitors-audit.sh` (modeled on `configure-sentry-alerts.sh`).
- [ ] 1.2 Create `apps/web-platform/scripts/sentry-monitors-audit.test.sh` with T1-T5 cases (env-var missing, region probe, orphan join logic, idempotency, match-by-id).
- [ ] 1.3 Script emits rule IDs as machine-readable JSON array at end of report.

## Phase 2: Run audit

- [ ] 2.1 Operator runs audit locally; report committed to `knowledge-base/legal/audits/2026-05-15-sentry-migration-audit.md`.
- [ ] 2.1.5 If non-zero orphans: classify each (monitor-no-alert / alert-no-monitor / pre-2026-auto-migration-orphan) and remediate per Phase 2.1.5 runbook. Document each in audit report.
- [ ] 2.2 Add CI step to `reusable-release.yml` to re-run audit on PR-A merge and upload artifact.

## Phase 3: Legal corpus (8 files)

- [ ] 3.1 Edit `docs/legal/data-protection-disclosure.md` §2.3(m) + bump Last Updated.
- [ ] 3.2 Edit `docs/legal/privacy-policy.md` §5.10 + bump Last Updated.
- [ ] 3.3 Edit `docs/legal/gdpr-policy.md` operational-telemetry + bump Last Updated.
- [ ] 3.4 Mirror 3.1 edits to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.
- [ ] 3.5 Mirror 3.2 edits to `plugins/soleur/docs/pages/legal/privacy-policy.md`.
- [ ] 3.6 Mirror 3.3 edits to `plugins/soleur/docs/pages/legal/gdpr-policy.md`.
- [ ] 3.7 Edit `knowledge-base/legal/article-30-register.md` PA8 §(c) + bump YAML `last_reviewed`.
- [ ] 3.8 Edit `knowledge-base/legal/compliance-posture.md` Active Compliance Items row.
- [ ] 3.9 Run source/mirror diff verification (Phase 3 verification block).

## Phase 4: Cron monitor wiring (9 workflows)

- [ ] 4.1 `scheduled-terraform-drift.yml` — add 3 check-in steps.
- [ ] 4.2 `scheduled-oauth-probe.yml` — add 3 check-in steps.
- [ ] 4.3 `scheduled-cf-token-expiry-check.yml` — add 3 check-in steps.
- [ ] 4.4 `scheduled-github-app-drift-guard.yml` — add 3 check-in steps.
- [ ] 4.5 `scheduled-daily-triage.yml` — add 3 check-in steps.
- [ ] 4.6 `scheduled-realtime-probe.yml` — add 3 check-in steps.
- [ ] 4.7 `scheduled-skill-freshness.yml` — add 3 check-in steps.
- [ ] 4.8 `scheduled-content-vendor-drift.yml` — add 3 check-in steps.
- [ ] 4.9 `scheduled-community-monitor.yml` — add 3 check-in steps.

## Phase 5: Terraform onramp

- [ ] 5.1 Create `apps/web-platform/infra/sentry/` root: `versions.tf`, `main.tf`, `variables.tf`, `issue-alerts.tf`, `cron-monitors.tf`, `README.md`.
- [ ] 5.2 Fill `cron-monitors.tf` per-workflow grace-period table (Phase 0.3 outputs).
- [ ] 5.3 Document import rollback in `README.md` (terraform state rm matrix).
- [ ] 5.4 Write ADR-031 at `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`.
- [ ] 5.5 Create `.github/workflows/apply-sentry-infra.yml` (auto-applies cron-monitor resources on push-to-main).
- [ ] 5.6 File Phase 7 deprecation tracking issue at commit time with `blocked-on:next-release-cycle` label.

## Phase 6: GDPR-gate

- [ ] 6.1 Run `/soleur:gdpr-gate` on full PR diff. Capture outcome in audit artifact.
- [ ] 6.2 Address any Critical findings inline.

## Pre-merge ACs

- [ ] AC1: Phase 0 artifacts captured.
- [ ] AC2: Audit script test suite passes.
- [ ] AC3: Audit report committed with zero open orphans.
- [ ] AC4: Legal corpus grep counts match (all 1s, plus YAML last_reviewed).
- [ ] AC5: 9 workflows have curl-pattern check-in steps.
- [ ] AC6: 3 new repo secrets exist.
- [ ] AC7: Terraform fmt + validate pass.
- [ ] AC8: ADR-031 committed.
- [ ] AC9: sentry-scrub.ts unchanged.
- [ ] AC10: GDPR-gate PASS.
- [ ] AC11: PR body uses `Ref #3814` + `Closes #3236`.
- [ ] AC12: operator-keyed grep invariant preserved.

## Post-merge operator ACs

- [ ] AC13: terraform import 4 issue-alert rules; plan no-op.
- [ ] AC14: auto-apply workflow (Phase 5.5) creates 9 cron monitors. Verify via API GET.
- [ ] AC15: first scheduled run of each workflow produces recognized check-in.
- [ ] AC16: one full production release cycle ships under Terraform management.
- [ ] AC17: manually `gh issue close 3814`; proceed to Phase 7 PR-B.
