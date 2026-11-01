---
title: "ci: ci-shard-balance-watch — advisory scheduled probe for floor-priced and never-measured manifest rows"
type: feat
date: 2026-10-31
slug: ci-shard-balance-watch-drift-probe
branch: feat-one-shot-11564-shard-balance-watch
issue: 11564
closes: 11564
domain: engineering
priority: p3-low
lane: cross-domain
brand_survival_threshold: none
---

# ci: ci-shard-balance-watch — advisory drift probe for the shard manifests

## Enhancement Summary

**Deepened on:** 2026-10-31
**Sections enhanced:** Research Insights (deepen verifications); all halt gates verified mechanically in place.
**Review coverage:** `Reviewed-Coverage: sequential-fallback` — this harness has no Task agent roster; the per-section research/review fan-out ran as one consolidated in-process pass applying the reviewers' lenses (correctness, over-engineering, simplicity) plus the mechanical halt gates below.

### Key verifications (deepen pass)

1. **Halt gates:** User-Brand Impact (present, threshold `none`, no sensitive-path files — `SENSITIVE_PATH_RE` matched nothing across the file lists), Observability (5-field schema complete; `discoverability_test` verb `bash` is allowlisted, `expected_output: ok` is a matchable literal, no `ssh`, sub-15 s), PAT sweep (0 hits), UI-wireframe (no UI-surface files — skipped), Encryption Posture (no persistent store or new cross-component connection; the word "queue" is GitHub's merge queue, not a store class — skipped), Guard Contract (`scripts/lint-guard-contract.py` → rc 0; adequacy read: Assembly names chokepoints not member lists; matrix rows are design-derived with harness rows 4/8/9), Scope Check (exactly one unfenced section, all subsections, every ask mapped, inferred rows justified, no BLOCKED marker), Task Design (one unfenced section, all six fields non-placeholder, dedupe names the sentinel mechanism beyond `concurrency.group`).
2. **Precedent-diff (Phase 4.4):** 58 Inngest `cron-*` functions exist and would normally be canonical per ADR-033 — but this work is purely repo-scoped (GH API reads + issue comments, default `GITHUB_TOKEN`, no app secrets, no Sentry, no `step.run` replay value), which is carve-out (a) of that ADR; the `*-watch.yml` filename also keeps clear of the `scheduled-*.yml` Inngest-preference hook. Three live siblings (`registration-narrowing`, `codeql-1537-revisit`, `code-quality-followups`) are the binding precedent — the plan mirrors their shape rather than inventing.
3. **Verify-the-negative (Phase 4.45):** "main pushes elide the shards job" confirmed — ci.yml's shard jobs carry `if:` with `needs.push-dedupe.outputs.elide != 'true'`; "artifacts live 14 days" confirmed — `retention-days: 14` on both upload steps; `-p 'suite-timings-scripts-*'` downloads heavy artifacts too, which the generator's `LIGHT_ARTIFACT`/`HEAVY_ARTIFACT` dir-name filters segregate per group (the per-leg-sums pollution gotcha is absorbed by the filter, not by naming discipline).
4. **Post-edit self-audit:** no plan reference names a dropped symbol; every cited path was verified to exist on this branch (`scripts/regenerate-shard-manifest.py`, both manifests + durations tables, `scripts/lib/watch-notify-once.sh`, the runbook, `scripts/ci-pr-affected-audit.accept.tsv`).

### New considerations discovered

- The new `scripts/watch-shard-balance-11564` suite lands **floor-priced itself** after the incremental regen — the first concrete instance of the class the watcher exists to catch (expected, benign, and worth a line in the runbook section).
- `LEG_OBSERVED` is defined as sum-of-cross-run-medians per leg (deterministic, matches the generator's aggregation semantics), which differs from the epic comment's per-run leg wall-clock; that is intentional — the assertion is about *packing* drift, not wall-clock overhead.

## Overview

Ship the deferred `ci-shard-balance-watch` capability (issue #11564, child of open epic #11556) as an **advisory, notify-only scheduled GitHub Actions workflow**. It samples per-suite timing artifacts from recent merge-queue CI runs, compares fresh measurements against the committed shard manifests' pricing, and flags `src=floor` rows (never-measured or floor-priced suites) whose real cost exceeds a bound — the drift class that priced one suite at a 1.2 s floor while it actually cost ~25 min on a 54-min leg. A secondary leg-balance assertion compares predicted per-leg sums from the committed durations table against the perfect-balance bound, so a rebalance need is flagged before it becomes a worst-leg incident.

`Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).`

## Problem Statement / Motivation

- `scripts/suite-durations.tsv` currently carries **97 `src=floor` rows of 698** (all priced at the 1,222 ms default weight). A floor-priced suite that is actually expensive is unpriced risk: it keeps its ~1 s price through every `--incremental` regen and can grow unboundedly before any balance check notices — the exact failure the Lever-A slice had to perform surgery on (floor-priced 1.2 s, measured 24.9 min).
- The `ci-leg-balance-9232` daily sweep closed 2026-09-30; **nothing sweeps drift today**. Regen is manual per `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
- Post-reprice baseline (epic #11556 checkpoint comment, 2026-10-31): worst `test-scripts` legs ~37 min vs ~30.3 min perfect-balance bound. Arm rows are now *measured*, not estimated — so floor-priced and never-measured rows are the remaining pricing-drift class.
- The issue prescribes machinery class "advisory scheduled workflow first, ratchet second." This slice ships the advisory probe; the required-ratchet promotion is deferred (see Deferrals).

## Proposed Solution

Three cooperating pieces, all matching the established `*-watch.yml` + `scripts/watch-*-<issue>.sh` convention (siblings: registration-narrowing-watch, codeql-1537-revisit-watch, code-quality-followups-watch):

1. **`scripts/regenerate-shard-manifest.py --drift-report`** — a new read-only reporting mode on the existing timing-aggregation authority. Given repeated `--timings-dir` dirs (one per sampled run), it emits machine-readable rows: per-floor-row fresh medians (`DRIFT_ROW`), predicted per-leg sums from the committed tables (`LEG_PREDICTED`), observed per-leg sums (`LEG_OBSERVED`, light group only), the perfect-balance bound (`BOUND_PERFECT`), and a count of floor rows absent from all samples (`FLOOR_UNMEASURED`). It writes nothing and exits 0 on findings (2 on bad input).
2. **`scripts/watch-shard-balance-11564.sh`** — thin bash driver: selects the last 5 green `merge_group` `ci.yml` runs, downloads their `suite-timings-scripts-*` artifacts into per-run temp dirs, invokes the drift report, thresholds the findings (floor rows ≥ 300 s; leg ratios > 1.30), and manages a dedicated drift tracker issue (find-or-file, sentinel-hash dedup, close-on-clear). `--dry-run` prints the would-be comment and posts nothing.
3. **`.github/workflows/shard-balance-watch.yml`** — weekly advisory schedule plus `workflow_dispatch` with a `dry_run` input, scoped to the default branch of `jikig-ai/soleur`, `contents: read` + `issues: write`, no secrets.

### Why merge_queue runs and `--timings-dir` (not `--runs`)

`--runs N` resolves "the N most recent successful **main-push** runs" (`green_main_runs()` filters `--branch main`). Under `push-dedupe` the shards job is **elided on push events** when an identical-SHA merge_group run already passed — so main-push runs routinely carry no `suite-timings-scripts-*` artifacts and the floor rows that need measuring never get measured. `merge_group` runs always run the full matrix and always upload timings (`if: always()`), and artifacts live 14 days. The watch therefore enumerates green `merge_group` runs itself and hands the generator local artifact dirs — the same `--timings-dir` path the runbook prescribes for arm pricing.

## Technical Approach

### Architecture

```
cron (weekly) / workflow_dispatch
  └─ shard-balance-watch.yml  (advisory; default-branch only; issues:write)
       └─ scripts/watch-shard-balance-11564.sh
            ├─ gh run list --workflow ci.yml --event merge_group --status success -L 5
            ├─ gh run download <id> -R jikig-ai/soleur -p 'suite-timings-scripts-*' -D <run-dir>   (×N runs)
            ├─ python3 scripts/regenerate-shard-manifest.py --drift-report \
            │       --timings-dir <d1> ... --timings-dir <dN>          (measurement, read-only)
            └─ threshold + sentinel-dedup + tracker lifecycle            (policy, issues API)
```

Separation of concerns: the generator owns **measurement** (it is the only implementation of the timing-merge verdict exclusions and the per-group artifact-name filters — duplicating them in bash/awk would rot); the watch script owns **policy** (bounds, cadence, notification dedup, tracker lifecycle); the workflow owns **scheduling**.

### Implementation Phases

#### Phase 1: `--drift-report` measurement mode in the generator

- Add `--drift-report` to `scripts/regenerate-shard-manifest.py`: requires `--timings-dir` (repeatable, one dir per sampled run — the same merging path the timing inputs already use); refuses `--write`/`--incremental`/`--legs` (report mode never writes). `--durations`/`--manifest` remain honored as the comparison-base overrides (default: each group's committed tables) — they are the fixture seam the unit suite uses to feed synthetic committed tables.
- Emission contract (stdout, one row per line, exit 0):
  - `DRIFT_ROW <group> <label> <committed_ms> <fresh_median_ms> <timed_runs>/<sampled_runs>` — one per `src=floor` row of each durations table that HAS at least one fresh measurement. Group loop covers light + heavy (heavy comes free: same runs carry `suite-timings-scripts-heavy-N`, filtered by `HEAVY_ARTIFACT`).
  - `LEG_PREDICTED <group> <leg> <sum_ms>` — predicted per-leg sum from committed durations + manifest.
  - `LEG_OBSERVED light <leg> <sum_ms>` — fresh per-leg sum: each light label's cross-run median, summed through the incumbent manifest's leg assignment. **Light only** — heavy-leg artifacts must not enter light leg sums (per-leg-sums pollution gotcha); heavy balance is a one-suite-per-leg atomic floor where the assertion has no lever.
  - `BOUND_PERFECT light <ms>` — `sum(light timings)/8`.
  - `FLOOR_UNMEASURED <group> <count>` — floor rows absent from every sampled run (informational; cannot exceed a cost bound while unmeasured).
- Extend `plugins/soleur/test/regenerate-shard-manifest.test.sh` with drift-report cases (fixture dirs, emission shape, floor-vs-measured discrimination, light/heavy artifact filtering, refusal arms).
- Success: dry-run on a downloaded real artifact set prints the report; unit suite green.

#### Phase 2: watch script + tracker lifecycle

- `scripts/watch-shard-balance-11564.sh` (conventions copied from `scripts/watch-registration-narrowing-9564.sh`): `set -uo pipefail`, xtrace refusal (exit 78), exit vocabulary `0 ok / 1 post failed / 2 usage / 3 cannot establish`, `--dry-run` and `--print-report` modes, `GH_TOKEN`+`GH_REPO` env from the workflow.
- Run selection: `gh run list --workflow ci.yml --event merge_group --status success -L 5 --json databaseId`; artifact download per run via `gh run download <id> -R "$GH_REPO" -p 'suite-timings-scripts-*' -D <tmpdir>/<id>` (`-R` is load-bearing on this repo's hosts — see learnings).
- Thresholds (constants at the top of the script):
  - `FLOOR_DRIFT_BOUND_MS=300000` — flag `DRIFT_ROW` rows ≥ 5 min (the issue's own re-evaluation bound; ~17% of a 30-min leg).
  - `LEG_DRIFT_RATIO=1.30` — flag when `max(LEG_OBSERVED)/BOUND_PERFECT` or `max(LEG_PREDICTED)/mean(LEG_PREDICTED)` exceeds it. Today's known state (~1.22) does not fire — that is leg-*content* debt tracked by open #11647/#11648, not pricing drift.
- Tracker lifecycle: find-or-file ONE issue titled `ci-shard-balance-watch: manifest drift findings` carrying sentinel `<!-- shard-balance-watch:v1 drift=<sha1-of-flagged-set> -->`; post a comment only when the flagged-set hash changes; when the set empties post a resolution comment and close the tracker (the watch owns this tracker — the no-close convention binds trackers it does not own). Self-disable: if the workflow/script machinery is retired the tracker close is the last act.
- Success: `--dry-run` prints the composed findings; fixture suite green.

#### Phase 3: workflow + registration + docs

- `.github/workflows/shard-balance-watch.yml`: `schedule: '41 9 * * 2'` (Tue 09:41 UTC — staggered from the Mon 09:17 sibling trio); `workflow_dispatch` with `dry_run` boolean; top-level `permissions: {}`; job-level `permissions: contents: read, issues: write`; `if: github.repository == 'jikig-ai/soleur' && (github.event_name == 'schedule' || github.ref == format('refs/heads/{0}', github.event.repository.default_branch))`; `concurrency.group: shard-balance-watch`, `cancel-in-progress: false`; `timeout-minutes: 15`; checkout `persist-credentials: false`, `fetch-depth: 1` (no git history needed); header carries WHY/DEDUP/SELF-DISABLE/RESIDUAL-RISK/RETIREMENT comment block per sibling convention.
- Register `scripts/watch-shard-balance-11564.test.sh` as `run_suite "scripts/watch-shard-balance-11564"` in `scripts/test-all.sh` (want_scripts region, beside the other `watch-*` suites), then `python3 scripts/regenerate-shard-manifest.py --incremental --write` to add its floor row to `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv`.
- Update the sharding runbook: watcher section (cadence, tracker lifecycle, `--timings-dir` regen recipe for the elided-shards-on-push gotcha, retirement pointer).
- Success: full `bash plugins/soleur/test/scripts-shard-manifest.test.sh` + the new watch suite + shard-totality green; `gh workflow run shard-balance-watch.yml -f dry_run=true` verified post-merge per the workflow header's own check recipe.

### Files to Create

| File | Purpose |
|---|---|
| `scripts/watch-shard-balance-11564.sh` | Probe driver: run selection, artifact download, thresholding, tracker lifecycle |
| `scripts/watch-shard-balance-11564.test.sh` | Fixture suite: mutation matrix, dedupe, exit codes, tracker find-or-file |
| `.github/workflows/shard-balance-watch.yml` | Weekly advisory schedule + dispatch |

### Files to Edit

| File | Change |
|---|---|
| `scripts/regenerate-shard-manifest.py` | Add `--drift-report` read-only reporting mode |
| `plugins/soleur/test/regenerate-shard-manifest.test.sh` | Cases for the new mode |
| `scripts/test-all.sh` | `run_suite "scripts/watch-shard-balance-11564"` registration |
| `scripts/suite-shard-legs.tsv` | Incremental regen row (floor, deterministic placement) |
| `scripts/suite-durations.tsv` | Incremental regen row (`<label>\t1222\tfloor` at current floor) |
| `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` | Watcher section + `--timings-dir` regen recipe |
| `scripts/ci-pr-affected-audit.accept.tsv` | Conditional: accept rows only if the replay ratchet flags this suite's fixture path names |

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Required ratchet (a blocking check in `ci.yml`) | Issue prescribes "advisory scheduled workflow first, ratchet second"; a blocking check before the probe has proven low-noise would gate merges on an uncalibrated bound. Deferred — see Deferrals. |
| Follow-through sweeper tracker | The sweeper comments on every non-pass verdict with no per-verdict dedup; a recurring drift monitor would comment every sweep. `followthrough-convention.md` routes this shape to a dedicated scheduled workflow. |
| Standalone bash/awk aggregation in the watch script | Duplicates `merge_tsv` verdict exclusions (`skip=`, FAIL/KILLED/TRIPWIRE) and the per-group artifact-name filters; two implementations of timing semantics rot independently. The generator is the measurement authority. |
| Comment on epic #11556 or on #11564 | #11564 closes when this ships; the epic is human-owned and every-set-change comments are noise. The watch owns a dedicated findings tracker it can also close on all-clear. |
| Sample `pull_request` runs too | PR runs may run pr-selection-skipped shapes and draft-light elisions; merge_group is the canonical as-merged full-matrix run. Widening is a listed deferral. |

## Research Insights

**Premise validation.** Issue #11564 OPEN, epic #11556 OPEN (both verified via `gh issue view --json state`). The brainstorm (`2026-10-29-required-check-time-brainstorm.md`, archived 2026-10-30) and the epic's 2026-10-31 checkpoint comment were read; the post-reprice leg table matches the brief's ~37/~30 min figures. The issue asserts "nothing sweeps drift today" — verified: `grep -rn "regenerate-shard-manifest" .github/workflows/` returns no scheduled job, and the `ci-leg-balance-9232` daily sweep is closed. Mechanism-vs-ADR check: the `*-watch.yml` scheduled-watcher pattern is established precedent (ADR-033 Inngest-cron decision routes repo-scoped, secret-free, comment-only watchers to GHA schedules — three live siblings exist); the proposed mechanism is not in any ADR's rejected-alternatives table. **Collision precheck** (`collision-precheck.sh 11564`) reported open PR #11728 — inspected: it is this pipeline's own auto-created draft on this very branch (`feat-one-shot-11564-shard-balance-watch`, "WIP" draft created 2026-10-31T20:04Z), i.e. a benign self-collision, not foreign work.

**Property List** (Phase 0.6b). The issue's mechanism restated as observable properties: (P1) a `src=floor` manifest row whose real measured cost exceeds a bound is detected without a human remembering to regen; (P2) a leg-balance drift vs the committed durations is surfaced before it becomes a worst-leg incident; (P3) detection happens on a cadence without blocking PRs (advisory); (P4) repeated identical findings do not spam; (P5) a finding reaches a place a human reads (tracker issue).

**Cut List** (Phase 0.6b). Mechanisms the ask names that are already covered or unneeded: (a) "required ratchet" — the issue itself defers it; the advisory probe buys P1–P5 without the merge-gating risk, so the ratchet mechanism is cut from this slice. (b) A bespoke aggregation engine — cut: `regenerate-shard-manifest.py` already implements fetch/merge/median/floor semantics; the plan adds a report mode rather than a second implementation. (c) Local `WEIGHT_DRIFT` warn (test-all.sh, warn-only, local-only, CI never defaults) — covers local affected-shaped runs only; it does not buy P1/P3 on CI. No cut.

**Relevant paths.** `scripts/regenerate-shard-manifest.py` (911 lines; `fetch_timings_from_dir`, `aggregate_runs`, `read_durations`, `read_incumbent`, `LIGHT_ARTIFACT`/`HEAVY_ARTIFACT` filters, `--timings-dir` repeatable). `scripts/suite-durations.tsv` (`label<TAB>ms<TAB>src`, 598 measured / 97 floor). `scripts/suite-shard-legs{,-heavy}.tsv` (committed manifests). `.github/workflows/ci.yml` (test-scripts K=8 job, `suite-timings-scripts-${strategy.job-index}` upload `if: always()`, retention 14 d; push-dedupe elision `if:` on shard jobs). `scripts/test-all.sh` (run_suite registration + `TEST_TIMING_LOG` feed). `plugins/soleur/test/scripts-shard-manifest.test.sh` (durations↔manifest keys-parity lint). `.github/workflows/code-quality-followups-watch.yml` + `registration-narrowing-watch.yml` + `scripts/lib/watch-notify-once.sh` (workflow/script conventions). `scripts/ci-pr-affected-audit.accept.tsv` (accept-row convention for fixture path names).

**Learnings applied.** `2026-10-29-decompose-ci-leg-wallclock-from-suite-timings-before-attributing-overhead.md`: suite-timings artifacts settle cost attribution; floor rows are unpriced risk; `gh run download` needs `-R`; PR-event medians ≠ merge/main medians (hence merge_group sampling). `2026-10-03-a-manifest-priced-from-staged-runs-misses-a-suite-that-landed-after-them.md` (sample freshness). Drift-guard corpus (`best-practices/2026-08-13-every-guard-i-shipped...`): sentinel dedupe + must-PASS rows in the mutation matrix.

**External research:** skipped — the mechanism is repo-internal machinery with live precedent; community artifacts cannot carry repo-specific manifest knowledge (functional-overlap check done inline; no overlap found).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on this branch | Plan response |
|---|---|---|
| "nothing sweeps drift today — regen is manual" | Confirmed: no scheduled workflow touches the manifests | The watch is the sweep |
| "floor-priced or never-measured manifest rows" | 97 floor rows exist, all at the 1,222 ms default; none currently > 60 s real | Probe starts at a clean baseline; bound set at 300 s |
| "a leg-balance assertion vs the committed suite-durations.tsv" | Predicted legs are computable from committed tables; observed legs need artifacts | Both emitted; observed restricted to light group (heavy pollution gotcha) |

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — worst case is a missed or noisy drift notice on an internal tracker; PR CI is unaffected (advisory workflow, never a required check).
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the probe reads this repo's CI artifacts and writes comments on this repo's own tracker using the default workflow token; no secrets, no user data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the deliverable is a read-only probe plus issue comments in our own repo; it cannot ship a bad commit, expose data, or change any required check — internal tooling with no user surface.

## Observability

```yaml
liveness_signal:
  what: Weekly scheduled run of shard-balance-watch green on the Actions tab (a silently dead watcher is detected by a missing/red run, not by content)
  cadence: weekly (Tue 09:41 UTC) + on-demand workflow_dispatch
  alert_target: GitHub Actions failure email to the actor that last edited the cron line; Actions tab run list
  configured_in: .github/workflows/shard-balance-watch.yml
error_reporting:
  destination: GitHub Actions run log + ::error:: annotations (no Sentry — repo-scoped machinery per sibling convention)
  fail_loud: exit 3 (cannot establish) fails the run; a green run that silently skipped measurement is the banned state
failure_modes:
  - mode: Artifact listing/download API outage or auth loss
    detection: gh call fails -> exit 3 red run
    alert_route: Actions failure notification
  - mode: Zero suite-timings artifacts found (retention expiry, artifact rename, upstream upload change)
    detection: explicit empty-sample check -> exit 3, never a green "no drift"
    alert_route: Actions failure notification
  - mode: Drift tracker deleted or auto-closed externally
    detection: find-or-file recreates it on the next drift
    alert_route: none needed (self-healing; the new tracker links the old number in its first comment)
  - mode: Scheduled run silently dropped by GitHub (known residual, shared with sibling watches)
    detection: missing Monday run visible in `gh run list --event schedule`
    alert_route: none — documented residual risk; no dead-man alarm by design
logs:
  where: GitHub Actions run log for shard-balance-watch
  retention: default Actions retention (~90 days)
discoverability_test:
  command: bash -n scripts/watch-shard-balance-11564.sh && grep -q 'shard-balance-watch' .github/workflows/shard-balance-watch.yml && printf 'ok\n'
  expected_output: ok
```

## Infrastructure (IaC)

The detection surface is a `schedule:` cron — the mechanism that satisfies it is the committed `.github/workflows/shard-balance-watch.yml` itself, which **is** this repo's established IaC for repo-scoped scheduled machinery (ADR-033; three sibling `*-watch.yml` files). No hosts, secrets, vendor accounts, DNS, or persistent processes are introduced; the job uses the default `GITHUB_TOKEN` only. There is no manual-provisioning step in any phase, so no Terraform work is prescribed.

## Task Design

```yaml
tasks:
  - task: shard-balance-watch
    trigger: cron weekly Tue 09:41 UTC + workflow_dispatch (dry_run input)
    services: reads GitHub Actions runs/artifacts REST + committed TSVs; writes issue create/comment/close on its own drift tracker (issues: write)
    next: files or updates the drift tracker when the flagged set is non-empty/changed; closes it on all-clear; nothing else
    human_reentry: `gh workflow run shard-balance-watch.yml -f dry_run=true` prints findings and posts nothing; closing the tracker is overridden by re-file on next drift; deleting the workflow retires the task (RETIREMENT block in the workflow header)
    dedupe: sentinel `<!-- shard-balance-watch:v1 drift=<set-sha1> -->` on the watch-owned tracker — a comment posts only when the flagged-set hash differs from the last posted sentinel; concurrency.group serializes overlapping runs but the sentinel is the work-level dedupe
    source_dedupe: it is the ticket source — find-or-file on the sentinel title across open issues; never a second tracker while one is open
```

## Guard Contract

### Guard 1 — shard-balance drift detection

**Property.** Every `src=floor` row of the committed durations tables whose fresh merge-queue median is ≥ `FLOOR_DRIFT_BOUND_MS`, and every light-leg predicted/observed sum exceeding `LEG_DRIFT_RATIO`× the per-leg bound, appears in the watch's findings set; an identical findings set never posts twice.

**Assembly.** The chokepoints are: (a) the committed durations tables' `src=floor` rows, enumerated only through `read_durations`/`read_durations_ms` in `scripts/regenerate-shard-manifest.py`; (b) the sampled runs' `suite-timings-scripts-{N}` artifacts (light) and `suite-timings-scripts-heavy-{N}` (heavy), enumerated only through the generator's per-group `ARTIFACT` regexes — both legs of the fetch funnel through `fetch_timings_from_dir`; (c) the threshold + set-compare + sentinel-write path in `scripts/watch-shard-balance-11564.sh`; (d) the tracker find-or-file sentinel scan.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture `src=floor` row with fresh median 25 min (> bound) — the guard must flag it (a report listing zero flagged rows while the fixture over-runs is vacuous) | RED |
| 2 | Drop the threshold comparison / report emission from the watch driver — findings reach the tracker | RED |
| 3 | Two distinct over-bound floor rows in one fixture — BOTH must appear (a first-match-only check is the defect class) | RED |
| 4 | Identical flagged set on a second invocation — must NOT post a second comment (sentinel dedupe) | RED |
| 5 | Mixed download dir containing `suite-timings-scripts-heavy-N` dirs — heavy rows must not enter the LIGHT leg sums | RED |
| 6 | Timings fixture rows carrying `skip=`/FAIL/KILLED/TRIPWIRE verdicts — must be excluded from medians | RED |
| 7 | Zero timing artifacts in every sampled run dir — exit 3 (cannot establish), never a green all-clear | RED |
| 8 | Floor row with fresh median just under the bound (e.g. 299 s) — must-PASS unflagged (the bound is discriminating, not flag-all) | PASS |
| 9 | Flagged set that shrinks but is non-empty — exactly one comment carrying the new sentinel | PASS |

**Anchor.** The bound constants and sentinel live in the committed script; a PR that weakens `FLOOR_DRIFT_BOUND_MS`/`LEG_DRIFT_RATIO` is review-visible in the diff — the values are not self-certified by the run.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "A scheduled probe or required ratchet that flags `suite-shard-legs.tsv` drift before it becomes a 50-min leg" | `.github/workflows/shard-balance-watch.yml` + `scripts/watch-shard-balance-11564.sh` + `--drift-report` mode | mapped |
| 2 | "floor-priced or never-measured manifest rows above a cost bound" | `DRIFT_ROW` detection + `FLOOR_DRIFT_BOUND_MS=300000` threshold + `FLOOR_UNMEASURED` informational count | mapped |
| 3 | "optionally a leg-balance assertion vs the committed `suite-durations.tsv`" | `LEG_PREDICTED` + `LEG_OBSERVED` rows + `LEG_DRIFT_RATIO=1.30` threshold | mapped |
| 4 | "Machinery class; likely an advisory scheduled workflow first, ratchet second" | advisory workflow this slice; required-ratchet promotion filed as a deferred-item issue | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `.github/workflows/shard-balance-watch.yml` | "A scheduled probe or required ratchet" / "likely an advisory scheduled workflow first" | asked |
| `scripts/watch-shard-balance-11564.sh` | "a scheduled probe … that flags `suite-shard-legs.tsv` drift" | asked |
| `scripts/watch-shard-balance-11564.test.sh` | — | inferred — justification: every watch script in this repo ships a fixture suite registered via run_suite; an untested notify-once script is exactly the class that silently stops working |
| `scripts/regenerate-shard-manifest.py` (`--drift-report`) | "flags … manifest rows above a cost bound" | inferred — justification: measurement must reuse the single timing-aggregation authority; the issue names the property, not the implementation surface |
| `plugins/soleur/test/regenerate-shard-manifest.test.sh` | — | inferred — justification: the generator's own suite is where new modes are pinned |
| `scripts/test-all.sh` registration | — | inferred — justification: suite registration is the only path that gets the fixture suite onto a CI leg |
| `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv` rows | — | inferred — justification: keys-parity lint (`check_durations`) requires both tables to carry every registered label |
| `knowledge-base/.../ci-test-scripts-sharding.md` | — | inferred — justification: the runbook is the documented owner of regen cadence guidance the watcher changes |
| `scripts/ci-pr-affected-audit.accept.tsv` | — | inferred — justification: conditional accept rows only if the replay ratchet flags the new suite's fixture path references |

### Split Assessment

- Subsystems touched: 4 — `scripts`, `.github`, `plugins`, `knowledge-base`
- Planned files: ~9 | Estimated changed lines: ~1,000
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over the root/line thresholds, but the generator mode without its consumer is dead code and the watch without the mode cannot measure; stage as two reviewable commits (generator+tests, then watch+workflow+registration) inside one PR rather than two PRs

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (sequential-fallback — no Task agent roster on this harness; assessment applied from the CTO definition inline)
**Assessment:** The machinery the issue asks for is a delta on existing, well-tested substrate: the timing-artifact feed (uploaded `if: always()` on every shard leg), the aggregation authority (`regenerate-shard-manifest.py`), and the `*-watch.yml` advisory-watcher convention (three live siblings). Risk is LOW for correctness of the probe itself (read-only + comment-only) and MEDIUM for uncalibrated thresholds (mitigated by the 300 s/1.30 bounds chosen against the measured baseline and by the informational-only treatment of never-measured rows). Named residual: a silently dropped scheduled run has no dead-man alarm (documented in the workflow header, same as siblings).

**Brainstorm carry-forward:** the brainstorm's `## Domain Assessments` (Engineering/CLO/Operations) name no additional specialists to invoke for this slice; its D10 Productize Candidate is exactly this issue. CLO/COO findings (required-check invariants, cost ledgering) do not bind this slice — the probe touches no required check and consumes $0 runner cost on a public repo.

## Acceptance Criteria

- [ ] AC1: `.github/workflows/shard-balance-watch.yml` exists with a weekly cron, a `dry_run` workflow_dispatch input, top-level `permissions: {}`, job-level `contents: read` + `issues: write`, a default-branch/repo-scoped `if:`, `concurrency.group: shard-balance-watch` with `cancel-in-progress: false`, and a header comment block covering WHY / cadence / dedupe / self-disable / residual risk / retirement checklist.
- [ ] AC2: `python3 scripts/regenerate-shard-manifest.py --drift-report --timings-dir <d1> [--timings-dir <d2> ...]` prints `DRIFT_ROW`, `LEG_PREDICTED`, `LEG_OBSERVED` (light only), `BOUND_PERFECT` and `FLOOR_UNMEASURED` rows; refuses `--write`/`--incremental`/`--legs`; writes no files; exits 0 with findings and 2 on bad input.
- [ ] AC3: `bash scripts/watch-shard-balance-11564.sh --dry-run` enumerates the last 5 green merge_group `ci.yml` runs, downloads their `suite-timings-scripts-*` artifacts, and prints the thresholded findings (floor rows ≥300,000 ms; leg ratios >1.30) without posting.
- [ ] AC4: Tracker lifecycle — the watch finds-or-files exactly one open `ci-shard-balance-watch: manifest drift findings` issue carrying the `<!-- shard-balance-watch:v1 drift=<hash> -->` sentinel; posts a comment only when the flagged-set hash changes; posts a resolution comment and closes the tracker when the flagged set empties.
- [ ] AC5: `scripts/watch-shard-balance-11564.test.sh` is registered via `run_suite` in `scripts/test-all.sh` and covers the Guard Contract mutation matrix (over-bound flagging, multi-row, dedupe no-repost, mixed light/heavy dir isolation, verdict exclusions, empty-sample exit 3, sub-bound must-pass, shrink-set single comment).
- [ ] AC6: `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` each gain the `scripts/watch-shard-balance-11564` row via `--incremental --write` (src=floor), and `bash plugins/soleur/test/scripts-shard-manifest.test.sh` passes (keys parity).
- [ ] AC7: `scripts/required-checks.txt` is byte-identical and `.github/workflows/ci.yml` is untouched — the watch is advisory and adds no required check.
- [ ] AC8: `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` gains a shard-balance-watch section: cadence, tracker lifecycle, the `--timings-dir` regen recipe for push-elided shard jobs, and the retirement pointer.
- [ ] AC9: `plugins/soleur/test/regenerate-shard-manifest.test.sh` contains cases pinning the `--drift-report` emission contract (row shapes, floor-vs-measured discrimination, light/heavy artifact filtering, refusal arms).
- [ ] AC10: A follow-up issue is filed for the required-ratchet promotion with re-evaluation criteria (advisory soak period + zero false-positive weeks).

## Test Scenarios

- Given a fixture durations table with a `src=floor` row and fixture timing dirs where that label measures 25 min, when `--drift-report` runs, then a `DRIFT_ROW` line carries `committed_ms=1222` and the fresh median — `unit`.
- Given two over-bound floor rows in one fixture set, when the watch script thresholds, then both appear in the findings set — `unit`.
- Given a mixed download dir containing `suite-timings-scripts-heavy-0`, when `--drift-report` computes `LEG_OBSERVED light`, then heavy labels contribute nothing — `unit`.
- Given fixture timing rows with `skip=`/FAIL/KILLED/TRIPWIRE verdicts, when medians are computed, then excluded rows never enter the sample — `unit`.
- Given an identical flagged set on a second run, when the sentinel matches, then no comment posts — `unit`.
- Given an empty flagged set while a tracker is open, when the watch runs, then it posts the resolution comment and closes the tracker — `unit`.
- Given zero timing artifacts in all sampled dirs, when the watch runs, then exit 3 and no green all-clear — `unit`.
- Given the real repo state at merge, when the first scheduled run executes, then it produces either an all-clear no-op or a tracker comment listing only genuinely over-bound rows — `e2e` (post-merge verification via `gh workflow run ... -f dry_run=true`; `pyramid-justified: exercises the live gh API + artifact download + tracker lifecycle end to end`).

## Success Metrics

- First scheduled/dispatched run completes green; `--dry-run` output enumerates ≥3 merge_group runs with timing artifacts.
- Baseline at ship: zero `src=floor` rows flagged ≥300 s (verified against the live 97-row floor set).
- A synthetic over-bound fixture is flagged in test and in a dispatch dry-run.
- The drift tracker exists iff a real finding exists (close-on-clear verified in fixtures).

## Dependencies & Risks

- **Artifact retention (14 d):** 5 green merge_group runs accrue within ~a day at current merge cadence; a quiet period degrades gracefully (WARN + smaller sample, `allow_empty`-style). Zero artifacts → exit 3, never a false all-clear.
- **Download budget:** ~11 artifacts/run × 5 runs ≈ 55 zip downloads per sweep — bounded and weekly; `timeout-minutes: 15` sized against it.
- **Uncalibrated bounds:** 300 s / 1.30 are deliberately conservative; the informational `FLOOR_UNMEASURED` count plus `--dry-run` output give the data a future re-calibration needs.
- **`push`-event blindness is by design:** the watch measures merge_queue (as-merged) cost, matching how the manifests are priced post-Lever-A; PR-event inflation is a separate lever already tracked.
- **Token surface:** `issues: write` on a scheduled workflow — writes confined to the watch-owned tracker (create/comment/close); no repo mutation, no secrets.

## Open Code-Review Overlap

One open `code-review` issue touches a planned file:

- `#7942` — "Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate" names `scripts/test-all.sh`. **Disposition: acknowledge** — this plan adds a `run_suite` registration but no `.mutation.sh` battery; different concern, no fold-in.

No other open code-review issue body names `scripts/regenerate-shard-manifest.py`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, `.github/workflows/ci.yml`, or the sharding runbook.

## Deferrals

- **Required-ratchet promotion** of drift findings into a blocking check — issue filed at implementation with re-evaluation criteria (advisory soak of ≥4 weekly runs, zero false-positive flags, bounds holding against at least one genuine drift event or deliberate fixture).
- **Sampling widened to `pull_request` runs + infra-group leg balance** — deferred; re-evaluate if merge_group sampling proves thin (e.g. merge cadence drops) or the infra group develops floor-row churn.

## References & Research

- Issue #11564 (open, `priority/p3-low`, `type/feature`, `domain/engineering`, `meta/machinery`, milestone 6); epic #11556 (open) — checkpoint comment of 2026-10-31 carries the post-reprice baseline (worst leg 37.5 min vs 30.3 min bound; shard sum 242.1).
- Brainstorm: `knowledge-base/project/brainstorms/archive/20261030-170617-2026-10-29-required-check-time-brainstorm.md` (D10 productize candidate = this work; CLO invariants and out-of-scope list).
- Convention sources: `.github/workflows/registration-narrowing-watch.yml`, `.github/workflows/code-quality-followups-watch.yml`, `scripts/watch-registration-narrowing-9564.sh`, `scripts/lib/watch-notify-once.sh`, `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
- Generator authority: `scripts/regenerate-shard-manifest.py` (`fetch_timings_from_dir`, `aggregate_runs`, `read_durations`, `read_incumbent`, `read_ci_leg_count`, `LIGHT_ARTIFACT`/`HEAVY_ARTIFACT`/`INFRA_ARTIFACT`).
- Related open levers: #11647 (arm debt), #11648 (fast-tier labels over the 10 s cap).
- Learning: `knowledge-base/project/learnings/2026-10-29-decompose-ci-leg-wallclock-from-suite-timings-before-attributing-overhead.md`.
