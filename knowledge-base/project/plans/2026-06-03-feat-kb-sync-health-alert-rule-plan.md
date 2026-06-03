---
title: "feat: Sentry alert rule for workspace-sync-health findings"
type: feat
issue: 4882
branch: feat-kb-sync-health-alert-rule
pr: 4885
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-03
spec: knowledge-base/project/specs/feat-kb-sync-health-alert-rule/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-03-kb-sync-health-alert-rule-brainstorm.md
---

# feat: Sentry alert rule for workspace-sync-health findings

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Overview

Add a single `sentry_issue_alert "workspace_sync_health"` Terraform resource that
notifies the operator when the existing `cron-workspace-sync-health` daily probe
reports a diverged / stale / unreachable workspace KB clone. Closes the
notification half of the KB-sync-stale PIR (#4882): the probe + its three
detection arms already ship (#4712 / #4717, merged 2026-06-01) and emit Sentry
events with `feature=workspace-sync-health`, but no `sentry_issue_alert` rule
matches that feature, so the events land in Sentry un-notified
(`hr-no-dashboard-eyeball-pull-data-yourself`).

**No application-code change.** The cron and its emitted finding ops are
unchanged; this plan only adds an alert rule + its drift-pinning contract test,
and wires the new resource into the auto-apply `-target` set.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified on branch) | Plan response |
|---|---|---|
| FR1: add resource to `issue-alerts.tf` | `chat_message_save_failure` (issue-alerts.tf:349-396) is the exact same-class precedent | Mirror it verbatim, swapping feature/ops/frequency |
| (spec silent on apply path) | `apply-sentry-infra.yml` auto-applies a curated `-target` set; NEW issue-alerts (no Sentry rule to import) must be listed there — `byok_*` + `chat_message_save_failure` are (lines 213-215), the 4 import-only `auth_*` are not | **Add** `-target=sentry_issue_alert.workspace_sync_health` to the workflow (2nd edited file) |
| TR1: mirror `sentry-chat-alert-op-contract.test.ts` | File exists (2532 B); reads `issue-alerts.tf` + the emit-site file, asserts feature + op slugs in both, and the comma-joined IS_IN value | Create sibling test reading `cron-workspace-sync-health.ts` |
| (spec silent on scope guard) | `sentry_issue_alert` is **already** an allowed `-target` type (#4364) in `test-destroy-guard-sentry-scope-guard.sh`; `destroy-guard-filter-sentry.jq` already has its nested-clause | **No** scope-guard / jq-filter edit needed |
| Op-set scoping (spec FR2 said `op IS_IN {3 finding ops}`) | The cron emits 7 ops on `feature=workspace-sync-health`: 3 findings (`ready-null-installation`/`stale-sync-failed`/`went-quiet`) + 4 probe-failures (`scan`/`scan-stale`/`scan-went-quiet`/`went-quiet-probe`). Arms 2/3 **swallow** their own scan errors (return `{reported:0}`/`{wentQuiet:0}`); the heartbeat only keys on arm-1's scan, so a broken arm-2/3 query notifies via the probe-failure op ONLY (plan-review HIGH) | **Drop the op filter — match `feature` only.** Covers findings + probe-self-failures; future-proof; the feature tag is dedicated to this one cron so every event is operator-actionable (unlike `cc-dispatcher`). Spec FR2 superseded. |

**Premise validation:** PR #4878 MERGED (2026-06-03); #4712/#4717 MERGED (2026-06-01); `cron-workspace-sync-health.ts`, `issue-alerts.tf`, the contract test, and the apply workflow all confirmed present on branch. The bullet-1 case (`non_fast_forward`, `recovered!=true`) writes `{ok:false, error_class:'non_fast_forward'}` (`kb-route-helpers.ts:307-309`); Arm 2 fires on *any* `latest.ok===false`, so matching `op=stale-sync-failed` covers it. No stale premises.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf` — append `resource "sentry_issue_alert" "workspace_sync_health"` mirroring `chat_message_save_failure` (lines 349-396), with a header comment explaining the feature/op contract and the anti-fatigue lifecycle-condition rationale.
- `.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_issue_alert.workspace_sync_health \` to the `terraform plan` target list, immediately after `-target=sentry_issue_alert.chat_message_save_failure \` (line 215).

## Files to Create

- `apps/web-platform/test/sentry-workspace-sync-health-alert-op-contract.test.ts` — sibling of `sentry-chat-alert-op-contract.test.ts`; reads `infra/sentry/issue-alerts.tf` + `server/inngest/functions/cron-workspace-sync-health.ts`; pins the single cross-artifact contract that matters under feature-only matching: `FEATURE_TAG="workspace-sync-health"` (the cron's `SENTRY_FEATURE` const value) appears in BOTH files, so a rename on either side silently zeroing the alert is caught. No op-set assertion (matching is feature-only).

## Implementation Phases

### Phase 1 — Alert resource (RED test first)
1. Create the contract test (`Files to Create`). It fails initially: the new `feature`/op strings + IS_IN value are not yet in `issue-alerts.tf`.
2. Add the `workspace_sync_health` resource to `issue-alerts.tf`. **Match `feature` only** — unlike the `cc-dispatcher` precedent (whose feature spans many unrelated ops, forcing op-scoping), this feature tag is dedicated to this one cron and *every* event it emits (findings AND probe-self-failures) is operator-actionable, so no `op` filter is needed; this also future-proofs against new cron arms and covers the swallowed arm-2/3 scan errors the heartbeat misses (plan-review HIGH finding). Use **multi-line block style** matching the siblings so `terraform fmt -check` (AC2) passes — run `terraform fmt` and commit the formatted result:
   ```hcl
   resource "sentry_issue_alert" "workspace_sync_health" {
     organization = var.sentry_org
     project      = data.sentry_project.web_platform.slug
     name         = "workspace-sync-health"
     action_match = "any"
     filter_match = "all"
     # Distinct frequency dodges Sentry POST-time exact-duplicate dedup (taken by
     # siblings: 5,10,15,30,60,61,62). Not evaluated by lifecycle-condition rules,
     # but must be unique. See chat_message_save_failure for the full rationale.
     frequency = 11

     conditions_v2 = [
       { first_seen_event = {} },
       { reappeared_event = {} },
       { regression_event = {} },
     ]
     filters_v2 = [
       {
         tagged_event = {
           key   = "feature"
           match = "EQUAL"
           value = "workspace-sync-health"
         }
       },
     ]
     actions_v2 = [
       {
         notify_email = {
           target_type      = "IssueOwners"
           fallthrough_type = "ActiveMembers"
         }
       },
     ]

     lifecycle {
       ignore_changes = [environment]
     }
   }
   ```
3. Contract test goes GREEN.

### Phase 2 — Wire auto-apply
4. Add the `-target=sentry_issue_alert.workspace_sync_health \` line to `apply-sentry-infra.yml`.
5. Run `test-destroy-guard-sentry-scope-guard.sh` → still green (`sentry_issue_alert` type already allowed).

### Phase 3 — Validate
6. `terraform fmt -check` + `terraform validate` in `apps/web-platform/infra/sentry/`.
7. Run the full test gate (`vitest run` for the new contract test).

## Acceptance Criteria

### Pre-merge (PR)
- AC1: New contract test passes — `feature=workspace-sync-health` appears in BOTH `cron-workspace-sync-health.ts` (the `SENTRY_FEATURE` const) and `issue-alerts.tf` (the alert's feature filter value). Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-workspace-sync-health-alert-op-contract.test.ts`.
- AC2: `terraform fmt -check` and `terraform validate` clean in `apps/web-platform/infra/sentry/` (config-phase validation passes against `jianyuan/sentry@0.15.0-beta2`).
- AC3: `test-destroy-guard-sentry-scope-guard.sh` exits 0 (no new `-target` resource type introduced; `sentry_issue_alert` already allowed).
- AC4: `grep -c 'sentry_issue_alert.workspace_sync_health' .github/workflows/apply-sentry-infra.yml` returns 1.
- AC5: `grep -cE '^[[:space:]]+frequency[[:space:]]*=[[:space:]]*11\b' apps/web-platform/infra/sentry/issue-alerts.tf` returns 1 and no other rule uses 11 (frequency uniqueness preserved). NOTE: anchor on the indented assignment line — a loose `frequency\s*=\s*11` also matches the resource's header comment prose (`frequency=11`), a false second hit.

### Post-merge (automated — no operator dashboard step)
- AC6: The `apply-sentry-infra.yml` run triggered by the merge (push to `main` touching `issue-alerts.tf`) reports `Plan: 1 to add, 0 to change, 0 to destroy` for `sentry_issue_alert.workspace_sync_health` and applies cleanly. Verify via `gh run list --workflow=apply-sentry-infra.yml --branch main --limit 1` + `gh run view <id> --log` (API, not dashboard). The new `-target` line is present in the same merge commit, so the triggered run includes it — no staleness.

## User-Brand Impact

**If this lands broken, the user experiences:** the operator is not notified when their workspace KB clone diverges or goes stale, so the PIR failure mode recurs — a user reports a missing KB file before the operator knows anything is wrong (single-user incident).
**If this leaks, the user's data is exposed via:** the `notify_email` action routes to the operator only (IssueOwners → ActiveMembers); the underlying `workspace-sync-health` events carry only `op` + a hashed `userId` (per the cron's `reportSilentFallback` calls), no cross-tenant content. No new exposure vector.
**Brand-survival threshold:** single-user incident (carried forward from the source PIR + brainstorm).

`requires_cpo_signoff: true` — satisfied by operator review: the product owner drove both the scope decision (alert-rule-only) and the user-impact framing (alert fatigue) during brainstorm. `user-impact-reviewer` runs at PR review (review-skill conditional agent).

## Domain Review

**Domains relevant:** Engineering (carried forward from brainstorm `## Domain Assessments`, single-domain lane).

### Engineering
**Status:** reviewed (carry-forward)
**Assessment:** Observability config change mirroring the proven `chat_message_save_failure` rule. Anti-fatigue is structural (lifecycle conditions fold repeats into one issue). The only non-obvious risk — the auto-apply `-target` wiring — is resolved (new issue-alerts must be listed; precedent at line 215; scope-guard already allows the type).

### Product/UX Gate
**Tier:** none — no UI surface. Files-to-Edit/Create are Terraform + a vitest contract test; no path matches the UI-surface term list/globs. Mechanical UI override did not fire.

## Infrastructure (IaC)

### Terraform changes
- Files: `apps/web-platform/infra/sentry/issue-alerts.tf` (1 new `sentry_issue_alert` resource) + `.github/workflows/apply-sentry-infra.yml` (1 new `-target` line).
- Provider: `jianyuan/sentry@0.15.0-beta2` (already pinned; no version change).
- Sensitive variables: none new. The resource uses existing `var.sentry_org` + `data.sentry_project.web_platform`; apply credentials come from Doppler `prd_terraform` via the existing workflow (read-only, unchanged).
- `terraform-architect` NOT invoked: declarative resource added to an already-provisioned root, applied by the existing workflow; no SSH, no manual Doppler secret writes, no dashboard click-through, no new server / secret / vendor / runtime process. (Phase 2.8 reviewed — see ack comment at top.)

### Apply path
Path (b) — existing-root apply via `apply-sentry-infra.yml` on merge. The workflow's `on.push.paths` includes `issue-alerts.tf`, so the merge auto-triggers a `-target`-scoped `terraform plan` + apply that CREATES the new rule (no `terraform import` — it's a brand-new Sentry rule, exactly like `chat_message_save_failure`). Expected blast radius: 1 resource added, 0 changed, 0 destroyed; no downtime.

