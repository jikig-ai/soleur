---
title: "fix: #8335 green baseline — all five standing red suites verified stale on current main; verify in-runner and close"
type: fix
date: 2026-10-24
slug: fix-8335-green-baseline
branch: feat-one-shot-8335-green-baseline
issue: 8335
closes: 8335
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: #8335 green baseline — all five standing red suites verified stale on current main; verify in-runner and close

## Overview

Issue #8335 filed five suites as standing red, measured 2026-09-18 in a pristine `--detach origin/main` worktree during #8297's ship Phase 4 battery (`429/444 suites passed`). This is child 1 of epic #10971; the green baseline it certifies gates the arc's capstone #8231 (parallelize local `test-all.sh`).

The plan-time reproduction census (below, re-run on this worktree = `origin/main` + one empty scaffold commit, Node v26.12.0) found **all five rows stale**: every named suite passes standalone today, each failure has an identified root cause that was fixed on main by named commits in the #8231-arc portability work (#8270, #8261/#8263, #8250, #8738, #9339, #9635), and the most recent `ci.yml` run on main (`40078153278`, on this branch's exact base `d9e38b4c87`) is `success`.

Scope is therefore narrowed to **zero code changes** to the five suites or their subjects: the deliverable is an in-runner verification record (standalone re-runs + the PR's own CI legs, which execute the full `scripts`/`webplat` groups) and the issue close-out with per-row fixed-by citations — the green-baseline evidence #8231's precondition needs. No assertions are added or removed; the suites' coverage is untouched because none needs it.

## Research Reconciliation — Census vs. Issue Rows

| # | Issue claim | Reproduction verdict (this tree, 2026-10-24) | Root cause at filing | Fixed by |
|---|---|---|---|---|
| 1 | `apps/web-platform/test/mobile-rail-collapse-leak.test.tsx` — 15/15 fail, `localStorage` undefined in `beforeEach` (line 142) | **STALE — PASS** `npx vitest run test/mobile-rail-collapse-leak.test.tsx`: 15/15 pass, exit 0 | Node ≥25 ships a `globalThis.localStorage` getter returning `undefined` without `--localstorage-file`; vitest 4.1's `getWindowKeys` skips pre-existing globals, so happy-dom storage never landed (#8261) | `5073651110` — `workerExecArgv: ["--no-experimental-webstorage"]` in `apps/web-platform/vitest.config.ts`, gated on the descriptor check |
| 2 | `scripts/lint-legal-scope-block-placement.test.sh` — arm (a) expects rc=1, gets rc=0; "arms not co-reported" | **STALE — PASS** `bash scripts/lint-legal-scope-block-placement.test.sh`: `passed: 71 failed: 0`, exit 0 | Filing host's git config (`diff.mnemonicprefix` class) rewrote the diff `b/` header prefix to `w/`; every path failed the file lookup, the lint reported "0 violations", rc=0 (#8238) | `5e859ceac2` (#8270) — subject pins `--src-prefix=a/ --dst-prefix=b/ --no-ext-diff`; test adds GIT_CONFIG_* harness guards; also `a76f489b0d` (#8082) |
| 3 | `scripts/lib/scratch-root.test.sh` — `FAIL: HOME fallback` + `FAIL: containment`, `got='/home/jean/.cache/soleur/tmp'` | **STALE — PASS** `bash scripts/lib/scratch-root.test.sh`: 10/10 PASS, exit 0 | GNU `env` stops option parsing at the first `NAME=VALUE`: `env HOME=$TMP_ROOT --unset=XDG_CACHE_HOME` defined a variable literally named `--unset`, so ambient `XDG_CACHE_HOME` on a desktop host leaked into the "XDG unset" arms. CI doesn't export it → green there, red on the filing host (#8263) | `5e859ceac2` — arg reorder + `export XDG_CACHE_HOME="$TMP_ROOT/ambient-xdg"` ambient sentinel + ORDERING CONTRACT comment in `resolve()`; hardened by `09c7cc31cd` (#8738) and `caa09512ef` (#9339) |
| 4 | `plugins/soleur/test/notice-frontmatter.test.sh` — rc 127 before asserting | **STALE — PASS** `bash plugins/soleur/test/notice-frontmatter.test.sh`: `Passed: 49 Failed: 0 Skipped: 2`, exit 0 | TS-cron-5 timed via `/usr/bin/time -f "%e"` — GNU time's absolute path, absent on macOS/minimal Linux → `command not found`, `set -e` abort (#8250) | `5e859ceac2` — `$EPOCHREALTIME` reads via shared `plugins/soleur/test/lib/wall-clock.sh` with a fail-closed parser (`_wall_clock_self_test`); also `88acf996aa` (#9635) |
| 5 | `plugins/soleur/test/_base-notice-frontmatter.test.sh` — rc 127 before asserting | **STALE — PASS** `bash plugins/soleur/test/_base-notice-frontmatter.test.sh`: `Passed: 41 Failed: 0 Skipped: 2`, exit 0 | Same `/usr/bin/time` portability defect (the two files carried a byte-identical copy, now shared via `lib/wall-clock.sh`) | `5e859ceac2`; `88acf996aa` |

### Main-side vs. local-env judgment (flagged per census instructions)

- **Row 3 (scratch-root)** was environment-*dependent*, not environment-*wrong*: the filing host's exported `XDG_CACHE_HOME` exposed a real test-harness bug (the `env` argument-order defect). It needed a **main-side** fix and got one — no residual env-guard work remains; the ambient sentinel now makes every host behave like the one that exposed it.
- **Rows 4–5 (notice ×2)** were toolchain-*manifested* but a real portability defect (absolute-path GNU time). Also fixed **main-side** — no `command -v` env-guard is needed because the dependency was removed, not gated.
- **Row 1 (mobile-rail)** was Node-version-dependent; the issue's own correction notes CI always passed it. Fixed **main-side** in `vitest.config.ts`; applies globally to all component suites, not just the named file (the correction's 18-file list is covered by the same worker flag).
- **Row 2 (legal-scope)** was git-config-dependent; fixed **main-side** by pinning the diff format flags.

