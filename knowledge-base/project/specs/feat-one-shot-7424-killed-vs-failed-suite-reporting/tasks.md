---
feature: feat-one-shot-7424-killed-vs-failed-suite-reporting
issue: 7424
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-10-fix-test-all-killed-vs-failed-and-sibling-suite-probe-plan.md
status: ready
---

# Tasks — #7424 KILLED vs FAILED suite reporting + sibling-suite probe

Derived from the **post-review** plan (5-reviewer panel applied). Two findings against
operator-stated scope are recorded in `decision-challenges.md` and were deliberately **not** applied.

**Do not touch `apps/web-platform/infra/run-registered-suites.sh`** — it is the live target of open
#7376 / draft PR #7423.

## Phase 0 — Preconditions

- [ ] 0.1 On branch `feat-one-shot-7424-killed-vs-failed-suite-reporting`; `git status --porcelain` empty.
- [ ] 0.2 Re-measure the `kill -l` oracle: `0→EXIT`, `15→TERM`, `31→SYS`, **`32`/`33`→rc 0, EMPTY**, `64→RTMAX`, `65→REJECT`, `143→TERM` (masking). Record any host difference.
- [ ] 0.3 Verify sandbox anchors: one `^run_suite() {`, one `^_infra_in_diff=0$`, one `^_infra_detect_ok=0$`, and the first col-0 `}` after line 143 is `run_suite`'s.
- [ ] 0.4 Capture pre-edit baselines: `lint-diagnosis-claims.sh` (OK, 1 vs highwater 1), `lint-shell-capture-exit.py --baseline …` (0 new), `lint-orphan-test-suites.sh` (none).

## Phase 1 — RED (classifier as a stub)

- [ ] 1.1 Add `suite_exit_class()` to `scripts/test-all.sh` as a stub returning `failed`, **above** `run_suite` and outside its brace range. (Inline, **not** a `scripts/lib/` file — the sandbox suite copies a single file.)
- [ ] 1.2 Create `scripts/test-all-killed-classification.test.sh` — **Part A** only: extract by anchored range (`assert count == 1`), `unset -f` then source in a subshell that sets `set -euo pipefail`, assert `declare -F` succeeds, `bash -n` the block. Table-drive **24 rows**: `0,1,2,3,124,126,127,128,129,130,134,136,137,139,141,143,159,160,161,162,192,193,255` plus `""`, `" "`, `abc`. Expect `killed` only for `129,130,134,136,137,139,141,143,159,162,192`. Add a `MIN_ASSERTIONS` floor.
- [ ] 1.3 Run it; confirm it **REDs** against the stub before proceeding.

## Phase 2 — GREEN (classify, render, count, exit)

- [ ] 2.1 Implement `suite_exit_class`: **numeric guard first** (`[[ "$rc" =~ ^[0-9]+$ ]] || return failed` — without it `""` returns `ok`, measured); then `rc == 0 → ok`; then `rc > 128 && rc <= 192` **and** `kill -l $((rc-128))` yields a **non-empty** name → `killed`; else `failed`. Guard `kill -l` with `2>/dev/null || name=""`. `rc > 128` and `-n "$name"` are load-bearing; **`<= 192` is redundant** given the non-empty guard (no reachable rc discriminates it) — keep it with an honest comment, do not claim a test pins it.
- [ ] 2.2 Add `killed=0` beside `failed=0` / `suites=0`. (Under `set -u` an uninitialized `killed` aborts after the marker but before the exit arm → exit 0 on a failing run.)
- [ ] 2.3 Rewrite `run_suite`'s status block: `local rc=0`; `"$@" || rc=$?`; `status="$(suite_exit_class "$rc" 2>/dev/null)" || status="failed"`; `case` with **`ok)`, `failed)`, `killed)` and a fail-closed `*)`** that warns and counts FAILED. Keep `run_suite() {` and `}` at column 0 with no new col-0 `}`.
- [ ] 2.4 Add the `[KILLED]` render. **Read the live `CLAIM` regex in `scripts/lint-diagnosis-claims.sh` first** and check the string against it — do not work from a restated list.
- [ ] 2.5 `TEST_TIMING_LOG` field 3 → `KILLED` on the killed arm, preserving the labelled `tmp_delta=` field; update the header's format-contract comment.
- [ ] 2.6 **Breakdown line FIRST (gated on `killed > 0`), terminal marker LAST** — `work/SKILL.md` says match the runner's LAST emitted line, so a summary-shaped line must not follow the marker. Summary `$((suites - failed - killed))`; `elif (( killed > 0 )); then exit 3`; add the `EXIT CONTRACT` header block incl. "3 is top-level-only".

