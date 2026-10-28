---
title: "fix: unblock terraform apply — narrow logtail_exploration_alert.inngest_luks_key_probe_fail data range past the BetterStack 422 ceiling"
type: fix
date: 2026-10-28
slug: fix-logtail-key-probe-alert-422
branch: feat-one-shot-11372-logtail-alert-422
issue: 11372
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix: unblock terraform apply — narrow the LUKS key-probe alert's data range past the BetterStack 422 ceiling

## Overview

#11372 — the post-merge `terraform apply` on main (2026-10-27T22:52Z) failed when the Better Stack Telemetry API rejected the creation of `logtail_exploration_alert.inngest_luks_key_probe_fail` (`apps/web-platform/infra/betterstack-logs-alerts.tf:369`) with HTTP 422: "This configuration is too resource intensive. Please increase the check period or reduce the data range." The alert — introduced by merged PR #11260 for the on-host LUKS key-continuity probe (#9927 item 2) — is configured `check_period = 300` over `query_period = 10800` against the shared prd Vector source. The targeted apply pipeline stays red until the alert configuration fits under Better Stack's resource ceiling. The fix narrows `query_period` to 5400 s — the value `logtail_exploration_alert.inngest_luks_wrong_volume` already carries in applied state on the same source with a strictly heavier query — while `check_period = 300` and every ruled paging semantic stay unchanged.

## Problem Statement / Motivation

The alert never reached Better Stack: the exploration (`logtail_exploration.inngest_luks_key_probe_fail`, id 888101) was created by the failed run, and the follow-up `POST /api/v2/explorations/888101/alerts` was rejected at the resource-intensity ceiling. Every subsequent `apply-web-platform-infra.yml` run that targets this resource red for the same reason, independently of the web-1 reboot deferral — the issue is pre-existing and unrelated to revert PR #11345. Per the issue body, the likely fix is "widen the alert's check period / narrow its data range". The sibling data point on the same source selects which lever: `inngest_luks_wrong_volume` evaluates a three-predicate `JSONExtractString` query **with `GROUP BY`** every 300 s over a 5400 s window and is in applied state, while this alert — a lighter two-predicate whole-window aggregate — was rejected at 300 s over a 10800 s window. The window size is the variable the evidence isolates.

## Proposed Solution

Change one number: `query_period = 10800` → `query_period = 5400` on `logtail_exploration_alert.inngest_luks_key_probe_fail`, and update every pin, comment, and doc that records the old window.