## Implementation Phases

### Phase 1 — In-runner green verification (no code changes)

No per-suite filter exists in `scripts/test-all.sh` (suites are selected by `TEST_GROUP`); the authoritative in-runner evidence is the PR's own CI run plus cheap standalone re-runs.

1. Re-run the five standalone commands from the census table on this branch; record exit codes in the spec's `measurements.md`. All must exit 0.
2. Confirm each suite's runner registration is intact and in scope for the group CI runs:
   - `plugins/soleur/test/*.test.sh` glob (SUITE_GLOBS, `scripts/test-all.sh:97`) → notice ×2, `scripts` group.
   - `scripts/lib/*.test.sh` glob (`scripts/test-all.sh:108`) → scratch-root, `scripts` group.
   - `run_suite "scripts/lint-legal-scope-block-placement-unit"` (`scripts/test-all.sh:5482`, inside `want_scripts`, unconditional) → `scripts` group.
   - vitest component project under `want_webplat` → mobile-rail, `webplat` group.
3. On the pushed PR, verify the `ci.yml` `test-scripts` and `test-webplat` legs are `success` and the named suites appear green in the job output (`run_suite` PASS lines / vitest file summary). The groups run in full per leg, so all five execute regardless of this diff's relevance gating.

### Phase 2 — Issue close-out and baseline record

1. Update the PR body: replace `Refs #8335` with `Closes #8335` **in the body** and drop `(Closes #8335)` from the title — `wg-use-closes-n-in-pr-body-not-title`.
2. Post the census table on #8335 (per-row verdict + fixing commit + the re-run commands), noting the issue's own caveat resolved: rows 4–5 were a toolchain-manifested portability defect, row 1 confirmed stale on a deps-installed tree.
3. Comment the green-baseline statement the epic needs on #10971 (or the spec `measurements.md`): "the five #8335 rows are verified green on `d9e38b4c87`; zero standing red attributable to this issue; #8231's precondition is measurable from here."

## Files to Edit

- None of the five suites or their direct subjects — all pass; editing them would be unrequested scope and risks weakening coverage for zero gain.
- PR metadata only (title/body per Phase 2.1).

## Files to Create

- `knowledge-base/project/plans/2026-10-24-fix-8335-green-baseline-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-8335-green-baseline/measurements.md` (census record + in-runner evidence; one-shot artifact)

## Observability

```yaml
liveness_signal:
  what: "per-suite PASS lines from the five standalone runs and the run_suite/vitest pass lines in the ci.yml test-scripts and test-webplat legs"
  cadence: "on PR CI; on any local test-all.sh scripts|webplat run"
  alert_target: "CI job status + stdout artifacts (Layer 7 cli-stdout-artifact; no hosted sink — verification machinery only)"
  configured_in: "scripts/test-all.sh (run_suite reporting), apps/web-platform/vitest.config.ts"
error_reporting:
  destination: "suite stdout FAIL lines + non-zero run_suite exit -> job failure (Layer 7)"
  fail_loud: "any of the five suites exiting non-zero reddens its leg"
discoverability_test:
  command: "grep -c 'workerExecArgv' apps/web-platform/vitest.config.ts; grep -c 'ambient-xdg' scripts/lib/scratch-root.test.sh; grep -c 'wall-clock.sh' plugins/soleur/test/notice-frontmatter.test.sh"
  expected_output: "2 / 1 / 2 — the three fixes remain present (counts measured 2026-10-24)"
```

## Guard Contract

### Guard 1 — No-weakening: the five suites keep their coverage and their registrations

