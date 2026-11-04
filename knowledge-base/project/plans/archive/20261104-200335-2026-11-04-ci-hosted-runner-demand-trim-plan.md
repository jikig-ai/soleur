---
title: "ci: hosted-runner starvation dequeues green PRs from the merge queue (checks_timed_out)"
type: chore
date: 2026-11-04
slug: ci-hosted-runner-demand-trim
branch: feat-one-shot-12030-ci-runner-starvation
issue: 12030
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

# ci: hosted-runner starvation dequeues green PRs from the merge queue (#12030)

## Enhancement Summary

**Deepened on:** 2026-11-04
**Sections enhanced:** 6 (Research Reconciliation, Research Insights, Proposed Solution, Implementation Phases, Acceptance Criteria, Observability)
**Agents and gates used:** `soleur:engineering:cto` (two rulings), `soleur:engineering:research:repo-research-analyst`, `soleur:engineering:research:learnings-researcher`, a sharp-edges verification pass, the `plan-review` panel (DHH, Kieran, code-simplicity), and the deepen-plan halt gates 4.5 to 4.13.

### Key Improvements

1. Replaced proxy acceptance checks (`git diff --stat`, a hedged lint entry point) with a deterministic comment-only proof and a stale-figure sweep that covers every "30-minute window" and "75-minute" hit, not one sentence.
2. Anchored the ADR-270 edit to the correct one of two same-dated addendum headings, and re-worded the cap row to "re-verified" because ADR-276 already recorded the docs figure on 2026-10-07.
3. Made the ADR-276 "no safe lever beyond S2/S3" sentence conditional on the peak-window census, and added the three levers the review found missing from the Cut List (`max_entries_to_build`, suite minutes, the 5-minute watchdog dispatch).

### New Considerations Discovered

- The hour-of-day evidence flipped a CTO ruling: at work time both the 2.7-day and the 9-day histograms show offset 5 (05/11/17/23) lowest, by only 3.5% and 6.1%, so no cron change ships.
- Delivered concurrency, not the 60-job cap, was the binding limit in the two deep-queue samples (26 and 31 jobs in flight), so the residual risk is supply-side.
- A green PR run now reads about 330 job-min against ADR-276's about 100 (2026-10-07); the cause is unmeasured and is handed to epic #11556.

### Deepen-pass verification (live, 2026-11-04)

- Gates 4.6, 4.7, 4.8, 4.12: section present; threshold `none` carries the sensitive-path scope-out line; observability command (`grep -c`) is on the probe-verb allowlist, finishes well inside 15 s, and `expected_output` is the literal `1`; no PAT-shaped token; one unfenced `## Scope Check`.
- Gates 4.9, 4.10, 4.11, 4.13, 4.4, 4.55: not triggered (no UI file, no `.tf`/migration/cloud-init file, no guard deliverable, no new autonomous task, no pattern-bound behaviour, no downtime-inducing operation).
- Gate 4.5 (network-outage): the keyword scan matches `timeout` and `502`, but both are non-network uses (the merge-queue response timeout and a GitHub API HTTP 502 aborting the census script). There is no SSH, firewall, DNS or provisioner hypothesis, so the L3/L7 checklist does not apply; no `terraform apply` is involved.
- Cited issues resolve and are OPEN: #12030, #8735, #7942, #9729, #10448, #11556, #12086. Labels `deferred-scope-out` and `domain/engineering` and milestone "Post-MVP / Later" exist. The plan cites no AGENTS.md rule IDs. No test pins the infra-validation "6.7 min" comment text (grep of `.github/scripts/test`, `plugins/soleur/test`, `scripts` found none).
- `tasks.md` already carries every correction from the review pass (it was regenerated after plan-review); no further propagation is needed.

## Overview

Green pull requests were removed from the merge queue because the candidate CI run waited for hosted runners past the
queue's response timeout. The timeout stopgap (75 to 120 minutes) is already on main at
`infra/github/ruleset-ci-required.tf:363`. This plan answers the issue's open investigation list with measured data,
rules on every demand-side lever the brief names, and fixes the out-of-date timeout figures that the stopgap left in
comments.

