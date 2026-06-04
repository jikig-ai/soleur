---
title: "observability: alert on KB tenant-mint reportSilentFallback rate (PIR #4913 follow-up)"
issue: 4918
type: chore
classification: observability
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
source_pir: knowledge-base/engineering/operations/post-mortems/generate-link-tenant-mint-regression-postmortem.md
date: 2026-06-04
---

# ✨ observability: alert on KB tenant-mint `reportSilentFallback` rate (#4918)

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Research Reconciliation, Observability, IaC, Risks (deepen-pass verification folded in below).

### Key Improvements (deepen-pass verifications — all live, against repo state)
1. **Premise reframe confirmed (R1).** `failure_issue_threshold` exists only on `sentry_cron_monitor`/`sentry_uptime_monitor` (`cron-monitors.tf`), NOT on `sentry_issue_alert` — verified via `grep`. Issue-alert first-occurrence paging = `conditions_v2` triad + `action_match="any"`, the proven `chat_message_save_failure`/`workspace_sync_health` shape.
2. **Op enumeration confirmed (R3).** Verify-the-negative pass: the ONLY `reportSilentFallback`/`warnSilentFallback`/`infoSilentFallback` emits carrying `feature: "kb-route-helpers"` are the 6 ops named in R3 (3 tenant-mint + `workspace-sync-*` + 3 `self-heal-*` + `kb-sync.unexpected`). `op: "delete"` (kb-route-helpers.ts:430) is a TS type-union literal, NOT an emit; `op: "manual"` (sync/route.ts:117) is an unrelated structured-log call — neither is a tenant-mint emit. The feature-only vs op-scoped decision stands: **op IS_IN is mandatory.**
3. **Third sibling op confirmed (R2).** `kb-sync.tenant-mint` (sync/route.ts:60) is the identical `RuntimeAuthError → 503` class — folded into the IS_IN filter.
4. **Apply-workflow shape confirmed.** `apply-sentry-infra.yml` produces `-out=tfplan` (plan step, targets at lines 186-217) and the apply step runs `terraform apply tfplan` (line 268) — it reuses the saved plan and does NOT re-list targets. So a single `-target=` add in the plan block is sufficient (one edit, not two). This matches the saved-plan AC-grep expectation: `-target=` appears in the plan step only.
5. **Frequency 12 free (R6), payload PII-safe.** Taken set `5,10,11,15,30,60,61,62`; `12` free. `observability.ts:200` pseudonymizes `userId → userIdHash` (Recital 26) at the emit boundary; events carry only hashed id + op + pg_code — no raw userId, no content, so the IssueOwners→ActiveMembers fallthrough is safe at N=1.

### Precedent-Diff (Phase 4.4)
The alert is a pattern-bound resource with an exact in-repo precedent — `sentry_issue_alert.chat_message_save_failure` (issue-alerts.tf:349-396): same `action_match="any"`, `filter_match="all"`, `conditions_v2` triad, `tagged_event` feature EQUAL + op IS_IN, `actions_v2` IssueOwners→ActiveMembers, `lifecycle.ignore_changes=[environment]`. This plan mirrors it byte-for-byte, differing only in `name`, `frequency` (12), feature value (`kb-route-helpers`), and the 3 op slugs. **Not novel — strong precedent.** No new scheduled job (no Inngest/cron precedent check needed).

## Overview

PR #4913 fixed the KB Generate-link regression by adding a service-role fallback when the tenant-JWT mint fails — but the PIR ([generate-link-tenant-mint-regression-postmortem.md](../../engineering/operations/post-mortems/generate-link-tenant-mint-regression-postmortem.md)) names the *root durability gap*: the failure emitted a `reportSilentFallback` Sentry signal on every mint failure, yet **no alert routed it to attention**, so a Sentry-visible signal sat latent for ~19 days until the founder hit the dead button while dogfooding.

