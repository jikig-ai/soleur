---
title: "fix(ci): bound the webplat mutation batteries so monitor shards stop hitting the 30-min step timeout"
type: fix
date: 2026-11-11
slug: fix-webplat-monitor-timeout
branch: feat-one-shot-12626-webplat-monitor-timeout
issue: 12626
closes: 12626
priority: P1
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

<!-- lane note: no spec.md exists for this branch yet, so lane falls back to the
     fail-closed default `cross-domain` (plan-issue-templates.md Stage 2). -->

# fix(ci): bound the webplat mutation batteries so monitor shards stop hitting the 30-min step timeout

## Enhancement Summary

**Deepened on:** 2026-11-11
**Sections enhanced:** Research Insights (learnings), Research Reconciliation,
Guard Contract (lint-compliant mutation matrix), Proposed Solution (invocation
shape), Acceptance Criteria (ambient-run fix), Dependencies & Risks
(required-check surface).
**Research agents used:** sequential-fallback — all deepen-plan roles executed
inline in this session (nested Task spawns unavailable in the Devin subagent
harness): per-section repo research, learnings scan
(`knowledge-base/project/learnings/`), plan-review panel (dhh / kieran /
code-simplicity / cto-devex), gate verifiers §4.4–§4.13.
**Reviewed-Coverage: sequential-fallback**

### Key Improvements

