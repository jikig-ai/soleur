---
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-30-sentry-byok-alert-rules.md
issue: "#4364"
---

# Tasks — Sentry BYOK Alert Rules (#4364)

Derived from `2026-05-30-sentry-byok-alert-rules.md`. Extends the existing
terraform IaC root `apps/web-platform/infra/sentry/` — do NOT write a TS script.

## Phase 0a — Substrate gap (CPO decision gate, blocks Rule 1)

PR-A does NOT emit `art_33_breach` / `op=cross-tenant-violation` (verified zero on
origin/main). Rule 1's filter has no signal until this is closed.

- [ ] 0a.1 CPO ack: choose 0a (add emission in this PR) vs 0b (ship Rule 2 only,
      follow-up for Rule 1). Default recommendation: 0a.
- [ ] 0a.2 (if 0a) RED: test in `apps/web-platform/test/server/` asserting a
      cross-tenant P0001 raise yields a Sentry event tagged
      `op=cross-tenant-violation` + `art_33_breach=true`.
- [ ] 0a.3 (if 0a) Extend `SilentFallbackOptions` with `art33Breach?: boolean` →
      `tags.art_33_breach = "true"` in `server/observability.ts` (both
      `reportSilentFallback` and `warnSilentFallback`); add a distinct
      cross-tenant branch in `server/cost-writer.ts` emitting
      `op: "cross-tenant-violation", art33Breach: true` (currently swallowed by
      `op: "merged-rpc-failure"`). GREEN.
- [ ] 0a.4 (if 0b) Re-scope Rule 1 to a follow-up issue; ship Rule 2 only.

## Phase 0 — Schema verify (mandatory before writing any HCL)

- [ ] 0.1 `cd apps/web-platform/infra/sentry && terraform init -input=false`
      (needs `SENTRY_AUTH_TOKEN` GitHub-secret value exported locally + R2 creds
      from Doppler `prd_terraform` per README §Local invocation).
- [ ] 0.2 `terraform providers schema -json | jq '.provider_schemas[].resource_schemas.sentry_issue_alert'`
      — read exact beta2 nested-attribute names for `conditions_v2`,
      `filters_v2` (key/match/value + `match` enum: is `is_in` supported?),
      `actions_v2`. Pin the output in the work log.
- [ ] 0.3 Determine available action objects on the `jikigai-eu` org (Slack /
      PagerDuty integration vs `notify_email`-only). Choose Rule 1 (high) and
      Rule 2 (low) action targets; if no integration, both use `notify_email`
      (still distinct via filters+frequency).
- [ ] 0.4 Decide `is_in` vs `filter_match="any"`+two-`eq` for Rule 2's cap-op set.

## Phase 1 — Add terraform resources

- [ ] 1.1 Add `sentry_issue_alert.byok_art_33_breach` to `issue-alerts.tf`:
      `feature = byok-delegations` AND `art_33_breach = true` tagged-event
      filters; `frequency = 5`; high-urgency action; CREATE (NOT import-only).
- [ ] 1.2 Add `sentry_issue_alert.byok_cap_exceeded` to `issue-alerts.tf`:
      `feature = byok-delegations` AND `op IN {hourly-cap-exceeded,
      daily-cap-exceeded}`; `frequency = 15`; lower-urgency action; CREATE.
- [ ] 1.3 Verify tag literals against `apps/web-platform/server/cost-writer.ts:136-146`
      (`emitDelegationEvent`: feature/op/art_33_breach setTag + fatal/warning/info levels).

## Phase 2 — Wire the apply workflow

- [ ] 2.1 Add `-target=sentry_issue_alert.byok_art_33_breach` and
      `-target=sentry_issue_alert.byok_cap_exceeded` to the apply step in
      `.github/workflows/apply-sentry-infra.yml` (else silent no-op — the 4
      auth rules' import-only `-target` scoping currently excludes all alerts).

## Phase 3 — Docs + validate

- [ ] 3.1 Update `apps/web-platform/infra/sentry/README.md` inventory
      ("4 issue alerts" → "6: 4 import-only auth + 2 apply-created BYOK").
- [ ] 3.2 `terraform fmt` + `terraform validate` (accept the known
      `sentry_issue_alert` deprecation warning; expect zero errors).
- [ ] 3.3 `terraform plan` → asserts `2 to add, 0 to change, 0 to destroy`.

## Phase 4 — Ship + post-merge verify

- [ ] 4.1 PR body `Closes #4364`; split AC into Pre-merge / Post-merge(operator).
- [ ] 4.2 Post-merge: `apply-sentry-infra.yml` fires (push path-filter
      `infra/sentry/**`); confirm run log prints "2 added".
- [ ] 4.3 Discoverability test (read-only, no synthetic prod event):
      `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/rules/" | jq '[.[]|select(.name|test("BYOK"))]|length'`
      → expect `2`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 `issue-alerts.tf` contains 2 new `sentry_issue_alert` resources with
      the verified tag filters and distinct frequencies (5, 15).
- [ ] AC2 `terraform validate` passes (only the accepted deprecation warning).
- [ ] AC3 `terraform plan` shows `2 to add, 0 to change, 0 to destroy`.
- [ ] AC4 `apply-sentry-infra.yml` apply step includes both new `-target` flags.
- [ ] AC5 README inventory updated; 2 rules documented as NOT import-only.

### Post-merge (operator / CI)
- [ ] AC6 `apply-sentry-infra.yml` run succeeds; log shows 2 resources added.
- [ ] AC7 Discoverability GET returns 2 BYOK rules.
- [ ] AC8 `gh issue close 4364` after AC6/AC7 confirm (Closes #4364 in PR body
      auto-closes at merge; this is the belt-and-braces verify).