The headline result of the research changes the shape of the deliverable. The operator brief asked for "matrix and
trigger trimming in ci.yml, tenant-integration.yml, infra-validation.yml and their tests". Measured against the repo as it
stands today, the CTO agent ruled that no demand-trim code in those three files is safe or worthwhile beyond what ADR-276
stages S2 (push dedupe) and S3 (draft-light) already shipped (see `## Research Insights` and the ruling table). The
remaining demand lever, S4 (affected-only PR runs, #9729), is operator-activated and out of scope. The residual risk is
runner supply: on the worst sample the scheduler delivered 26 concurrent jobs against a 60-job entitlement. So this
change ships the accounting, the decision record, the comment corrections, and tracked operator-only follow-ups.

## Research Reconciliation: issue text vs. repository reality

| Issue / brief claim | Reality (evidence) | Plan response |
|---|---|---|
| Team-plan cap recalled as 60, "not verified against the docs" | Re-verified 2026-11-04 (ADR-276 Context already recorded the same figure from the docs on 2026-10-07; only the issue and the ADR-270 addendum still say "not verified"): <https://docs.github.com/en/actions/reference/limits> lists Team = 60 total concurrent jobs (standard runners), 1,000 for larger runners (Free 20, Pro 40, Enterprise 500). Org `jikig-ai` reads `plan.name=team, seats=1` (`gh api orgs/jikig-ai`). | Record in audit; one-line "re-verified 2026-11-04" note under the ADR-270 `### Addendum 2026-11-03 (#12030)` heading. |
| "The snapshot sits exactly at 60" implies the cap is the limiter | 90 half-hourly `scheduled-actions-queue-health` samples: 88 HEALTHY, 1 SATURATED, 1 UNDER_ASSIGNED. Only 5/90 had >= 55 jobs in flight, none reached 60. The deep-queue samples show 26 and 31 jobs in flight (2026-11-03T22:52Z: 100 queued runs, 26 in flight, median live queued age 998 s). | Name delivered concurrency (supply) as the residual risk; file operator-only follow-ups. |
| Stopgap is "in a separate pull request" | Already on main: `infra/github/ruleset-ci-required.tf:363` reads 120; ADR-270 addendum 2026-11-03 records it. | No Terraform change in this PR. |
| `ubuntu-latest` everywhere | `infra-validation.yml` runs on `ubuntu-24.04` (11 `runs-on` lines). | Irrelevant to supply (same standard pool); noted in audit. |
| Infra Validation and Tenant integration run on every event | `infra-validation.yml` has `paths:` filters on push and pull_request; `tenant-integration.yml` always runs a cheap `detect-changes` and gates the heavy suite (PR runs average 2.2 job-minutes). | No trimming of either trigger. |
| About 70% of `CI` runs cancelled | 396 of 698 `pull_request` CI runs (57%) over 2026-11-01 to 2026-11-04. | Quantify the minutes (below), not the run count. |
| ADR-276 Context: PR run ~100 job-min, cancelled jobs 4% of minutes (2026-10-07) | Sample 2026-11-04: green PR run mean 330.5 job-min (median 344, 40 jobs), failed 159, cancelled mean 105 (median 6.2). Not reconciled to a cause; the 2026-11-03 top-15 report shows test-scripts suites 12% to 190% above their committed prices. | Audit states the two bases differ (all runs vs green sample) and marks the cause as unmeasured. |

## Research Insights

### Premise Validation (Phase 0.6)

- Cited issue #12030 is OPEN, no closing PR. The collision pre-check names PR #12086, which is this branch's own draft PR (not a duplicate).
- Cited paths all exist on `origin/main`: `cron-merge-queue-stall-dispatch.ts` (stale "75" at lines 20 and 42), `ci.yml`, `tenant-integration.yml`, `infra-validation.yml`, `infra/github/ruleset-ci-required.tf` (120).
- ADR corpus grep for the proposed mechanisms (settle/debounce gate, cron re-slotting, path trimming): ADR-262 rejected job-level path filters on heavy legs and ADR-276 Decision 4/5 reversed that only behind the merge queue and kill-switches; S4 is NO-GO (index completeness, #10448). Required contexts must report on `merge_group` (learning 2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers).
- `ADR-276` already contains stages S1 (census), S2 (push dedupe), S3 (draft-light); this plan does not duplicate them.

### Property List (Phase 0.6b)

1. The cap figure used in decisions is confirmed against vendor documentation, with the source cited.
2. Runner-minutes per workflow are accounted from a reproducible command, and the accounting says where the demand is.
3. Every demand lever the brief names has an explicit, evidenced ship or do-not-ship ruling, so the next person does not re-derive it.
4. No comment in the repository states a merge-queue timeout figure that contradicts the live ruleset value (120) without dating it.
5. Spend and vendor-contact options are tracked as operator decisions, not executed.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| Settle/debounce gate before heavy matrix | fewer wasted cancelled minutes | CUT: 74% of cancelled minutes sit in runs that lived > 40 min; runs dying within 5 min are 2% of the waste, so a start delay saves about nothing. |
| Re-slot `main-health-monitor` cron (05/11/17/23) | avoid the evening peak | CUT: hour-of-day tables show the shift cuts exposure only 3.5% to 6.1% (re-derived in the audit); costs a 6-file lockstep change plus a Sentry Terraform apply. |
| Tree-identity skip for `main-health-monitor` | fewer full runs | CUT: new proof logic on the Sentry check-in contract; the monitor is the un-gated backstop (ADR-181, ADR-262). |
| infra-validation `paths:` tightening or draft skip | fewer infra PR runs | CUT: every `paths:` entry guards a named drift suite (#10032, #10065, #10138, #10445); no `ready_for_review` trigger exists, so a draft skip would leave no run at ready. |
| ci.yml shard-count (K) changes | fewer job-minutes | CUT: K trades ~60 s per-leg overhead against wall clock; fewer legs lengthen the `merge_group` critical path toward the 120-minute timeout; manifest and shard-totality tests pin K. |
| Regression test pinning measured numbers | drift detection | CUT: numbers go stale; the audit cites the reproduction command instead. |
| Lower `max_entries_to_build` (currently 2) to cut `merge_group` rebuild pressure | fewer concurrent 375-job-min candidates | NOT EVALUATED here: it is a queue-throughput trade (ruleset comment: "raise only after the canary measures it", ADR-270 raise checklist) and lowering it lengthens every merge; the audit records it as an open lever with the measured candidate cost, owned by ADR-270, not by this change. |
| Shrink suite minutes (test-scripts suites 12% to 190% over committed prices, `suite-durations.tsv` stale) | fewer job-minutes per run | OUT OF SCOPE: owned by epic #11556 Lever A (2026-11-03 top-15 report); the Phase 4 epic comment hands it the PR-run-cost finding. |
| Thin the 5-minute `scheduled-supabase-watchdog` dispatch (71 runs, 169.8 job-min per 6 h, about 7% of the quiet window) | fewer small runs | OUT OF SCOPE: cron fleet, not one of the three named workflows; each cadence protects a named detection window (2026-09-21 brainstorm). Recorded in the audit only. |

Lever ids used in the rulings: 1a main-health-monitor cadence (cut rows 2 and 3), 1b late-cancel waste (cut row 1), 1c infra-validation (cut row 4), 1d ci.yml matrices (cut row 5), 1e tenant-integration (no cut row needed: 2.2 job-min per run), 3 supply (operator-only).

### Measured accounting (2026-11-04, reproduce with `scripts/ci-demand-census.sh` and `gh api`)

- 6-hour quiet window 2026-11-04T10:00Z to 16:00Z: 2,290.8 runner job-minutes, 344 runs. By workflow: `ci.yml` merge_group 1,121.7 (3 runs, 105 jobs), `main-health-monitor.yml` 376.8 (1 run), `ci.yml` pull_request 283.0 (1 run), `scheduled-supabase-watchdog.yml` 169.8 (71 runs), `tenant-integration.yml` push 48.5, `ci.yml` push 40.3, CodeQL 40.2. The peak window (2026-11-03 19:00Z to 22:00Z, 1,269 runs) could not be censused: the script aborted on a persistent HTTP 502 for one run after 3 attempts, so peak shares below come from direct `gh api` job sampling.
- `ci.yml` merge_group run: about 375 job-min; `test-scripts` (8 legs, about 34 min each) is 269 of it, `test-webplat` 37, `test-scripts-heavy` 29, `shard-totality-mutations` 13. With `max_entries_to_build = 2` two such candidates can build at once.
- `ci.yml` pull_request run, sampled: success 330.5 job-min (26 runs), failure 159.4 (20), cancelled 105.1 mean / 6.2 median (35). 258 PR runs per day, 57% cancelled: estimated CI PR demand about 43,000 job-min/day, of which cancelled runs about 15,000 (about 35%). This is an estimate from 81 sampled runs, not census-grade.
- Cancelled PR-run lifetime (60 runs, 4,884 job-min): runs ending within 5 min hold 2% of cancelled minutes, within 20 min 6%, within 40 min 26%, so 74% sits in runs that lived longer than 40 min.
- `main-health-monitor.yml`: 376.8 job-min per run, 16 jobs, 4 runs a day (Inngest cron `0 */6 * * *`), about 1,500 job-min/day (about 3%).
- `infra-validation.yml` pull_request run: success 55.6 job-min (deploy-script-tests 4 legs 41.9, deploy-script-tests-fixed 9.2), failure 53.9, cancelled 17.4 mean; 73 PR runs/day, 41% cancelled. Legs measure about 10.5 min, not the 6.7 min its comment records; `timeout-minutes: 15` is now about 1.4x.
- `tenant-integration.yml` pull_request run: success 2.2 job-min, cancelled 0.5.
- Number bases (state these in the audit): the cancelled-run lifetime sample is 60 runs averaging 81 job-min, a different draw from the 35-run cancelled mean of 105; the daily estimate re-weights the sample by the observed mix (cancelled 57%, so 258 x 0.57 x 105 = about 15,400; the other 111 runs x about 255 = about 28,300; total about 43,700 job-min/day); the 10:00Z to 16:00Z "quiet window" overlaps busy hours 10 to 15, so it is a Wednesday-midday sample, not an overnight trough; the 90 probe samples are the half-hourly runs from 2026-11-02T23:30Z to 2026-11-04T17:30Z.
- Hour-of-day load of `ci.yml` PR plus 3x merge_group runs (the 3x merge_group weight is a rough cost proxy: about 375 vs about 150 job-min; UTC, 9 days from 2026-10-27, the newest 2,600 runs, 24 hourly sums total 3,040 weighted units from 2,600 runs minus push and dispatch runs): h0 87, h1 51, h2 49, h3 36, h4 28, h5 37, h6 50, h7 71, h8 179, h9 276, h10 161, h11 146, h12 130, h13 149, h14 181, h15 127, h16 139, h17 244, h18 159, h19 139, h20 184, h21 154, h22 185, h23 78. Three-hour overlap load by cron offset: 0 = 1429, 1 = 1596, 2 = 1699, 3 = 1611, 4 = 1444, 5 = 1341.
- Queue health (90 samples): 88 HEALTHY, 1 SATURATED (2026-11-04T00:30Z, 38 queued, 31 in flight), 1 UNDER_ASSIGNED (2026-11-03T22:52Z, 100 queued, 26 in flight, cap 60); 20 of 90 had a median live queued age of 300 s or more.

### Institutional learnings applied

- `2026-09-22-actions-queue-under-assignment-metrics-and-monitor.md`: entitlement is not delivered capacity; measure delivered-vs-entitled.
- `knowledge-base/project/learnings/workflow-issues/2026-11-03-draft-prs-fail-the-test-aggregate-by-design-and-ceiling-raises-ship-alone.md`: a ceiling raise ships alone (this PR adds none).
- `knowledge-base/project/learnings/best-practices/2026-09-24-measured-claims-in-comments-need-the-full-cancelled-set.md`: re-derive measured claims over the whole run set (the infra-validation comment fix follows this: worst leg and p95 over the same runs, not a mean against a worst case).
- `knowledge-base/project/learnings/2026-10-12-docs-only-ci-skip-premise-is-false-when-tests-read-the-kb.md`: docs-only skips are unsafe by path alone.
- `knowledge-base/project/learnings/best-practices/2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`: every required producer must report on `merge_group`.

### Technical rulings

Recorded in `knowledge-base/project/specs/feat-one-shot-12030-ci-runner-starvation/decision-challenges.md` (one row per item).

## Problem Statement / Motivation

A merge that should take about 45 minutes took two or more hours and needed repeated re-enqueues because hosted-runner
queue wait pushed the candidate run past the queue timeout. The timeout is raised, but nothing records whether the demand
side has a safe lever left, whether the cap is the limiter, or what the next trigger is. Meanwhile
`cron-merge-queue-stall-dispatch.ts` still tells the next engineer that the margin against the queue timeout is about
zero at the measured p90 runner wait, which is false at 120 minutes.

## Proposed Solution

Documentation and decision-record deliverables only. No workflow trigger, matrix, concurrency or cron behaviour changes.

1. A dated audit `knowledge-base/engineering/audits/2026-11-04-ci-runner-minute-accounting.md` carrying the cap verification, the per-workflow accounting, the cancelled-run lifetime distribution, the hour-of-day table, the delivered-concurrency finding, and one row per lever with its ruling.
2. An ADR-276 amendment (dated, append-only) recording that demand trimming was evaluated and found to have no safe lever beyond S2/S3, that the residual risk is delivered concurrency, and the re-evaluation triggers. A one-line note under the ADR-270 2026-11-03 addendum that the 60-job Team cap is verified against the docs.
3. Comment corrections: the two stale 75-minute statements in `cron-merge-queue-stall-dispatch.ts` (lines 20 and about 42) rewritten with the 120/45 arithmetic, and the "~6.7 min" leg comment in `infra-validation.yml` gets a dated re-measure.
4. Two linked operator-only issues (larger runner for the `test` aggregator and tail gate jobs; GitHub support ticket for under-assignment), each with re-evaluation criteria and the 2026-11-03T22:52Z sample, plus a hand-off comment on epic #11556.

### Stall-dispatch margin arithmetic (replaces the line-42 text)

Margin = 120 minutes (ruleset `check_response_timeout_minutes`) minus (45-minute stall threshold + 0 to 10 minute wait for the next tick + dispatch-to-runner wait + run time).

All figures are the margin before the executor's own run time (the stall-check job is capped at `timeout-minutes: 10`; the comment must say so).

- Worst tick phase, no runner delay: 120 - 45 - 10 = about 65 minutes.
- Average tick phase, median runner wait (about 30 s): 120 - 45 - 5 - 0.5 = about 70 minutes.
- Worst tick phase at the p90 runner wait of about 20 minutes (ADR-248 population, 2026-09-24): 120 - 45 - 10 - 20 = about 45 minutes. A different population, the 2026-11-03T22:52Z probe sample, shows a median live queued age of 998 s (about 17 minutes) during the under-assignment episode, consistent with that p90; the comment cites ADR-248 and names that sample.
- At the original 75-minute timeout the same worst-phase p90 case was about zero; that history is kept, dated and worded "was".
- ADR-270 notes the timeout may count from the `merge_group` build start rather than `enqueuedAt`, so the figures are conservative.
- The "30-minute window" statements (the header sentence at the "WHY NOT `schedule:`-only" paragraph, and the "not a substitute for the 30-minute window" sentence in the "WHY INNGEST DISPATCH IS ELIGIBLE HERE" paragraph) become dated statements: "30 minutes when written (June 2026, against the then 75-minute timeout); a 75-minute window (45 to 120) since the 2026-11-03 raise to 120".

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "confirm the GitHub Team-plan concurrent-job cap against the docs" | Audit section 1; ADR-270 one-line note | mapped |
| 2 | "account runner-minutes per workflow" | Audit section 2 (census plus job sampling, reproduction commands) | mapped |
| 3 | "trim CI demand (cancelled-run churn, matrix and trigger trimming in ci.yml, tenant-integration.yml, infra-validation.yml and their tests)" | Audit lever table with CTO ruling per lever (b to e); ADR-276 amendment; infra-validation comment re-measure. Ruling: no safe demand-trim code beyond S2/S3. Flagged as a User-Challenge row (scope narrower than the ask). | mapped (ruled no-change) |
| 4 | "fix the stale 75-minute comment in apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts (line ~42) in the same change" | Phase 2 (lines 20 and 42) | mapped |
| 5 | "Technical forks go to the CTO agent, not the operator" | Ruling table in decision-challenges.md | mapped |
| 6 | "Do not touch the launch-check files or the worktree chore-launch-check-live-check-11956" | Constraint; nothing in Files lists | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Audit file | "account runner-minutes per workflow" | asked |
| ADR-276 amendment | "Do the open investigation list" | asked |
| ADR-270 one-line note | "confirm the GitHub Team-plan concurrent-job cap against the docs" | asked |
| Stall-dispatch comment fix (lines 20 and 42) | "fix the stale 75-minute comment ... (line ~42)" | asked (line 20 holds the same stale figure) |
| infra-validation leg-time comment re-measure | "matrix and trigger trimming in ... infra-validation.yml" | asked (CTO ruling 1c: comment only) |
| Two deferred operator issues | "Technical forks go to the CTO agent" | inferred: the CTO classed larger runners (spend) and the support ticket (vendor contact) as operator-only; tracking them avoids an invisible deferral |

### Split Assessment

- Subsystems touched: 3 (decision records, one server comment, one workflow comment)
- Planned files: 7 | Estimated changed lines: about 260 (mostly the audit and ADR amendment prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

Two open code-review issues name `.github/workflows/infra-validation.yml`:

- #8735 (`notify-main-failure` misses cancelled jobs): Acknowledge. Different concern (alert routing); this plan only edits a comment in that file.
- #7942 (two `*.mutation.sh` batteries run in no gate): Acknowledge. Different concern; remains open.

No open code-review issue names the other planned files.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent was consulted twice (rulings 2026-11-04). It ruled no change for PR-run cancel logic (1b), infra-validation triggers and matrix (1c), ci.yml matrices (1d) and tenant-integration (1e); keep the 120-minute timeout and the 45-minute stall threshold (2); classed supply options as operator-only spend or vendor contact (3); and required the audit, the ADR-276 amendment and the ADR-270 note (4). It first ruled a main-health-monitor cron re-slot (05/11/17/23), then withdrew it after the 9-day hour-of-day table showed a 6% difference.

No Product/UX surface: no UI files in Files to Edit or Create, so the Product/UX gate is not triggered. Finance/COO are not relevant to this change; the spend decision is deferred to the operator through a tracked issue.

## User-Brand Impact

- **If this lands broken, the user experiences:** no behaviour change: the change is comment text, a dated audit, and decision records (merging a file under `apps/web-platform/**` does trigger a `web-platform-release` redeploy of the same behaviour). The only user-facing risk is a wrong comment misleading a future change to the merge-queue probe.
- **If this leaks, the user's workflow is exposed via:** no vector: no secret, credential, or customer data enters the audit (only workflow names, run counts and job-minute totals).
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** none, because no runtime behaviour, trigger, or required-context reporting changes; a tier above would apply only if S4 were activated, which is out of scope.

threshold: none, reason: the only server file touched is comment-only (`cron-merge-queue-stall-dispatch.ts`); no runtime behaviour changes.

## Observability

```yaml
liveness_signal:
  what: scheduled-actions-queue-health probe verdict (HEALTHY / SATURATED / UNDER_ASSIGNED) with jobs_in_flight vs the 60-job cap
  cadence: every 30 minutes (Inngest dispatch with schedule fallback)
  alert_target: Sentry cron monitor heartbeat plus the [ci/actions-queue-health] action-required issue
  configured_in: .github/workflows/scheduled-actions-queue-health.yml and scripts/actions-queue-health.sh
error_reporting:
  destination: GitHub issue [ci/actions-queue-health] (action-required) and a Sentry cron check-in flipped to error
  fail_loud: the SOLEUR_ACTIONS_QUEUE_HEALTH log line carries verdict=UNDER_ASSIGNED and the issue is filed
failure_modes:
  - mode: runner under-assignment (delivered concurrency far below the 60-job entitlement)
    detection: UNDER_ASSIGNED verdict from the 30-minute probe
    alert_route: action-required issue plus Sentry error check-in
  - mode: merge-queue entry pending past the stall threshold (45 minutes)
    detection: merge-queue-stall-check.yml dispatched every 10 minutes by cron-merge-queue-stall-dispatch
    alert_route: merge-queue-stall issue and Sentry check-in
  - mode: queue timeout figure drifts from the comments that describe it
    detection: ruleset parity test T-mq-1 (tests/scripts/test-audit-ruleset-bypass.sh) holds tf, DR script and README equal; drift in the stall-dispatch header comment is undetected and accepted (CTO ruling 4 rejects a test pinning it) - the acceptance-criteria greps cover this PR only
    alert_route: CI failure on the PR that changes tf, DR script or README
logs:
  where: GitHub Actions run logs of the queue-health and stall-check workflows
  retention: 90 days (GitHub default)
discoverability_test:
  command: grep -c -e "check_response_timeout_minutes *= 120" infra/github/ruleset-ci-required.tf
  expected_output: 1
```

## Architecture Decision (ADR/C4)

### ADR

No new ADR. The decision "demand trimming has no safe lever beyond S2/S3; residual risk is delivered concurrency" extends ADR-276 (Decisions 1, 4, 5 and its stage structure), so the work phase appends a dated `## Amendment 2026-11-04 (#12030 demand-lever evaluation)` to `ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`, using the `soleur:architecture` skill. It contains: the explicit line that demand trimming was evaluated and has no safe lever beyond S2/S3; the residual supply-side risk; the lever table by reference to the audit; and the re-evaluation triggers (peak queued-job count under about 60 for a week, or a `checks_timed_out` removal after the 120-minute raise, or a second UNDER_ASSIGNED sample). Append a dated line under the stage-status list per the append-only convention. ADR-270 gets one dated line under "Addendum 2026-11-03" stating that the 60-job Team cap is verified against docs.github.com/en/actions/reference/limits (2026-11-04).

### C4 views

No C4 impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): no new external human actor (no new correspondent or reviewer), no new external system or vendor (GitHub, modelled as `github` "Source control, CI/CD, issue tracking, and releases", is the only system involved and is unchanged), no new container or data store, and no change to any actor-to-surface access relationship. Derived cardinalities embedded in edge prose are unchanged because no workflow, cron monitor or heartbeat slug is added or removed; `plugins/soleur/test/c4-count-parity.test.sh` passes on the baseline (13 passed, 0 failed) and must still pass after the change.

### Sequencing

The ADR amendment is authored in the same PR as the audit it cites; nothing is deferred to a follow-up issue.

## Implementation Phases

### Phase 1: Evidence and audit

1. Re-run `scripts/ci-demand-census.sh` for one 3-hour evening-peak window (2026-11-03T19:00Z to 22:00Z; it aborts on a persistent per-run HTTP 502, so retry once in two 90-minute halves). Cap the effort: if it still aborts, label every peak figure "sampled" in the audit and move on. If the peak census contradicts the sampled shares (for example `ci.yml` cancelled runs below 20% of peak minutes, or a workflow outside `ci.yml`, `infra-validation.yml` and `main-health-monitor.yml` above 15%), do NOT write the "no safe lever" sentence: return the figures to the CTO agent for a re-ruling first. Keep the quiet-window figures already in Research Insights.
2. Write `knowledge-base/engineering/audits/2026-11-04-ci-runner-minute-accounting.md` modelled on `2026-11-03-suite-time-top-15-report.md`: method with reproduction commands; cap verification with the docs URL and quoted table; per-workflow accounting; cancelled-run lifetime distribution; hour-of-day table with both windows and the 6% result; delivered-concurrency finding; one table row per lever (a to e, S4, supply) with its CTO ruling and the measured reason.

### Phase 2: Comment corrections

1. `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` (comment text only): rewrite the "WHY NOT `schedule:`-only" window sentence (header line 20 at plan time), the "not a substitute for the 30-minute window" sentence, and the DETECTION LATENCY paragraph (the "Against the 75-minute timeout the margin is 30 minus those three terms" text, line 42 at plan time) using the margin arithmetic above. Sweep the whole file: `grep -nE "75-minute|30-minute window|75 minutes" <file>` and fix or date every hit.
2. `.github/workflows/infra-validation.yml` (comment only, in the `deploy-script-tests` matrix comment block that says "worst leg ~6.7 min" and sets `timeout-minutes: 15`): re-measure the WORST leg and the p95 over the same 10 green PR runs (leg durations from the jobs API, `deploy-script-tests (1/4)` to `(4/4)`), then add a dated line "worst leg X min, p95 Y min, so the 15-minute ceiling is Zx the worst leg (was 2.2x at 6.7 min)". Compare worst with worst, never a mean with a worst case (the mean is about 10.5 min). Raise to 20 only if leg p95 exceeds 12 min (a follow-up trigger, not an action). Keep the original 6.7 min text as history. Cost note: this PR will run the infra-validation workflow on itself (about 56 job-min).
3. Before editing the infra-validation comment, grep `.github/scripts/test`, `plugins/soleur/test` and `scripts` for the literals `6.7` and `403` near `deploy-script-tests` to confirm no suite pins that comment text.

### Phase 3: Decision records

1. Append the ADR-276 amendment and the dated stage-status line (see Architecture Decision). Keep the amendment short: the ruling sentence, the residual-risk sentence, the re-evaluation triggers, and a pointer to the audit; the data lives in the audit only.
2. Add the ADR-270 one-line note under the heading `### Addendum 2026-11-03 (#12030)` (the first of the two ADR-270 headings that start "Addendum 2026-11-03"; the other, `## Addendum 2026-11-03: follower detection-only ...`, is the ADR-318 follower contract and must not be touched): "re-verified 2026-11-04: Team = 60 concurrent jobs, <https://docs.github.com/en/actions/reference/limits>".

### Phase 4: Tracking issues and hand-offs

Create two `deferred-scope-out` issues in milestone "Post-MVP / Later", each with what was deferred, why, and re-evaluation criteria, and link them from the audit and ADR-276 amendment:

1. "ci: evaluate larger runners for the `test` aggregator and tail gate jobs (spend, operator decision)". Larger runners have a separate 1,000-job pool billed per minute (docs). Re-evaluate when UNDER_ASSIGNED or `checks_timed_out` recurs after the 120-minute raise.
2. "ci: open a GitHub support ticket about runner under-assignment (26 of 60 delivered, 2026-11-03T22:52Z)". Attach the probe sample, the 90-sample distribution and the 2026-09-22 precedent. The body carries `automation-status: UNVERIFIED - soleur:work MUST run a Playwright attempt against the GitHub support portal before any operator hand-off`.

Then post one comment on epic #11556 (Lever A) handing over the PR-run-cost finding: a green PR run now reads about 330 job-min (ADR-276 Context read about 100 on 2026-10-07; different bases, cause unmeasured) and the test-scripts suites sit 12% to 190% over their committed prices.

### Phase 5: Verify

Run the acceptance-criteria commands below. The PR is opened by `soleur:ship`, which authors the PR body: it must lead with the plain finding ("no safe demand-trim lever beyond S2/S3; ask #3 met by a ruling, not by code"), link the audit and the two linked issues, use `Ref #12030` (the issue's own re-evaluation triggers keep it open unless the operator closes it), and carry the User-Challenge row from `decision-challenges.md`. The PR touches `infra-validation.yml`, so its own PR run includes the infra-validation workflow (about 56 job-min).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` (comment text only: the two "30-minute window" sentences, the "Against the 75-minute timeout" DETECTION LATENCY paragraph, and any other stale timeout figure)
- `.github/workflows/infra-validation.yml` (comment only, near the deploy-script-tests matrix)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (append amendment and stage-status line)
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` (one dated line under `### Addendum 2026-11-03 (#12030)`)

## Files to Create

- `knowledge-base/engineering/audits/2026-11-04-ci-runner-minute-accounting.md`
- `knowledge-base/project/specs/feat-one-shot-12030-ci-runner-starvation/tasks.md` (planning)
- `knowledge-base/project/specs/feat-one-shot-12030-ci-runner-starvation/decision-challenges.md` (planning)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -nE "75-minute|30-minute window|75 minutes" apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` lists only hits that carry a date or the word "was" (each reads as history, none states the live timeout as 75); `grep -c "75-minute merge-queue check timeout" <same file>` prints `0`; the DETECTION LATENCY paragraph states the 120/45 arithmetic as margins before run time (about 65 / 70 / 45 minutes).
- [ ] Comment-only proof, run for each of `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` and `.github/workflows/infra-validation.yml`: `git diff -U0 origin/main...HEAD -- <file> | grep -E '^[+-][^+-]' | grep -vcE '^[+-][[:space:]]*(//|\*|/\*|#)' || true` prints `0` (the `|| true` is needed because `grep -c` exits 1 on zero).
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-merge-queue-stall-dispatch.test.ts` exits 0; `bash scripts/lint-workflows.sh` reports no finding for `infra-validation.yml` that is absent on `origin/main` (the script exits 0 even with findings, so compare the finding lines, not the exit code).
- [ ] The audit exists and contains: the docs URL `https://docs.github.com/en/actions/reference/limits` with Team = 60; a per-workflow job-minute table with its number bases; the cancelled-run lifetime distribution; the hour-of-day table with both windows (9-day and 2.7-day) and the 6% result; the 2026-11-03T22:52Z under-assignment sample; one ruled row per lever (1a to 1e, S4, supply, `max_entries_to_build`, suite minutes, supabase-watchdog); and a reproduction command for every number (each figure in the audit traces to `scripts/ci-demand-census.sh` or a named `gh api` query).
- [ ] ADR-276 has a dated amendment containing the sentence that demand trimming was evaluated and found to have no safe lever beyond S2/S3 and that the residual risk is delivered concurrency (written only if the Phase 1 peak census did not contradict the sampled shares); the stage-status list gains a dated line and no earlier row is edited.
- [ ] ADR-270 carries the "re-verified 2026-11-04" cap note under `### Addendum 2026-11-03 (#12030)` and the ADR-318 follower addendum is unchanged (`git diff origin/main...HEAD -- <ADR-270 file>` shows one added line).
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 with 0 failed; `bash tests/scripts/test-audit-ruleset-bypass.sh` exits 0 (its T-mq-1 holds the ruleset tf, DR script and README equal at 120).
- [ ] `git diff --name-only origin/main...HEAD` lists no launch-check file and nothing under `.worktrees/chore-launch-check-live-check-11956`; the only workflow file listed is `.github/workflows/infra-validation.yml`; no `.tf` file and no cron expression is changed.
- [ ] Two linked follow-up issues exist (`deferred-scope-out`, milestone "Post-MVP / Later"), linked from the audit and the ADR-276 amendment; the epic #11556 comment is posted.
- [ ] PR body uses `Ref #12030` and carries the User-Challenge row from `decision-challenges.md`; `npx markdownlint-cli2` passes on every file this change adds or edits under `knowledge-base/`.

### Post-merge (operator)

- [ ] None required. The re-evaluation triggers live in the two linked follow-up issues and the ADR-276 amendment.

## Test Scenarios

- Given the stall-dispatch header after the edit, when a reader computes the margin at the worst tick phase and p90 runner wait, then the text yields about 45 minutes before run time, not "about zero".
- Given the ruleset value 120, when `grep -c -e "check_response_timeout_minutes *= 120" infra/github/ruleset-ci-required.tf` runs, then it prints `1`.
- Given the full diff, when it is scanned for workflow `on:`, `strategy.matrix`, `concurrency` and cron changes, then none appear.

## Dependencies & Risks

- Risk: the peak window could not be censused (HTTP 502 abort). Mitigation: Phase 1 re-runs split windows; the audit states which figures are sampled.
- Risk: the per-run PR cost sample (330 job-min) conflicts with ADR-276's 2026-10-07 figure (about 100). Mitigation: the audit states the bases differ and the cause is unmeasured, rather than asserting one.
- Risk: the operator may prefer a trim lever despite the ruling. Mitigation: flagged as a User-Challenge row; S4 activation (#9729) is the only structural lever and stays operator-gated.
- Risk: the residual starvation is supply-side, so the cap fix may not remove the symptom. Mitigation: the two operator follow-ups carry the evidence.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan carries a concrete section with threshold `none` and a scope-out reason.
- Do not pin the measured numbers in a test; they go stale (CTO ruling 4).
- When sweeping for stale timeout figures, exclude `web-platform-release.yml`'s unrelated 75-minute needs-path cap (`scripts/ci-push-dedupe.test.sh:824`) and the egress-audit 75-minute window; they are not the merge-queue timeout.
- ADR-276's stage table still reads "S4 not started"; the convention is append-only dated lines, so add a dated line, do not edit the row.
- The PR edits `infra-validation.yml`, so it triggers that workflow on itself; keep the edit comment-only so no behaviour is under test.

## References

- Issue #12030; ADR-270 (addendum 2026-11-03), ADR-276, ADR-248, ADR-262, ADR-217, ADR-181
- `scripts/ci-demand-census.sh`, `scripts/actions-queue-health.sh`, `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md`
- Vendor: <https://docs.github.com/en/actions/reference/limits> (fetched 2026-11-04)
