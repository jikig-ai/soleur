# Learning: the brief named the wrong rc=4, and a chokepoint that reads 3 of 6 conjuncts is a gate that reads none

## Problem

P4d of umbrella #9757 (tracker #10924) asked for a bounded wait, then "CI is the gate", when "the local detached-battery run is refused with rc=4". The brief glossed rc=4 as the per-PR monitor lock (`DUPLICATE MONITOR`). The issue text, the P4c plan and the P4c learning all mean the battery refusal of `scripts/test-all.sh` / `affected-tests.sh` ("refusing a full-gate run ... N sibling full-gate run(s) already in flight"). "CI is the gate" has no meaning for a duplicate monitor (the monitor is a watcher, not a test run), so the brief's gloss could not be the intended scope.

## Solution

Re-scoped by reading the three documented rc=4 sites before planning (CTO ruling F1): a new `ship/scripts/battery-refusal-wait.sh` classifies the refused log, polls `affected-tests.sh --capacity`, and exits `CI_IS_THE_GATE` 42 only when a bounded wall-clock budget (default 1800 s) elapses on a pure sibling-contention refusal. `test-all.sh`, `affected-tests.sh`, `harness.ts` and `drain-prs/SKILL.md` stay untouched (many consumers; ship/SKILL.md has bytes of headroom, not paragraphs).

## Key Insight

1. **A shared numeric code needs the issue's meaning, not the brief's gloss.** Two different scripts exit 4 with different meanings. When the operator's sentence defines the code and the issue body defines it differently, open every site that documents it and take the one whose consequence ("CI is the gate") is meaningful. Cheap: one grep, done before the plan.
2. **A single decision point must read every conjunct of the verdict it emits.** The first cut returned 42 after checking three of six conditions (contention-only log, budget elapsed, capacity seen); the other three (diff not infra, not `--full`, not `force-all`) were enforced by control-flow position or shape-only validation upstream. The review panel's structural seat found it. The fix puts one `case` at the exit that reads all six values (`class:budget:seen:full:infra`) so a reordering cannot skip one. The generalizable rule: the line that emits the only continue-value is the place to read every precondition, not the places that happen to run before it.
3. **A wait helper is only as bounded as the state it keeps.** Epoch state files need a digit-count, leading-zero, staleness and regular-file check, or one bad value turns a 30-minute bound into an unbounded or instant verdict.
4. **A relaunch recipe is itself part of the contract.** The first recipe launched `--affected` and ignored `FULL_BATTERY`, bypassing the pinned dispatch. Suite rows now execute the recipe against stubs for every exit arm, and mutate its glue (R1-R13).

## Session Errors

1. **Scope followed the brief's gloss of rc=4 (monitor lock) rather than the issue's (battery refusal).** Recovery: CTO ruling F1 re-scoped before any code. Prevention: when a brief glosses a shared exit code, grep every documenting site and confirm which one the stated consequence fits before planning.
2. **First cut of the 42 chokepoint read 3 of 6 conjuncts.** Recovery: single `case` over all six values, mutant rows per conjunct. Prevention: review's structural-enumeration seat (already in the panel); for any "only value X continues" exit, list every precondition in the plan and assert each at the emit site.
3. **Review found 24 unique defects (state epoch unbounded, infra detection cwd-relative, recipe ignored `FULL_BATTERY`, capacity substring match, relaunch uncapped, and others).** Recovery: fixed inline across two rounds. Prevention: plan-time checklist for polling helpers: bound every input, anchor every parse, clear `GIT_*`, cap relaunches.
4. **Repo-global ratchets went red on a file-selected suite set: `context-sanitize` drift sentinel (needed a disposition row) and the fixture-relative P1b baseline (new suite added sites).** Recovery: disposition row; `assert_fixture_dir` guards without growing the baseline. Prevention: already covered by the work-skill rule on file-selected suite sets and repo-global ratchets; run the ratchet suites by name for any new test file.
5. **The full affected gate queued behind a foreign worktree's battery** (the very contention P4d addresses). Recovery: stopped my own queued run, ran the targeted gates, stated in the PR Test plan that CI is the gate for the rest. Prevention: P4d itself.
6. **`test-helpers.sh` sets `set -euo pipefail`, aborting the new suite on the first non-zero probe.** Recovery: `set +e` after sourcing. Prevention: one-off.
7. **One push returned a transient `remote rejected (failed)`.** Recovery: retry succeeded. One-off.
8. **Residual markdownlint errors in the plan file (MD022/MD032, planner formatting).** Plan directories are outside the markdown gate. One-off.

## Tags

category: logic-errors
module: plugins/soleur/skills/ship
