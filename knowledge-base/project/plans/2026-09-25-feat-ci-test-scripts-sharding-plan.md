---
title: "ci: rebalance the already-sharded test-scripts legs under the ~10-minute ceiling"
type: feat
date: 2026-09-25
slug: ci-test-scripts-sharding
branch: feat-one-shot-ci-test-scripts-sharding
issue:
lane: cross-domain
brand_survival_threshold: none
---

# ci: rebalance the already-sharded test-scripts legs under the ~10-minute ceiling

## Enhancement Summary

**Deepened on:** 2026-09-25
**Sections enhanced:** Research Reconciliation, Research Insights, Proposed
Solution, Technical Considerations, Guard Contract, Acceptance Criteria
**Research/review mode:** inline sequential pass (planning subagent has no
Task-spawn surface; `Reviewed-Coverage: sequential-fallback` — no independent
agent review ran). Mechanical gates executed for real: PAT-shaped-variable
grep (clean), `lint-guard-contract.py` (1 guard entry, green), User-Brand
Impact + Observability section checks, markdownlint (clean).

### Key Improvements

1. **Premise correction (load-bearing):** the sharding the brief asks for is
   already merged (#8585/#8612/#8665, verified live via `gh pr view` — all
   MERGED). Residual scope is manifest regeneration ± K=6→K=7 tune, decided by
   a measured gate, not a re-implementation.
2. **Real baselines measured, not quoted:** leg timings pulled from the run's
   own `suite-timings-scripts-*` artifacts (run 36123485360): light legs
   7.6–12.9 min suite time, setup ≈ 0.4 min/leg, 502 light + 3 heavy
   registrations. The cited baseline run 32415069661 is dated 2026-08-20 —
   pre-shard.
3. **K-bump blast radius enumerated:** ci.yml matrix + in-job `K=6` comments
   (incl. the `timeout-minutes` block), `suite-shard-legs.tsv` `# n=` header,
   `scripts-shard-totality-mutations.sh` ROW5 literal, runbook tables. All
   other guards (`scripts-shard-manifest.test.sh`, `scripts-shard-totality
   .test.sh`, `ci-test-aggregator-diagnosis.test.sh`) derive N/K dynamically.
4. **Ordering constraint discovered in deepen:** `regenerate-shard-manifest.py`
   derives N from ci.yml via `read_ci_leg_count(job)` — the matrix edit MUST
   land before `--write` or the TSV regenerates with stale `n=6`.
5. **merge_group invariant verified:** the only two `github.event_name ==
   'pull_request'` job gates in ci.yml are `sandbox-canary-capture-gate` and
   `plugin-root-propagation-gate` — neither is a required context
   (cross-checked against `scripts/required-checks.txt`).

### New Considerations Discovered

- Job-minutes comparison is confounded: ~53→~108 min/run is mostly organic
  suite growth (374→505 registrations) + new jobs; shard overhead is only
  ~0.4 min setup per leg. Public repo → minutes unmetered; the real budget is
  the org's 60-concurrent-job ceiling (Team plan, post-#8450).
- The `registry-gate-mutation-battery` contention ceiling (14.3–27.9 min under
  load, per runbook) cannot be beaten by any K — AC1 is evaluated on nominal
  green-run timings and the caveat is disclosed.
- `regenerate-shard-manifest.py` default lookup (`latest green main ci.yml
  run`) returned HTTP 404 when probed — always pass `--run <id>` explicitly.

## Overview

The feature ask — "shard the `test-scripts` job in `.github/workflows/ci.yml`
into parallel jobs" — is **already implemented on `main`**. The job is a K=6
manifest-driven matrix (`test-scripts (k/6)`), beside `test-scripts-heavy`
(K=3, dedicated legs for the three heaviest suites) and
`shard-totality-mutations` (2 legs), landed by #8585, #8612, #8665 under
issue #8006 / ADR-238 / ADR-240. `scripts/test-all.sh` remains the single
source of the suite list; leg membership comes from the committed manifests
`scripts/suite-shard-legs.tsv` / `suite-shard-legs-heavy.tsv` (sticky-LPT over
measured durations, hash fallback for untabled labels).

The honest residual gap against the acceptance criteria, measured in this
planning session on a current green CI run, is:

- **Worst leg is ~13.0 min, not under ~10.** `test-scripts (6/6)` ran
  12.9 min of suite time + ~0.4 min setup on run 36123485360 (2026-09-25);
  light-leg spread was 7.6–12.9 min suite time (mean ≈ 9.5 min over 502
  registrations). The current manifest was generated 2026-09-24 from run
  35945250103 and has already drifted.
- **Job-minutes roughly doubled** versus the pre-shard baseline (~53 → ~108
  per CI run), but this is almost entirely organic suite growth (374 → 505
  registrations), not shard overhead: per-leg setup measures ~0.4 min, so a
  leg costs its suites + ~24 s. On a **public** repo, hosted-runner minutes
  are unmetered; the real budget is wall-clock and the org's 60-job concurrency
  ceiling (Team plan; #8450 closed via upgrade — brainstorm
  2026-09-21 decided it).
- All other acceptance criteria are already satisfied and must be preserved:
  only the synthetic `test` check is a required context (shard legs are not
  required contexts), `merge_group` coverage is unconditional, and suite-count
  parity is enforced by `plugins/soleur/test/scripts-shard-totality.test.sh`.

This plan therefore re-derives leg composition from current timing artifacts
(manifest regeneration, plus a leg-count adjustment if regeneration alone
cannot hold the ~10-minute ceiling), records honest before/after numbers in
the PR body, and leaves `scripts/test-all.sh` completely untouched (collision
constraint vs. open PR #8763).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified 2026-09-25) | Plan response |
|---|---|---|
| "`test-scripts` is a single 27.7-min job (baseline run 32415069661)" | Run 32415069661 is dated 2026-08-20 and predates the shard merges; current `test-scripts` is a K=6 matrix (worst leg 13.0 min on run 36123485360) | Treat sharding as landed; residual scope is rebalancing under the ~10-min ceiling |
| "~53 job-min per CI run" | ~108–122 job-min on 2026-09-25 PR runs — driven by suite growth (374→505) + new jobs, not shard overhead (~0.4 min setup/leg) | Report both numbers in the PR body with the confound named |
| "Shard to cut wall-clock AND job-minutes" | Public repo → minutes unmetered; binding budgets are wall-clock and the 60-job org concurrency ceiling (Team plan, post-#8450) | Optimize worst-leg wall-clock; keep added legs minimal (each costs ~0.4 job-min + one runner slot) |
| "No suite-count parity assertion exists — plan must add one" | `scripts-shard-totality.test.sh` + `--mutations.sh` battery + `scripts-shard-manifest.test.sh` already prove union-exactly-once and n-consistency | Reuse them as the parity gate; add a leg-union verification step at work time |
| "Required-check names must stay satisfied" | `scripts/required-checks.txt` + `infra/github/ruleset-ci-required.tf` require only the `test` aggregate (plus `e2e`, `dependency-review`, `skill-security-scan PR gate` from ci.yml); legs are not required contexts | No ruleset/Terraform change needed; do not rename `test` or its `needs:` jobs |

## Research Insights

**Premise validation (Phase 0.6).** Cited artifacts verified: the runbook
(`knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`),
ADR-238, `infra/github/ruleset-ci-required.tf`, `scripts/required-checks.txt`,
`scripts/test-all.sh`, and `.github/workflows/ci.yml` all exist. The cited
baseline run 32415069661 is real but **stale** (2026-08-20, pre-shard). Issue
#8006 (shard-balance tracking) is CLOSED. Open PR #8763
(`feat-one-shot-8736-deploy-script-tests-parallel`, live session) edits
`scripts/test-all.sh` (`want_scripts` region), `scripts/regenerate-shard-manifest.py`,
`apps/web-platform/infra/suite-shard-legs.tsv` (new file on the #8763 branch —
not in this worktree; different path than ours), and the same runbook file —
confirmed via `gh pr view 8763`. Collision
posture: this plan touches none of `test-all.sh`, `regenerate-shard-manifest.py`
(only *runs* it), or the infra TSV; the one shared file is the runbook, edited
in disjoint sections (our edits: "Current topology" table + "Measured history";
#8763 adds infra-suite documentation).

**Property List (Phase 0.6b).** Observable outcomes the ask wants:

1. Longest CI job under ~10 min.
2. Required-check names unchanged; `test` keeps reporting.
3. Every registered suite runs exactly once across the leg set (no drop, no dup).
4. merge_group coverage for all required-context producers.
5. Before/after measurement reported (job-min + longest job).

**Cut List (Phase 0.6b).**

- "Shard `test-scripts` into parallel jobs" → buys properties 1–4 → **already
  on `origin/main`** (#8585 K=5 + heavy carve-out; #8612 manifest; #8665
  K=6 + mutations split + parallel enumerate). Cut — not re-designed.
- "Add a suite-count parity CI step/test" → buys property 3 → already covered
  by `scripts-shard-totality.test.sh` (union = reference set, no dup, no
  empty leg) plus its 24-row mutation battery. Cut — reused instead.
- "Migrate the ruleset via Terraform if names change" → buys property 2 →
  unnecessary: shard legs are not required contexts; only `test` is. Cut —
  no `infra/github/` change.

**Value measurement (Phase 0.6c).** Command producing the numbers:
`gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs?per_page=100` +
per-suite `suite-timings-scripts-*` artifacts. Baseline (run 32415069661,
2026-08-20): `test-scripts` single job 27.7 min; run total ≈ 53 job-min.
Current (run 36123485360, 2026-09-25): legs [9.9, 8.2, 10.4, 8.2, 10.4, 13.0]
wall / suite-time totals [9.3, 7.6, 9.7, 7.6, 9.9, 12.9] min; heavy legs
[8.7, 5.1, 7.6]; run total ≈ 108 job-min; 502 light + 3 heavy registrations
(`bash scripts/test-all.sh --enumerate scripts | wc -l`).

**Relevant files.**

- `.github/workflows/ci.yml` — `test-scripts` job (`strategy.matrix.shard`,
  `SCRIPTS_SHARD: ${{ matrix.shard }}` binding, `timeout-minutes: 60` with a
  comment block that must NOT be re-sized — see Technical Considerations),
  `test-scripts-heavy`, `shard-totality-mutations`, `test` aggregator
  (`needs:` + per-result env).
- `scripts/test-all.sh` — `_shard_selects` chokepoint, `_SHARD_K/_SHARD_N`
  parse (§Shard partition), manifest engagement contract (group + `n` match),
  `--enumerate`. **Not edited.**
- `scripts/suite-shard-legs.tsv` (`# n=6`, generated 2026-09-24 from run
  35945250103) and `suite-shard-legs-heavy.tsv` (`# n=3`) — generated data;
  regenerate, never hand-edit.
- `scripts/regenerate-shard-manifest.py` — sticky-LPT regenerator;
  `python3 scripts/regenerate-shard-manifest.py --run <green-run> --write`
  (`--group heavy` for the heavy table). Its default latest-green-main-run
  lookup returned HTTP 404 when probed this session — pass `--run <id>`
  explicitly with a run that has `suite-timings-*` artifacts.
- `plugins/soleur/test/scripts-shard-totality.test.sh` — reads ci.yml's
  matrix dynamically; also exercises a non-canonical alt-K. K-agnostic.
- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — 24-row
  mutation battery; **ROW5 holds the literal
  `shard: ["1/6", ..., "6/6"] → ["1/6", ..., "5/6"]` against the live ci.yml —
  a K bump MUST update both arms** or the mutation cannot apply.
- `plugins/soleur/test/scripts-shard-manifest.test.sh` — derives declared N
  from ci.yml's matrix and asserts `manifest n == N`; self-consistent on a
  K bump. `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` —
  fixtures the 6 `needs:` job results (not legs); unaffected by K.
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  — topology table + measured history to update (disjoint from #8763's
  additions; #8763 edits the same file).

**Institutional learnings applied.**

- `2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`
  — a regenerated file every sibling PR also regenerates cannot stay
  mergeable. The TSV is exactly such a file: commit the regen output, expect
  re-regen on rebase; resolve TSV conflicts by regenerating, never hand-merging
  (runbook §The manifests).
- `2026-05-12-ci-test-job-speedup-replan-and-validation-mechanics.md` —
  suite counts and cache keys drift from plan to code; we re-measured live
  (502 registrations, ~0.4-min leg setup) rather than trusting the brief.
- `2026-08-13-a-benchmark-carries-the-machine-that-produced-it.md` —
  durations were re-derived from the Actions API + run artifacts on the
  platform that pays them, and reported as a spread, not one sample.
- `2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md` —
  docs arrays drift; the runbook topology table and the ROW5 mutation literal
  are the two drift surfaces this plan must update atomically with the matrix.
- `2026-09-21-ci-runner-concurrency-brainstorm.md` — org `free` plan,
  60-concurrent-job ceiling (Team plan, post-#8450), ~33 jobs per CI run; each added leg is
  one more slot against a saturating budget.

## Problem Statement / Motivation

`test-scripts` was cut from a 27.7-min single job to a K=6 matrix, but leg
composition has drifted: the worst leg now measures ~13.0 min while the best
measures ~8.2 min. Drift is expected — suite registrations churn (502 light
registrations today vs ~489 at manifest generation), untabled labels
hash-fall onto legs, and suite durations move. The runbook already prescribes
the remedy: regenerate the manifests when legs skew. Left un-tuned, the worst
leg keeps the PR-feedback loop above the ~10-minute target the shard work was
built to hold.

## Proposed Solution

Two-step, each step gated on measurement (runbook procedure throughout):

1. **Regenerate the light manifest from a current green run**
   (`python3 scripts/regenerate-shard-manifest.py --run <run-id> --write`,
   dry-run first to read predicted per-leg totals). Sticky-LPT should pull the
   worst leg toward the ~9.5-min suite-time mean → ~9.9 min wall.
2. **Decision gate on the predicted worst leg.** If the regen's predicted
   worst light leg is **≥ 9.5 min suite time** (i.e., no headroom under the
   ~10-min ceiling — the next suite addition or a slow runner pushes it over),
   bump the light matrix **K=6 → K=7**: suite time per leg ≈ 57/7 ≈ 8.1 min,
   +0.4 min setup → ~8.5 min worst leg with real margin. Cost: one runner slot
   (+~0.4 job-min/run) against the org's 60-concurrency ceiling (Team plan, post-#8450) — acceptable
   and recorded. Then regenerate the manifest (its `# n=` header must equal
   the new matrix N — `scripts-shard-manifest.test.sh` fails closed on drift)
   and update the K-sensitive surfaces atomically:
   - `ci.yml` `strategy.matrix.shard` literal (`"1/7"…"7/7"`) + the job's
     K=6 comment block (rewritten to state K=7 and the new nominal).
   - `plugins/soleur/test/scripts-shard-totality-mutations.sh` ROW5 — both
     the match literal and the mutant literal move to /7 form.
   - Runbook "Current topology" table + TL;DR K reference.
   If predicted worst < 9.5 min, **stay at K=6** — regen-only, and the runbook
   gets only a measured-history line.

`test-scripts-heavy` and `shard-totality-mutations` are **out of scope for
edits**: worst heavy leg measured 8.7 min (nominal, under the ceiling); the
battery's contention ceiling (14.3–27.9 min under load) is the documented
floor no K beats — see Alternatives for why splitting it is deferred.

No `scripts/test-all.sh` edit, no `infra/github/` change, no new job names —
the required `test` context, `merge_group` coverage, and every existing guard
are untouched.

## Technical Considerations

- **`timeout-minutes: 60` is not touched.** The comment block on the job
  explains why: it is the only bound on a leg and must sit above the repo's
  declared expectation, not near a leg estimate. A K bump lowers the nominal
  leg — the hang cap stays 60 either way; do NOT re-size it to the new
  estimate (the silent-bound trap is documented in that comment and #7902).
- **UNTRUSTED-CI.** This PR edits `.github/workflows/ci.yml` — workflow-file
  PRs merge only on green required checks; no `--admin` merge downstream.
- **Runner-slot budget.** CI already dispatches ~33 jobs per run against the
  org's 60-concurrent ceiling (Team plan, post-#8450); queueing is still the norm on bursts (runbook §Runner-availability
  data: occupied on ~24% of main pushes). One added leg is marginal; a bigger
  K (8+) is rejected in Alternatives.
- **Merge_group invariant.** No job may gain an `event_name`/`pull_request`
  gate; this plan adds none (verified: no existing job gates on the event).
- **The one bounded dispatch asymmetry stays bounded.** Deleting the
  `SCRIPTS_SHARD` env line would run the full 502-suite group on every leg and
  stay green — tracked pre-existing gap (#7931), NOT made worse here; the
  matrix VALUES (not the binding) are what K changes, and `scripts-shard-
  totality.test.sh` asserts both the binding shape and leg coverage.
- **Generated-artifact conflict posture.** The TSV diffs will conflict with
  any sibling regen — resolve by re-running the regenerator on a fresh green
  run, never by hand-merge (runbook; also the 2026-09-19 learning).
- **PR #8763 adjacency.** It edits `regenerate-shard-manifest.py` — if it
  lands first, re-read its `--help`/flags before the regen step (its CLI may
  gain a third group). It does not touch `scripts/suite-shard-legs.tsv` or
  ci.yml, and our runbook edits sit in the "Current topology"/"Measured
  history" blocks, disjoint from its infra-suite additions.
- **NFRs:** CI feedback latency (NFR target: longest job < ~10 min) and
  devex runner-slot consumption — assessed inline; no `soleur:architecture`
  substrate change.

### Implementation Phases

#### Phase 1: Measure + dry-run regen

- Pick a completed green `ci.yml` run carrying `suite-timings-scripts-*`
  artifacts (any recent green PR/main run; e.g. the run measured at plan
  time or a newer one).
- `python3 scripts/regenerate-shard-manifest.py --run <id>` (no `--write`) —
  record predicted per-leg totals in the spec dir's `measurements.md`.
- Gate: predicted worst light leg ≥ 9.5 min suite time → Phase 2a (K bump);
  else → Phase 2b (regen-only).

#### Phase 2a: K=6→K=7 + regen (conditional)

- Edit `.github/workflows/ci.yml`: matrix literal to `"1/7"…"7/7"`; rewrite
  the `# MATRIX SHARDED`/`K=6` comment block to state K=7, the measured
  nominal (~8.5 min incl. ~0.4 setup), and the drift warning (unchanged).
  Sweep every other `K=6`/`/6` citation inside the same job — including the
  "light leg ~7 min nominal at K=6" line inside the `timeout-minutes`
  comment block (the `60` hang cap itself stays; only the nominal it
  references is re-stated).
- Update `plugins/soleur/test/scripts-shard-totality-mutations.sh` ROW5 to
  the /7 literals (match `["1/7"…"7/7"]`, mutant drops leg 7), plus the
  adjacent `/6`-citing comments in `scripts-shard-totality.test.sh` (line
  ~170 describes the ROW5 shape — cosmetic but drift-prone).
- `python3 scripts/regenerate-shard-manifest.py --run <id> --write` — the
  TSV's `# n=` header becomes 7; `scripts-shard-manifest.test.sh` stays green.
  **Ordering is load-bearing:** the regenerator derives N from ci.yml via
  `read_ci_leg_count()` (`scripts/regenerate-shard-manifest.py`), so the
  matrix edit MUST land before `--write`, or the TSV regenerates with `n=6`.
- Runbook: update TL;DR + "Current topology" table (K, worst-leg figures) +
  one "Measured history" line citing the run ids.

#### Phase 2b: regen-only (alternative arm)

- `python3 scripts/regenerate-shard-manifest.py --run <id> --write`; commit
  the TSV only.
- Runbook: one "Measured history" line (skew observed, regen applied, run id).

#### Phase 3: Verify locally

- `bash plugins/soleur/test/scripts-shard-totality.test.sh`
- `bash plugins/soleur/test/scripts-shard-manifest.test.sh`
- `bash plugins/soleur/test/scripts-shard-totality-mutations.sh --rows 1-12`
  and `--rows 13-24` (at minimum the rows touching ci.yml: ROW5 family)
- `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`
- `bash plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`
- Leg-union parity at the *runtime* level (belt over the guard):
  `for k in 1..K; SCRIPTS_SHARD=k/K bash scripts/test-all.sh --enumerate scripts`
  unioned == `bash scripts/test-all.sh --enumerate scripts` (no dup).
- Diff-review the TSV: sorted-by-label, provenance header updated, no phantom
  labels (`scripts-shard-manifest.test.sh` also asserts this).

#### Phase 4: PR body + ship inputs

- Before/after table: baseline run 32415069661 (single job 27.7 min,
  ~53 job-min, 374-era suite set) vs post-merge run (leg count, worst leg,
  total job-min) with the suite-growth confound named explicitly.
- Note the runner-slot delta (+0 or +1) and that no required context changed.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Hand-tune `suite-shard-legs.tsv` rows | The file is generated; next regen overwrites and `scripts-shard-manifest.test.sh` expects generator output. Regenerate, never hand-edit (runbook). |
| K=8 or higher | Each leg costs a runner slot against the 60-job org ceiling (Team plan, post-#8450) and re-tests the whole toolchain setup path; K=7 already leaves ~1.5 min headroom. Revisit if suites keep growing — the runbook records the simulation method. |
| Move `lint-orphan-test-suites-mutations` (588.8 s single suite, leg 5) or the battery to/within heavy group | A group move edits `want_scripts`/`want_scripts_heavy` in `scripts/test-all.sh` — the exact region open PR #8763 is editing. Deferred: file a follow-up issue rather than collide; both suites fit under 10 min today. |
| Split `registry-gate-mutation-battery` into `--rows` shards like `shard-totality-mutations` | Its contention ceiling (14.3–27.9 min under load) is a documented floor no matrix beats; a row-split is a suite-internal change touching test-all.sh registration — same #8763 collision, larger scope. Deferred to a follow-up issue; the AC is evaluated on nominal timings. |
| Positional round-robin at higher K | Runbook §Why the OLD positional method is retained — ordinal accidents swing worst legs ±5 min on suite churn; the manifest exists precisely to remove this. |
| Reduce per-leg setup (~0.4 min) | Already near-zero (no npm ci on these legs); nothing to save. |
| Do nothing / accept 13.0 min | Violates the ~10-min acceptance criterion and worsens as suites grow. |

## User-Brand Impact

- **If this lands broken, the user experiences:** slower or falsely-green PR
  feedback on the Soleur plugin repo — worst case a leg silently running the
  full 502-suite group (all green, 5x cost) or a required `test` check that
  blocks every merge.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the change touches CI job topology only; no secrets, no data
  surfaces, no new network edges.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: CI YAML + generated manifest + test-fixture edits
  on an unmetered public repo; no user-facing surface, no regulated data, no
  privileged token scope changes.`

## Observability

```yaml
liveness_signal:
  what: "the required `test` aggregate check per CI run + per-leg suite-timings-* artifacts (worst-leg duration is the signal this plan moves)"
  cadence: "per CI run"
  alert_target: "required-check redness on the PR (ruleset blocks merge); skew noticed via suite-timings artifacts per runbook"
  configured_in: ".github/workflows/ci.yml (test job needs/aggregate step; suite-timings upload steps)"
error_reporting:
  destination: "GitHub Actions job logs + suite-timings-* artifacts (14-day retention)"
  fail_loud: "a leg failure propagates through needs.test-scripts.result into the `test` aggregate and reds the required check"
failure_modes:
  - mode: "manifest n drifts from ci.yml matrix N (K bump without regen)"
    detection: "plugins/soleur/test/scripts-shard-manifest.test.sh fails inside the test-scripts leg"
    alert_route: "required `test` check fails → merge blocked"
  - mode: "untabled registration hash-falls onto one leg (skew regrows)"
    detection: "per-leg suite-timings-* artifact spread on green runs (runbook §Regeneration)"
    alert_route: "operator regenerates manifest (runbook procedure)"
logs:
  where: "GitHub Actions job logs + suite-timings-scripts(-heavy)-* artifacts"
  retention: "Actions log retention / 14-day artifact retention"
discoverability_test:
  command: "grep -m1 -e '# n=' scripts/suite-shard-legs.tsv"
  expected_output: "# n="
```

## Guard Contract

The parity acceptance criterion is delivered by **existing** guards (no new
guard is authored); this section records the contract the plan relies on and
the one guard fixture it edits on the K-bump arm.

### Guard 1 — shard-totality + manifest leg-count parity

**Property.** Every suite registered under `want_scripts` /
`want_scripts_heavy` in `scripts/test-all.sh` runs exactly once across the
declared leg set of `test-scripts` / `test-scripts-heavy` — no drop, no
duplicate, no valid-but-empty leg, and the manifest's `n` always equals the
matrix's declared N.

**Assembly.** The chokepoint is `_shard_selects` in `scripts/test-all.sh`
(manifest lookup → hash fallback → positional degrade), quantifying over: the
`want_*` registration lists, `ci.yml`'s two `strategy.matrix.shard` literals
plus `SCRIPTS_SHARD` env bindings, both `suite-shard-legs*.tsv` manifests, and
`scripts/regenerate-shard-manifest.py` (the producer of the TSVs). Guards:
`plugins/soleur/test/scripts-shard-totality.test.sh` (union = statically
extracted reference set, plus a non-canonical alt-K arm),
`scripts-shard-totality-mutations.sh` (24-row battery incl. the live-ci.yml
ROW5/ROW5B leg-count mutations), `scripts-shard-manifest.test.sh` (n parity,
label ⊆ registered, no dups, provenance). The `test` aggregator
(`ci-test-aggregator-diagnosis.test.sh`) proves the required check cannot
swallow a red leg.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop one leg from ci.yml's light matrix literal (7→6 with manifest n=7) | RED — ROW5 shape: totality fails / manifest-n mismatch fails |
| 2 | Delete `scripts-shard-totality-mutations.sh` ROW5's expected-RED arm so the mutation cannot apply (this is the exact defect the K-bump fixture update prevents) | RED — battery reports unapplied/mismatched row |
| 3 | Add a second `want_scripts` registration after a compliant first while holding the manifest stale | PASS-green today (hash fallback covers) AND totality must still prove union; if it reds, that is the regen signal — the property holds either way |
| 4 | (harness) Swap a totality expected-fail row to expected-pass in the battery | RED — battery self-check flags the verdict inversion |
| 5 | (harness, must-PASS) Run `SCRIPTS_SHARD=k/K bash scripts/test-all.sh --enumerate scripts` for each leg of the NEW K and diff the union against the unsharded enumerate | PASS — disjoint legs, union identical, count identical |

**Anchor.** The reference set is extracted from `scripts/test-all.sh` at
runtime, not stored in-repo — a weakening must move the runner AND the suite
list in one diff to pass falsely; the manifests carry `generated-from-run`
provenance so a stale table is attributable to a run id, not silently current.

## Acceptance Criteria

- [ ] AC1: Worst `test-scripts*` leg on a post-change green CI run measures
      **under ~10 min wall-clock** (target ≤ ~9.5 incl. setup), verified via
      `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs` — recorded in
      `knowledge-base/project/specs/feat-one-shot-ci-test-scripts-sharding/measurements.md`.
      **Atomic-floor carve-out (post-review amendment):** leg 5 is the single
      atomic suite `lint-orphan-test-suites-mutations` (588.8 s suite ≈ ~10.2
      min wall predicted) — no K can split one suite, so leg 5 is exempt from
      the strict ~10-min bound pending its suite-internal split/heavy move,
      tracked in #8864. The AC is satisfied when every non-atomic leg lands
      under ~10 min and the atomic leg is within ~0.5 min of it.
- [ ] AC2: Required-check set unchanged — `git diff origin/main --
      scripts/required-checks.txt infra/github/` is empty, and the `test`
      job's `needs:` list + name are unmodified; no new required contexts, no
      removed ones.
- [ ] AC3: Suite-count parity — `scripts-shard-totality.test.sh`,
      `scripts-shard-manifest.test.sh`, `scripts-shard-totality-mutations.sh`
      (both row halves) and `ci-test-aggregator-diagnosis.test.sh` all green;
      plus a leg-union enumerate diff (Phase 3) showing every registered
      suite runs exactly once at the shipped K.
- [ ] AC4: merge_group invariant — `git diff` on `.github/workflows/ci.yml`
      touches no `on:` trigger and adds no `if: github.event_name` gate to
      any job producing a required context.
- [ ] AC5: `scripts/test-all.sh` untouched — `git diff origin/main --
      scripts/test-all.sh` is empty (collision constraint vs. PR #8763).
- [ ] AC6: If the K-bump arm ships, `scripts/suite-shard-legs.tsv` `# n=`
      header == ci.yml matrix leg count AND
      `scripts-shard-totality-mutations.sh` ROW5 literals match the new
      matrix (atomic drift-surface update).
- [ ] AC7: Runbook updated — "Current topology" table and TL;DR reflect the
      shipped K and measured worst leg; "Measured history" gains a dated line
      with run ids.
- [ ] AC8: PR body carries the before/after measurement table (longest job;
      job-min per run; suite-count confound named).

## Test Scenarios

- Given a regenerated manifest, when `scripts-shard-manifest.test.sh` runs,
  then it reports manifest `n` == ci.yml declared N, labels ⊆ registered set,
  no dups, provenance present.
- Given the shipped matrix K, when each leg enumerates
  (`SCRIPTS_SHARD=k/K ... --enumerate scripts`), then the union equals the
  unsharded `--enumerate scripts` output with zero duplicates.
- Given a hypothetical one-leg-removal mutation of the matrix, when ROW5 of
  the mutation battery applies it, then the totality guard must go RED
  (battery asserts this on the live file).
- Given a PR run post-merge, when `test` aggregates, then
  `needs.test-scripts.result`/`needs.test-scripts-heavy.result` reflect the
  matrix outcomes and the required `test` context reports.
- Given a sibling manifest regen landing first, when this PR rebases, then
  the TSV conflict resolves by re-running `regenerate-shard-manifest.py
  --run <fresh-green-run> --write` — never hand-merge.

## Success Metrics

- Longest CI job ≤ ~10 min (from 13.0 current / 27.7 pre-shard baseline).
- Time-to-`test` verdict improves correspondingly (leg-bound).
- Job-min per run reported honestly (expect ~108–125; delta vs. pre-change
  limited to ±(new legs × ~0.4 min)); suite-count confound disclosed.
- Zero changes to `required-checks.txt` / `infra/github/` / `test-all.sh`.

## Dependencies & Risks

- **PR #8763** edits `scripts/regenerate-shard-manifest.py` and the same
  runbook — if it merges first, re-check the regenerator's CLI and expect a
  runbook-context conflict (disjoint sections; rebase resolves).
- **Regenerator needs a green run with `suite-timings-*` artifacts**
  (14-day retention); its default latest-green lookup 404'd in this session —
  pass `--run` explicitly. If no suitable run exists (artifacts expired),
  push the branch once and use the PR's own CI run as the source.
- **A run landing between regen and merge re-drifts the manifest** — accepted
  by design (sticky-LPT tolerates drift); resolve TSV conflicts by regen.
- **Contention days**: the battery leg can still exceed ~10 min under load
  (documented floor); AC1 is evaluated on nominal green-run timings, and the
  caveat is disclosed in the PR body + runbook.

## Open Code-Review Overlap

- **#8659** (test-helpers EXIT-trap refactor across 33 suites, body references
  `scripts/test-all.sh`): **Acknowledge** — this plan does not edit
  `test-all.sh` or suite internals; disjoint scope.
- **#7942** (two `*.mutation.sh` batteries run in no gate): **Acknowledge** —
  different files (`scripts-shard-totality-mutations.sh` is gated inside the
  `test-scripts` group itself); no fold-in.

## Domain Review

**Domains relevant:** engineering (CI tooling) — assessed inline (planning
subagent has no Task-spawn surface; sequential-fallback disclosure: no
independent domain-leader review ran).

### Engineering

**Status:** reviewed
**Assessment:** Devex-positive (faster required-check feedback); cost is ≤1
extra runner slot against the 60-job org ceiling (Team plan, post-#8450), weighed and recorded in
Alternatives. No product/marketing/legal/finance surface; Product/UX gate
not triggered (no UI-surface files in the edit set).

## Architecture Decision (ADR/C4)

No new architectural decision — the shard topology (matrix + manifest +
degrade contract) is already decided and recorded (ADR-238 taxonomy carries
the CI matrix topology; ADR-240 duration-aware manifests). A K-bump is a
parameter change inside that decision, not a reversal or extension.

**C4 check:** enumerated the rubric against `model.c4`/`views.c4`/`spec.c4` —
(a) external human actors: none new (same GitHub-hosted runners, already
outside the modeled product boundary); (b) external systems: GitHub Actions
is unchanged as an execution substrate — no new integration edge; (c)
containers/data stores: none touched; (d) relationships: none change — a leg
count is an instance count of an unmodeled CI fleet, not a model element.
Conclusion: **no C4 impact**.

## Deferred Follow-ups

- File a P3 issue at work time: "ci: split/move the two >8-min long-tail
  suites (`lint-orphan-test-suites-mutations` ~588.8 s; the
  `registry-gate-mutation-battery` contention ceiling) if regen can no
  longer hold worst-leg < ~10 min" — blocked-by relationship to this PR's
  issue if one is filed; re-evaluate on next skew event (runbook trigger).

## References & Research

- Runbook (authority): `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
- Decisions: ADR-238 (taxonomy carries matrix topology), ADR-240 (duration-aware manifests), ADR-212 (deploy gate)
- Prior work: #8585 (K=5 + heavy carve-out), #8612 (manifests), #8665 (K=6 + mutations split + parallel enumerate), issue #8006 (closed)
- Measurements: run 32415069661 (2026-08-20 baseline), run 36123485360 (2026-09-25 current), run 35945250103 (manifest provenance)
- Collision surface: PR #8763 (`feat-one-shot-8736-deploy-script-tests-parallel`)
- Required checks: `scripts/required-checks.txt`, `infra/github/ruleset-ci-required.tf`
- Org concurrency: `knowledge-base/project/brainstorms/2026-09-21-ci-runner-concurrency-brainstorm.md`