1. **Learning applied:** `2026-11-07-a-required-shard-on-its-timeout-edge…`
   — this exact defect already cost PR #12262 ~7h of merge-queue coin flips;
   the recorded flip trigger ("pin the batteries to one shard or give them
   their own job") is this plan's arms D/B, and its "third shard would repeat
   them" warning eliminates the naive K-increase option. Arm A (bare raise)
   was already executed as #12279 (25→35) and went stale in ~4 days.
2. **Guard Contract brought to lint compliance:** `**Mutation matrix:**` is
   now a 4-row table (silent-decline, matrix-drop, second-member,
   dispatch-red) satisfying `lint-guard-contract.py` ≥3 rows.
3. **Plan-review consolidation applied:** brittle count-probe replaced with
   a substring probe; AC-5 re-expressed against a plan-controlled
   `workflow_dispatch` run; `shard-totality-mutations` job cited as the
   verbatim copy-shape for exit-code/`elapsed_s` propagation; required-check
   ruleset sync added as a named risk.

### New Considerations Discovered

- ci.yml hard-codes the leg census in three places beyond the `if:` mirror —
  the "gated set is eight jobs" comment (~line 151), the oracle-selection jq
  leg list (~line 252), and the draft-light leg list (~line 275); each names
  `test-webplat` et al. and must gain `test-webplat-mutations` in lockstep.
- Arm-A precedent documented: bare timeout raises here have a measured
  ~4-day half-life; the derivation comment must name the measured max, not
  just the result.

## Overview

Every scheduled `main-health-monitor` run since 2026-11-10 fails a `test-webplat`
shard: the `Run test suite` step is killed at its 30-minute `timeout-minutes`
ceiling while the `approval-guard1-mutation` kill battery (G1-ISO*/G1-WH* rows)
is still mid-run — run `43016553737` killed it with exit 143/SIGTERM at
`1243146ms` (~20.7 min on a starved leg), and both webplat legs failed in runs
`43016553737` and `42777702144`.

Root cause is structural, not a regression in any one battery: the three webplat
mutation batteries (`approval-guard1-mutation`, `destroy-ask-mutation`,
`home-census-mutations`) are plain unconditional `run_suite` registrations
inside `scripts/test-all.sh`'s `webplat` arm (scripts/test-all.sh:7387–7395),
while `VITEST_SHARD` partitions only the vitest projects. Each 2-way monitor leg
therefore runs every battery in full — a duplicated, unbounded ~25-min serial
cost that sits on top of the sharded vitest work and grew past the ceiling as
rows were added (the ADR-309 9b expansion). The same duplication exists in
`ci.yml`'s `test-webplat` legs, whose own comment names the same two remedies
(bound/split vs. raise the ceiling).

The recommended fix (see Alternative Approaches for the rejected arms): move the
three battery registrations behind a `VITEST_SHARD`-unset gate in the webplat
arm — so the sharded vitest legs decline them honestly via `skip_suite` — and
run them on a dedicated `test-webplat-mutations` job in both `ci.yml` and
`main-health-monitor.yml` with a per-battery matrix and a step ceiling derived
from measured per-battery maxima, mirroring the `test-scripts-heavy`
dedicated-leg precedent. Whole-battery-per-leg first; `--rows` row-splitting of
`approval-guard1-mutation` is a follow-up lever if a single leg later tips.

## Research Insights

### Premise Validation

| Issue claim | Verdict | Evidence |
|---|---|---|
| `test-webplat` monitor shards hit the 30-min `Run test suite` timeout | confirmed | `.github/workflows/main-health-monitor.yml` webplat job: `timeout-minutes: 50` job / `timeout-minutes: 30` step; issue cites runs `43016553737`, `42777702144` |
| `approval-guard1-mutation` killed mid-run (~1243s, SIGTERM) | consistent | `apps/web-platform/test/approval-guard1-mutation.test.sh` is ~1,151 lines, ~343 mutation rows, one targeted Vitest run per mutant, header estimate ~25 min; `WALL_BUDGET_S=3000` is advisory only — warns, never enforces |
| "Shards hop" — `test-scripts (3/8)+(4/8)` on run `42812155417` | partially refuted | That run's scripts legs died on assertion failures (`fixture-relative-assert.test.sh`, `required-checks-merge-group-coverage.test.sh`), not timeout kills — a different defect class; scope stays on webplat |
| Fix space = bound/split OR raise timeout | confirmed | `ci.yml` flip-trigger comment states both remedies for the identical topology |

### Property List (invariants the fix must preserve)

- Every mutation battery keeps running on main and on relevant PRs — coverage is
  relocated, never silently dropped (the `#5417` orphan-suite class).
- `run_suite`/`skip_suite` pairing: a decline is a verdict (ADR-181); each
  registration site ticks exactly once per leg per execution surface.
- `scripts/test-all-webplat-gate.test.sh` keeps its 16-assertion anti-vacuity
  shape: the `repo-wide`/`unit` vitest gate predicates must remain the first
  `_diff_touches` token in the `want_webplat` block — new conditionals must sit
  below the existing unit gate and must not reuse that token.
- Monitor static guard (`plugins/soleur/test/main-health-monitor-workflow.test.sh`)
  stays green: every leg job timeout > suite-step timeout + margin; `report`
  `needs` covers all legs; report timeout + worst leg ≤ the 360-min inter-fire
  Sentry envelope.
- `bash scripts/test-all.sh --list` enumerate output must still list the three
  battery labels (local runs unaffected — `VITEST_SHARD` unset → `run_suite`).
- `guard-vacuity-floor.test.sh` PROMOTED_FILES and
  `fixture-relative-assert.baseline.txt` references to the battery files stay
  valid (files are edited in place or not at all in this slice).
- Local dev UX unchanged: `bash scripts/test-all.sh` with no `VITEST_SHARD`
  still runs the batteries.

### Cut List

- Not in scope: `test-infra` Docker/apt starvation (#12549 — separate issue).
- Not in scope: `test-scripts`/`test-scripts-heavy` leg balance (already
  manifest-sharded; the observed scripts failures were assertion, not timeout).
- Not in scope: shrinking battery coverage, capping mutation rows, or changing
  per-mutant verdict semantics (`KILLED`/`SURVIVED`/`MISATTRIBUTED`/`BROKEN`/
  `UNRESOLVED`).
- Not in scope: `--rows` row-splitting machinery for webplat batteries —
  deferred lever; implementing it now would pull the shard-totality `-<letter>`
  label contract + manifest plumbing into this diff.

### Relevant Learnings / Prior Art

- `test-scripts-heavy` (3-way `SCRIPTS_SHARD` matrix in the monitor +
  `scripts/suite-shard-legs-heavy.tsv` leg assignment) is the existing dedicated
  heavy-leg precedent: `registry-gate-mutation-battery` (~854s issue / 491,178ms
  measured in `scripts/suite-durations-heavy.tsv`) and
  `battery-tag-authorship-mutations` (~584s / 379,182ms) already live on
  dedicated heavy legs, not inside the vitest shards.
- `_suite_budget_ms()` in `scripts/test-all.sh` already declares a measured
  budget for `tests/scripts/registry-gate-mutation-battery` (`2500000`) — no
  webplat battery has one; the fix should add budget entries for the moved
  batteries so the capacity signal sees them.
- `#7942` (open code-review): two `plugins/soleur/test` `*.mutation.sh`
  batteries run in no gate — same unbounded-battery class, different files; do
  not conflate.
- `test-all-webplat-gate.test.sh` mutation-matrix discipline: every static
  shape assertion pairs with a mutant that must drive it red.
- **`2026-11-07` learning — `a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip`:**
  the SAME defect already cost PR #12262 ~7 hours of merge-queue coin flips —
  `test-webplat` shards cancelled at the (then) 25-min job ceiling with no
  failing assertion. The remediation was a one-integer raise to 35 min
  (#12279), and the review falsified the assumed cause: the vitest split is
  ~5 min; the wall time is the mutation batteries running in full on BOTH
  shards. Its recorded flip trigger is verbatim: *"pin the batteries to one
  shard or give them their own job"* — exactly this plan's arms D and B. Its
  warning that a third shard "would repeat them" eliminates the naive
  K-increase option. `ci.yml` now carries `timeout-minutes: 35` on the
  webplat job (line ~1551) — arm A was already tried and bought 4 days.

### File Paths Examined

`.github/workflows/main-health-monitor.yml`, `.github/workflows/ci.yml`,
`scripts/test-all.sh` (webplat arm ~7228–7400; `_suite_budget_ms`;
`SCRIPTS_SHARD` engagement + validation), `scripts/suite-shard-legs.tsv`,
`scripts/suite-shard-legs-heavy.tsv`, `scripts/suite-durations-heavy.tsv`,
`apps/web-platform/test/{approval-guard1-mutation,destroy-ask-mutation,home-census-mutations}.test.sh`,
`plugins/soleur/test/main-health-monitor-workflow.test.sh`,
`plugins/soleur/test/scripts-shard-totality.test.sh`,
`scripts/test-all-webplat-gate.test.sh`, `scripts/guard-vacuity-floor.test.sh`.

## Research Reconciliation — Spec vs. Codebase

- **Arm A was already executed once and went stale in ~4 days.** ci.yml's
  webplat job was raised 25→35 min in #12279 (2026-11-07, learning
  `a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip`);
  the monitor's step ceiling stayed 30 and is now red again. A bare raise is
  the documented symptom-treating arm, not the fix.
- **"Shards hop" is two different defects.** Issue text mixes webplat timeout
  kills (this fix) with `test-scripts` assertion failures on `42812155417`
  (different class). Plan scope: webplat timeout only.
- **"30-min action timeout" is a step ceiling, not a job ceiling.** Job is
  50 min; only the `Run test suite` step is capped at 30. The kill is GitHub's
  `timeout-minutes` enforcement (exit 143), not a runner eviction or heartbeat
  loss — the issue's `##[error]The action 'Run test suite' has timed out`
  annotation is authoritative.
- **Measured outliers in the issue are scripts-heavy batteries**, not webplat:
  `registry-gate-mutation-battery` ~854s and `battery-tag-authorship-mutations`
  ~584s sit in the scripts group/manifest, proving the dedicated-leg pattern
  works at exactly this magnitude.
- **The 30-min ceiling was derived honestly** (workflow comment: measured leg
  max ~17.2 min × 1.5 → 30) but the derivation predates the unbounded-battery
  growth; the same derivation discipline must re-apply to whatever topology
  lands.

## Problem Statement

The `test-webplat` monitor (and PR `test`) topology conflates two workloads in
one step: native-Vitest-sharded unit/component/repo-wide coverage, and serial
shell mutation batteries that `VITEST_SHARD` cannot partition. As
`approval-guard1-mutation` grew to ~343 rows / ~25 nominal minutes, each leg's
wall time reached the 30-min step ceiling; on a starved or loaded leg the
battery is killed mid-table, the step reports `timed out`, and every monitor
run since 2026-11-10 files red — masking real signal and burning the
main-health signal budget (#12455, #12618 trackers; #11556 wall-clock epic).

## Proposed Solution

**Move the three battery registrations behind a `VITEST_SHARD`-unset gate and
run them on a dedicated per-battery monitor/CI job.**

1. `scripts/test-all.sh` webplat arm: wrap the three battery registrations
   (current `run_suite` sites at 7387/7391/7395) in a `VITEST_SHARD`-unset
   predicate — `run_suite` when unset (local), `skip_suite` when set (CI legs),
   with the skip reason naming the dedicated job as the execution surface.
   Sits below the existing unit gate; uses no `_diff_touches` token.
2. `.github/workflows/ci.yml` + `.github/workflows/main-health-monitor.yml`:
   new `test-webplat-mutations` job, `strategy.matrix.battery` over the three
   battery stems, invoking `bash apps/web-platform/test/<battery>.test.sh`
   directly (mirroring the `shard-totality-mutations` direct-invocation
   precedent — copy that job's shape verbatim, including battery exit-code →
   step-failure propagation and the leg-report/`elapsed_s` emission the
   monitor's report job consumes), with the same checkout/bun/npm-ci/bwrap
   preamble the webplat legs use.
3. Ceilings: step `timeout-minutes` = `roundup5(measured_max × 1.5)` applied per
   the worst battery leg (`approval-guard1-mutation` ~25–30 min nominal →
   step 45, job 60 monitor / 45–50 ci); lighter legs finish early under the
   shared ceiling. Re-derive and update the budget comments in both workflows.
4. Monitor wiring: add the job to `report` `needs`, leg-status env (`R_` vars),
   failure-leg iteration, artifact naming, and the leg-report upload steps;
   update `plugins/soleur/test/main-health-monitor-workflow.test.sh`'s leg
   census, timeout-margin, and 360-min envelope expectations.
5. `ci.yml` wiring: add the job to the `test` aggregator's `needs`/`if:` set and
   to any oracle-selection / draft-light `if:` mirrors that enumerate leg ids;
   update the flip-trigger comment that names this fix.
6. `_suite_budget_ms()` entries for the three moved batteries so
   `test-all-capacity-signal` continues to see them; update
   `scripts/suite-durations*.tsv` if the capacity machinery consumes them for
   the new job's legs.

### Deferred lever

`--rows` row-splitting of `approval-guard1-mutation` — only if a dedicated leg
later approaches its ceiling. Not needed at current row counts. **Correction
(CTO ruling, 2026-11-11):** the battery does NOT support `--rows` today — its
argv is `[--only <ERE>] [--list] [--check-anchors]` — so the follow-up lever is
"add a `--rows` arm (or an `--only` ERE tiling plus a row-count/DECLARED_TOTAL-style
pin)", carrying the `shard-totality-mutations` contiguous-tiling + `-<letter>`
label contract with it.

## Alternative Approaches Considered

| Arm | Shape | Verdict |
|---|---|---|
| **A. Raise the step timeout only** (e.g. 30→45) | one-line YAML + comments | Rejected as the fix: treats the symptom; batteries stay duplicated on both legs (2× runner cost per battery), the vitest-vs-battery conflation remains, and the edge re-opens on the next row expansion. Kept in the diff anyway as a *derived* number — the dedicated job still needs an honest ceiling. |
| **B. Dedicated per-battery job + `VITEST_SHARD` gate** (recommended) | new job in 2 workflows; ~10-line gate in test-all.sh | Removes duplication, bounds each battery on its own leg with an honest derived ceiling, gives each battery a distinct verdict line in the leg report, matches the `test-scripts-heavy` precedent. Cost: new required-check surface in ci.yml (aggregator + `if:` mirrors). |
| **C. `--rows` row-split inside test-all.sh via VITEST_SHARD** | each leg runs a row slice | Rejected for this slice: pulls the shard-totality contract (labels `-<letter>`, contiguous tiling, manifest placement) into the vitest arm where no manifest exists; bigger diff, same outcome as B at current sizes. |
| **D. Pin each battery to one existing leg** (guard1→leg1, etc.) + raise | small gate, no new job | Rejected: leg1 still carries battery+vitest (~26+ min) → still edge-bound; skews leg balance; strictly worse than B. |
| **E. Reduce battery coverage on monitor legs** (subset of rows) | cap rows | Rejected: silently cuts mutation-coverage signal on main; the issue asks to bound/split or re-budget, not to drop coverage. |

## Implementation Phases

### Phase 1 — test-all.sh gating + dedicated job (core)

- Gate the three registrations behind `VITEST_SHARD`-unset in the webplat arm;
  skip reason cites `test-webplat-mutations` legs.
- Add the `test-webplat-mutations` job to `ci.yml` and
  `main-health-monitor.yml` (matrix over three battery stems; derived ceilings;
  same dep preamble).
- Update `_suite_budget_ms()` entries and budget comments.

### Phase 2 — wiring + guards

- Monitor `report` job: `needs`, `R_` env, failure-leg loop, leg artifacts.
- ci.yml `test` aggregator join, plus the three hard-coded leg lists that
  name the webplat leg: the "gated set is eight jobs" comment (~line 151),
  the oracle-selection jq leg list (~line 252) and `skip_legs` membership
  (~line 1539 `if:`), and the draft-light leg list (~line 275); flip-trigger
  comment.
- `plugins/soleur/test/main-health-monitor-workflow.test.sh`: leg census,
  margin assertions, envelope re-derivation.
- `scripts/test-all-webplat-gate.test.sh` (CTO ruling): `run_suite`/`skip_suite`
  pair assertions for each gated battery label — paired mutants per assertion.
- Leg-report compatibility (CTO constraint): a direct
  `bash apps/web-platform/test/<battery>.test.sh` emits no `=== N suites:`/`^RED `
  runner markers, so capture-greps yield thin detail — the leg verdict stays
  honest via `status.env` `outcome=` and the filer on `needs.*.result`. The leg
  MUST still tee into `leg-report/capture.txt`, emit `status.env` + `elapsed_s`,
  and propagate the battery exit code explicitly.

### Phase 3 — validation

- `bash scripts/test-all.sh --list` shows the three labels; `VITEST_SHARD=1/2`
  run declines them via `skip_suite` with the named reason; unset runs them.
- `bash scripts/test-all-webplat-gate.test.sh` and
  `plugins/soleur/test/main-health-monitor-workflow.test.sh` green.
- First scheduled monitor run post-merge: `test-webplat` legs green under the
  unchanged 30-min step; `test-webplat-mutations` legs green under their
  derived ceiling; leg-report artifact records `elapsed_s` per battery.

## Files to Edit

- `scripts/test-all.sh` — `VITEST_SHARD`-unset gate around the three battery
  `run_suite` sites (7387/7391/7395); `_suite_budget_ms()` entries.
- `.github/workflows/ci.yml` — new `test-webplat-mutations` job; `test`
  aggregator join (`needs:`/env/`entries`/`oracle_re` ~2283–2373); `if:` mirrors;
  flip-trigger comment; Guard-3 jq leg list + `length == 6`→7 and its
  "SIX lane-skippable legs" comment (~243–255); "eight jobs" gated-set comment
  (~151–153); draft-light "four heavy families" comment (~275).
- `.github/workflows/main-health-monitor.yml` — new job; `report` wiring
  (`needs:`/`R_` env/filer-OR/closer-AND); `EXPECTED_LEGS` 15→18; ceiling comments.
- `plugins/soleur/test/main-health-monitor-workflow.test.sh` — `LEG_JOBS` tuple
  (~line 116) extension; leg census, margin/envelope expectations for the new leg.
- `scripts/test-all-webplat-gate.test.sh` — `run_suite`/`skip_suite` pair
  assertions for the `VITEST_SHARD` gate (CTO ruling: this file owns the
  `want_webplat`-block extraction and the `mutate()` harness the Guard Contract's
  4-row mutation matrix needs).
- `scripts/ci-push-dedupe.test.sh` — `GATED_PINNED` (~L85), `DL_GATED_PINNED`
  (~L89), `OR_GATED_PINNED` (~L108): classify the new job in both directions.
- `scripts/ci-draft-light.test.sh` — `HEAVY_PINNED` (~L80), `OR_GATED_PINNED`
  (~L97), `LEGS` census (~L161).
- `scripts/ci-oracle-lane.sh` — `ORACLE_SKIP_SET` (~L92), `GUARD:O-GRAMMAR` regex
  (~L420); keep the new leg oracle-skippable (batteries don't exercise the
  C4-render path — `diagrams` carve-out ~L402 stays).
- `scripts/ci-oracle-lane.test.sh` — `ORACLE_FIVE`/`FIVE_RE` (~L259–261) plus its
  check sites.

## Files to Create

- None expected. (If the shard-totality guard contract is reused for a static
  battery-gating assertion, a sibling test may be added under
  `plugins/soleur/test/` — decide at implementation review.)

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` bodies for every
planned path: only `#7942` (`plugins/soleur/test` `*.mutation.sh` batteries,
different files — same defect class, cite as sibling) and `#8881` (ci.yml
test-scripts shard rebalance — tangential). No overlap on the webplat
batteries, the webplat arm, or the monitor workflow.

## Hypotheses

(Network-outage checklist: `timeout` trigger fired; layers verified/opted-out.)

1. **L3 firewall allowlist** — opted out: the kill artifact is GitHub Actions'
   own `timeout-minutes` enforcement (`##[error]The action 'Run test suite'
   has timed out after 30 minutes.` + exit 143 on the step), not a transport
   reset; no host firewall exists in this path. Artifact: the run annotation
   itself.
2. **L3 DNS/routing** — opted out: the step was executing and emitting log
   output when killed (mutation rows progressing through ~1,243s); packets
   flowed. Artifact: step log progression in run `43016553737`.
3. **L7 TLS/proxy** — opted out: no HTTPS dependency governs the step ceiling;
   the step runs local `bash`/`vitest`. Artifact: the workflow step has no
   network precondition.
4. **L7 application layer** — verified: `bash scripts/test-all.sh` was
   mid-battery when the 30-min wall expired; the battery's own advisory
   `WALL_BUDGET_S=3000` documents expected ~50 min > 30 min ceiling.
5. **Service hypothesis (primary): unbounded duplicated serial battery inside a
   sharded step whose ceiling predates the battery's growth** — verified by
   registration inspection (unconditional `run_suite`, VITEST_SHARD only
   reaches vitest) + measured runtimes vs. the derived 30-min ceiling.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  blast radius is CI signal: a miswired gate could silently stop running the
  mutation batteries (coverage silently dropped — the orphan-suite class) or
  keep the monitor red (noise, missed real regressions on main).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  data exposure; wasted GitHub Actions runner minutes if duplication persists.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI topology only — no
  user-facing artifact, API, or data path changes; the worst case is degraded
  internal signal, not user-visible behavior.
- *Scope-out override:* `threshold: none, reason: .github/workflows/*.yml and
  scripts/test-all.sh are preflight-flagged paths but they govern CI
  orchestration, not shipped product behavior.`

## Observability

```yaml
liveness_signal:
  what: main-health-monitor scheduled run + leg-report artifact (existing Sentry envelope monitor for the monitor itself)
  cadence: per scheduled run (360-min inter-fire)
  alert_target: Sentry issue + report-job issue filer on leg failure
  configured_in: .github/workflows/main-health-monitor.yml (report job + upload steps)

error_reporting:
  destination: GHA job/step log + leg-report artifact; monitor failure files an issue via the existing report/filer path
  fail_loud: "##[error]The action '<step>' has timed out after N minutes." plus per-leg non-zero conclusion in the report table; a silently-dropped battery would appear as absence of its verdict line — the leg census in main-health-monitor-workflow.test.sh is the static trip-wire

failure_modes:
  - mode: battery leg still exceeds derived ceiling (starved runner)
    detection: step timeout annotation + leg-report elapsed_s censored; next-run retry pattern in the monitor table
    alert_route: report job failure → issue filer
  - mode: battery silently not running anywhere (gate bug)
    detection: static guard assertion on the run_suite/skip_suite pair + enumerate check (labels absent from CI leg summaries where expected, present in job matrix)
    alert_route: scripts/ plugin test failure on PR + monitor leg-census drift
  - mode: webplat legs regress toward 30 min from vitest growth alone
    detection: elapsed_s in leg-report artifact vs 30-min step ceiling
    alert_route: monitor failure → issue filer

logs:
  where: GHA run logs + uploaded leg-report artifacts per matrix leg
  retention: GitHub default artifact/log retention for the repo

discoverability_test:
  command: grep -n 'test-webplat-mutations' .github/workflows/main-health-monitor.yml
  expected_output: test-webplat-mutations
```

## Task Design

Skipped — no new autonomous-task surface: this edits existing workflow files
(jobs inside `ci.yml`/`main-health-monitor.yml`), not a new
`.github/workflows/*.yml` file, Inngest registration, cron entry, or daemon.
The dedicated job rides the existing monitor/PR triggers.

## Architecture Notes

- **ADR needed:** no — the change re-uses existing doctrine (dedicated heavy
  legs: `test-scripts-heavy`; run_suite/skip_suite decline-as-verdict: ADR-181;
  `VITEST_SHARD` partitioning). No trust boundary, substrate, or C4 element
  changes. If implementation review judges the new required check a required-
  check-topology decision worth recording, a short ADR addendum may follow.
- **C4/diagram impact:** none — CI jobs are not C4 model elements here.

## Domain Review

Domains relevant: **none.** CI/tooling change only — no UI surface (no
`.tsx`/`page`/`layout` paths), no API/schema/auth/data-store changes, no
billing/infra provisioning. Cross-domain implications: none found.

## Guard Contract

### Guard 1 — webplat battery leg-assignment coverage

**Property.** Each of the three webplat mutation batteries executes on exactly
one CI surface per run (the dedicated `test-webplat-mutations` leg) and is
honestly declined — never silently absent, never duplicated — on every
`VITEST_SHARD` leg.

**Assembly.** The three `run_suite`/`skip_suite` pairs in the `want_webplat`
block of `scripts/test-all.sh` (quantifies over the registration sites, not
discovered files — the sites are enumerated by label:
`apps/web-platform/test/{approval-guard1-mutation,destroy-ask-mutation,
home-census-mutations}`), plus the `strategy.matrix.battery` list in both
workflows. The static guard greps the test-all.sh block for each
`run_suite "apps/web-platform/test/<battery>"` paired with a `skip_suite` of
the same label under a `VITEST_SHARD` conditional, and greps both workflow
files for the same three battery stems in the job matrix. If a fourth battery
is registered in the webplat arm later, the guard's label set must be updated
— the guard asserts the label list in both surfaces so drift fails loudly.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one battery's `skip_suite` arm in the `want_webplat` block (decline becomes silent absence on CI legs) | RED |
| 2 | Drop one battery stem from the `strategy.matrix.battery` list in either workflow (coverage gap the monitor can't see) | RED |
| 3 | Add a SECOND battery registration after a compliant first but emit only one `run_suite`/`skip_suite` pair (a check that stops at the first member is the defect itself) | RED |
| 4 | Point the guard at a mutant `test-all.sh` copy where the gate sits below an `exit`-reached line (dispatch never reaches it — vacuous green) | RED |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Every scheduled `main-health-monitor` run since 2026-11-10 fails on the `test-webplat` shards… `##[error]The action 'Run test suite' has timed out after 30 minutes.`" [issue #12626] | Proposed Solution; Phase 1–3; AC-1..AC-4 | mapped |
| 2 | "run `43016553737`, where `approval-guard1-mutation` was killed with exit 143/SIGTERM after `1243146ms`; both webplat shards failed in runs `43016553737` and `42777702144`" [issue #12626] | Proposed Solution item 1 (gate) + item 2 (dedicated job); AC-2 | mapped |
| 3 | "either bound/split the monitor legs or raise the action timeout where the battery legitimately exceeds it" [issue #12626] | Proposed Solution (bound via dedicated leg + derived ceiling); Alternative Approaches A–E | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `VITEST_SHARD`-unset gate on the three battery registrations | "bound/split the monitor legs" | asked |
| Dedicated `test-webplat-mutations` job in both workflows | "bound/split the monitor legs" | asked |
| Derived step/job ceilings + budget comments | "raise the action timeout where the battery legitimately exceeds it" | asked |
| Monitor `report` wiring + `main-health-monitor-workflow.test.sh` updates | — | inferred — justification: the report job `needs:` and the static guard enumerate legs mechanically; a new leg without them is unreported red / a red guard |
| `_suite_budget_ms()` + capacity-signal entries | — | inferred — justification: the capacity signal consumes declared budgets; dropping the entries hides the moved batteries' cost |
| `--rows` split deferred | — | inferred — justification: contiguous-tiling + `-<letter>` contract is a second mechanism; current sizes don't require it |

### Split Assessment

- Subsystems touched: 3 — `.github`, `scripts`, `plugins/soleur`
- Planned files: 4 | Estimated changed lines: ~180
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: `VITEST_SHARD=1/2 bash scripts/test-all.sh` (webplat arm) declines each of `approval-guard1-mutation`, `destroy-ask-mutation`, `home-census-mutations` via `skip_suite` with a reason naming `test-webplat-mutations`; each label still appears in `--list` enumerate output.
- [ ] AC-2: `bash scripts/test-all.sh` with `VITEST_SHARD` unset still registers and runs all three batteries (local coverage preserved).
- [ ] AC-3: `main-health-monitor.yml` contains a `test-webplat-mutations` job with a 3-row `matrix.battery`; the `report` job `needs:` includes it; every leg job timeout > its suite-step timeout + margin; report + worst leg ≤ 360-min envelope — all enforced by `main-health-monitor-workflow.test.sh` green.
- [ ] AC-4: `ci.yml` `test-webplat` legs no longer run the batteries and the new job is in the `test` aggregator's required set; the flip-trigger comment is updated.
- [ ] AC-5: On a `workflow_dispatch` run of the merged `main-health-monitor.yml` (plan-controlled trigger — the deterministic core is AC-1's local decline; this leg verifies only the real-runner timeout ceiling, which no synthetic fixture can exercise — pyramid-justified): `test-webplat` legs complete under the unchanged 30-min step with `elapsed_s` recorded, and `test-webplat-mutations` legs complete under the derived ceiling — verified from the run's downloaded leg-report artifacts, not asserted.
- [ ] AC-6: `bash scripts/test-all-webplat-gate.test.sh` stays green (16-assertion floor) and the extended leg-coverage guard fails on each mutation-matrix row.

## Test Scenarios

- **unit** — gate shape: extract the `want_webplat` block, assert each battery
  label has a `run_suite`/`skip_suite` pair inside a `VITEST_SHARD`
  conditional (drives Guard 1 mutation rows).
- **unit** — enumerate: `VITEST_SHARD=1/2 bash scripts/test-all.sh --list`
  contains the three labels exactly once; unset same.
- **integration** — workflow shape: the extended
  `main-health-monitor-workflow.test.sh` census over six legs incl.
  `test-webplat-mutations`; margin + envelope assertions.
- **integration** — decline verdict: a `VITEST_SHARD=1/2` webplat run emits
  `skipped … test-webplat-mutations` per battery in the summary output.
- **e2e** — post-merge monitor run (pyramid-justified: the defect is the
  GitHub Actions `timeout-minutes` enforcement itself; only a real scheduled
  run exercises it): both webplat legs + three mutation legs green, leg-report
  artifact shows `elapsed_s` for all three batteries.

## Success Metrics

- Zero `test-webplat` step-timeout annotations in monitor runs after merge
  (baseline: every run since 2026-11-10 red).
- `test-webplat` leg `elapsed_s` drops from ~25–30 min to ≤ ~12 min (vitest +
  light suites only) — measured from leg-report artifacts.
- Each battery leg `elapsed_s` within its derived ceiling; savings claim:
  ~15–20 min of duplicated battery wall-clock removed per webplat leg × 2 legs
  × (monitor + PR runs) — measured by diffing leg `elapsed_s` before/after on
  the first green run.

## Dependencies & Risks

- **Risk:** gate conditional placed above the unit gate or reusing
  `_diff_touches` breaks `test-all-webplat-gate.test.sh`'s UNGATED slice →
  mitigated by explicit placement rule + running the guard (Phase 3).
- **Risk:** new required check in ci.yml needs mirrors in
  oracle-selection/draft-light `if:` sets; missing one = leg skipped or
  double-run → mitigated by grepping every `test-webplat`-naming `if:` in
  ci.yml during implementation.
- **Risk:** `guard-vacuity-floor` / `fixture-relative-assert.baseline`
  references to battery files → files are not moved/renamed, only their
  registration sites gated; verify both suites green.
- **Risk (downgraded by CTO ruling, 2026-11-11):** required-check surface —
  `infra/github/ruleset-ci-required.tf:95` pins only the `test` aggregator
  context, not leg names, so NO Terraform/ruleset/required-checks.txt change
  is needed **contingent on the new job joining `test`'s `needs:`** (mandatory
  per the row-4 ruling — keeps battery failures merge-blocking). Residual:
  the `required-checks-merge-group-coverage.test.sh` census still runs at
  implementation to confirm the join lands.
- **Risk:** a starved dedicated leg still tips the derived ceiling → residual
  risk accepted; `--rows` split is the named follow-up lever; the issue
  remains the tracking surface.
- **Dependency:** none external. Sibling issue `#7942` may want the same
  treatment for `plugins/soleur/test` batteries — out of scope, cited.

## References & Research

- Issue #12626 (primary); #11556 (wall-clock epic); #12549 (distinct infra
  starvation); #12455, #12618 (main-red trackers); #7942 (sibling class);
  #8881 (shard-rebalance review precedent).
- `main-health-monitor.yml` webplat: job 50 / step 30; `report` needs 5 legs.
- `scripts/test-all.sh` registrations: 7387, 7391, 7395; `_suite_budget_ms`.
- `approval-guard1-mutation.test.sh`: ~343 rows, `WALL_BUDGET_S=3000`
  advisory, ~25-min header estimate; killed at 1,243s in run `43016553737`.
- Precedent: `test-scripts-heavy` dedicated 3-way matrix;
  `suite-shard-legs-heavy.tsv`; `shard-totality-mutations` `--rows` contract.
- Reviewed-Coverage: **sequential-fallback** — plan/deepen-plan research and
  advisor-consult roles executed inline in this session (nested Task spawns
  unavailable in the Devin subagent harness); functional-overlap and
  community-discovery checks run inline (no uncovered stacks: repo is
  TypeScript/Bash/GHA; no community artifact needed for CI-internal sharding).
