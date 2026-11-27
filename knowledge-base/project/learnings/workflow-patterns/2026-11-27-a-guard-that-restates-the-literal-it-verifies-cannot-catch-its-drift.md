---
title: A guard that restates the literal it verifies cannot catch its drift
date: 2026-11-27
category: workflow-patterns
module: .github/workflows + plugins/soleur/test
tags: [shard-matrix, expected-legs, derive-dont-restate, sentinel-design, k-bump]
issue: 11556
---

# Learning: when a value is bumped, every *restated copy* of it is a candidate miss — including inside the guard that was written to catch the miss

## Problem

PR #12964 bumped the light `test-scripts` matrix K=8→12 in `ci.yml` and
`main-health-monitor.yml` and regenerated the shard manifests. The plan's
blast-radius table and the implementer's prose sweep covered the matrix
literals, comments, and totality-mutation rows — and still missed
`EXPECTED_LEGS` in the monitor's report job, which stayed at `scripts-0..7`.

The deeper failure: `main-health-monitor-workflow.test.sh` check S4 was
*written* to catch exactly this class ("a matrix resize without an update here
is a RED, not a drift" — the yml's own comment). But S4 computed the expected
leg set with `[f"scripts-{i}" for i in range(8)]` — a restated literal.
Comparing restatement to restatement, the guard stayed green while the
shipped census was wrong by four legs. The same shape existed one layer
deeper: the behavioral-harness census (`EXPECTED_LEGS_FULL` + `rec()`
denominators) restated 18/22 the same way.

Consequences of the stale `EXPECTED_LEGS`: legs 8–11's uploaded reports would
have been classified "unexpected leg report", their `^RED`/`UNACCOUNTED`
captures never scanned, the `legs=reported/expected` completeness metric
denominated wrong, and a killed leg among 8–11 never named "no leg report" —
the silent-window class the monitor exists to catch.

## Solution

Derive, never restate — and apply the rule recursively to the guard's own
fixtures:

- S4 now reads scripts/heavy leg counts from the committed manifests' `# n=`
  lines via the existing `_manifest_n()` helper (fail-closed: absent manifest
  → `or 0` → mismatch → RED).
- `EXPECTED_LEGS_FULL` is extracted from the workflow's `EXPECTED_LEGS:`
  literal by `sed` (with a `[FATAL]` on empty extraction); the `_leg_dir`
  staging loop and the `rec()`/R1–R3 `legs=N/M` denominators all derive from
  it via `wc -w`.
- Verified RED-then-GREEN: the deriving S4 failed against the still-stale
  yml literal, then passed after `EXPECTED_LEGS` gained `scripts-8..11`.

## Key Insight

Two prior lessons compound here. The repo already knew "adding a CI leg
means mirroring every naming surface" (EXPECTED_LEGS 15→18 was on that
list) — yet the plan's blast-radius table omitted it anyway, because
*checklists decay*: the enumeration lives in a learning nobody re-ran. And
the failure mode the "derive, don't restate" doctrine exists to prevent
happened inside the guard itself: the expected-value computation was the
thing that drifted. The durable fix is not a longer checklist but a guard
whose expected set *cannot* be stale because it is computed from the
authoritative source.

Sweep pattern for any count/topology bump: grep the repo for restated
forms of the value (`eight legs`, `K=8`, `range(8)`, `x8`, `legs=18`,
`/18`, `scripts-7`-adjacent lists) across code, comments, tests, fixtures,
and runbook prose — the misses hide in comments and fixture data as often
as in code.

## Session Errors

1. **Plan cited #9307 for the K=7→K=8 precedent** — the real bump PR is
   #9449; #9307 is the umbrella issue. **Prevention:** verify `#NNNN`
   citations against `gh pr view` before pasting into plans and comments;
   the same mis-citation propagated into a new monitor comment and had to
   be swept twice.
2. **Brief machinery path stale** (`test-all-pr-battery-gate` → the real
   artifact is `.test.sh`). **Prevention:** premise-validation step already
   exists; record corrections there, as done.
3. **Scan-gate invoked with no file args** produced `files=0` skip instead
   of findings; the tool takes file paths, not a rev range.
   **Prevention:** on any `files=0`/`skip` receipt, re-check the tool's
   `--help` before accepting it as evidence.
4. **New test arm ran `python3` bare under `set -e`** — the suite died
   mid-run with no FAIL line (the expected rc=2 aborted the script).
   **Prevention:** every fixture command with an expected non-zero exit
   belongs inside `if …; then` or suffixed `|| true`; a suite that ends
   without its verdict line is itself the signal.
5. **Checkbox-regex rewrite ate task numbers** in tasks.md (restored by
   position). **Prevention:** test regex rewrites on `git diff` of the
   target file, not on the reported count.
6. **`/tmp` timing artifacts absent after session restart** — no loss; the
   recorded values lived in the runbook entry. **Prevention:** commit or
   record irreplaceable measurement data; treat `/tmp` as per-session.
7. **EXPECTED_LEGS + fixture census missed the K bump** (the P1 above).
   **Prevention:** the subject-grep sweep described under Key Insight —
   run it at plan time, not just implementation time.
8. **`ART_READ_CAP` 260→320 broke three restated expectations** in
   `pr-battery-gate-saving-9323.test.sh` (11-artifact shape, cap-math
   literal, and dedupe-union prices derived from the committed durations
   TSV) — caught only by CI leg 9, not by the local sentinel sweep that
   omitted this suite. **Prevention:** when a PR changes a constant or a
   committed data file, grep that constant's dependents' *test* files for
   restated values (the cap, the artifact count, the priced literals) —
   and run the dependents' suites, not only the suites named in the plan.

## Tags

shard-matrix, expected-legs, derive-dont-restate, sentinel-design,
k-bump, review-catch