**Property.** The diff contains zero changes to the five named suite files and their direct subjects (`apps/web-platform/vitest.config.ts`, `scripts/lint-legal-scope-block-placement.{sh,test.sh}`, `scripts/lib/scratch-root.{sh,test.sh}`, `plugins/soleur/test/{,_base-}notice-frontmatter.test.sh`, `plugins/soleur/test/lib/wall-clock.sh`); every suite still runs under its existing `test-all.sh` registration and exits 0.

**Assembly.** `git diff origin/main...HEAD -- <the five suites + subjects>` is empty; registration lines/globs at `scripts/test-all.sh:97,108,5482` and the webplat vitest project are untouched.

**Mutation matrix.** (Each row reverts one landed fix; the expected RED proves the suite still detects its original defect — these are verification probes the implementer may run on a scratch checkout, not diff contents.)

| # | Mutation | Expected |
|---|---|---|
| 1 | Set `workerExecArgv` to `[]` in `apps/web-platform/vitest.config.ts` (undo `5073651110`) | `mobile-rail-collapse-leak.test.tsx` RED on Node ≥25 — `localStorage` undefined in `beforeEach` |
| 2 | Restore the misordered `env HOME=$TMP_ROOT --unset=XDG_CACHE_HOME` in `scripts/lib/scratch-root.test.sh` (undo `5e859ceac2`) | `FAIL: HOME fallback` + `FAIL: containment` on a host exporting `XDG_CACHE_HOME` |
| 3 | Drop `--src-prefix=a/ --dst-prefix=b/` from the diff invocation in `scripts/lint-legal-scope-block-placement.sh` (undo `5e859ceac2`) | arm (a) RED under a `diff.mnemonicprefix` git config — rc=0 where 1 expected |
| 4 | Replace the `lib/wall-clock.sh` timing in `plugins/soleur/test/notice-frontmatter.test.sh` with `/usr/bin/time` (undo `5e859ceac2`) | rc 127 on a host without GNU time |

**Harness rows.**

| # | Edit to the suite or must-PASS input | Expected |
|---|---|---|
| H1 | The five standalone commands re-run on this branch | all exit 0 |
| H2 | A change that removed an assertion or a `run_suite` line | out of scope by construction — none proposed |

**Anchor.** The suites themselves are the guards; `lint-orphan-test-suites` keeps each registered, and `ci.yml` `test-scripts`/`test-webplat` legs run them in full on this PR.

## Acceptance Criteria

- [ ] **AC1 (mobile-rail):** `cd apps/web-platform && npx vitest run test/mobile-rail-collapse-leak.test.tsx` exits 0 with `Tests 15 passed (15)`.
- [ ] **AC2 (legal-scope):** `bash scripts/lint-legal-scope-block-placement.test.sh` exits 0 with `passed: 71  failed: 0`.
- [ ] **AC3 (scratch-root):** `bash scripts/lib/scratch-root.test.sh` exits 0 with `All scratch-root tests passed` (10 PASS lines, incl. `falls back to $HOME/.cache/soleur/tmp` and `containment`), deterministic on a host exporting `XDG_CACHE_HOME` via the ambient sentinel.
- [ ] **AC4 (notice-frontmatter):** `bash plugins/soleur/test/notice-frontmatter.test.sh` exits 0 with `Passed: 49` / `Failed: 0` (2 CI-only timing skips acceptable).
- [ ] **AC5 (_base-notice-frontmatter):** `bash plugins/soleur/test/_base-notice-frontmatter.test.sh` exits 0 with `Passed: 41` / `Failed: 0` (2 CI-only timing skips acceptable).
- [ ] **AC6 (in-runner):** on the PR's `ci.yml` run, `test-scripts` and `test-webplat` legs are `success` with all five named suites green in job output — covering each suite's `test-all.sh` group registration (scripts glob suites, `scripts/lint-legal-scope-block-placement-unit`, webplat component project).
- [ ] **AC7 (no-weakening):** `git diff origin/main...HEAD` contains no edit to the five suite files, their subjects, or `scripts/test-all.sh` registrations.
- [ ] **AC8 (close-out):** #8335 carries the census comment (per-row verdict + fixing commit), the PR body says `Closes #8335` (title does not), and the green-baseline statement is recorded for epic #10971/#8231.

## Test Scenarios

- **Scenario 1 (regression-signal check):** the five suites are green *because their fixes landed*, not because they stopped asserting — spot-evidence: scratch-root's `resolve()` ORDERING CONTRACT comment + ambient sentinel, notice suites' `_wall_clock_self_test`, legal-scope's 12 mutation-killed rows (`mutation '…' killed`) all present in output.
- **Scenario 2 (host-parity):** re-run scratch-root and notice suites with a dirty ambient env (`XDG_CACHE_HOME` exported, no `/usr/bin/time` on PATH): still green — the exact conditions that produced the filing.