This plan wires a single **Sentry issue alert** (`sentry_issue_alert`) that pages on the first occurrence of a KB tenant-mint `reportSilentFallback` event, closing the operator-blind-zone for this regression class. It is a pure IaC + observability change against the already-provisioned `apps/web-platform/infra/sentry/` Terraform root, mirroring the `chat_message_save_failure` (#4849) and `workspace_sync_health` (#4882) alert precedents byte-for-byte.

**Why an issue alert, not a cron/uptime monitor:** the signal is an *event* (`Sentry.captureException` with `feature`/`op` tags), not a missed scheduled check-in. The issue text's `failure_issue_threshold = 1` is a `sentry_cron_monitor` / `sentry_uptime_monitor` attribute and does not exist on `sentry_issue_alert` (see Research Reconciliation R1). The issue-alert equivalent of "auto-page on the first occurrence" is `conditions_v2 = [{ first_seen_event = {} }, { reappeared_event = {} }, { regression_event = {} }]` with `action_match = "any"` — the exact shape the two precedent alerts use. This delivers the intent of `failure_issue_threshold = 1` (page on the very first event, re-page on recurrence after resolve) per `hr-observability-as-plan-quality-gate` and `hr-no-dashboard-eyeball-pull-data-yourself`.

## Research Reconciliation — Spec vs. Codebase

| Issue/PIR claim | Reality (verified in repo) | Plan response |
|---|---|---|
| R1: "Alert must auto-page (`failure_issue_threshold = 1`)" | `failure_issue_threshold` is a `sentry_cron_monitor`/`sentry_uptime_monitor` attribute (`cron-monitors.tf:70…526`). `sentry_issue_alert` has **no such attribute**; first-occurrence paging is expressed via `conditions_v2 = [{first_seen_event={}}, {reappeared_event={}}, {regression_event={}}]` + `action_match="any"`. | Reframe the requirement to the issue-alert equivalent. Use the `chat_message_save_failure`/`workspace_sync_health` conditions_v2 triad. AC asserts the triad, not the literal `failure_issue_threshold`. |
| R2: Issue names two ops: `resolveUserKbRoot.tenant-mint` + `authenticateAndResolveKbPath.tenant-mint` | **A third sibling tenant-mint op exists**: `kb-sync.tenant-mint` at `app/api/kb/sync/route.ts:60-65` — identical `RuntimeAuthError → 503` mint-failure class, same regression class, same user-invisible dead-end. | **Fold `kb-sync.tenant-mint` into the `op IS_IN` filter.** At brand-survival threshold `single-user incident`, scoping out the next-most-likely sibling is anti-pattern (AGENTS.md). The alert exists to catch the mint-failure class; all three ops ARE that class. |
| R3: `feature: "kb-route-helpers"` is dedicated to tenant-mint | **False — 6 distinct ops** carry `feature: "kb-route-helpers"`: the 3 tenant-mint ops above PLUS `workspace-sync-${context.op}` (kb-route-helpers.ts:448), `self-heal-aborted-dirty/reset/failed` (:530/:557/:570), `kb-sync.unexpected` (sync/route.ts:40). | **Must filter by `op IS_IN`, NOT feature-only.** A feature-only filter (the `workspace_sync_health` shape) would page on unrelated self-heal/workspace-sync events. Use the `chat_message_save_failure` op-scoped shape. |
| R4: alert is "import-only" like the 4 auth rules | The 4 auth rules are import-only (mirror legacy script rules); the 2 BYOK rules + chat + workspace-sync rules are **apply-created** from real `conditions_v2`/`filters_v2`. No pre-existing Sentry rule for KB tenant-mint. | This is an **apply-created** rule (no import). `conditions_v2`/`filters_v2`/`actions_v2` are the source of truth (NOT under `ignore_changes`); only `environment` is ignored. Must be added to BOTH `-target` blocks in `apply-sentry-infra.yml`. |
| R5: `reportSilentFallback` emits the `feature`/`op` tags the filter needs | Verified: `observability.ts:188-189` sets `tags = { feature }; if (op) tags.op = op;` then `Sentry.captureException(err, { tags, … })` (`:220`). `RuntimeAuthError extends Error` → captureException path. | Tags `feature` + `op` are queryable in Sentry exactly as the `tagged_event` filter expects. No app-code change required. |
| R6: free Sentry alert `frequency` value | Taken set in `issue-alerts.tf`: `5,10,11,15,30,60,61,62`. Sentry dedups POST-time on action-shape+frequency+match (not conditions) — needs a unique value. | Use `frequency = 12` (free). Not evaluated by lifecycle-condition rules but must be unique to dodge create-time dedup. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing changes for the end user directly (this is an observability layer); but the *operator* stays blind to a recurring KB tenant-mint failure — the exact ~19-day latent-regression failure mode the PIR documents. A broken/silent alert recreates the operator-blind-zone for KB Generate-link / KB upload / KB sync.

**If this leaks, the user's data/workflow is exposed via:** the alert payload carries only the pseudonymized `userIdHash` (Recital-26 hashed at the emit boundary, `observability.ts:hashExtraUserId`), the `op` slug, and `pg_code` — no raw userId, no document content, no share token. The notify-email fallthrough (`IssueOwners → ActiveMembers`) over-discloses only to active Sentry seats; with a solo founder this is correct. There is **no cross-tenant content** in these events (unlike the BYOK Art-33 rule), so the fallthrough does not over-disclose at N=1.

**Brand-survival threshold:** single-user incident — carried forward from the source PIR frontmatter (`brand_survival_threshold: single-user incident`). The tenant-zero founder is the primary affected user; a silently-broken core sharing feature for the founder is the brand-survival cost this alert guards.

> **CPO sign-off required at plan time before `/work` begins.** Confirm CPO has reviewed (or is covered by the Phase 2.5 Domain Review carry-forward) before implementation. `user-impact-reviewer` will be invoked at review-time.

## Goals

1. A `sentry_issue_alert.kb_tenant_mint_silent_fallback` resource in `apps/web-platform/infra/sentry/issue-alerts.tf` that pages on the first occurrence of any KB tenant-mint `reportSilentFallback` event.
2. The alert filters on `feature == "kb-route-helpers"` AND `op IS_IN {resolveUserKbRoot.tenant-mint, authenticateAndResolveKbPath.tenant-mint, kb-sync.tenant-mint}` — scoped to the mint-failure class, excluding the unrelated self-heal / workspace-sync / unexpected ops.
3. The alert is wired into BOTH the `terraform plan` and `terraform apply` `-target` blocks of `.github/workflows/apply-sentry-infra.yml` (apply-created, not import-only).
4. A cross-artifact op/feature contract test (`sentry-kb-tenant-mint-alert-op-contract.test.ts`) pins the 3 op slugs + feature tag in both the emit sites and the tf filter, so a rename of either breaks CI instead of silently zeroing the alert's matches.
5. PIR follow-up checkbox (line 138) ticked; issue #4918 closed.

## Non-Goals

- **Applying the alert to prod.** The `apply-sentry-infra.yml` workflow auto-applies on merge to `main` (path-filtered on `apps/web-platform/infra/sentry/**`). No operator SSH / dashboard step. Verification is read-only via the workflow run + `gh`/Sentry API (see Observability §discoverability_test).
- **User-facing error toast on a genuine share 503** (PIR follow-up line 139) — separate concern, separate issue if pursued.
- **Mint-failure resilience for `authenticateAndResolveKbPath`** (PIR follow-up line 137 / #4914) — already filed/tracked; out of scope here. This plan only ADDS the alert; #4914 is the fallback behavior.
- **Migrating `sentry_issue_alert` → `sentry_alert`** — blocked on provider GA (#4610), see issue-alerts.tf header.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf` — add `resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback"` (apply-created shape mirroring `chat_message_save_failure`: `action_match="any"`, `filter_match="all"`, `frequency=12`, `conditions_v2` triad, `filters_v2` = feature EQUAL + op IS_IN 3-slug, `actions_v2` IssueOwners→ActiveMembers, `lifecycle.ignore_changes=[environment]`).
- `.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_issue_alert.kb_tenant_mint_silent_fallback` to BOTH the `terraform plan` target block (after :217) AND ensure the `terraform apply tfplan` at :268 consumes the same plan (it applies the saved `tfplan`, so the single `-target` add in the plan block suffices — **verify** the apply step reuses `tfplan` and does not re-list targets).
- `knowledge-base/engineering/operations/post-mortems/generate-link-tenant-mint-regression-postmortem.md` — tick the follow-up checkbox at line 138 (`[ ]` → `[x]`) and update the Action Items note to cite #4918 as filed/landed.

## Files to Create

- `apps/web-platform/test/sentry-kb-tenant-mint-alert-op-contract.test.ts` — cross-artifact contract test mirroring `sentry-chat-alert-op-contract.test.ts`. Reads `infra/sentry/issue-alerts.tf` + `server/kb-route-helpers.ts` + `app/api/kb/sync/route.ts`; asserts (a) `feature == "kb-route-helpers"` present in both emit + tf, (b) each of the 3 op slugs present in its emit file AND in the tf filter, (c) the tf binds the 3 slugs into one comma-joined `IS_IN` value, (d) the tf declares `resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback"`.

## Open Code-Review Overlap

None — verified `gh issue list --label code-review --state open` against the planned file paths returns no matches. (To be re-run at Step 2 against the finalized file list.)

## Implementation Phases

### Phase 0 — Preconditions (verify before writing)
1. `terraform providers schema -json` (or read existing precedent) confirms `conditions_v2` accepts `first_seen_event`/`reappeared_event`/`regression_event` and `filters_v2.tagged_event.match` accepts `IS_IN` — both already proven in `byok_cap_exceeded` / `chat_message_save_failure` (no re-verify needed; cite those resources).
2. Confirm frequency `12` is free (taken: `5,10,11,15,30,60,61,62`).
3. Confirm `apply-sentry-infra.yml` apply step (:268) applies the saved `tfplan` and does not maintain a SEPARATE target list — grep the apply step. If it re-lists targets, edit both blocks.

### Phase 1 — Write the contract test (RED)
Create `sentry-kb-tenant-mint-alert-op-contract.test.ts`. It fails initially (the tf resource + op-in-filter do not yet exist).

### Phase 2 — Add the alert resource (GREEN)
Add the `kb_tenant_mint_silent_fallback` block to `issue-alerts.tf` with the op-scoped 3-slug `IS_IN` filter. Re-run the contract test → green.

### Phase 3 — Wire the apply workflow
Add the `-target` to `apply-sentry-infra.yml`. Run `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` (already allow-lists `sentry_issue_alert` — confirm still green) and `terraform validate` / `terraform fmt -check` in the sentry root.

### Phase 4 — PIR follow-up + issue close
Tick PIR line 138, update Action Items note, ensure PR body uses `Closes #4918` (this is a pre-merge code change, not an ops-remediation, so `Closes` is correct — the alert ships at merge, not via a post-merge operator apply; the auto-apply workflow handles prod).

## Acceptance Criteria

### Pre-merge (PR)
- [x] `issue-alerts.tf` declares `resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback"` with `action_match = "any"`, `filter_match = "all"`, `frequency = 12`.
- [x] `conditions_v2` contains exactly `first_seen_event`, `reappeared_event`, `regression_event` (the first-occurrence + recurrence triad — the issue-alert equivalent of `failure_issue_threshold = 1`).
- [x] `filters_v2` contains a `tagged_event` with `key="feature" match="EQUAL" value="kb-route-helpers"` AND a `tagged_event` with `key="op" match="IS_IN" value="resolveUserKbRoot.tenant-mint,authenticateAndResolveKbPath.tenant-mint,kb-sync.tenant-mint"` (the comma-joined 3-slug value, verified as one literal string).
- [x] `actions_v2` = `notify_email { target_type="IssueOwners" fallthrough_type="ActiveMembers" }`; `lifecycle.ignore_changes = [environment]`.
- [x] `apply-sentry-infra.yml` `terraform plan` `-target` block includes `-target=sentry_issue_alert.kb_tenant_mint_silent_fallback` (and the apply step consumes the same `tfplan`).
- [x] `apps/web-platform/test/sentry-kb-tenant-mint-alert-op-contract.test.ts` passes: all 3 op slugs + feature tag present in BOTH emit sites and tf filter; the 3-slug `IS_IN` value present as one literal.
- [x] `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` exits 0 (issue_alert still in allow-list scope).
- [x] `terraform fmt -check` and `terraform validate` pass in `apps/web-platform/infra/sentry/` (the deprecation warning on `sentry_issue_alert` is EXPECTED — see file header).
- [x] webplat vitest shard green for the new test (`./node_modules/.bin/vitest run test/sentry-kb-tenant-mint-alert-op-contract.test.ts` from `apps/web-platform/`).
- [x] PIR line 138 checkbox is `[x]`; PR body says `Closes #4918`.

### Post-merge (operator)
- [ ] None requiring manual action. `apply-sentry-infra.yml` auto-applies on merge (path-filtered `on.push` to `apps/web-platform/infra/sentry/**`). **Automation: feasible — handled by the existing auto-apply workflow.** Verify via `gh run watch` on the triggered apply run (see Observability discoverability_test) — no SSH, no dashboard eyeballing.

## Observability

```yaml
liveness_signal:
  what: "sentry_issue_alert.kb_tenant_mint_silent_fallback fires on first KB tenant-mint reportSilentFallback event"
  cadence: "event-driven (on any RuntimeAuthError mint failure in the 3 KB ops)"
  alert_target: "Sentry IssueOwners → ActiveMembers (solo founder)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf"
error_reporting:
  destination: "Sentry (captureException) + pino mirror (Better Stack) via reportSilentFallback"
  fail_loud: true
failure_modes:
  - mode: "tenant-mint RuntimeAuthError on resolveUserKbRoot (Generate-link / KB read)"
    detection: "feature=kb-route-helpers op=resolveUserKbRoot.tenant-mint Sentry event"
    alert_route: "kb_tenant_mint_silent_fallback issue alert → email"
  - mode: "tenant-mint RuntimeAuthError on authenticateAndResolveKbPath (file PATCH/DELETE)"
    detection: "feature=kb-route-helpers op=authenticateAndResolveKbPath.tenant-mint Sentry event"
    alert_route: "kb_tenant_mint_silent_fallback issue alert → email"
  - mode: "tenant-mint RuntimeAuthError on kb-sync (POST /api/kb/sync)"
    detection: "feature=kb-route-helpers op=kb-sync.tenant-mint Sentry event"
    alert_route: "kb_tenant_mint_silent_fallback issue alert → email"
  - mode: "alert silently zeroed by op-slug or feature-tag rename drift"
    detection: "sentry-kb-tenant-mint-alert-op-contract.test.ts fails in CI"
    alert_route: "CI red on PR"
logs:
  where: "Sentry issues (tag: feature=kb-route-helpers, op IS_IN 3 slugs) + container stdout (pino) → Better Stack"
  retention: "Sentry plan default; Better Stack log retention default"
discoverability_test:
  command: "gh run list --workflow=apply-sentry-infra.yml --limit 1 --json conclusion,databaseId && gh run watch <id>  # then, optionally, query the Sentry rules API for the rule by name via configure-sentry-alerts.sh pattern"
  expected_output: "apply-sentry-infra run conclusion=success; sentry_issue_alert.kb_tenant_mint_silent_fallback present in tf state / Sentry rules list"
```

## Infrastructure (IaC)

This plan modifies the already-provisioned `apps/web-platform/infra/sentry/` Terraform root (R2 backend per the existing root). No new vendor, server, secret, or persistent process.

### Terraform changes
- Files: `apps/web-platform/infra/sentry/issue-alerts.tf` (add one `sentry_issue_alert` resource). Provider already pinned: `jianyuan/sentry` `0.15.0-beta2` (`versions.tf:10`). Required vars unchanged (`sentry_org`, the `data.sentry_project.web_platform` data source). No new sensitive variables.

### Apply path
- **(a) apply-created via the existing auto-apply workflow.** `apply-sentry-infra.yml` runs `terraform plan -target=… -out=tfplan` then `terraform apply tfplan` on merge to `main` (path-filtered). The new `-target` scopes the apply to this resource + the existing monitor/alert set. No taint, no replace, no downtime — pure resource create. Blast radius: one new Sentry rule; the 4 import-only auth rules are untouched (their `-target`s are not in the untargeted apply path).

### Distinctness / drift safeguards
- `dev != prd`: the Sentry root targets the single Sentry org/project (`var.sentry_org`); there is no dev/prd split for Sentry monitoring infra (it observes prod). No `dev`-vs-`prd` precondition applies.
- `lifecycle.ignore_changes = [environment]` only (matches the apply-created BYOK/chat/workspace rules) — `conditions_v2`/`filters_v2`/`actions_v2` are the source of truth and must NOT be ignored (the whole point of the rule).
- State: `terraform.tfstate` in the R2 backend; no secret values land in state for this resource (alert config only).

### Vendor-tier reality check
- `sentry_issue_alert` (issue alerts) is available on the project's Sentry tier — already in use by 8 existing rules in this file. No paid-tier gate needed (unlike `betteruptime_policy`). The `sentry_alert` (v2) migration is deferred to provider GA (#4610), not relevant here.

## Domain Review

**Domains relevant:** Product (observability/operator-experience axis), Engineering/CTO (IaC).

### Engineering / CTO

**Status:** reviewed (carry-forward from PIR + this plan's IaC analysis)
**Assessment:** Pure additive IaC against a well-established precedent (`chat_message_save_failure`, `workspace_sync_health`). The op-scoping decision (IS_IN vs feature-only) is the single load-bearing design choice and is grounded in the 6-op enumeration (R3). The third sibling op `kb-sync.tenant-mint` (R2) is the highest-value plan-time catch. No new failure surface introduced; the alert is read-only observability.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no user-facing surface. This is operator-facing observability infra (Sentry rule + Terraform + test). No `components/**`, `app/**/page.tsx`, or UI-surface file in Files to Edit/Create.
**Pencil available:** N/A (no UI surface)

## Risks & Mitigations

- **Risk: op-slug drift silently zeroes the alert.** Mitigation: the contract test pins all 3 slugs in both emit + tf (the `chat`/`workspace-sync` precedent pattern). A rename breaks CI.
- **Risk: feature-only filter pages on unrelated kb-route-helpers ops** (self-heal, workspace-sync). Mitigation: `op IS_IN` 3-slug scoping (R3). Verified the 6-op enumeration.
- **Risk: missing the third sibling `kb-sync.tenant-mint`.** Mitigation: folded into the filter (R2); enumerated all `feature: "kb-route-helpers"` emit sites via grep.
- **Risk: frequency collision triggers Sentry POST-time exact-duplicate dedup.** Mitigation: `frequency = 12`, verified free against the taken set (R6).
- **Risk: apply workflow applies a stale plan or re-lists targets.** Mitigation: Phase 0.3 greps the apply step to confirm it consumes the saved `tfplan`; if it re-lists, edit both blocks.
- **Risk: `notify_email` fallthrough over-discloses at N>1 seats.** Mitigation: accepted N=1 risk (mirrors the 8 existing rules); these events carry NO cross-tenant content (only hashed userId + op + pg_code), so even the fallthrough is safe. Revisit `target_type="Member"` before the first non-founder Sentry seat (same note as `chat_message_save_failure:378-383`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6. This plan's section is filled with threshold `single-user incident` (carried from the PIR).
- The issue's `failure_issue_threshold = 1` is a **cron/uptime-monitor** attribute, NOT an issue-alert attribute — do not add it to the `sentry_issue_alert` block (it will fail `terraform validate`). The issue-alert equivalent is the `conditions_v2` triad. (R1)
- `feature: "kb-route-helpers"` spans 6 ops — a feature-only filter would over-page. MUST use `op IS_IN`. (R3)
- There is a THIRD tenant-mint op (`kb-sync.tenant-mint`) the issue body did not name. (R2)
- The `terraform validate` deprecation warning on `sentry_issue_alert` is EXPECTED (provider beta2; GA migration deferred to #4610) — do not treat it as a regression, do not migrate to `sentry_alert`.

## Provenance / References

- Source PIR: `knowledge-base/engineering/operations/post-mortems/generate-link-tenant-mint-regression-postmortem.md` (PR #4913, follow-up line 138).
- Precedent alerts: `apps/web-platform/infra/sentry/issue-alerts.tf` — `chat_message_save_failure` (#4849, lines 329-396), `workspace_sync_health` (#4882, lines 398-459), `byok_cap_exceeded` (#4364, op IS_IN pattern, lines 288-327).
- Precedent contract test: `apps/web-platform/test/sentry-chat-alert-op-contract.test.ts`.
- Emit sites: `server/kb-route-helpers.ts:105` (authenticateAndResolveKbPath), `:269` (resolveUserKbRoot); `app/api/kb/sync/route.ts:60` (kb-sync).
- `reportSilentFallback` tag emit: `server/observability.ts:183-235`.
- Apply workflow: `.github/workflows/apply-sentry-infra.yml` (plan targets :186-217, apply :268).
- Scope guard: `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` (already allow-lists `sentry_issue_alert`).
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`.