### Distinctness / drift safeguards
- `lifecycle { ignore_changes = [environment] }` mirrors all sibling issue-alerts.
- Single Sentry project (`web_platform`); no dev/prd split for Sentry IaC.
- The destroy-guard (`destroy-guard-filter-sentry.jq`) already counts `sentry_issue_alert` array-of-blocks shrinks, so a future edit that drops a `filters_v2`/`conditions_v2` element is caught.

### Vendor-tier reality check
Sentry issue alerts are not free-tier-gated (three `sentry_issue_alert` resources already apply on the same plan); no `count = var.*_paid_tier` gate needed.

## Observability

```yaml
liveness_signal:
  what: contract test asserts the alert's feature/op strings match the cron's emitted finding ops; terraform plan asserts the resource exists with no drift
  cadence: every PR (vitest) + every merge touching sentry infra (apply workflow)
  alert_target: CI job failure (red check) on drift
  configured_in: apps/web-platform/test/sentry-workspace-sync-health-alert-op-contract.test.ts + .github/workflows/apply-sentry-infra.yml
error_reporting:
  destination: the feeding cron already routes findings to Sentry via reportSilentFallback (feature=workspace-sync-health); this alert is the notification layer on those events
  fail_loud: contract test fails CI if the op/feature contract drifts (the alert-silently-unmatches failure mode)
failure_modes:
  - mode: cron op/feature string renamed without updating the alert filter (alert silently matches nothing)
    detection: contract test (AC1)
    alert_route: CI red check, pre-merge
  - mode: rule deleted / array-of-blocks shrunk
    detection: destroy-guard-filter-sentry.jq in apply-sentry-infra.yml
    alert_route: apply step blocks the destructive plan
  - mode: alert too noisy (operator inbox fatigue)
    detection: operator inbox volume
    alert_route: tune frequency / lifecycle conditions in a follow-up
logs:
  where: apply-sentry-infra.yml GitHub Actions run logs
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-workspace-sync-health-alert-op-contract.test.ts"
  expected_output: "all assertions pass (feature + 3 op slugs present in both cron and tf; IS_IN value matches)"
```

