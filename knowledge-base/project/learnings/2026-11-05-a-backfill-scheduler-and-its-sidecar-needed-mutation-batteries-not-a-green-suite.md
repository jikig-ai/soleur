# Learning: a backfill scheduler and a provisional-red sidecar needed mutation batteries, not a green suite

## Problem

#12013 (local affected-gate speed-up): the gate's parallel pool launched strictly FIFO, so one
`lock:test-all` head blocked token-free suites behind it, and a budget kill (rc 124/137) mapped
to `budget-deferred` even after a provisional red had printed. The 10-minute bar was not met
(measured gap about 5x; the gate is about 52% faster than the earlier single reading).

## Solution

- `_pj_fill` is a conservative backfill (launch iff a slot is free, no live suite conflicts, no
  earlier queued suite conflicts; `*` is a barrier). `SOLEUR_PJ_FIFO=1` restores strict FIFO as
  the control arm and is demoted with `export -n` so it never leaks into sandboxed arms.
- The gate hands the runner a mktemp sidecar (`SOLEUR_PJ_PROVISIONAL_FILE`); the runner records
  only the `failed` class of `suite_exit_class` (signals are `killed`, never recorded). On rc
  124/137 a record with rc 1..255 and an epoch strictly before `AFFECTED_DEADLINE` yields exit 1
  `failed-before-budget`, otherwise exit 6.
- Three empty-token `lane_declare` entries for the `ci-pr-affected-replay-{a,b,c}` arms.
- Raw readings and the pricing are in the ADR-242 amendment of 2026-11-05.

## Key Insight

A passing suite proves the author's fixtures agree with the author's code, not that the arms can
fail. Every scheduler clause (slot check, live-conflict check, queued-ahead check, barrier, head
order, solo-flag clear, drain loop) was only trusted after a mutation on a COPY of the SUT
(`TESTALL_TARGET_OVERRIDE`, `AFFECTED_TESTS_SUT`) turned a named arm red; nine of nine scheduler
mutants die now. Mutation rounds found real holes: an arm that never interrupted the runner,
an arm that could not fail (stale files outside the gate's `TMPDIR`), and an equivalent-mutant
arm that was removed rather than kept as decoration.

## Session Errors

1. **Nested-heredoc Python patch cut short (SyntaxError)** — Recovery: rewrote as a file patch. Prevention: write multi-line patches to a file, never a heredoc inside a heredoc.
2. **F4i could not fail (planted stale files were not in the gate's `TMPDIR`)** — Recovery: `RUN_TMPDIR`. Prevention: for every new arm, run the mutation that should redden it before trusting it.
3. **A9 `sigred` arm never interrupted the runner** — Recovery: fixture targets the runner pid; the `_pj_sig` guard stays as labelled defense in depth. Prevention: same mutation-first rule.
4. **Starvation arm non-discriminating (equivalent mutant)** — Recovery: removed with a tombstone comment. Prevention: an arm that no mutant can redden is deleted, not kept.
5. **Repo ratchets tripped by new tests** (`fixture-relative-assert`, `guard-vacuity-floor`, `lint-trap-tempfile-ownership`, `grep-q-pipe-guard`) — Recovery: `assert_fixture_dir`, `tee -a`, EXIT trap, floor restructure, here-strings. Prevention: already covered by the file-selected-suite-set rule in `soleur:work`; run the ratchets over a new test file before the first commit.
6. **Sibling suite C6 red after the sidecar prefix change** — Recovery: widened `scoped_re`. Prevention: grep sibling suites that assert the changed command line before editing it.
7. **`SOLEUR_PJ_FIFO` leaked into the control reading and sandboxed arms** — Recovery: `export -n` plus `env -u` in `run_arm`. Prevention: a knob that selects an arm is scrubbed at the arm boundary.
8. **`kill -l` has no name for 32, so rc 160 is host-dependent** — Recovery: expectation derived at run time. Prevention: derive host-dependent expectations, never hard-code them.
9. **Hook and tool blocks**: `pgrep -f` / `ps | awk` self-match (use `proc.sh list_runs`), `sleep` chains (use Monitor), `/tmp` redirect with unset `$TMPDIR`, `git stash`. Recovery: used the sanctioned form each time. Prevention: already hook-enforced.
10. **Ran suites while the operator was on a call; the browser crashed** — Recovery: stopped on request, resumed on approval, relaunched niced. Prevention: run heavy suites `nice -n 10`, and ask about load when the operator reports a call or a crash.
11. **One-off `scratch-residue` failure in r2 under load (232/232 standalone)** — recorded as unreproduced in the ADR, not dismissed.
12. **My own mutation-count line printed `fails=0` for M9 (rc=2)** though the arm failed — the summary grep missed the line; the log's own total (2 failed) was authoritative. Prevention: read the runner's total, not a derived grep count.

## Triage

| item | recurring? | disposition |
|---|---|---|
| 1, 8, 9, 11 | one-off | noted |
| 2–4, 7 | recurring (fixture that cannot fail) | covered by the mutation-first rule above; no new AGENTS rule (budget WARN, domain-scoped) |
| 5, 6 | recurring | already enforced by ratchets and the `soleur:work` rule |
| 10 | recurring | `nice -n 10` for local suite runs; no hook |
| 12 | one-off | noted |

Unreaped finished worker (follow-up) and edge/token narrowing are tracked on #12013, #12151, #12152.

## Tags
category: workflow-issues
module: scripts/test-all.sh, plugins/soleur/scripts/affected-tests.sh