- `check_period = 300` stays: the sibling proves the API accepts a 300 s check cadence on this source, and 300 s preserves the ~5-minute page latency the ruled design carries.
- `recovery_period = 3600` stays; `confirmation_period = 0` stays; `on_missing_data = "treat_as_zero"` stays; the paging SQL is byte-identical (the file's SQL RULES — position-1 marker anchor, no `raw LIKE` prefilter, `dt` column window, no `GROUP BY` — are untouched).
- Hysteresis is preserved: the probe re-emits hourly after any non-`ok` token (`luks_key_probe_tick` in `apps/web-platform/infra/inngest-cutover-flip.sh` — "at most once per 24h after an ok, hourly after any other token"), so a failing row stays inside a 5400 s window for 1.5 h and the next hourly re-probe lands with ~30 min of slack — the same slack the sibling documents as "an hour wide plus slack".
- Incident-clear timing changes from ~3–4 h to ~1.5–2.5 h after the LAST failing row (window + recovery_period) — a tightening, documented in the runbook edits below.

**Contingency ladder (if the apply still 422s at 300/5400):** keep `query_period = 5400`, raise `check_period` to 900, then to 3600 (sibling precedent: `luks_monitor_host_timer_dark` runs 3600/97200). Only reached if the ceiling regressed below the sibling's already-accepted tuple; each step re-runs the same guard-pin update, and each step is recorded against this plan's decision-challenges row before the value changes.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/betterstack-logs-alerts.tf` | `logtail_exploration_alert.inngest_luks_key_probe_fail`: `query_period = 10800` → `5400`; rewrite the window-rationale comment above the resource (the "3 h window … clears about 3 to 4 h" prose) to state the 1.5 h window, the hourly re-probe slack, the ~1.5–2.5 h clear time, and the #11372 422 cause. |
| `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` | Param pin row (~line 175–177): `query 10800` → `5400` in both the `param` assertion and its `[ok]`/`[FAIL]` strings; mutation row (~line 308–309): the edit anchor literal `"query_period        = 10800"` → `"query_period        = 5400"` (the `"90000"` replacement and the "25 h" label stay — the mutation's property, an over-wide window, is unchanged). |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | Line ~63–64: "evaluated every 300 s over a 10800 s window" → 5400 s window. |
| `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` | "Key-continuity probe (#9927 item 2)" section (~line 630): "the 3 h window, then the 1 h recovery period … clears about 3 to 4 hours" → the 1.5 h window and ~1.5–2.5 h clear time. |

## Files to Create

None.

## Research Insights

### Repository research (soleur:engineering:research:repo-research-analyst — sequential-fallback inline; parallel Task fan-out not available on this harness)

- The failing resource: `apps/web-platform/infra/betterstack-logs-alerts.tf:369` — `check_period = 300`, `query_period = 10800`, `recovery_period = 3600`, `alert_type = "threshold"`, `operator = "higher_than"`, `value = 0`, `on_missing_data = "treat_as_zero"`, `paused = false`, email + push armed (#11068 convention).
- The exploration it hangs off (`:347`) was created remotely as id 888101 during the failed run; the rejection hit the `POST .../alerts` call keyed on `check_period` per the [BetterStack API reference](https://betterstack.com/docs/logs/api/exploration-alerts/create/) — the 422 text is byte-identical to the issue's.
- Sibling evidence, same source `local.vector_prd_source_id`: `inngest_luks_wrong_volume` (`:264`) runs `check_period = 300 / query_period = 5400` with THREE `position(JSONExtractString())` predicates + `GROUP BY` — heavier than this alert's two predicates, no `GROUP BY` — and is in applied state (the failed plan's only "to add" entries were the two key-probe resources). `luks_monitor_host_timer_dark` (`:1024`) runs `check_period = 3600 / query_period = 97200`; `claude_cost_*` (`:875`, `:932`) run 3600/86400.
- The probe cadence that bounds window slack: `luks_key_probe_tick` re-emits "at most once per 24h after an ok, hourly after any other token" (`apps/web-platform/infra/inngest-cutover-flip.sh:53–55`), shipped on two channels (journald tag + curl phone-home whose message begins with the marker).
- Apply route already exists: `.github/workflows/apply-web-platform-infra.yml:655–656` carries both `-target=` lines; the drift guard pins them (`#5566` rule — an untargeted resource is never applied).
- Push-arm probe `plugins/soleur/scripts/inngest-alerts-push-probe.ts:34` asserts `push = true` on this alert's TF source (file-text assertion, not live state) — unaffected by this change; `push = true` is already armed and stays.
- Gap callouts: none — every artifact the issue cites exists on this branch (verified by direct read, not search).

### Learnings research (soleur:engineering:research:learnings-researcher — sequential-fallback inline)

- `knowledge-base/INDEX.md` regenerated then swept (`query_period|check_period|resource intensive|exploration_alert`): no prior learning records this specific 422 — first encounter.
- Adjacent institutional knowledge that shapes the fix:
  - ADR-218 — native Better Stack Logs alerts are Terraform-managed via the `BetterStackHQ/logtail` provider (`~> 11.2`): parameter tuning inside the existing resource is the conformant fix; no mechanism change.
  - `betterstack-quota-near-miss-postmortem.md` — an 80% log-quota warning is on record; a narrower data range is directionally consistent with quota hygiene.
  - `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — the shared prd source is contaminated by webhook traffic; this is WHY the SQL keeps its position-1 anchor and why a `raw LIKE` cost optimization is rejected (also a pinned negative row in the guard).
  - `2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md` — the guard's own mutation anchor must move with the new literal or the "paging window widens" row degrades to "did not land".
- Patterns directory: no `knowledge-base/project/patterns/` entries pin this alert's window values.

### Premise Validation (Phase 0.6)

Checked and held: #11372 OPEN (not closed by any merged PR); cited file/resource exists at `betterstack-logs-alerts.tf:369` on this branch; cited issues #10835, #10768, #9927, #11266, #6027 all OPEN (context/scope-guard, not blockers); #11345 MERGED as the issue states. ADR corpus grep (`logtail|betterstack|check_period|422`): the proposed mechanism — tune `check_period`/`query_period` on an existing `logtail_exploration_alert` — sits inside ADR-218's Decision, not in any rejected-alternatives table. Collision pre-check (`scripts/collision-precheck.sh 11372`): one hit, PR #11374 — this pipeline's own auto-created draft PR on this branch; not a foreign duplicate. Stale: nothing.

### Property List (Phase 0.6b)

1. The `terraform apply` step of `apply-web-platform-infra.yml` succeeds — Better Stack accepts the alert configuration (HTTP 201, not 422).
2. The paging property the CTO rulings D4/D12 fixed is preserved: a `token=fail_*` row of `SOLEUR_INNGEST_LUKS_KEY_PROBE` still pages (email + push); `indeterminate` still never pages; hysteresis over the hourly re-probe still holds; the SQL text is unchanged.
3. Every mechanical pin on the window values moves with the new value in the same diff (guard param row, guard mutation anchor, two runbook descriptions) — no consumer left asserting 10800.

### Cut List (Phase 0.6b)

- `raw LIKE` / prefilter SQL rewrite → property 1 (cheaper query) → already covered by narrowing `query_period`; and explicitly forbidden by the file's SQL RULES + a guard negative row (a quoting webhook row would count as a live probe row). CUT.
- Widening `check_period` as the primary lever → property 1 → property 1 is already bought by the sibling-proven window value; the widen buys it again at a 3–12× page-latency cost. Kept only as the named contingency ladder.
- New dead-man / absence alert for the probe → not a property of this ask → already tracked on owner-hold #11266 (D12 split is pinned by the guard's negative rows). CUT — out of scope.
- Any `server.tf` `ignore_changes` / placement-group or vector allow-set edit → not a property of this ask → orchestrated cutover tracked in #6027; explicitly out of scope per the brief. CUT.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 issues) contains no mention of any of the four `## Files to Edit` paths.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (one-shot entry at plan); the issue body's factual claims were verified directly — the resource exists, its values are as stated, the `-target` lines exist, and the 422 cause matches the API reference. Nothing to reconcile.

## User-Brand Impact

- **If this lands broken, the user experiences:** no immediate artifact — the direct blast radius is internal (the apply pipeline stays red or the alert silently never pages). The downstream user-facing artifact is delayed or lost founder-action executions: an un-paged LUKS key loss on the dedicated Inngest host can take the Redis-AOF-backed queue offline at the next reboot, dropping or delaying queued founder-approved sends across users.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector — the alert reads internal probe marker rows (`token=fail_*`) already flowing to the prd source; no user data is newly collected, stored, or surfaced.
- **Brand-survival threshold:** `aggregate pattern` — a silently-dead page path would, if it materialized, hit every queued founder action rather than one user's account.
- **Threshold decision (challengeable):** `aggregate pattern`, not `single-user incident`, because no single user's data or money is directly at risk in one failure; not `none`, because the alert's only purpose is to avert a store-loss event that would cross to users.

## Observability

```yaml
liveness_signal:
  what:            # Better Stack Logs per-bucket threshold alert "soleur-inngest-luks-key-probe-fail-prd" evaluating SOLEUR_INNGEST_LUKS_KEY_PROBE fail_* rows
  cadence:         # 300 s check over a 5400 s window (post-fix)
  alert_target:    # operator email + push (escalation policy when var.betterstack_paid_tier)
  configured_in:   # apps/web-platform/infra/betterstack-logs-alerts.tf — logtail_exploration_alert.inngest_luks_key_probe_fail

error_reporting:
  destination:     # Better Stack incident (email + push), mirrored to a deduplicated GitHub issue by the repo-side watchdog (ADR-298)
  fail_loud:       # a failed apply prints the 422 in the "Terraform apply" step of apply-web-platform-infra.yml — the signal this fix removes

failure_modes:
  - mode:          # alert config still over the resource ceiling after the fix
    detection:     # the apply workflow's "Terraform apply" step exits non-zero with the same 422 text
    alert_route:   # workflow red on main; drift trackers #10835/#10768 already watch the pipeline
  - mode:          # window narrowed below the hourly re-probe cadence (silent flap: count hits 0 mid-incident, recovery begins)
    detection:     # guard param pin + mutation row "paging window widens to 25 h"; runbook documents the 1.5 h > 1 h cadence + slack reasoning
    alert_route:   # CI red on apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh
  - mode:          # probe rows stop arriving entirely (dead emitter / Vector outage) — reads as zero, treat_as_zero is blind to it
    detection:     # out of scope for this diff; tracked by the deferred dead-man alert on #11266 (D12)
    alert_route:   # — (documented gap, owner-held)

logs:
  where:           # Better Stack Logs prd Vector source (local.vector_prd_source_id) — SOLEUR_INNGEST_LUKS_KEY_PROBE rows via journald tag + phone-home
  retention:       # per the source's configured retention in Better Stack

discoverability_test:
  command:         # grep -F 'query 5400 s' apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh
  expected_output: # query 5400 s
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — one attribute edit (`query_period`) plus a comment rewrite on `resource "logtail_exploration_alert" "inngest_luks_key_probe_fail"`. No new resources, no new providers (existing `BetterStackHQ/logtail ~> 11.2`, `main.tf:52`), no new variables, no sensitive values touched.

### Apply path

- `terraform apply` via the existing `apply-web-platform-infra.yml` `-target` entries (`:655–656`). On the next run the plan adds only `logtail_exploration_alert.inngest_luks_key_probe_fail` (the exploration, id 888101, was created by the failed run; if state was not saved it re-adds cleanly — either way AC-1 holds). Expected downtime/blast radius: none — an alert resource create carries no host mutation.
- **Merging this PR alone mutates production** — `apply-web-platform-infra.yml` is push-triggered on `apps/web-platform/infra/**` (`on.push.paths`, `:15–20`) and its `-target` graph reaches this resource, so the merge click is the per-command authorization and the PR body's first line states that answer. Apply-workflow enumeration (sharp edge: every workflow that can apply a changed TF resource must be named): only `apply-web-platform-infra.yml` reaches `logtail_exploration_alert.inngest_luks_key_probe_fail` — `apply-deploy-pipeline-fix.yml`'s `paths:` list does not include `betterstack-logs-alerts.tf` and its `-target` set is `terraform_data.*`; `apply-git-data-root-key.yml` is `workflow_dispatch`-only on a separate root; `apply-inngest-rls.yml`, `apply-sentry-infra.yml`, `apply-github-infra.yml` scope to other roots/file sets; `scheduled-terraform-drift.yml` and `infra-validation.yml` do not apply.
- **PR body convention (ops-remediation class):** the PR body references `Ref #11372`, never `Closes #11372` — the remediation is only proven when the post-merge apply accepts the alert, so auto-closing at merge could falsely resolve while the pipeline is still red (#2880-class). Issue closure happens after AC-4's post-merge verification (or under the contingency ladder).

### Host fan-out

- None — no `terraform_data` SSH provisioner is touched; this is a vendor-API resource, so plan-host-fanout.md's fleet classification does not apply.

### Distinctness / drift safeguards

- The alert is prd-only (`soleur-inngest-luks-key-probe-fail-prd` on `local.vector_prd_source_id`); no dev/prd collapse vector is introduced. `lifecycle.ignore_changes` — none on this resource; the scope guard stands: `server.tf` `ignore_changes` and the vector allow-set are #6027's cutover work and are NOT touched by this plan.

### Vendor-tier reality check

- The `escalation_target` block is already `var.betterstack_paid_tier`-gated (`policy_id`/`team_name` ternary) — unchanged. The 422 is the Telemetry resource-intensity ceiling on `check_period`, not a free-tier feature gate; the sibling's accepted tuple on the same source is the evidence the value is under the ceiling for the current tier. If the ceiling still rejects (contingency ladder), that is evidence the tier's compute allowance shrank — an operator-notify finding, not a tier-upgrade authorization.

## Encryption Posture

```yaml
at_rest: []          # no persistent store is introduced or modified — a vendor alert parameter
in_transit:
  - connection:      # Terraform logtail provider -> telemetry.betterstack.com API (existing, unchanged by this diff)
    enforced_at:     # apps/web-platform/infra/main.tf:96 (provider "logtail" block)
    tls:             # https
    cert_verification: on
    does_not_defend: # a leaked betterstack_api_token grants Telemetry write within its scope
    disclosed_as:    # not-publicly-claimed
```

No new store and no new cross-component connection is created — the section records the posture of the unchanged API edge the apply already traverses; no `exception` block applies.

## Guard Contract

The deliverable is a parameter tune, not a new guard — but it mutates the pinned values of an existing drift guard, so the contract records which of that guard's rows bound this change and how each is driven red.

### Guard 1 — key-probe alert window pin (`apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`)

**Property.** The drift guard's pinned window values equal the values live in `betterstack-logs-alerts.tf` — any drift between the .tf and the pin goes red, in either direction.

**Assembly.** Chokepoint: the `param "$FAIL_AL" check_period|query_period|recovery_period` row (~line 175) — the one assertion that binds all three window values — plus the mutation-row anchor literal (~line 309) that must name the same `query_period` value to keep the "over-wide window" mutation landable. Both live in the one test file reading the one .tf through `res_block logtail_exploration_alert inngest_luks_key_probe_fail`; there is no second injection site.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | `.tf` edited to `query_period = 5400` while the guard still pins `10800` (this diff without the test update) | RED — param row fails |
| 2 | Guard's mutation anchor left as `"query_period        = 10800"` after the .tf edit (mutation can no longer land) | RED — "mutation did not land" surfaces as a failed row, not a pass |
| 3 | `recovery_period` drifted in the .tf without a pin update | RED — same param row binds all three values |
| 4 | `check_period` raised to the contingency value (900/3600) without re-running the pin update | RED — param row fails until the pin moves in the same diff |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Likely fix: widen the alert's check period / narrow its data range to satisfy BetterStack's resource ceiling." [issue #11372] | `betterstack-logs-alerts.tf` `query_period` edit + contingency ladder | mapped — the narrow-data-range arm; evidence selects it over the widen arm (see Ruling) |
| 2 | "terraform apply fails because BetterStack rejects resource logtail_exploration_alert.inngest_luks_key_probe_fail with HTTP 422 'too resource intensive'" [brief] | AC-1 (apply succeeds), Phase 1 edit, Observability `error_reporting.fail_loud` | mapped |
| 3 | "an orchestrated cutover tracked in a different open issue (6027) will later remove placement_group_id from server.tf's ignore_changes and update a vector allow-set — that work is NOT in scope" [brief] | Non-goal below + Cut List row + IaC Distinctness note | mapped — descoped by ask, guard kept by naming the boundary |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `betterstack-logs-alerts.tf` query_period 10800→5400 | "narrow its data range" | asked |
| Guard pin + mutation-anchor update | — | inferred — justification: the drift guard pins the window values verbatim; a .tf edit without the pin move is an immediate CI red (enforcement contract `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`) |
| `betterstack-log-query.md` window wording | — | inferred — justification: doc asserts the 10800 s window; left stale it misstates the live config the on-call reads |
| `inngest-luks-cutover-6894.md` clear-time wording | — | inferred — justification: the runbook the alert's `incident_cause` links to describes the 3 h window/3–4 h clear; a stale clear-time misdirects the paged operator |
| Contingency ladder (check_period 900 → 3600) | "widen the alert's check period" | asked — carried as contingency, not primary |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 4 | Estimated changed lines: ~30
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering, Operations

*Sequential-fallback disclosure: this harness has no Task tool; the prescribed parallel leader fan-out was executed inline, sequentially, under each agent's own definition — `Reviewed-Coverage: sequential-fallback`.*

### Engineering

**Status:** reviewed
**Assessment:** (soleur:engineering:cto, Rule interface executed inline — see decision-challenges.md) — Decision: narrow `query_period` to 5400, keep `check_period = 300`. The sibling `inngest_luks_wrong_volume` proves 300/5400 is accepted on the same source with a heavier query; the 1.5 h window preserves hourly-re-probe hysteresis with the sibling's documented slack. A `raw LIKE` cost optimization is rejected — it violates the file's SQL RULES and the guard's negative pin. No architectural decision is made or changed (the mechanism stays inside ADR-218); no capability gaps.

### Operations

**Status:** reviewed
**Assessment:** (soleur:operations:coo, inline) — no vendor change, no new spend, no procurement step. Directionally consistent with quota hygiene (the 80% log-quota near-miss is on record). No operator console step is introduced — the apply path is the existing workflow's `-target` entries, consistent with `hr-all-infrastructure-provisioning-servers`. No specialists recommended.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1: `logtail_exploration_alert.inngest_luks_key_probe_fail` in `apps/web-platform/infra/betterstack-logs-alerts.tf` declares `query_period = 5400` with `check_period = 300`, `recovery_period = 3600`, `confirmation_period = 0`, `on_missing_data = "treat_as_zero"`, `paused = false`, `email = true`, `push = true` all unchanged, and the resource's window-rationale comment describes the 1.5 h window and the #11372 cause.
- [ ] AC-2: The paging SQL local `inngest_luks_key_probe_fail_sql` is byte-identical to its pre-change form (marker anchored at message position 1, `token=fail_` predicate, `dt` window filter, no `LIKE`, no `GROUP BY`, no `indeterminate`).
- [ ] AC-3: `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` exits 0 on the edited tree — its param row pins `check 300 / query 5400 / recovery 3600` and its "paging window widens" mutation row still lands and still reddens on the mutated copy.
- [ ] AC-5: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` and `inngest-luks-cutover-6894.md` describe the 5400 s window and ~1.5–2.5 h incident-clear timing — no remaining assertion of a 10800 s / 3 h window for this alert.
- [ ] AC-6: `server.tf` `ignore_changes` and any vector allow-set are untouched (the #6027 cutover scope guard); `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/server.tf` exits 0 (merge-base form, so a sibling merge touching `server.tf` cannot false-red this AC).

### Post-merge (apply verification)

- [ ] AC-4: `terraform apply` (via `apply-web-platform-infra.yml`'s existing `-target` lines) creates the alert — Better Stack accepts the configuration; the apply step no longer returns the 422 text. *If it still 422s, the contingency ladder (check_period 900 → 3600) is followed under the same guard-pin discipline, recorded against the decision-challenges row.* The issue closes only after this verification (PR body: `Ref #11372`).

## Test Scenarios

- Given the edited `.tf` and test file, when `bash apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` runs, then every row is `[ok]` and the mutation battery reports every row RED as designed (`unit` — guard self-test + mutation rows).
- Given the `.tf` edited to 5400 but the guard still pinning 10800 (negative control), when the guard runs, then the window param row fails — proving the pin binds (`unit`).
- Given `query_period` mutated to `90000` on a scratch copy, when the guard runs against the copy, then the "paging window widens to 25 h" row is RED — proving the anchor still lands after this diff (`unit`).
- Given the merged PR, when `apply-web-platform-infra.yml` next runs `terraform apply`, then the step exits 0 and the alert exists in Better Stack (`integration` — the AC-4 verification; executed by the pipeline, not locally).
- Given a `token=fail_passphrase` probe row in the prd source, when the next 300 s check evaluates the 5400 s window, then count > 0 and the alert pages (`e2e` — deferred to live verification: no unauthenticated local substitute exists; `pyramid-justified: the property lives only in the vendor's evaluation loop`).
- Regression: the guard's existing battery (position-1 anchor, `token=fail_`, no `indeterminate`, `dt` filter, census of exactly one key-probe pair, exactly two `-target` lines) stays green — the change touches only the window values.

## Success Metrics

- `apply-web-platform-infra.yml` `terraform apply` step green on the first run after merge.
- `inngest-luks-key-probe-alert.test.sh` green in CI.
- Alert object present in Better Stack (`soleur-inngest-luks-key-probe-fail-prd`, unpaused) — verifiable via `scripts/betterstack-query.sh`-class readback or the Telemetry GET with the operator's token.

## Dependencies & Risks

- **Risk:** the ceiling rejects 300/5400 too (if it moved since the sibling's acceptance). Mitigation: named contingency ladder — `check_period` 900 then 3600 — each step a one-value diff under the same guard-pin update, recorded in decision-challenges before landing.
- **Dependency:** none blocking — the alert is quiet-by-design until the owner delivers the signed probe bundle (#11266); `on_missing_data = treat_as_zero` keeps a not-yet-feeding alert silent.
- **Non-goals:** the dead-man/absence alert (#11266, D12-pinned split); the #6027 cutover's `server.tf` `ignore_changes` and vector allow-set edits; any SQL rewrite.

## Deepen-Plan Pass (2026-10-28)

*Sequential-fallback disclosure: this harness has no Task/Workflow tool, so the prescribed parallel skill/learnings/review fan-outs and the named-panel review were executed inline, sequentially, under each component's own definition — `Reviewed-Coverage: sequential-fallback`. No independent subagent review ran.*

**Halt-gate verification:** 4.4 precedent-diff (sibling `inngest_luks_wrong_volume` cited with its file anchor — pass) · 4.5 network-outage (no trigger — skip) · 4.55 downtime & cutover (vendor-API alert create, no offline-inducing op — skip) · 4.6 User-Brand Impact (present, `aggregate pattern`, challengeable — pass) · 4.7 Observability (all fields non-placeholder; `grep`-verb probe, <15 s, no creds, literal expected output — pass) · 4.8 PAT-shaped variable (none in plan — pass) · 4.9 UI wireframe (no UI surface — skip) · 4.10 Encryption Posture (present; `at_rest: []` per the `2026-09-29-infra-inngest-cli-pin-bump-freshness-plan.md` precedent for no-new-store .tf edits — pass) · 4.11 Guard Contract (`lint-guard-contract.py` run on this file: 1 entry, matrix ≥3 rows, structural Assembly — pass) · 4.12 Scope Check (exactly one unfenced section; every ask mapped; inferred items carry justifications — pass) · 4.13 Task Design (no new autonomous-task surface — skip).

**Skill/learnings match (Phase 2–3):** no additional installed skill matched this single-parameter Terraform tuning; the learnings sweep (INDEX.md + `git grep` over `knowledge-base/`) surfaced no prior art for this specific 422 — the adjacent items are already folded into Research Insights (ADR-218, quota post-mortem, syslog-field-isolation learning, vacuous-green learning).

**Named-panel relevance scan (plan-review):** eng panel (DHH/Kieran/code-simplicity lenses, inline) — no findings beyond the two mechanical fixes applied (Pre/Post-merge AC split; runbook-heading preservation note in tasks.md). Named panel: `soleur:engineering:cto` (devex lens, inline — apply path and contingency ladder read clean, no DX concern); CPO/CMO/ux-design-lead not relevant (no product/market/user-facing surface — independent read of Files-to-Edit confirms zero UI-surface hits).

**Enhancement outcome:** plan unchanged in direction; sharpened in verification discipline (AC split, merge-mutates-production declaration, `Ref`-not-`Closes` convention, merge-base diff form in AC-6, uniquely-post-edit discoverability probe).

## References & Research

- Issue: #11372 (OPEN, p1-high); context: #10835, #10768 (drift), #9927 (probe), #11266 (bundle delivery, owner-hold), #6027 (cutover — out of scope), PR #11345 (revert — merged, unrelated), PR #11260 (introduced the alert).
- Introducing plan: `knowledge-base/project/plans/archive/20261027-112122-2026-10-26-feat-inngest-luks-key-continuity-probe-plan.md`; rulings: `knowledge-base/project/specs/archive/20261027-112122-feat-one-shot-9927-key-continuity-probe/decision-challenges.md` (D4/D12).
- ADR-218 (logtail-managed alerts), ADR-282 (sole-copy LUKS protection set), ADR-298 (incident→issue mirror).
- BetterStack API reference: [exploration-alerts/create](https://betterstack.com/docs/logs/api/exploration-alerts/create/) (the 422 text and the check_period/data-range remedy).
- Sibling precedent: `apps/web-platform/infra/betterstack-logs-alerts.tf:264` (`inngest_luks_wrong_volume`, 300/5400, applied).
