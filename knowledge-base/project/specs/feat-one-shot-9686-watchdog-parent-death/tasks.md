# Tasks — feat-one-shot-9686-watchdog-parent-death (#9686)

Derived from `knowledge-base/project/plans/2026-10-07-fix-test-all-parent-death-watchdog-debounce-plan.md`.
Failing fixtures first (cq-write-failing-tests-before): Phase 1 arms are written
against the CURRENT single-poll watchdog — the transient/non-consecutive/reverify
arms MUST redden before the debounce lands; sustained/real-death arms stay green.

## 1. Test coverage first — RED (scripts/test-all-orphan-log-retention.test.sh)

- [ ] 1.1 Structural pins on `wd_block`: `_RUN_WD_FAILS_N` parsed once with the numeric-floor idiom; `_wd_fails` counter present; NO `|| break`/`&& break` remaining on the three parent legs; counter-reset-on-healthy-poll line present; WARN per-failure diagnostic line present.
- [ ] 1.2 Pin `SOLEUR_TEST_ALL_WD_FAILS_N=1` on existing B1 real-parent-death arm (preserves 12s deadline; proves floor semantics).
- [ ] 1.3 New arm: real parent death under default N=3 still terminates within ~25s; runner + transitive children reaped; `parent process gone` printed.
- [ ] 1.4 New arm: `ps` PATH-shim returns `Z` once for the parent's `stat=` poll → run completes, no fire, rc=0; assert shim injection marker exists (anti-vacuity).
- [ ] 1.5 New arm: shim returns forged `lstart` on the SECOND `lstart=` call for the parent pid (first call is the arm-time baseline) → no fire; marker asserted.
- [ ] 1.6 New arm: shim fails parent `stat=` on alternating calls → no fire (consecutive-not-cumulative pin).
- [ ] 1.7 New arm: shim returns `Z` on EVERY parent `stat=` poll → run reaped after >=N polls (must-fire direction stays pinned).
- [ ] 1.8 New arm: shim fails exactly the first N parent `stat=` calls then passes → deciding-poll re-verify reads call N+1 healthy → NO fire.
- [ ] 1.9 Run the suite against CURRENT `scripts/test-all.sh`: arms 1.4/1.5/1.6/1.8 MUST be red; if green, the shim harness is vacuous — fix the harness before proceeding.
- [ ] 1.10 If `plugins/soleur/test/fixture-relative-assert.test.sh` reds, regenerate `fixture-relative-assert.baseline.txt` via `--write-baseline` (never hand-edit).

## 2. Debounce the `_RUN_WD` verdict — GREEN (scripts/test-all.sh)

- [ ] 2.1 Declare `_RUN_WD_FAILS_N` beside `_RUN_WD_POLL_S`: `="${SOLEUR_TEST_ALL_WD_FAILS_N:-3}"`, `=~ ^[0-9]+$` + `10#` + `>= 1` floor, else default 3.
- [ ] 2.2 Init `_wd_fails=0` and `_wd_top_fails=0` inside the watchdog subshell before `while :; do` (set -u safe).
- [ ] 2.3 Runner-liveness leg counted: `kill -0 "$_RUN_WD_TOP_PID"` fail → `_wd_top_fails=$(( _wd_top_fails + 1 ))`, reap+exit only at `>= _RUN_WD_FAILS_N`; success resets to 0. (Assignment-form increments only — bare `(( x++ ))` aborts under `set -e`.)
- [ ] 2.4 Parent legs → single `_wd_bad` verdict w/ leg name (`kill0`/`zombie`/`lstart`); on `_wd_bad`: increment `_wd_fails`, `printf 'WARN: parent-liveness poll failed (leg=%s, %s/%s consecutive) (#9686)\n' >&2 || true`; at threshold run deciding-poll re-verify (fresh `kill -0` + `stat` + `lstart`) → still-failed `break`s, recovered resets `_wd_fails=0`; healthy poll resets `_wd_fails=0`.
- [ ] 2.5 Header comment updated to state the debounce contract; cites `#9686` beside `#8993`. Do NOT quote the uniqueness-asserted anchors (`tc_acquire "test-all"`, epilogue call) verbatim in comments.
- [ ] 2.6 Verify byte-identical: reap order, `ERROR: parent process gone` text, `SOLEUR_TEST_ALL_ALLOW_ORPHAN` banner, `_run_wd_disarm`, runner-identity re-check.
- [ ] 2.7 `bash scripts/test-all-orphan-log-retention.test.sh` all green; `bash -n scripts/test-all.sh`; `bash scripts/test-all-killed-classification.test.sh` + `bash scripts/test-all-runtime-ceiling.test.sh` green (splice-window regression).

## 3. Soak follow-through enrollment

- [ ] 3.1 Create `scripts/followthroughs/watchdog-debounce-soak-9686.sh` (detect-only; exit codes 2/3/5 per `watchdog-arm-soak-9237.sh`, never 0/1): count post-merge `main-health-monitor` runs; only runs whose tests step dispatched `bash scripts/test-all.sh` count (emitter-must-be-armed discipline); clean verdict = 2 consecutive runs w/o `parent process gone`/`[KILLED]`.
- [ ] 3.2 Create `scripts/followthroughs/watchdog-debounce-soak-9686.test.sh`; register via explicit `run_suite "scripts/watchdog-debounce-soak-9686" bash scripts/followthroughs/watchdog-debounce-soak-9686.test.sh` beside the other followthrough registrations.
- [ ] 3.3 PR body carries `<!-- soleur:followthrough script=scripts/followthroughs/watchdog-debounce-soak-9686.sh earliest=<merge+1d> secrets=GH_TOKEN -->` and `Closes #9686`; add `follow-through` label to #9686.
- [ ] 3.4 Verify no edits to `.github/workflows/main-health-monitor.yml`, `plugins/soleur/test/main-health-monitor-workflow.test.sh`, or the generated `suite-durations.tsv`/`suite-shard-legs.tsv` (manifest regeneration is a separate tool pass — flag if a freshness gate reds).