## GDPR / Compliance

No regulated-data surface touched (no schema, migration, auth flow, API route, or `.sql`). Trigger (b) (`single-user incident` threshold) fires, but the change introduces **zero new processing**: the `workspace-sync-health` events already flow to Sentry today carrying only a hashed `userId`; this plan adds a notification rule routing those existing pseudonymized events to the operator. No Art. 9 special-category data, no new lawful-basis question, no new Art. 30 processing activity. `gdpr-gate` skill not escalated — assessed inline as a no-op.

## Risks & Mitigations

- **R1 (proxy-vs-invariant):** Does `feature=workspace-sync-health` matching imply the issue's divergence cases are alerted? Yes, and more: every event the cron emits carries this feature, so all 3 findings (incl. the `non_fast_forward`/`recovered!=true` bullet-1 row via `stale-sync-failed`, verified at `kb-route-helpers.ts:307-309`) AND the 4 probe-failure ops are covered. Feature-only matching makes the *feature tag* the invariant — a single cross-artifact string, pinned by the contract test (AC1). No op can be silently excluded. (SpecFlow satisfied by direct trace; no separate spawn.)
- **R2 (apply staleness):** the new `-target` line lands in the same merge commit that touches `issue-alerts.tf`, and the push event evaluates the workflow at the merge commit — so the triggered apply includes the new target. No chicken-and-egg.
- **R3 (beta-provider validate):** `conditions_v2`/`filters_v2`/`actions_v2` is the beta2 API already used by `chat_message_save_failure`; the full-body resource passes config-phase validation (unlike the import-only `ignore_changes`-masked auth rules). AC2 gates this.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled.
- Do not extend the scope-guard or jq filter: `sentry_issue_alert` is already in-scope (#4364). Adding a new resource of an already-allowed type needs no guard-suite edit (confirmed by reading `test-destroy-guard-sentry-scope-guard.sh`).
- Use `Closes #4882` in the PR body (the alert lands + auto-applies on merge; not an operator-run remediation).
- **Known debt (not a blocker):** the apply workflow has a post-apply `assert-byok-rules-exist.sh` liveness check for the BYOK rules, but no equivalent existence assertion for the new rule — so if a future edit drops the `-target` line, the rule silently stops applying and the contract test (which reads only the `.tf`, not live Sentry) won't catch it. The `chat_message_save_failure` rule shipped with the same gap, so this is consistent precedent. Optional follow-up: extend the post-apply assertion to cover all apply-created issue-alerts (flagged by Kieran plan-review).
- HCL must be **multi-line block style** (siblings' convention); inline-object form won't survive `terraform fmt -check` (AC2). Run `terraform fmt` before committing (Kieran plan-review).
