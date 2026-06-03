---
feature: kb-sync-health-alert-rule
issue: 4882
lane: single-domain
plan: knowledge-base/project/plans/2026-06-03-feat-kb-sync-health-alert-rule-plan.md
---

# Tasks: Sentry alert rule for workspace-sync-health findings

## Phase 1 — Alert resource (RED → GREEN)

- [ ] 1.1 Create `apps/web-platform/test/sentry-workspace-sync-health-alert-op-contract.test.ts` (sibling of `sentry-chat-alert-op-contract.test.ts`); pin `FEATURE_TAG = "workspace-sync-health"` present in both `server/inngest/functions/cron-workspace-sync-health.ts` (the `SENTRY_FEATURE` const) and `infra/sentry/issue-alerts.tf` (the feature filter value). No op-set assertion. Test is RED.
- [ ] 1.2 Append `resource "sentry_issue_alert" "workspace_sync_health"` to `apps/web-platform/infra/sentry/issue-alerts.tf`, mirroring `chat_message_save_failure` but with a single `feature EQUAL "workspace-sync-health"` filter (no `op` filter), `frequency = 11`, lifecycle triad conditions, `notify_email` IssueOwners→ActiveMembers, `lifecycle { ignore_changes = [environment] }`. Multi-line block style. Add a header comment (feature/op contract + anti-fatigue + frequency rationale).
- [ ] 1.3 `terraform fmt` the file and commit the formatted result. Contract test is GREEN.

## Phase 2 — Wire auto-apply

- [ ] 2.1 Add `-target=sentry_issue_alert.workspace_sync_health \` to the `terraform plan` target list in `.github/workflows/apply-sentry-infra.yml`, immediately after the `chat_message_save_failure` target (≈line 215).
- [ ] 2.2 Run `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` → exits 0 (no new resource type; `sentry_issue_alert` already allowed).

## Phase 3 — Validate (Acceptance Criteria)

- [ ] 3.1 AC1: `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-workspace-sync-health-alert-op-contract.test.ts` passes.
- [ ] 3.2 AC2: `terraform fmt -check` + `terraform validate` clean in `apps/web-platform/infra/sentry/`.
- [ ] 3.3 AC4: `grep -c 'sentry_issue_alert.workspace_sync_health' .github/workflows/apply-sentry-infra.yml` == 1.
- [ ] 3.4 AC5: `grep -cE 'frequency\s*=\s*11\b' apps/web-platform/infra/sentry/issue-alerts.tf` == 1.
- [ ] 3.5 AC3 (spec): `filters_v2` has exactly one filter (`feature EQUAL workspace-sync-health`), no `op` filter.
- [ ] 3.6 Run the full test gate (per `package.json scripts.test`) to confirm no regressions.

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Closes #4882` + `## Changelog` section; `semver:patch` label (observability config, no new component).
- [ ] 4.2 Post-merge (automated): verify the `apply-sentry-infra.yml` run reports `Plan: 1 to add, 0 to change, 0 to destroy` and applies cleanly via `gh run view` (AC6).
