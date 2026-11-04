---
title: "chore(tests): measure the local affected gate and re-price its slow edge-selected suites"
date: 2026-11-04
slug: affected-gate-measure-and-reprice
branch: feat-one-shot-12013-12025-affected-gate-reprice
issue: 12013
closes: decided by the Closing Rules at ship time (#12013 and #12025 close only when their acceptance is met by recorded data)
type: chore
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# chore(tests): measure the local affected gate and re-price its slow edge-selected suites

## Overview

The parallel pool for the local `--affected` gate (width 4, `plugins/soleur/scripts/affected-tests.sh`) and the
live provisional-red line (`[run] <label> done (rc=N, <ms>ms) - provisional, verdict at drain`) are merged
(commit 377f8e3484, PR #12014). Two tracked items remain, and they are one decision chain:

1. **#12013** needs a measurement: does a typical single-feature PR now finish the local gate in under 10 minutes
   on a loaded machine, is a red reported live, and are per-suite timings kept for every suite?
2. **#12025** (deferred from #12013) re-prices the seven slow edge-selected suites from a measured selection rate
   and records the measured weights for `image-cve-verdict` and `destroy-ask-mutation`. Its own start condition is
   "only if the measured parallel run is still over 10 minutes".

So the work is measurement-first. This PR builds one small read-only measurement tool, takes the #12013 reading on
a real affected gate **before any edit to `scripts/lib/test-affected-paths.sh`**, records a disposition for every
suite in a pricing ledger, and edits the lib only if the measured data says it must (a conditional, final,
single commit). The PR closes an issue only when that issue's acceptance is met by recorded data.

Draft PR: #12103. Prior plan (archived): `knowledge-base/project/plans/archive/20261103-233632-2026-11-03-chore-local-test-gate-enable-pool-and-live-red-plan.md`.

## Research Reconciliation - Spec vs. Codebase

| Claim (brief, #12013, #12025, archived plan) | Reality (verified on this branch, `main` at 75353c511e) | Plan response |
|---|---|---|
| `image-cve-verdict` is always-on at ~57 s with an unmeasured-floor weight; an honest weight breaks the fast tier's committed-weight cap, so pricing it means demoting it | False. Only `scripts/image-cve-verdict-consumers` is in `ALWAYS_ON_SUITES` (the lib comment says "so the ~75 s verdict suite stays edge-selected"; `scripts/always-on-justifications.tsv` has only the `-consumers` row). `scripts/image-cve-verdict` has derived edges and a 1223 ms `src=floor` row in `scripts/suite-durations.tsv`. The 10 s / 300 s caps in `scripts/test-all-fast-tier-budget.test.sh` bind always-on labels only | No demotion. Weight goes in the pricing ledger. The floor row is a CI shard-balancing defect, tracked as #12106. State the correction in the ledger and on #12025 (UC-2); a grep of `knowledge-base/engineering/` finds no ADR or runbook sentence repeating it |
| `destroy-ask-mutation` has no weight row because the webplat shard has no duration table | Confirmed: registered in `want_webplat` (`run_suite "apps/web-platform/test/destroy-ask-mutation"`); durations tables exist for light, heavy and infra only. It has derived edges and no declared `AFFECTED_*` array, so there is no array to narrow | Ledger row only; priced-and-kept (nothing nameable to narrow) unless the rate data shows otherwise |
| `scripts/ci-battery-gate-replay.sh` cannot be reused | True for edge selection (it replays the `--pr-gated` arrays only). But `scripts/ci-pr-affected-replay.py` already holds the machinery: `glob_units` (pinned base, last N first-parent commits, classified), `glob_selector_rows` (one selector run gives every suite's edges), `glob_existing_hit`, `glob_spot_check`, and a `glob-rate` subcommand that models a CANDIDATE edge set offline. `collect` keeps only the skipped set and does per-commit `gh api` work | Add a thin read-only `suite-rate` built on those helpers (existing rate of every suite, one selector run); reuse `glob-rate` itself to evaluate narrowing candidates in Phase 5 (CTO ruling, Selection-rate tooling; plan review, Kieran P1) |
| The pool alone may reach 10 minutes | Unknown, and one reading is alarming: a COLD `--print-selection` in a fresh worktree took 6m06s under load 10-19 (docs-only path list: `AFFECTED_SUMMARY selected=118 of=730 always_on=116 edge=2`). The derive cache (`.soleur/cache/affected-derive/`) is per worktree, so every fresh one-shot worktree pays it | Measure cold derive, warm derive and suite run separately; judge the 10-minute bar on cold (CTO ruling). If derive dominates, file a follow-up (Phase 6) |
| Edge re-pricing and `demoted` are both available outcomes (#12025 text) | `demoted` to CI-only or ADR-262 pr-gated removes a suite from the locally selected set for a diff touching its subject files, which #12025's own constraint forbids | `demoted` is recorded once as "not available, constraint"; outcomes are `narrowed` or `priced-and-kept` |
| The PR can measure its own gate | No. Any diff touching `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` degrades `--affected` to the full battery (`AFFECTED_FALLBACK reason=runner-changed`) unless it is registration-only. #12014 hit exactly this and could not measure | Take the measurement from a throwaway worktree with the lib untouched, and make the lib edit a conditional final commit (UC-1) |
| New measurement tests can be added to `plugins/soleur/test/ci-pr-affected-replay.test.sh` | That file is rows-split: three `run_suite` arms in `scripts/test-all.sh` with `--rows 1-193/194-386/387-596`, a `DECLARED_TOTAL` census inside it, and `plugins/soleur/test/scripts-shard-totality.test.sh` asserting the tiling. New rows force a runner edit and a re-split | New sibling test file (CTO ruling, test location) |
| Weight rows can be produced by the generator | `regenerate-shard-manifest.py --incremental` never stamps measurements; a measured row needs CI timing artifacts; a hand edit contradicts the generated table and its `growth-acked` stamp | Pricing ledger in the ADR-242 amendment (CTO ruling, weight rows); #12106 tracks the CI-timings regen |
| S4 affected-only PR runs make a narrowing consequential beyond the local gate | S4 is NO-GO and inactive (`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`); `merge_group` stays the full-battery authority (ADR-276) | Local gate only today; the never-lose-a-selection constraint also protects S4 if it activates later |

## Research Insights

- **Premise validation (Phase 0.6).** Cited and checked: #12013 (open, p3, meta/machinery), #12025 (open), #12014 (merged as 377f8e3484), PR #12103 (this branch's draft), ADR-133, ADR-177, ADR-183, ADR-196, ADR-242 (amendment of 2026-11-03), ADR-262, ADR-276, PR #11779 (commit 0bc2634a40: 16 files, +1309/-56, lib +640 lines, 8 labels left `ALWAYS_ON_SUITES`, 7 `AFFECTED_*` arrays added, baselines and justification rows touched, `suite-durations.tsv` untouched). All hold; the stale premise is the always-on claim above. Collision pre-check: no other open PR names #12013 or #12025; foreign worktrees have live `test-all.sh` processes (sibling test runs, not duplicate work) and will be present during measurement, which is the "loaded machine" condition.
- **ADR corpus check (Phase 0.6 item 4).** The mechanisms named (narrow edges by selection rate, demote) were checked against ADR-242 (decisions 18 and 20, always-on ratchets), ADR-262 (CI-only demotion of five batteries) and ADR-276 (local-first policy; point 6 "push before local" dropped). None rejects measured narrowing; ADR-262-style demotion is excluded here only by #12025's own constraint.
- **Property List.** P1: the #12013 acceptance is decided by a reproducible reading of the local gate on representative single-feature diffs under load, with cold derive, warm derive, queue wait and suite-run time separated. P2: a red is observed live (suite name and wall time) in a real run. P3: per-suite timings exist for every selected suite, passing or failing. P4: every slow edge-selected suite has a recorded disposition driven by a measured selection rate and local wall time. P5: `image-cve-verdict` and `destroy-ask-mutation` have recorded measured weights. P6: no narrowing removes a suite from the set a subject-file diff selects, and the legal-register lints are untouched.
- **Cut List.** Result cache (rejected twice; `scripts/lib/test-affected-derive-cache.sh` header). Demotion to CI-only (constraint). Hand-editing `suite-durations*.tsv` (CTO ruling). A new standalone replay script, and a per-commit selector loop (`glob_units` + one selector run replace 100 selector runs). Reusing `ci-battery-gate-replay.sh` (wrong arrays). Rows in the split replay test (runner edit). Push-before-local and an unconditional CI-only skip (ADR-276, ADR-196, ADR-183; already dropped on #12013). A shared or seeded derive cache across worktrees (out of scope; Phase 6 files a tracker only if the measurement shows derive dominates).
- **Value measurement (Phase 0.6c).** The saving is a forecast until Phase 2 and Phase 3 measure it. Commands that produce the numbers: `python3 -I scripts/ci-pr-affected-replay.py suite-rate` (selection rate), `AFFECTED_SUMMARY`/`suite-timings.tsv` from `plugins/soleur/scripts/affected-tests.sh` (gate time), `time bash scripts/test-all.sh --print-selection --paths=<docs-only path>` in a fresh worktree (cold derive: 6m06s on 2026-11-04, load average 10-19, 16 cores). Price any narrowing in **suite-seconds saved minus the derive cost it adds**: the #9307 demotion priced 31 s of savings and missed an 84 s derive it added.
- **Learnings applied.** `2026-11-01-fast-tier-demotion-edge-audit-blast-radius.md` (hidden reads via fragmented literals are invisible to derive and audit; read the SUT); `2026-11-03-verdict-input-edges-and-the-442-pair-myth.md` (`glob:**.gitignore` under-covers, `glob:**/.gitignore` is malformed; re-derive a premise from the mechanism); `2026-10-09-committed-ci-weights-are-not-local-costs.md` (committed weights are CI-leg numbers, 2-3x off local; cap measured on the paying machine); `2026-10-26-a-verdict-tool-needs-positive-proof-inputs-and-a-mandatory-cross-check.md` (a rate verdict needs positive coverage proof and a mandatory per-candidate spot check); `2026-10-22-a-hop-regex-was-quadratic-on-one-long-token-and-my-own-stale-runs-held-the-test-queue.md` (kill your own runs before timing); `workflow-issues/2026-10-20-a-queued-gate-is-not-a-verdict-and-a-name-matcher-cannot-find-a-wrapper-run-process.md` (`AFFECTED_GATE_BUDGET_DEFERRED` after a queue wait is a deferral, not a reading); `2026-11-03-a-slow-gate-issue-measured-an-opt-in-feature-nobody-had-enabled.md` (assert `AFFECTED_SUMMARY` and the `[parallel] mode engaged - width=4` banner in every reading); `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-and-a-glob-registered-suite-degrades-the-affected-gate.md` (an edge declared for a glob-registered suite is INDEX-UNBOUND and degrades to full; stubs must pin the real shape); `2026-10-11-a-runner-arm-above-the-splice-window-fires-inside-every-sibling-sandbox.md` (`TEST_TIMING_LOG` arm; opt out with `/dev/null`, not an empty string).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "measure the local affected-gate wall time now that the parallel pool is merged" [brief, issue #12013] | Phase 3 | mapped |
| 2 | "under 10 minutes on a loaded machine" [issue #12013 acceptance] | Phase 3.6 (verdict), AC1 | mapped |
| 3 | "red reported live" [brief, issue #12013 acceptance] | Phase 3.4 (induced-red run), AC2 | mapped |
| 4 | "per-suite timings for every suite" [brief, issue #12013 acceptance] | Phase 3.5, AC3 | mapped |
| 5 | "re-price the slow edge-selected suites in scripts/lib/test-affected-paths.sh from a purpose-built selection-rate loop over the last ~100 first-parent commits" [brief, issue #12025] | Phase 1 (tool), Phase 2 (loop), Phase 4.3 (rule), Phase 5 (conditional edit) | mapped |
| 6 | "record each suite as narrowed/demoted/priced-and-kept" [brief, issue #12025] | Phase 4.4 ledger, Phase 6.1 ADR amendment | mapped (`demoted` recorded once as not available, constraint) |
| 7 | "include the measured weights for image-cve-verdict and destroy-ask-mutation" [brief, issue #12025] | Phase 4.1 and 4.4 ledger rows | mapped |
| 8 | "never remove a suite from the set selected by a diff touching its subject files" [brief, issue #12025] | Phase 5.3 before/after check, AC8 | mapped |
| 9 | "never skip the legal-register lints" [brief, issue #12025] | AC7, Phase 5.1 exclusion | mapped |
| 10 | "Close both issues in the PR body only if their acceptance is actually met; otherwise reference them and leave the remainder tracked" [brief] | Closing Rules, Phase 6.4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `suite-rate` subcommand in `scripts/ci-pr-affected-replay.py` | "from a purpose-built selection-rate loop over the last ~100 first-parent commits" | asked |
| New sibling test file for the subcommand | "purpose-built selection-rate loop" (a tool needs a test; repo ratchets require registration) | asked |
| Measurement throwaway worktree and replayed diffs | "measure the local affected-gate wall time" | asked |
| Pricing ledger in the ADR-242 amendment | "include the measured weights for image-cve-verdict and destroy-ask-mutation" | asked |
| Follow-up issue #12106 (CI-timings regen) | "otherwise reference them and leave the remainder tracked" | asked |
| Conditional follow-up for a derive-cache cold start | "otherwise reference them and leave the remainder tracked" | asked (conditional on the measurement) |
| Conditional lib edit | "narrow or demote edge arrays ... where a suite's verdict depends on a nameable path set" [issue #12025] | asked |

### Split Assessment

- Subsystems touched: 3 - `scripts/` (tool, lib if triggered), `plugins/soleur/test/` (new test), `knowledge-base/` (ADR, runbook, measurements)
- Planned files: about 10 | Estimated changed lines: about 600 without the conditional lib edit, up to about 900 with it
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, measurement-first. The CTO preferred two PRs; the conditional final commit is the stated fallback and the lib edit is the only part that could push the diff past the line threshold (UC-1).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. A wrong narrowing would let a regression pass the local gate; it then surfaces as a red required `test` check in the merge queue (ADR-276: `merge_group` runs the full battery), costing operator time and a re-run, not a silent merge.
- **If this leaks, the user's workflow is exposed via:** no data or credential exposure. The committed artifacts are suite labels, millisecond timings and commit SHAs. Raw timing logs must not contain paths outside the repo or environment values (checked in Phase 6).
- **Brand-survival threshold:** aggregate pattern
- **Threshold decision (challengeable):** aggregate pattern rather than single-user incident, because no user data or contract is touched and CI's full-battery merge authority bounds a local miss to a red check. #12014 carried single-user incident because it changed the runner's scheduling; this PR changes no runner code unless the conditional commit fires, and that commit is gated by the never-lose-a-selection check.

## Open Code-Review Overlap

- #7942 (mutation batteries named `*.mutation.sh` that run in no gate) touches `scripts/test-all.sh`. **Acknowledge:** different concern (suite naming), own cycle; this plan does not edit `scripts/test-all.sh`. No open code-review issue names `scripts/ci-pr-affected-replay.py`, `scripts/lib/test-affected-paths.sh`, ADR-242, the parallel-mode runbook or `scripts/suite-durations.tsv`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO (spawned during planning, 2026-11-04, five technical rulings plus two follow-ups, recorded as rows in `knowledge-base/project/specs/feat-one-shot-12013-12025-affected-gate-reprice/decision-challenges.md`): measure on a throwaway worktree with the lib untouched and judge on cold derive; no demotion; narrow only where rate x wall >= 5 s per PR and the verdict-input set is nameable; weights in a ledger, not the generated tables; extend `ci-pr-affected-replay.py` with `suite-rate`; new sibling test file; prefer two PRs (kept as one, UC-1). No Product, Legal, Marketing, Finance, Operations, Sales or Support implication: internal test tooling, no UI surface (no Product/UX Gate), no personal data (no GDPR gate), and the legal-register lints are only protected, never edited.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-242 (`knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`) with a dated amendment for #12013 / #12025: the decision rule (cost = selection rate x standalone wall; 5 s per PR attempt threshold; narrowing criteria; `demoted` not available because of the never-lose-a-selection constraint), the measurement table, the pricing ledger (one row per suite plus the two `local-measured` weights; raw rows live in `measurements/`) and the one-line correction that only `scripts/image-cve-verdict-consumers` is always-on. No new ADR: this extends a decision ADR-242 owns. No runbook edit: the script docstring and the header carry the how-to, and a second re-pricing is the trigger to add one. This is a Phase 6 task, not a follow-up.

### C4 views

No C4 impact. Checked by reading `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4` and `spec.c4` (a grep of the three for `test-all`, `suite`, `affected`, `battery` found only unrelated prose): external human actors added or changed - none; external systems or vendors - none (the tool makes no network calls; GitHub Actions and the required `test` check are already modeled and unchanged); containers or data stores - none (a TSV table in the spec directory and an ADR table are not modeled stores); actor-to-surface access relationships - none. The derived cardinalities `model.c4` embeds in edge prose are unaffected (no workflow, monitor or heartbeat added); `bash plugins/soleur/test/c4-count-parity.test.sh` passed on this branch at plan time.

### Sequencing

Authored in this PR.

## Observability

Not triggered: no file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` or `plugins/*/scripts/` is edited and no infrastructure surface is added. The tool is an operator-run local script whose header is its signal and whose non-zero exit is its alert; the discoverability check below is credential-free.

```yaml
discoverability_test:
  command: python3 -I scripts/ci-pr-affected-replay.py suite-rate --help
  expected_output: "suite-rate"
```

## Implementation Phases

The order is load-bearing: Phases 1-4 never touch `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh`, so the PR keeps a bounded affected gate while it measures. Only Phase 5 can edit the lib, it is gated by arithmetic, and it is the last code commit.

### Phase 0 - Preconditions (record, do not assert)

Record `git rev-parse origin/main` (pinned as `BASE_SHA` for every later step; never a moving ref), `uptime`, and the sibling runner count (`ps -eo pid,cmd | grep -c '[t]est-all.sh'`). Kill this session's own stale `test-all.sh` runs first. Confirm the current diff selects with a bounded gate: `bash scripts/test-all.sh --print-selection` prints `AFFECTED_SUMMARY ... fallback=none` (re-check once at the end of Phase 1).

### Phase 1 - The `suite-rate` subcommand (tests first, FR1, TR1)

The subcommand is thin because `ci-pr-affected-replay.py` already holds the machinery for `glob-rate` (S4 PR5, #10861): `glob_units` (pinned base sha, last N first-parent commits, each classified `attributable | runner | not_evaluable | empty` via `commit_files` and `evaluable`), `glob_selector_rows` (ONE `--print-selection --paths=README.md` run gives every suite's class and edge set), `glob_existing_hit` (the selection bit of a row for a diff) and `glob_spot_check` (the real selector on evenly spaced commits must agree with the model, else exit 4). `suite-rate` reuses them to report the **existing** selection rate of every suite. It models selection offline from the selector's own edge column, so the 100-commit loop costs one selector run plus the spot-check, not 100 selector runs. The standing limit (today's edges applied to older diffs; survivors only) is the script's own and is stamped in the header.

1.1 **Failing test first** (`cq-write-failing-tests-before`): new `plugins/soleur/test/ci-pr-affected-suite-rate.test.sh`, self-contained: a throwaway git repo with at least six first-parent commits, a selector stub reached through `PR_AFFECTED_REPLAY_TEST_ALL` that prints the **real five-column** `AFFECTED_SELECTED` shape (label, selected, class, edges; copy the shape from `scripts/test-all.sh`'s `AFFECTED_SELECTED` printf so the stub cannot drift), and a `gh` stub on `PATH` that fails the test if invoked. No cold derive. Rows:
   - R1 rate and denominator: a suite hit by 3 of 8 attributable commits reports 3, 8 and 37.5 percent; an `always_on` suite is flagged and reported as 100 percent by definition, never as a measured rate;
   - R2 a `runner` commit and a `not_evaluable` commit (comma path, non-printable byte, list over the limit) are counted in their own columns and excluded from the denominator;
   - R3 a selector failure on the spot-check commit exits non-zero (never "selected nothing"); zero attributable commits exits 1;
   - R4 the header carries the window, `BASE_SHA`, the lib sha (asserted equal to `git rev-parse BASE_SHA:scripts/lib/test-affected-paths.sh` in the fixture, so a wrong stamp is red) and the current-edges caveat; the run writes only under `--out`; the `gh` stub was never called.
   Mutations (each must turn exactly its row red): drop the runner/not-evaluable exclusion (R2); count `always_on` as measured (R1); swallow the spot-check error (R3); stamp a wrong lib sha (R4). Harness row: one must-PASS fixture differing from the canonical in a permitted way (different commit count, a suite absent from some commits).
1.2 Implement `cmd_suite_rate` in `scripts/ci-pr-affected-replay.py` as a loop over `glob_units` + `glob_selector_rows` + `glob_existing_hit` + `glob_spot_check` (default `--spot-check 5`; a verdict is not accepted until the model agrees with the real selector). Arguments: `--commits N` (default 100), `--base REF` (resolved to a sha and stamped), `--out DIR`, `--list FILE` (saved selector rows, as `glob-rate` takes). Outputs under `--out`: `suite-rate.tsv` (label, class, hits, attributable, rate), `commits.tsv` (sha, subject, kind, files_n, modelled selected_n) and the header. Update the script's docstring subcommand list. `collect`, `select()` and `cmd_glob_rate` stay untouched.
1.3 Registration: the test is glob-registered under `plugins/soleur/test/`. Run `python3 scripts/regenerate-shard-manifest.py --incremental --write` now (a deferred regen is a merge blocker) and verify `bash scripts/test-all.sh --print-affected-set | grep ci-pr-affected-suite-rate` reports `derived`. If it reports UNCLASSIFIED or INDEX-UNBOUND, move the file to `scripts/ci-pr-affected-suite-rate.test.sh` (CTO fallback) and re-check; never add rows to the rows-split `ci-pr-affected-replay.test.sh`. If it still cannot classify, stop and fix the classification; the only remaining route is to move Phase 1 into the Phase 5 PR, in which case Phase 2 uses `glob-rate` with a hand-written candidate file and the PR records that. Then run `bash scripts/lint-orphan-test-suites.sh` and the existing `ci-pr-affected-replay.test.sh` arms (unchanged).

### Phase 2 - Selection rates (FR1, FR4)

2.1 `python3 -I scripts/ci-pr-affected-replay.py suite-rate --commits 100 --base <BASE_SHA> --out <scratch>/suite-rate`. The one selector run is a cold derive on a fresh worktree (6m06s in the planning-time reading); record the elapsed time and whether the derive cache was warm. Run it in the background and watch it with `Monitor`.
2.2 Keep the evaluated denominator and the `runner` / `not_evaluable` / `empty` counts in the header. Runner-changed commits run the full battery in real life; report them separately as part of the "typical PR" picture. Copy `suite-rate.tsv` and `commits.tsv` into `knowledge-base/project/specs/feat-one-shot-12013-12025-affected-gate-reprice/measurements/`.
2.3 Expectation, stated up front: `argv-bearer-sweep` (47 s committed) and `scratch-residue` (26 s) need a rate of roughly 10 percent or more to clear the 5 s rule, and several of the seven carry whole-tree prefixes, so the most likely outcome is mostly `priced-and-kept`. That is a valid result, not a failure.

### Phase 3 - Measure the local gate (#12013, FR2, FR3, FR5)

3.1 **Choose the diffs by rule.** From `commits.tsv` (pinned `BASE_SHA`), restrict to the 30 most recent `attributable` first-parent commits that do not touch `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh`. Classify by top-level path into web-platform, plugins/soleur, and mixed or docs-adjacent. Pick one commit per class nearest that class's median modelled `selected_n`, with the web-platform class contributing a second pick nearest its upper quartile (index `ceil(0.75*n)-1` of the sorted counts); ties break to the lowest SHA. At least three diffs.
3.2 **Throwaway worktree, lib untouched.** `git worktree add --detach .worktrees/measure-affected-gate-<epoch> <BASE_SHA>` (fresh derive cache). Apply each pick as working-tree changes only, nothing committed (`git diff <sha>^1 <sha> | git apply --3way`, then `git status --short`). Check the replay is faithful: the gate's `AFFECTED_SUMMARY selected=` must equal that commit's modelled `selected_n` from `commits.tsv`; a mismatch is recorded and that pick is replaced by the next candidate by the same rule.
3.3 **Synthetic load, then the reading.** The loaded-machine condition must not depend on what sibling sessions happen to run. Start `nproc/2` CPU burners (for example 8 loops of `timeout 3600 sh -c 'while :; do :; done'`) before each reading, kill them in a `trap`, and record the burner count together with the ambient `uptime` at start and end. For each pick run `bash plugins/soleur/scripts/affected-tests.sh` with stderr timestamped per line (`while IFS= read -r l; do printf '%s %s\n' "$(date +%s.%N)" "$l"; done`). From the same run record the `[parallel] mode engaged - width=4` banner, `AFFECTED_SUMMARY`, the lock-queue wait (the `tc_acquire` lines), cold derive time (time before the first `[run] ... started`) and the per-suite timings. Locate `suite-timings.tsv` from the `[note] weight-drift: timing log at <path>` line (a per-run directory under `${SOLEUR_TEST_ALL_LOG_DIR:-/var/tmp/soleur-test-all-logs}`); never set `TEST_TIMING_LOG` empty. A reading that lacks the banner, shows a fallback, or ends in `AFFECTED_GATE_BUDGET_DEFERRED` is a deferral and is rerun.
   - **Cold:** the first run in the fresh worktree. Cold gate time = cold derive + warm run, validated by that first actual run. **Warm:** one rerun on the median pick only.
   - **Serial pair:** one run with `SOLEUR_TEST_JOBS=1` on the median pick only, time-boxed at 40 minutes (a stop at the box is itself the datum).
3.4 **Induced red, inside a reading.** In the web-platform pick's worktree make one small selected suite fail (edit its `.test.sh` to exit 1 early). Choose that suite by rule: the first-scheduled small suite, so other suites are provably still running. Assert from the timestamped log: its `[run] <label> done (rc=1, <N>ms) - provisional, verdict at drain` line has at least one `[run] ... started` line before it and at least one `[run] ... done` line after it, exactly one `[FAIL]` verdict follows at drain, and the exit code is non-zero. Revert the edit.
3.5 **Per-suite timing completeness.** For each run, count `suite-timings.tsv` rows whose third column does not start with `skip=` and compare with the `AFFECTED_SUMMARY` selected count; passing and failing rows must both appear in the induced-red run. Copy the logs to `measurements/gate-run-<n>.tsv`.
3.6 **Verdict by rule.** Median cold gate time over the burner-loaded readings. Under 600 s: #12013's time acceptance is met. At or over 600 s: not met, and the Phase 5 arithmetic gate is evaluated. If cold derive is 25 percent or more of the cold gate time, file the derive-cache tracker (Phase 6.4) regardless of the verdict.
3.7 Remove the throwaway worktree (`git worktree remove --force`), kill the burners and any leftover runs, and confirm no `test-all.sh` process of this session remains.

### Phase 4 - Weights, wall times and ledger (#12025, FR4, FR5)

4.1 **Unconditional:** the two asked-for weights. For `scripts/image-cve-verdict` and `apps/web-platform/test/destroy-ask-mutation`, run the registered command (`bash scripts/test-all.sh --enumerate-commands` gives each label's argv) three times standalone and take the median, with machine, load1 and date. `destroy-ask-mutation` needs the web-platform dependencies; if it cannot run in the environment record "unmeasured: <reason>" and leave that row tracked rather than inventing a number.
4.2 **Wall for the rule.** The 5 s rule uses the standalone median wall, so it is reproducible. Pool-contended timings from Phase 3 are recorded alongside for information. If Phase 3.6 says the bar is met, the other six suites take the Phase 3 row where selected, else their committed CI weight explicitly tagged `ci-committed` (2-3x off local, per the weights learning), and their disposition is `priced-and-kept (trigger not met)` without further runs. If the bar is not met, measure the six standalone once (the slowest are 244, 218 and 154 s, so this is the costly step).
4.3 **Apply the rule.** Expected cost per PR = rate x wall (runner commits reported separately). Attempt a narrowing only if cost >= 5 s per PR and the verdict-input set is nameable (evidence: the suite's own source plus `bash scripts/audit-suite-reads.sh record --mode check --only <label>`, not the current edge array). Whole-tree-population suites (`scripts/lint-shell-trace-credential-refusal`: every `*.sh`; `scripts/lint-orphan-test-suites` and `scripts/guard-vacuity-floor`: `git ls-files '*.test.sh'`) are priced-and-kept. `apps/web-platform/test/destroy-ask-mutation` has no declared array and is priced-and-kept unless a nameable subject set exists. `tests/scripts/argv-bearer-sweep`, `scripts/test-affected-kb-consumers` and `tests/scripts/scratch-residue` are the plausible candidates; this is a hypothesis for the data to falsify. A suite whose rate could not be derived is priced-and-kept with the rate flagged `unverified`.
4.4 **Pricing ledger** (goes in the ADR-242 amendment; raw rows in `measurements/`): one row per suite, using full registered labels (`tests/scripts/argv-bearer-sweep`, `apps/web-platform/test/destroy-ask-mutation`, `scripts/lint-shell-trace-credential-refusal`, `scripts/test-affected-kb-consumers`, `scripts/lint-orphan-test-suites`, `scripts/guard-vacuity-floor`, `tests/scripts/scratch-residue`, `scripts/image-cve-verdict`) - disposition (`narrowed`, `priced-and-kept`; `demoted`: not available, constraint, stated once), rate, wall and its source tag, expected cost per PR, committed CI weight for comparison, evidence; for `image-cve-verdict` and `destroy-ask-mutation` the `local-measured` weight. State once: only `scripts/image-cve-verdict-consumers` is always-on.

### Phase 5 - Conditional lib edit (arithmetic gate)

Fires only if **both** hold: Phase 3.6 says not met, and the summed upper-bound saving of the narrowing-eligible suites (their expected cost per PR, from 4.3) is at least the gap `median cold gate time - 600 s`. If narrowing cannot close the gap (for example when cold derive is most of the time), skip the phase, record why, and file the next-lever tracker through the #12013 comment. If it fires and the estimated diff exceeds 800 lines, split it into a second PR (the CTO's preference) and this PR references #12025.

5.1 One edit of `scripts/lib/test-affected-paths.sh` for all narrowings. Never touch `lint-legal-registers-unit`, `lint-legal-registers-live`, `check-pa-22-unit`, `check-pa-22-live`.
5.2 Per candidate, read the SUT first (hidden reads through fragmented literals defeat the derive and the audit). Evaluate the proposed globs with the **existing** `ci-pr-affected-replay.py glob-rate --candidates <file>` (it already models a candidate edge set against the last N commits, has the mandatory spot-check and refuses malformed heads) before editing the lib. Narrow only to a form the matcher parses (`glob:<root>/**.<ext>` with a root).
5.3 **Never-lose-a-selection check:** over the suite's whole subject population (`git ls-files` for its extensions plus the extensionless shebang scripts it scans), compare `bash scripts/test-all.sh --print-selection --paths=<file>` before and after, in batches (a path list per call, not one call per file), and show zero lost selections for that suite's row. Save the diff under `measurements/`. Then: pair-audit ratchets green with no new accept row (`scripts/ci-pr-affected-audit.baseline.tsv`, `scripts/ci-pr-affected-audit.accept.tsv`), `scripts/test-all-affected.test.sh`, `scripts/test-affected-derive.test.sh`, `scripts/test-affected-kb-consumers.test.sh` against its baseline, `scripts/test-all-corpus-weight-budget.test.sh`.
5.4 Gate for this commit: its local `--affected` is the full battery by construction and a sibling full run refuses it (`rc=4`, ADR-196). Substitute: `git add <files> && bash scripts/test-all.sh --affected --affected-scope=staged`, the suites in 5.3, and CI's required `test` check with the `merge_group` full battery as authority. State this in the PR test plan.

### Phase 6 - Record and close the loop

6.1 ADR-242 amendment (see Architecture Decision): rule, "demoted not available", ledger, measurement table, the always-on correction.
6.2 Run markdownlint on the plan, `tasks.md` and every new markdown, and `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`.
6.3 Follow-ups: #12106 is filed (CI-timings regen). If derive is 25 percent or more of the cold gate, file "seed the affected-derive cache for fresh worktrees" (design constraint: the cache-memo rejection in the `scripts/lib/test-affected-derive-cache.sh` header; milestone from the roadmap; `Mandated-By: wg-when-deferring-a-capability-create-a`). The next lever for an unmet #12013 is recorded in a comment on #12013, not a new issue.
6.4 PR body per the Closing Rules. Post the measurement table and the ledger as comments on #12013 and #12025.

## Closing Rules

- `Closes #12013` only if the median cold gate time over burner-loaded readings is under 600 s AND AC2 (live red) and AC3 (timings) hold. Otherwise `Ref #12013` and it stays open with the next-lever comment.
- `Closes #12025` only if every one of the eight suites has a ledger row and both weights are recorded (a `destroy-ask-mutation` weight that is "unmeasured" keeps it `Ref`), and, when the Phase 5 gate fired, the narrowing landed in this PR or was ruled out with evidence. Otherwise `Ref #12025`.

Closing keywords go in the PR body only (`wg-use-closes-n-in-pr-body-not-title-to`), never the title.

## Files to Create

- `plugins/soleur/test/ci-pr-affected-suite-rate.test.sh` (or `scripts/ci-pr-affected-suite-rate.test.sh` under the CTO fallback)
- `knowledge-base/project/specs/feat-one-shot-12013-12025-affected-gate-reprice/measurements/` (`suite-rate.tsv`, `commits.tsv`, `gate-run-<n>.tsv`, the summary table; in Phase 5 the before/after selection diffs)
- `knowledge-base/project/specs/feat-one-shot-12013-12025-affected-gate-reprice/tasks.md`

## Files to Edit

- `scripts/ci-pr-affected-replay.py` (new `suite-rate` subcommand and docstring entry; `collect`, `select()` and `cmd_glob_rate` untouched)
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (only the incremental-regen delta for the new test label, never by hand)
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` (amendment)
- Conditional (Phase 5 only): `scripts/lib/test-affected-paths.sh`, and with it any of `scripts/ci-pr-affected-audit.baseline.tsv`, `scripts/always-on-justifications.tsv`, `scripts/test-affected-kb-consumers.baseline.txt` that a narrowing moves
- Pipeline-written files the allow-list AC permits: `knowledge-base/INDEX.md` if regenerated, `specs/feat-one-shot-12013-12025-affected-gate-reprice/session-state.md` and `decision-challenges.md`, the plan file

**Never edited:** `scripts/test-all.sh`, `scripts/suite-durations-heavy.tsv`, `scripts/suite-weight-exemptions.tsv`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, the parallel-mode runbook.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 (#12013 time, deterministic): the measurement table in the ADR-242 amendment lists at least three replayed diffs with selected count (equal to the modelled `selected_n`), cold derive time, warm run time, cold gate time, burner count, ambient `uptime` at start and end, queue wait, and the serial pair for the median diff; the verdict line states the median and applies the 600 s rule. Every table row comes from a run that printed the `[parallel] mode engaged - width=4` banner, has `fallback=none`, and did not end in `AFFECTED_GATE_BUDGET_DEFERRED`. (The load is synthetic and recorded, so the criterion does not depend on what sibling sessions run.)
- [ ] AC2 (#12013 live red): in the induced-red log the provisional `done (rc=1, <N>ms)` line has a `started` line of another suite before it and a `done` line of another suite after it, exactly one `[FAIL]` verdict follows at drain, and the exit code is non-zero.
- [ ] AC3 (#12013 timings): for every recorded run the count of `suite-timings.tsv` rows whose third column does not start with `skip=` equals the `AFFECTED_SUMMARY` selected count; passing and failing rows both appear in the induced-red run.
- [ ] AC4 (#12025 tool): `suite-rate` is read-only and network-free, its test file passes with the R1-R4 rows and the four mutations each red-then-green, `bash scripts/lint-orphan-test-suites.sh` lists the new test as registered, `--print-affected-set` reports it `derived`, and `plugins/soleur/test/ci-pr-affected-replay.test.sh` passes unchanged.
- [ ] AC5 (#12025 ledger): exactly one ledger row per full label in Phase 4.4 (checkable by exact match), each with disposition, rate, wall plus source tag, expected cost per PR and evidence; `scripts/image-cve-verdict` and `apps/web-platform/test/destroy-ask-mutation` carry `local-measured` weights (or "unmeasured: <reason>" for the latter); the always-on correction sentence is present.
- [ ] AC6 (diff allow-list): `git diff --name-only origin/main...HEAD` is a subset of the Files to Create / Files to Edit lists (merge-base form, not the moving tip). When Phase 5 did not fire this implies `scripts/lib/test-affected-paths.sh` and `scripts/test-all.sh` are untouched and `scripts/suite-durations.tsv` / `scripts/suite-shard-legs.tsv` show only added rows for the new test label.
- [ ] AC7 (legal lints, never skipped): `grep -c 'run_suite "scripts/check-pa-22' scripts/test-all.sh` prints 2, and `awk '/^ALWAYS_ON_SUITES=\(/,/^\)/' scripts/lib/test-affected-paths.sh | grep -c -e '"scripts/lint-legal-registers-unit"' -e '"scripts/lint-legal-registers-live"' -e '"scripts/check-pa-22-unit"' -e '"scripts/check-pa-22-live"'` prints 4.
- [ ] AC8 (only if Phase 5 fired): `measurements/` holds a before/after `--print-selection` diff per narrowed suite over its whole subject population with zero lost selections, the pair-audit ratchets are green with no new accept row, and the PR test plan states the full-battery-by-construction gate and its substitute.
- [ ] AC9: ADR-242 amendment written; `technical-ruling-gate.sh --branch` and markdownlint green; follow-ups filed per Phase 6.3; the PR body applies the Closing Rules.

### Post-merge (operator)

None. Every step is agent-runnable in the work phase; CI's required `test` check is the merge authority.

## Test Scenarios

- `suite-rate` over a fixture history: a suite hit by 3 of 8 attributable commits reports 3, 8, 37.5 percent; a runner commit moves its own column and not the denominator; an `always_on` suite is flagged 100 percent by definition.
- Zero attributable commits, or a spot-check selector failure: non-zero exit, never "selected nothing".
- Header lib sha differs from `git rev-parse BASE_SHA:scripts/lib/test-affected-paths.sh`: the test is red.
- Gate on a replayed web-platform diff under burners: banner present, `fallback=none`, `selected` equals the modelled count, timing rows equal the selected count.
- Induced red: another suite starts before and finishes after the provisional line; one `[FAIL]` at drain.
- Phase 5 (if fired): moving a prefix member to a `glob:` form and re-running `--print-selection` over every subject file shows no lost selection; deleting a needed member makes the check red.

## Risks and Sharp Edges

- **Cold derive may dominate.** One reading is 6m06s under load. If it is 25 percent or more of the cold gate, suite narrowing cannot reach 10 minutes; the Phase 5 arithmetic gate skips narrowing and Phase 6.3 files the tracker instead of over-claiming #12025's lever.
- **The measurement is a replay, not an organic PR.** Diffs are replayed onto a pinned main with synthetic burner load; the table says so. Median-of-three is a bar, not a proof.
- **Rate is a proxy.** Today's edges applied to older diffs; commits that landed are survivors. Stamped in the header and in the ledger.
- **Narrowing risk.** Hidden reads defeat both the derive and the audit; the SUT read in Phase 5.2 is mandatory and `glob-rate`'s spot-check must agree with the real selector. A malformed `glob:` head fails wide or selects nothing.
- **The new sibling test is glob-registered.** If the census reports it UNCLASSIFIED or INDEX-UNBOUND the local gate degrades to the full battery and a sibling full run refuses it (rc=4); the single fallback is in 1.3. Never add rows to the split replay test.
- **Every number carries its command** (`hr-no-dashboard-eyeball-pull-data-yourself`). Counts such as 116 always-on labels drift; record them as observations.
- **Committed logs** contain suite labels, milliseconds and SHAs only; strip anything else before commit.
- An empty or placeholder `## User-Brand Impact` fails `deepen-plan` Phase 4.6; this one is filled.

## Plan Review Disposition (2026-11-04: DHH, Kieran, code-simplicity)

Applied (mechanical): `suite-rate` rebuilt on the existing `glob_units` / `glob_selector_rows` / `glob_spot_check` helpers (one selector run, built-in spot-check; Kieran P1); test trimmed to four rows and four mutations; serial pair and warm rerun cut to the median diff only; standalone runs cut to the two weight suites unless the bar is missed; synthetic burner load replaces the ambient-load condition (standing check `cq-ac-must-not-depend-on-concurrent-sessions`); induced-red assertion made structural (a suite starts before and ends after) and folded into a reading; base SHA pinned, percentile and tie-break defined, replay-faithfulness check added; timing-log location and filter spelled out; full registered labels used; AC7 gets its command, ACs 4/6/8 collapsed into one diff allow-list; Observability, runbook edit, `c4-count-parity` run and the next-lever issue cut; Closing Matrix collapsed to two rules; classification ladder reduced to one fallback; Phase 5 gated by savings-versus-gap arithmetic with a split-to-second-PR rule above 800 lines.

Not applied (kept, with reason): replacing the tool with an awk loop (CTO ruled the tool; it is now about 40 lines over existing helpers); making Phase 5 a mandatory second PR (UC-1: the operator asked for one PR, so the conditional commit stays and splits only above 800 lines); moving the ledger out of ADR-242 (CTO ruling puts it there; raw data stays in `measurements/`); gating the rate loop behind the verdict (it is one selector run now and feeds diff selection).
