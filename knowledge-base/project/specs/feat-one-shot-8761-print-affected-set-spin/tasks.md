# Tasks — feat-one-shot-8761-print-affected-set-spin

## Phase 0 — Locate the target seams (independent, no edits)

- [x] 0.1 In `scripts/test-all.sh`, locate: the flag-parse loop where `--print-affected-set` sets `_PRINT_AFFECTED`/`_ENUMERATE`; the bare-repo guard block (`git rev-parse --is-bare-repository`); `_shard_selects` (the single per-registration chokepoint — verify `run_suite` and `skip_suite` are its only call sites); `_affected_derive`'s closure `while` loop; the `_ENUMERATE == 1` terminal block (`[shard] enumerate complete` + `trap - EXIT`).
  - Test: none (orientation task)
- [x] 0.2 Verify no receipt consumer does a whole-stream equality assert that a stray `ERROR:` stdout line would break (`git grep -n "AFFECTED_CLASS\|SUITE_COMMAND" -- 'scripts/*.sh' 'plugins/*/test/*.sh'`), and confirm consumers prefix-select.
  - Test: none

## Phase 1 — Runner changes (scripts/test-all.sh)

- [x] 1.1 Add the up-front checkout guard after the bare-repo guard: `git rev-parse --show-toplevel` must succeed AND `[[ -d "$PWD" ]]` must hold; else print `ERROR: working tree missing (deleted worktree?)` to stderr AND stdout, `exit 4`. Probe MUST be path-based — `[[ -e . ]]`/`stat .` stay true on a deleted cwd (measured). Parse `SOLEUR_ENUM_DEADLINE_S` (default 900 — raised from plan's 300 after a loaded-host walk measured >300s; the bound caps the multi-hour incident class, it is not a perf assertion), `=~ ^[0-9]+$`-validated) nearby.
  - Test: pre-deletion-start arm in the suite (task 2.2)
- [x] 1.2 At the top of `_shard_selects` (after the arg-count refusal, before the ordinal increment): `[[ -d "$PWD" ]] || _wt_missing_die` — `exit`, never `return` (call sites are `|| return 0`). Add the enumerate deadline: `if (( _ENUMERATE == 1 && SECONDS > _ENUM_DEADLINE_S ))` -> deadline error + `exit 4`.
  - Test: mid-walk deletion arm (task 2.1)
- [x] 1.3 Add the same `[[ -d "$PWD" ]]` die as the first statement inside `_affected_derive`'s closure `while` loop.
  - Test: mid-walk deletion arm (task 2.1)
- [x] 1.4 Arm the pure-bash watchdog subshell after flag validation when `_ENUMERATE == 1` (placed before `tc_acquire`, after `SOLEUR_DISABLE_SESSION_STATE`): capture `_ENUM_TOP_PID=$$`, spawn a subshell that `sleep`s the deadline as a TRACKED child — `sleep D & _wd_sleep=$!` + `trap` on TERM that kills `_wd_sleep` — then `wait`s it and, only on natural expiry, prints the deadline error to stderr AND stdout, `kill -TERM`s the top pid, and `kill -KILL`s after 5s grace. No `timeout(1)` — absent on stock macOS.
  - DESIGN NOTE (found during implementation): a bare `( sleep D; kill … ) &` leaks the `sleep` child on disarm — the orphan inherits the runner's stdout, so a `$( )`/pipe consumer of the enumerate stream blocks until the sleep expires (reproduced live: sandbox `--affected` arm blocked 14min in `anon_pipe_read`). The TERM-trap shape kills the child on disarm. Pinned by arm z5.
  - Test: spliced-spin arm (task 2.3)
- [x] 1.5 Disarm the watchdog in the `_ENUMERATE == 1` terminal block before `trap - EXIT` (`kill "$_ENUM_WD_PID"` + `wait` reap, guarded by `${_ENUM_WD_PID:-}`).
  - Test: healthy-path arm asserts no deadline line (task 2.4)

## Phase 2 — Regression arms (scripts/test-all-affected.test.sh)

- [x] 2.1 Mid-walk deletion arm (y1): fixture `git init` repo + `git worktree add` subdir in TESTROOT, sandbox runner living OUTSIDE the worktree, `sleep 0.4` spliced after the ordinal tick to widen the walk, `rm -rf` mid-walk after first receipt observed; assert rc != 0 and `working tree missing` in output.
  - Test: this arm
- [x] 2.2 Pre-deletion-start arm (y2): `( cd wt; rm -rf wt; bash runner --print-affected-set )`; assert rc=4 fast with the named error.
  - Test: this arm
- [x] 2.3 Watchdog arm (z1): `while :; do :; done` spliced at the TOP of `_shard_selects` (ahead of the liveness/deadline checks — only the watchdog can end it), run with `SOLEUR_ENUM_DEADLINE_S=5`; assert death within 40s and the deadline error line.
  - Test: this arm
- [x] 2.4 Must-pass arms: intact fixture worktree exits 0 with programmatically-counted full receipts (z3 — baseline from a same-runner run in the fixture's main checkout, not `runnable_n`: declined registrations emit AFFECTED_CLASS but SUITE_COMMAND_DECLINED, so record types differ), symlinked-cwd variant (z4); assert no guard/deadline line fires.
  - Test: this arm
- [x] 2.5 Sibling flag spelling (y3): `--enumerate` through the pre-deletion arm. Plus z5: `$( )` consumer must get EOF at run exit, not watchdog-lifetime (pins the trap-kill-children disarm).
  - Test: this arm

## Phase 3 — Sweep gates

- [ ] 3.1 `bash scripts/test-all-affected.test.sh` green (new arms + all existing arms).
- [ ] 3.2 Sibling runner suites green: `test-all-enumerate-toolchain`, `test-all-group-affected`, `test-all-killed-classification`, `test-all-capacity-signal`, `test-all-runtime-ceiling`, `test-all-infra-coverage-notice`, `test-all-webplat-gate`.
- [ ] 3.3 `bash scripts/lint-orphan-test-suites.sh` green (no new suite registered; receipt stream still parses). Consumer contract verified by read: `aff_set_rc` arm at line ~1067 exits non-zero loudly on a failed print run.
- [x] 3.4 `bash -n scripts/test-all.sh` and `bash -n scripts/test-all-affected.test.sh` clean.