## Phase 3 — Integration half

- [ ] 3.1 Add **Part B** to the suite: `TARGET` override, `mktemp -d` + `trap … EXIT`, pass/fail counters, `MIN_ASSERTIONS`.
- [ ] 3.2 Build the sandbox via a `python3` heredoc with `assert s.count(anchor) == 1` per anchor; keep `run_suite`/summary/exit intact; replace the region between `tc_acquire "test-all"` and `tc_epilogue …` with fixtures `ok` (`true`), `assertfail` (`exit 1`), `selfterm` (`kill -TERM $$; sleep 5`).
- [ ] 3.3 Arms A1 (killed-only → 1 `[KILLED]`, 0 `[FAIL]`, breakdown line, exit 3, `TEST_TIMING_LOG` field 3 = `KILLED`), A2 (mixed → exit 1), A3 (clean → tail diff-empty vs `git show origin/main:…`, main side asserted non-empty first), A4 (`[ok]`/`[FAIL]` from emitted output), A5 (classifier always `failed` → A1 REDs), **A7** (delete the `exit 3` arm → exit 0, suite REDs — NOT the `killed)` arm, which falls to `*)` and exits 1), **A8**/**A8-control** (`*)` default), **A9** (suite's own stdout carries no runner-marker-shaped lines; indent all sandbox dumps).
- [ ] 3.4 Register: `run_suite "scripts/test-all-killed-classification" bash scripts/test-all-killed-classification.test.sh` in the second `want_scripts` block, with a why-comment.

## Phase 4 — Sibling-suite probe

- [ ] 4.1 **`_tc_scan_procs` single-walk enumerator + thin `tc_siblings`/`tc_suite_siblings` filters** — NOT a `mode` parameter (it cannot express 4.3's cross-bucket cancellation without two non-atomic walks). Move the run matcher **byte-unchanged** with its rejected-alternatives comment block.
- [ ] 4.2 Add the `suite` matcher (`*.test.sh`, or `test-*.sh` and not `test-all.sh`; or shell `argv[0]` + a whitespace-free later token). Document the three scope edges inline (the `test-all.sh` exclusion; `test-contention.sh` matching latently; `test_*.sh` underscore + `timeout`/`env` `argv[0]` being under-broad).
- [ ] 4.3 Cancel run-children by **ancestry/pgid** (`_tc_ppid` walk under the 64-step guard, `_tc_pgrp` fallback) — **not** cwd. Do **one** `/proc` walk, classifying each pid into both buckets.
- [ ] 4.4 Emit the count line, per-pid detail lines, and `BANNER SIBLING_SUITE_DETECTED`. Leave `SIBLING_RUN_DETECTED` untouched.
- [ ] 4.5 Extend `make_fake_proc` for parameterisable `argv[0]` **and ppid/pgrp** (both hardcoded 0 today); add T9, T10, T11, **T11b** (`env`-wrapped run), **T11c** (`<unreadable>`, asserting the literal appears first so it cannot pass vacuously), **T11d** (over-cancellation control), T12, T13; raise the 40-assertion floor.

## Phase 5 — Declared time budgets

> Recommended for cutting by 2 reviewers; kept because it is operator-stated scope (issue item 3). See `decision-challenges.md` UC-1.

- [ ] 5.1 Add `_suite_budget_ms <label>` as a `case` (not `declare -A`) — reason: initialization order + zero churn at the 131 call sites, **not** bash 3.2.
- [ ] 5.2 Emit the advisory `[budget]` line after the elapsed computation; never change status or exit code.
- [ ] 5.3 Measure the long suite standalone and set the budget at a stated multiple, with the measurement/date/multiple in a comment. **If the battery is itself killed during measurement, defer Phase 5 to the Phase-7.2 issue — do not ship an empty `case`.**

## Phase 6 — Fold-in consumers

- [ ] 6.1 `main-health-monitor.yml`: **shape-anchored** `^\[KILLED\]` grep (the file contains arbitrary suite stdout) into an **initialised** flag, **appending hits to `SUMMARY`** with the `--- (tail) ---` separator and a `cut -c1-500` length bound; fourth arm; **per-arm `ACTIONS` block** (the current one is hardcoded and tells the operator to revert); **`${LEDE}` in the comment path**; fix the pre-existing "usually a step or job timeout" LEDE; leave `grep -E '^RED |^\[FAIL\]'` byte-unchanged.
- [ ] 6.2 `plugins/soleur/test/main-health-monitor-workflow.test.sh`: add assertion (8b) (distinct variable + SUMMARY append + cause-free fourth arm); leave (8) unmodified.
- [ ] 6.3 `plugins/soleur/skills/work/SKILL.md` — **three** edits: §663 (rc third arm + 2nd banner enumeration + `^\[KILLED\]` in its grep), §745 (reap discriminator), §743 (banner enumeration).
- [ ] 6.4 `plugins/soleur/skills/test-fix-loop/SKILL.md` — **four** sites: pre-loop gate (read rc, not "all tests pass"), parse step (define "non-zero exit, nothing parseable"), **iteration-delta arithmetic** (count must be `failures + killed`; otherwise a FAILED→KILLED transition reads as improvement and the return jump reads as Regression → `git reset --hard HEAD` **discards real fixes**), and a terminating row.
- [ ] 6.5 `plugins/soleur/scripts/grok-pre-push-gate.sh`: `run_step` captures rc; exit 3 → `[UNRESOLVED]`, still non-zero.
- [ ] 6.6 `plugins/soleur/skills/one-shot/SKILL.md`: poll the marker *shape* + rc file; state the green/killed/reap trichotomy (a killed run currently reads as a harness reap).
- [ ] 6.7 `AGENTS.rules.md`: one short clause on `wg-when-a-test-runner-crashes-segfault-oom`. **Budget-gated** — `B_ALWAYS`=44400 vs 46000 ratchet; keep under ~150 bytes, re-run `lint-agents-rule-budget.py`, else carry the ladder in ADR-175 + skills only.
- [ ] 6.8 No-edit checks recorded: `git-worktree/SKILL.md` process-table sentence; `review/SKILL.md` anchor-rule example.

## Phase 7 — ADR + deferral

- [ ] 7.1 Write `ADR-175-test-runner-result-taxonomy-unresolved-is-not-failed.md` (Decision, Alternatives A1–A5, Consequences incl. wrapper-absorption + top-level-only exit 3). Re-derive the ordinal against fresh `origin/main` at ship; sweep all artifacts on any renumber.
- [ ] 7.2 File the parity tracking issue (triple test already passed): wrapper surfaces from R4 (incl. the webplat `npm run test:ci` registration) + Phase 5 budgets if deferred. Verify labels exist first.

## Phase 8 — Verification

- [ ] 8.1 `bash scripts/test-all-killed-classification.test.sh`
- [ ] 8.2 `bash scripts/test-contention.test.sh`
- [ ] 8.3 `bash scripts/test-all-infra-coverage-notice.test.sh`
- [ ] 8.4 `bash scripts/lint-orphan-test-suites.sh`
- [ ] 8.5 `bash scripts/lint-diagnosis-claims.sh` (≤ highwater 1; gates both edited surfaces)
- [ ] 8.6 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
- [ ] 8.7 `bash plugins/soleur/test/main-health-monitor-workflow.test.sh`
- [ ] 8.8 Full-suite exit gate on a clean tree; read the terminal marker.
