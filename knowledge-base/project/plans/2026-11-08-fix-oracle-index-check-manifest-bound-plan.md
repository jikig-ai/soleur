---
title: "fix(ci): oracle-validation manifest exceeds oracle-index-check's 30-min bound — activation rolled back"
type: fix
date: 2026-11-08
slug: fix-oracle-index-check-manifest-bound
branch: feat-one-shot-12393-oracle-lane-bound
issue: 12393
closes: 12393
lane: cross-domain
priority: high
domain: engineering
brand_survival_threshold: none
---

# fix(ci): oracle-validation manifest exceeds oracle-index-check's 30-min bound — activation rolled back

## Overview

The first post-unlock oracle-only canary (run 42458135078, PR #12382) cancelled
`oracle-index-check` at `timeout-minutes: 30` after completing 5 of the 15 committed manifest
suites with zero failures — the serial manifest measures ~65.4 min from committed duration data
(~90 min projected on-runner) against a 30-minute bound. `CI_ORACLE_LANE` was deleted
2026-11-08; the lane is dark and the full battery gates every PR. This plan shrinks the
validation leg's wall clock under the bound by splitting the manifest's serial execution across
parallel matrix legs — the same shape the repo already runs for `test-scripts` (#7902) — driven
by a committed leg-assignment file, so the lane can be re-armed per
`knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` §Activation.

## Problem Statement

`oracle-index-check` runs every non-comment line of `scripts/ci-oracle-lane-suites.txt`
serially inside one job with `timeout-minutes: 30` (`.github/workflows/ci.yml:2220-2295`). The
measured serial total is 65.4 min (`scripts/suite-durations.tsv`, summed below), and the largest
single member (`plugins/soleur/test/ci-pr-affected-replay-a`) alone is 17.2 min. A cancelled or
skipped `oracle-index-check` is never tolerated by the `test` aggregator on
`pull_request`/`merge_group` (Guard 2 / O2-6 rows in
`plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`), so as activated the lane reds
every oracle-only diff. Re-activation is gated on this issue: the manifest must fit the bound.

## Hypotheses

Triggered by the `timeout` pattern (plan Phase 1.4). The failure is a runner-side
`timeout-minutes` job-kill on a compute-bound workload, not a connectivity defect — every layer
below is opted out per the checklist's opt-out clause, citing the run-log artifact.

1. **L3 firewall allow-list.** [opt-out: no host or SSH path is involved — the runner is
   GitHub-hosted `ubuntu-latest`; run 42458135078's log shows suite output streaming normally
   until the bound kill, i.e., network egress was live throughout]
2. **L3 DNS / routing.** [opt-out: the `git fetch --no-tags origin main` step and `gh` API reads
   inside the suites succeeded (every executed case printed `[ok]`); no resolution or routing
   error appears in run 42458135078]
3. **L7 TLS / proxy.** [opt-out: the failing surface is an intra-runner test loop, not an HTTPS
   endpoint; no TLS error in the run log]
4. **L7 application.** [verified: the job log records 5/15 manifest suites completing `[ok]` in
   29m53s before `timeout-minutes: 30` killed the job — measured-cause evidence, not a guess:
   serial duration exceeds the bound]
5. **H1 (accepted): serial manifest runtime exceeds the 30-min bound.** Measured 65.4 min from
   `scripts/suite-durations.tsv`; canary order-of-completion matches the first five manifest
   members' durations (~28.6 min) — the suite set is healthy, the serial topology is the defect.

## Research Insights

### Relevant file paths

- `.github/workflows/ci.yml:2220-2295` — the `oracle-index-check` job (serial manifest loop,
  `timeout-minutes: 30`, `fetch-depth: 0`, `git fetch origin main` step, `not-oracle-only`
  early exit). Comment at `:2216-2218` keeps `timeout-minutes` alone on its line for the
  release-workflow budget awk (`web-platform-release.yml:836-861` pattern
  `^    timeout-minutes:[[:space:]]*[0-9]+$`).
- `scripts/ci-oracle-lane-suites.txt` — the 15-member validation manifest; grammar pinned at
  exactly `label<TAB>argv` by `check_manifest()` (`MEMBER-BAD-FIELDS`). CODEOWNERS: `@deruelle`.
- `scripts/ci-oracle-lane.test.sh` — the sentinel suite (Guard 4): manifest↔registration parity
  (`check_manifest()` + 10 mutant rows), extracted-step-body sandbox replay
  (`env -i … ORACLE_ONLY=true` over stub manifests of `label<TAB>true|false`), checkout
  `fetch-depth`/`if:` pins.
- `scripts/ci-oracle-lane.sh:170-183` — the driver's hard-exclusion list (driver, sentinel,
  manifest: "a diff touching them always pays the battery").
- `scripts/lib/test-affected-paths.sh:2081-2089` — `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS`
  declared edge set for the sentinel suite.
- `scripts/suite-durations.tsv` — measured per-suite durations (ADR-240 authority).
- `scripts/suite-shard-legs.tsv` + `scripts/regenerate-shard-manifest.py` — the existing
  duration-aware leg-assignment precedent (main battery, K=8, `label<TAB>leg` grammar).
- `scripts/required-checks.txt` — `oracle-index-check` is **not** a required context; it gates
  through the `test` aggregator's `needs:` (job-ID level — a matrix rolls up into one
  `needs.oracle-index-check.result`, same as `test-scripts`' 8 legs).
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` §Activation (line 107+) —
  the authorized re-arm sequence; its Status block already names #12393 as the gate.
- `ADR-276` (amendment 2026-11-05, #12156) — records the leg as running the manifest
  "serially" and `timeout-minutes: 30`; amendment text is append-only (`### Stage status`).

### Measured durations (command: `grep -vE '^\s*#|^\s*$' scripts/ci-oracle-lane-suites.txt | cut -f1 | while read -r l; do awk -F'\t' -v l="$l" '$1==l{print $2}' scripts/suite-durations.tsv; done`)

| Member | measured |
|---|---|
| plugins/soleur/test/ci-pr-affected-replay-a | 17.2 min (1033094 ms) |
| scripts/test-all-affected-d | 10.2 min |
| scripts/test-all-affected-c | 8.6 min |
| scripts/test-all-affected-b | 8.4 min |
| plugins/soleur/test/ci-pr-affected-replay-b | 6.7 min |
| scripts/test-all-group-affected | 5.8 min |
| plugins/soleur/test/ci-pr-affected-replay-c | 5.4 min (+~1.5 min after #12377's 317-484) |
| scripts/test-affected-kb-consumers | 1.5 min |
| scripts/test-all-affected-a | 0.9 min |
| scripts/lint-orphan-test-suites | 0.5 min |
| scripts/test-affected-derive | 0.1 min |
| scripts/test-affected-derive-cache / ci-pr-selection / ci-oracle-review / preactivation | ≤0.1 min each |
| **serial total** | **65.4 min** |

The canary's 5-of-15-in-29m53s matches the first five manifest members' summed durations
(~28.6 min), confirming the table is accurate for this workload. Value-proposition check
(Phase 0.6c): the matrix cuts wall clock 65.4 → ~19 min (worst leg 17.2 + ~1.5 min setup)
per oracle-only run; non-oracle runs pay K−1 extra sub-minute no-op jobs (runner slots on the
org's 20-concurrent-job ceiling, per `2026-09-21-ci-runner-concurrency-brainstorm.md`).

### Applicable institutional learnings

- `2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md` — a
  `timeout-minutes` sized from a measurement is a stale-able claim; a required leg near its
  ceiling is a flaky gate. Design consequence: worst leg (~19 min) must sit well under 30, and
  the legs file carries a rebalance trigger when measured leg time approaches the bound.
- `2026-05-12-ci-test-job-speedup-replan-and-validation-mechanics.md` — the K-way split and
  synthetic-aggregator precedent; verify suite/row counts against the live tree, not the issue.
- `2026-08-16-every-number-i-inherited-was-stale-...` — the ci.yml comment's "~10-20 min"
  estimate was stale; this plan quotes only measured numbers and names the producing command.
- ADR-276 amendment line (net-cost accounting): lane cost accounting is measured, not asserted —
  record the +K−1 no-op jobs and the leg-minutes delta honestly in the ADR stage-status line.

### Premise Validation (Phase 0.6)

- `#12393` OPEN; asks extracted verbatim into Scope Check. `#11556` OPEN epic (≤20-min PR check
  goal — the matrix arm aligns; raising the bound to ~90+ contradicts it). `#12375`, `#12269`,
  `#9323`, `#9729` OPEN — stay out of scope per the brief.
- `#12274` OPEN but **verified already-fixed on `origin/main`**: `git show
  origin/main:.github/workflows/ci.yml` shows `fetch-depth: 0` + the explicit
  `git fetch --no-tags --quiet origin main` step on `oracle-index-check` (lines 2241-2251). This
  PR should note it as fixed-on-main and recommend close (verification only — not `Closes`).
- `#12377` OPEN edits `scripts/ci-oracle-lane-suites.txt` (replay-c `--rows 317-476 → 317-484`)
  and `scripts/test-all.sh`. This plan **does not edit the manifest** (legs file keyed on
  labels, argv untouched) → zero diff overlap either merge order.
- Cited paths all verified on `origin/main`: manifest, driver, sentinel, runbook §Activation,
  `fetch-depth: 0`.
- ADR corpus check on the proposed mechanism (matrix legs): matrix sharding is the *established*
  pattern (ADR-240 checked-in shard assignment; #7902, #8006, #8890 precedents), not a rejected
  alternative. `CI_ORACLE_LANE` is **not** Terraform-managed (no `github_actions_variable`
  resource in `infra/github/*.tf`) — `gh variable set` remains the sanctioned activation path.
- Collision pre-check: `gh pr list --search 12393` → only this pipeline's branch; no foreign
  run rows observed.

### Property List (Phase 0.6b)

- **P1** — the oracle-validation work completes inside `timeout-minutes: 30` on an oracle-only
  run (wall clock, not just billed).
- **P2** — every committed manifest member executes exactly once per run; no member silently
  escapes the parallel leg set (Guard-4 parity property extended to the assignment).
- **P3** — no new required-context names and no ruleset edit (matrix legs roll up into the
  existing `oracle-index-check` needs entry).
- **P4** — no diff to `scripts/ci-oracle-lane-suites.txt` member lines (#12377 live race) and no
  new `run_suite` registrations (keeps argv-parity untouched).

### Cut List (Phase 0.6b)

- **Raise `timeout-minutes` (~90-120)** — buys P1 trivially but fails the issue's own "only with
  evidence the runner stays inside it" framing *in spirit*: evidence says ~65-90 min serial, so
  the raise would institutionalize a ~70-90-min wall clock on every oracle-only PR, contradicting
  epic #11556's ≤20-min target. Kept as the documented fallback arm of the technical fork
  (decision-challenges), not designed.
- **Cut the ~11 s/case mutation-matrix cost** — buys P1 only partially (even halving every suite
  leaves ~33 min serial > 30) and is a suite-internals rework on shared test files; separate
  scope, deferrable under epic #11556. Not designed here.
- **In-runner parallelism (one job, `&`+`wait`)** — buys P1 with zero new jobs but runs ~15
  concurrent suite trees on a 4-vCPU runner (oversubscription flake risk) and loses per-leg logs
  and the established `needs`-rollup shape. Rejected in favor of the proven matrix topology.
- **Leg column inside the manifest** — fails `MEMBER-BAD-FIELDS` (grammar pinned at 2 fields)
  and maximizes the #12377 conflict surface. Rejected for the separate legs file.

## Research Reconciliation — Spec vs. Codebase

| Brief/issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "Projected serial runtime ~90 min" | 65.4 min from committed durations; canary pace (~28.6 min / 5 suites) projects ~66-90 | quote the measured number + command |
| "the ~10-20 min the ci.yml job comment estimates" | comment at ci.yml:2217 is stale (measured 65.4) | rewrite the comment where the diff already touches it; the wider nit sweep stays with #12375 |
| "checkout already carries fetch-depth: 0" | verified on `origin/main` (#12274 fixed) | note fixed-on-main in PR body; recommend close of #12274 |
| "the manifest itself is not in the oracle surface" | verified: driver's hard-exclusion list (ci-oracle-lane.sh:177-181) → this PR pays the full battery | pre-merge verification relies on the sentinel suite's sandbox replay + the K-leg no-op path on this PR's own runs |
| "oracle-selection skipped while dark" | verified: var-gated `if:` on oracle-selection | unchanged |

## Proposed Solution

**Matrix-ize `oracle-index-check` into K=5 parallel legs, member assignment committed in a new
`scripts/ci-oracle-lane-legs.tsv` (`label<TAB>leg`).** Each leg runs the manifest loop filtered
to its assigned members; the job ID is unchanged, so `needs.oracle-index-check.result` rolls
the legs up exactly as `test-scripts`' 8 legs roll up today — no aggregator, ruleset, or
required-context edit.

**Leg packing** (LPT over the measured durations above; leg values are the second TSV column):

| leg | members | projected |
|---|---|---|
| 1 | ci-pr-affected-replay-a | 17.2 min |
| 2 | test-all-affected-d, test-affected-kb-consumers, lint-orphan-test-suites, ci-oracle-review | ~12.2 min |
| 3 | test-all-affected-c, ci-pr-affected-replay-c, ci-pr-affected-preactivation | ~14.1 min (~15.6 post-#12377) |
| 4 | test-all-affected-b, test-all-group-affected, test-affected-derive-cache | ~14.2 min |
| 5 | ci-pr-affected-replay-b, test-all-affected-a, test-affected-derive, ci-pr-selection | ~7.7 min |

Worst leg ≈ 17.2 min + ~1.5 min checkout/fetch/setup ≈ **~19 min < 30** (~37% headroom —
deliberately NOT on the timeout edge per the #12262 learning). K=5 rather than K=4 keeps
member-growth margin; K>5 cannot beat 17.2 (replay-a floor) without splitting the suite, which
requires a new registration — rejected for this PR (P4).

**Run-block semantics** (all fail-closed, all inside the step the sentinel extracts):

1. `not-oracle-only` early exit stays FIRST — non-oracle runs collapse to the sub-minute no-op
   per leg, unchanged.
2. `ORACLE_LEG` (env, `k/K` from `matrix.leg`) unset, empty, or malformed → `::error` + exit 1.
3. legs file absent under `ORACLE_LEG` → `::error` + exit 1.
4. manifest member with no legs-file row → `::error` + exit 1 (unassigned member cannot
   silently skip — the P2 fail-closed anchor).
5. leg that runs zero members → `::error` + exit 1 (a vacuous leg cannot gate).
6. `strategy.fail-fast: false` (precedent: test-scripts) — one leg's failure does not cancel
   sibling evidence.

## Technical Approach

### Implementation Phases

#### Phase 1 — Leg-assignment file and membership wiring

- Create `scripts/ci-oracle-lane-legs.tsv`: commented header (purpose, grammar
  `label<TAB>leg`, K, the measured-durations provenance, the rebalance trigger "re-pack when a
  member's measured duration or a new member puts any leg's projected total within ~5 min of the
  bound"), then the 15 rows above.
- `scripts/ci-oracle-lane.sh`: add `scripts/ci-oracle-lane-legs.tsv` to the hard-exclusion case
  (lane machinery — a diff touching it always pays the battery), with the comment updated.
- `scripts/lib/test-affected-paths.sh`: add the legs file to
  `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS` (the sentinel suite reads it).
- `.github/CODEOWNERS`: add `/scripts/ci-oracle-lane-legs.tsv @deruelle` beside the manifest row.
- `scripts/pr-fanout-ledger.txt`: append a dated note on the ci.yml row — a matrix job is ONE
  declared job, so the count stays 22; the note records the +K−1 no-op leg slots on non-oracle
  `pull_request`/`merge_group` runs as the named consequence.

#### Phase 2 — The matrix and the leg-filtered run block

- `.github/workflows/ci.yml` `oracle-index-check`: add `strategy: { fail-fast: false, matrix: {
  leg: ["1/5","2/5","3/5","4/5","5/5"] } }`; pass `ORACLE_LEG: ${{ matrix.leg }}` into the
  manifest step env; extend the run block per Proposed Solution semantics 1-6. Keep
  `    timeout-minutes: 30` alone on its line at job indent (release-workflow budget awk).
- Rewrite the job's stale comment where the diff already touches it: serial→legs, and the
  per-leg expectation (drop the "~10-20 min" estimate in favor of "per-leg; the legs file pins
  measured members under the bound" — never re-quote a measured number in prose).
- Do NOT touch: `needs:`, `if:`, `timeout-minutes`, checkout/fetch `if:` gates, the `test`
  aggregator's `needs:`/`entries[]`/ORACLE-ONLY-SKIP arm, `scripts/test-all.sh`,
  `scripts/ci-oracle-lane-suites.txt`, `scripts/suite-shard-legs.tsv`,
  `scripts/suite-durations.tsv`.

#### Phase 3 — Sentinel guard extension (`scripts/ci-oracle-lane.test.sh`)

- New `check_legs()` beside `check_manifest()`: legs rows ≡ manifest member labels
  (bi-directional), each leg value ∈ the ci.yml `matrix.leg` set (parsed from the live YAML),
  every matrix leg owns ≥1 member, no duplicate assignment rows. Mutant rows per the Guard
  Contract matrix below.
- Extend the extracted-body sandbox replay: stub `ci-oracle-lane-legs.tsv` + `ORACLE_LEG=k/K`
  env exercises per-leg selection (only that leg's stub members run); new arms pin
  unset/malformed `ORACLE_LEG`, missing legs file, unassigned member, and vacuous leg → exit 1.
- Update comments that say "runs the manifest SERIALLY" / "label + argv per line" where the
  legs-aware semantics are now authoritative.
- If the driver-exclusion fixture enumeration pins the exclusion paths one-per-case, add the
  legs file's fixture case beside `ex_oracle_suites`.

#### Phase 4 — Recorded artifacts

- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md`: leg description
  ("runs every non-comment line serially" → legs), §Activation status line update naming this
  PR and the canary conditions for re-arm.
- `ADR-276` `### Stage status`: append one dated line — the validation leg moved from serial to
  K=5 matrix legs under the same job ID; serial runtime measured 65.4 min vs bound 30; cost note
  (+4 sub-minute no-op legs on non-oracle `pull_request`/`merge_group` runs; oracle-only runs
  ~19 min wall vs the ~66-90 serial).

#### Phase 5 — Post-merge activation (explicit verification, not a checklist)

Executed only after this PR merges, per runbook §Activation:

1. `gh variable set CI_ORACLE_LANE --body on --repo jikig-ai/soleur` — verify with
   `gh api repos/jikig-ai/soleur/actions/variables/CI_ORACLE_LANE` returning `"value": "on"`
   (404 vs 401/403 handled per the runbook note; also check the org-variable fallback listed
   there).
2. Open a docs-only canary PR (e.g., a one-line runbook touch — knowledge-base `*.md` paths
   classify `oracle_only`); watch the head run:
   - `oracle-selection` emits `SOLEUR_ORACLE_LANE … oracle_only=true active=true
     would_skip=<five legs>`;
   - the `test` aggregate prints `ORACLE-ONLY-SKIP` lines naming exactly the five legs;
   - **every** `oracle-index-check (k/5)` check-run concludes `success` inside
     `timeout-minutes: 30` — the acceptance signal for #12393.
3. If any leg cancels at the bound or reds: roll back immediately per runbook §Rollback
   (`gh variable delete CI_ORACLE_LANE --repo jikig-ai/soleur`) and file the follow-up under
   epic #11556 (options: split `ci-pr-affected-replay-a`'s `--rows` into a second registration,
   or the cut-per-case-cost arm).
4. On green: note the canary run ID in #12393 (closing comment) and in the ADR-276 stage-status
   thread; comment on #12274 that the depth-1 defect is verified fixed on main
   (`fetch-depth: 0` + explicit fetch step) and recommend close.

## Alternative Approaches Considered

| Option | Verdict | Reason |
|---|---|---|
| A. Matrix legs + committed legs file (chosen) | adopted (pending CTO ruling — see decision-challenges) | proven topology (#7902); P1-P4 all hold; ~19 min worst leg |
| B. Raise `timeout-minutes` to ~120 with evidence | rejected | institutionalizes ~66-90 min wall on every oracle-only PR; contradicts epic #11556 |
| C. Cut the ~11 s/case mutation-matrix cost | deferred | suite-internals rework on shared files; even 2× cut leaves ~33 min > 30; separate scope under #11556 |
| D. In-runner parallel `&`/`wait` in one job | rejected | 15-way oversubscription on 4 vCPU; loses per-leg logs and the needs-rollup shape |
| E. Leg column in the manifest | rejected | `MEMBER-BAD-FIELDS` pins grammar at 2 fields; widens the #12377 conflict surface |
| F. Reuse `suite-shard-legs.tsv` / the generator | rejected | that table serves the main battery's K=8 packing, not this manifest; conflating populations corrupts both |

*Deferred-item tracking:* option C is the per-case-cost follow-up — it stays tracked under epic
#11556's existing children rather than a new issue (re-evaluation: if the re-armed canary leg
approaches the bound, or when replay row counts grow again).

## Files to Create

- `scripts/ci-oracle-lane-legs.tsv` — `label<TAB>leg` assignment, 15 rows + commented header.

## Files to Edit

- `.github/workflows/ci.yml` — `oracle-index-check` job block only (matrix, env, run block,
  adjacent comment).
- `scripts/ci-oracle-lane.sh` — hard-exclusion case += legs file.
- `scripts/ci-oracle-lane.test.sh` — `check_legs()`, mutant rows, legs-aware sandbox replay
  arms, comment updates.
- `scripts/lib/test-affected-paths.sh` — `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS` += legs file.
- `.github/CODEOWNERS` — legs file row, `@deruelle`.
- `scripts/pr-fanout-ledger.txt` — dated note on the ci.yml row (count unchanged at 22).
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` — leg description +
  §Activation status.
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` — append dated `### Stage status` line.

## User-Brand Impact

- **If this lands broken, the user experiences:** an oracle-only PR (a docs-or-index repair
  cycle — the fast lane's whole purpose) whose `test` required check goes red on
  `oracle-index-check` while the five heavy legs legitimately skip — the same dead-end the
  rollback exists to prevent, delivered to every contributor who hits the lane.
- **If this leaks, the user's workflow is exposed via:** no data surface — the exposure is
  workflow integrity: a leg-set gap could let an oracle-machinery edit merge under-validated,
  weakening the index the lane protects (caught by the legs-parity guard + fail-closed run
  block).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI machinery with no user data, credential,
  or billing surface; the blast radius is contributor velocity, not user incidents.

*Scope-out override:* `threshold: none, reason: the diff touches .github/workflows and scripts/
— CI orchestration and test-sentinel code only, no auth/data/regulated path`

## Observability

```yaml
liveness_signal:
  what: "oracle-index-check leg conclusions rolled into the `test` aggregator's entries[]
    sweep — `needs.oracle-index-check.result` read alongside the five battery-leg results each
    pull_request/merge_group run; the per-leg `── oracle-index-check: <label>` progress lines
    and the closing `<N> manifest suites green` line in the job log"
  cadence: "per pull_request and merge_group run (legs); per sentinel-suite execution (parity)"
  alert_target: "the PR's required `test` check-run (red on leg failure) — the operator-facing
    surface is the PR check list, not a page"
  configured_in: ".github/workflows/ci.yml `test` job `Aggregate shard results` step
    (entries[] includes oracle-index-check:$ORACLE_INDEX_RESULT)"

error_reporting:
  destination: "GitHub Actions annotations on the failing leg —
    `::error title=oracle-index-check::<reason>` (unassigned member, malformed ORACLE_LEG,
    missing legs file, vacuous leg, member exit code) plus the job log"
  fail_loud: "a leg `timeout-minutes` kill renders oracle-index-check cancelled/failed while
    sibling legs conclude normally — the aggregator's existing cancelled-vs-superseded
    discriminator prints the measured cause (one leg dead vs all legs cancelled), distinguishing
    'too slow' from 'push superseded' without an API read"

failure_modes:
  - mode: "a leg's serial share grows past the bound (member added to an already-heavy leg,
    or suite slowdown)"
    detection: "leg `timeout-minutes: 30` kill → `oracle-index-check: cancelled/failure` in the
      aggregator's cause output while sibling legs conclude; legs-file header carries the ~5-min
      rebalance trigger"
    alert_route: "red required `test` check on the oracle-only PR"
  - mode: "a manifest member escapes every leg (legs-file gap) or runs under two legs"
    detection: "check_legs() parity tags in scripts/ci-oracle-lane.test.sh (pre-merge sentinel)
      plus the run-block's fail-closed `unassigned member` error (runtime backstop)"
    alert_route: "red sentinel suite leg pre-merge; red oracle-index-check leg on a lane run"
  - mode: "stale legs row naming a non-member, or a leg value outside the matrix set"
    detection: "check_legs() bi-directional pins (stale-row tag; leg-value ⊆ live matrix.leg set)"
    alert_route: "red sentinel suite leg on the offending PR"
  - mode: "ORACLE_LEG env missing/malformed on a real run (wiring drift)"
    detection: "fail-closed `::error` + exit 1 in the leg's first lines"
    alert_route: "red leg → red `test` aggregate"

logs:
  where: "GitHub Actions job logs per leg (`gh run view <run> --log`, per-leg job names
    `oracle-index-check (k/5)`); sentinel suite output in `scripts/ci-oracle-lane` leg logs"
  retention: "GitHub-hosted run logs, ~90 days"

discoverability_test:
  command: bash -c 'diff <(grep -vE "^#|^[[:space:]]*$" scripts/ci-oracle-lane-suites.txt | cut -f1 | sort) <(grep -vE "^#|^[[:space:]]*$" scripts/ci-oracle-lane-legs.tsv | cut -f1 | sort) >/dev/null && echo legs-parity-ok'
  expected_output: legs-parity-ok
```

Layer mapping (`hr-observability-layer-citation`): the leg-timeout and member-escape modes are
covered by the **CI aggregator layer** (the `test` job's per-leg result sweep + measured-cause
discriminator — in-band, no SSH); the assignment-integrity modes are covered by the **sentinel
suite layer** (`scripts/ci-oracle-lane.test.sh` parity guard, pre-merge) with the **run-block
fail-closed layer** as the runtime backstop inside the leg itself.

## Architecture Decision (ADR/C4)

### ADR

- Amend `ADR-276` in place per its append-only `### Stage status` convention (task in Phase 4):
  the validation leg's execution topology changes from "runs the committed manifest serially" to
  K=5 matrix legs under an unchanged job ID; record the measured serial 65.4 min, the chosen
  topology, and the +K−1 no-op leg cost in the same net-cost style the amendment already uses.
  No new ADR: this is an amendment of ADR-276's documented mechanism, not a new boundary.

### C4 views

- No C4 impact. Enumeration per the completeness mandate: (a) external human actors — none
  added (contributors are already modeled roles, and CI runner topology is not an actor);
  (b) external systems/vendors — GitHub Actions is already the implicit substrate, no new
  vendor or edge; (c) containers/data stores — none touched (a workflow YAML key and a TSV
  assignment file); (d) access relationships — unchanged (the lane's skip semantics and the
  aggregator's tolerance arms are unmodified). Checked `model.c4` — no CI-runner/job elements
  exist to falsify; workflow-job topology is not in the model's boundary.

## Guard Contract

### Guard 1 — oracle-leg assignment parity (`check_legs()` in `scripts/ci-oracle-lane.test.sh` + run-block fail-closed arms)

**Property.** Every `scripts/ci-oracle-lane-suites.txt` member executes under exactly one
`oracle-index-check` matrix leg, every leg owns at least one member, and no stale assignment
survives — the parallel split can never silently drop or double-run validation.

**Assembly.** The population: non-comment lines of `scripts/ci-oracle-lane-suites.txt` (the
chokepoint — membership can only enter or leave through that file, already pinned by
`check_manifest()`). The assignment: rows of `scripts/ci-oracle-lane-legs.tsv`. The dispatch
set: `strategy.matrix.leg` inside `.github/workflows/ci.yml`'s `oracle-index-check` job (the
only place legs are enumerated). The executor: the leg filter inside the manifest `run:` block
(second chokepoint — a member reaches a runner only through it). The guard: `check_legs()` in
`scripts/ci-oracle-lane.test.sh`, which reads all four.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one member's legs-file row (unassigned member) | RED — parity tag + run-block `unassigned member` error |
| 2 | Add a legs row naming a label not in the manifest (stale row) | RED — stale-row tag |
| 3 | Assign a member to leg `9`, outside the live `matrix.leg` set | RED — leg-value tag |
| 4 | Reassign members so one matrix leg owns zero members (vacuous leg) | RED — vacuous-leg tag |
| 5 | Run `check_legs` with the legs file absent (guard's own input missing) | RED — a missing input must not read clean |
| 6 | Duplicate one member's row onto a second leg (double-assignment) | RED — duplicate-assignment tag |
| 7 | Harness must-PASS: permute the assignment (move a member to a different leg) while keeping coverage total | PASS — the authority is coverage, not the specific packing |
| 8 | Harness must-PASS: reorder rows inside the legs file | PASS — assignment is by row content, not position |

**Anchor.** The legs file and the manifest are committed in the same diff and both are
CODEOWNERS-gated (`@deruelle`); the parity property is per-commit consistency, and the
run-block's fail-closed `unassigned member` arm is the runtime anchor — a legs file weakened in
isolation reds the guard, a manifest grown without an assignment reds the leg itself.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "shrink the manifest's serial runtime under the bound (parallelise the 15 suites across a matrix of legs, or cut the ~11 s/case mutation-matrix cost) or raise `timeout-minutes` only with evidence the runner stays inside it" [issue #12393] | Proposed Solution + Phases 1-3 + AC1-AC9 | mapped |
| 2 | "Then re-run a docs-only canary to green before re-attempting activation." [issue #12393] | Phase 5 + AC11 | mapped |
| 3 | "plan around a possible merge-order conflict; do not restructure lines you don't need to" [brief, re PR #12377] | P4 + Cut List (leg-column rejection) + AC7 | mapped |
| 4 | "evaluate whether this PR should note it as already-fixed so it can be closed (verification only, do not scope-creep)" [brief, re #12274] | Phase 5 step 4 + AC12 | mapped |
| 5 | "decide in the plan whether the comment sweep is absorbed here or stays with #12375" [brief] | Phase 2 comment scope + decision-challenges row | mapped |
| 6 | "find the activation runbook" + re-activation steps as explicit post-merge verification [brief] | Phase 5 + runbook edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/ci-oracle-lane-legs.tsv` (create) | "parallelise the 15 suites across a matrix of legs" | asked |
| `.github/workflows/ci.yml` matrix + run block | "parallelise the 15 suites across a matrix of legs" | asked |
| `ci-oracle-lane.test.sh` guard extension | — | inferred — justification: the repo's own contract (Guard 4 + `hr-write-boundary-sentinel-sweep-all-write-sites`) requires the sentinel to cover the new legs input; a new assignment file without a parity pin is the exact silent-escape class P2 forbids |
| `ci-oracle-lane.sh` hard-exclusion += legs file | — | inferred — justification: the driver's comment ("the driver, its sentinel and this manifest are all in the hard-exclusion list") defines lane machinery by enumeration; the legs file is the same class |
| `test-affected-paths.sh` edge set += legs file | — | inferred — justification: the sentinel suite reads the file; the declared edge set is the SELF-INCLUSION contract |
| `.github/CODEOWNERS` += legs file row | — | inferred — justification: sibling lane files are all `@deruelle`; an unowned lane-machinery file would dodge the paired-edit convention |
| `pr-fanout-ledger.txt` note | — | inferred — justification: the ledger's convention is a dated note for every fan-out consequence; the +K−1 no-op legs are exactly that |
| runbook + ADR-276 edits | "re-run a docs-only canary per runbook §Activation" | asked (activation path) + inferred (ADR stage status is the append-only convention for mechanism changes) |

### Split Assessment

- Subsystems touched: 3 — `.github`, `scripts`, `knowledge-base`
- Planned files: 9 | Estimated changed lines: ~260
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `bash scripts/ci-oracle-lane.test.sh` green including `check_legs()` and every
  mutant row in the Guard Contract matrix.
- [ ] AC2 — legs parity holds bi-directionally: legs-file labels ≡ manifest members; each leg
  value ∈ the live `matrix.leg` set; every matrix leg owns ≥1 member; no duplicate assignments.
- [ ] AC3 — run-block fail-closed arms verified in the extracted-body sandbox: unset/malformed
  `ORACLE_LEG` → exit 1; missing legs file under `ORACLE_LEG` → exit 1; unassigned member →
  exit 1; vacuous leg → exit 1; `not-oracle-only` early exit precedes all leg logic.
- [ ] AC4 — sandbox replay proves per-leg selection: a stub manifest + stub legs file under
  `ORACLE_LEG=k/5` executes only that leg's stub members (sibling members do not run).
- [ ] AC5 — `    timeout-minutes: 30` remains alone on its line at job indent (release-workflow
  budget awk shape preserved); no `needs:`/`if:`/aggregator/`required-checks.txt` edit.
- [ ] AC6 — legs file listed in the driver's hard-exclusion case, `CODEOWNERS`, and
  `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS`.
- [ ] AC7 — `git diff origin/main -- scripts/ci-oracle-lane-suites.txt` is empty (zero overlap
  with #12377 either merge order); no `run_suite` registration added or changed.
- [ ] AC8 — worst projected leg ≤ ~20 min per `scripts/suite-durations.tsv` at implementation
  time (re-run the measurement command; if the table has drifted, re-pack before writing the
  legs file).
- [ ] AC9 — `needs.oracle-index-check.result` still rolls up the legs (structural: unchanged
  job ID); the `test` aggregator's entries[] literal is byte-unchanged.
- [ ] AC10 — ADR-276 `### Stage status` dated line appended; runbook §leg-description and
  §Activation status updated.
- [ ] AC11 — PR body notes #12274 verified-fixed on `origin/main` (`fetch-depth: 0` + explicit
  `git fetch origin main` step) and recommends close; NOT listed as `Closes`.

### Post-merge (operator)

*Automation: feasible via `gh` CLI — held post-merge because activation is the runbook's
separately-authorized operator row O2 (a production-mutating authorization on the required-check
surface), not an automation limit.*

- [ ] AC12 — `gh variable set CI_ORACLE_LANE --body on` verified `"value": "on"` via
  `gh api repos/jikig-ai/soleur/actions/variables/CI_ORACLE_LANE`; docs-only canary PR shows
  `oracle_only=true`, the `ORACLE-ONLY-SKIP` aggregate lines, and every
  `oracle-index-check (k/5)` green inside the bound; else rollback per runbook §Rollback.

## Test Scenarios

- Given a stub manifest of 3 members and a stub legs file assigning them 2/1/1, when the
  extracted run block executes under `ORACLE_LEG=1/2`, then exactly the two leg-1 members run
  (`unit`, sandbox replay).
- Given the same fixture under `ORACLE_LEG=2/2`, then only the leg-2 member runs (`unit`).
- Given a manifest member with no legs row under `ORACLE_LEG=1/5`, then the step exits 1 with
  the unassigned-member annotation (`unit`, fail-closed).
- Given `ORACLE_LEG` unset / `x/y` / `0/5`, then exit 1 after the `not-oracle-only` check
  (`unit`).
- Given `ORACLE_ONLY=false` and any `ORACLE_LEG`, then the step exits 0 inside a minute without
  reading the legs file (`unit`, early-exit precedence).
- Given a legs file with a row for a non-member label / a leg `9` / a vacuous leg / a
  duplicated member, then `check_legs` emits the matching tag (`unit`, each matrix row).
- Given the re-ordered or re-packed-but-complete legs file, then `check_legs` is clean (`unit`,
  must-PASS rows 7-8).
- Given this PR's own `pull_request` run (dark lane), then all 5 `oracle-index-check (k/5)`
  legs conclude `success` printing `not-oracle-only` — the live pre-merge exercise of the matrix
  wiring (`integration`, observed on the PR's real CI run).
- Given the post-merge docs-only canary, then `oracle_only=true` runs all 15 members across the
  5 legs inside the bound (`e2e`, `pyramid-justified: the lane's real behavior only exists on a
  GitHub-hosted oracle-only run — no local replica of the matrix/`needs` rollup`).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI machinery change (workflow topology, a TSV
assignment file, a test-sentinel extension). Product/UX mechanical override: no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files-to-Create/Edit →
gate does not fire; tier NONE. No user-facing surface, no regulated-data surface, no new vendor
or infra resource.

## Open Code-Review Overlap

1 open scope-out name-matches a planned file: #3321 (`CODEOWNERS` coverage for the
knowledge-base/project/learnings/ subtree) — **acknowledged, unrelated**: it targets a different
CODEOWNERS subtree; this PR's CODEOWNERS edit adds one lane-machinery row and does not interact
with the learnings coverage. All other planned paths returned no matches.

## Success Metrics

- Every `oracle-index-check (k/5)` check-run green inside `timeout-minutes: 30` on the
  re-activation canary (the issue's own gate).
- Oracle-only run wall clock for the validation leg: ≤ ~20 min (vs ~66-90 serial).
- `CI_ORACLE_LANE` re-armed and held (no rollback) after the canary — measured by the variable
  remaining `on` and the next oracle-only merge completing green.
- Zero diff to `scripts/ci-oracle-lane-suites.txt` (merge-order safety vs #12377).

## Dependencies & Risks

- **Risk: leg-time drift.** Member durations drift with suite growth; replay-c grows ~1.5 min
  when #12377 merges. Mitigation: legs-file header carries the ~5-min-to-bound rebalance
  trigger; AC8 re-measures at implementation time.
- **Risk: matrix all-legs-skipped `needs.*.result` shape on push.** On `push` events the
  job-level `if:` skips every leg; `needs.oracle-index-check.result` is either `skipped`
  (tolerated structural absence — unchanged) or `success` (trivially accepted). Both shapes are
  aggregator-safe; verified structurally by AC9 and observable on the first post-merge push run.
- **Risk: +K−1 no-op jobs on every non-oracle `pull_request`/`merge_group`.** ~4 sub-minute
  runner slots on the org's 20-concurrent ceiling. Accepted and recorded (ledger note +
  ADR-276 stage status); alternative (conditional matrix) is not expressible in Actions.
- **Risk: replay-a remains the 17.2-min floor.** If it drifts past ~24 min the bound gets tight
  again; the documented remedy (split `--rows` into a second registration — needs a
  `run_suite` add, deferred) is named in Phase 5 step 3.
- **Dependency: #12377 merge order.** Zero manifest overlap by design (AC7); if it merges
  first, replay-c's legs row is unaffected (assignment is keyed on label, not argv).
- **Process: `@deruelle` CODEOWNER review** on manifest-adjacent files is mechanical but real;
  the diff is confined to CODEOWNERS-gated lane files by intent.

## References & Research

### Internal References

- `.github/workflows/ci.yml:1781-1860` — `test-scripts` matrix precedent (`strategy.matrix`,
  `fail-fast: false`, `suite-shard-legs.tsv` packing).
- `scripts/ci-oracle-lane.test.sh:1079-1290` — Guard 4 (`check_manifest`, mutants,
  extracted-body replay).
- `scripts/suite-durations.tsv` — the measurement authority (ADR-240).
- `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` (amendment 2026-11-05) —
  the lane design record this PR amends.
- `knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md` — the checked-in-assignment doctrine the legs file follows.
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` §Activation / §Rollback.
- `knowledge-base/project/learnings/2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md`.

### Related Work

- Issue #12393 (this plan), #12274 (verified fixed on main), #12377 (live race — zero overlap
  by design), #12375 (comment nits — stays out except comments inside the oracle-index-check
  block this diff touches), epic #11556, #12089 (epic, closed), PRs #12300/#12382,
  run 42458135078.

### Subagent-spawn disclosure

This planning run had no Task/subagent capability: the repo-research, learnings, discovery,
domain-leader, spec-flow, advisor and plan-review fan-outs were performed inline by the
planner (reads, greps, `gh` calls quoted above). The technical design fork was therefore
recorded `pending - assumed:` in `decision-challenges.md` rather than ruled by the CTO agent,
per `technical-ruling-delegation.md`.
