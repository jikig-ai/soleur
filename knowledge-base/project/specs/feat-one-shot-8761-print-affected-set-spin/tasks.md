# Tasks — feat-one-shot-8761-print-affected-set-spin

## Phase 0 — Locate the target seams (independent, no edits)

- [ ] 0.1 In `scripts/test-all.sh`, locate: the flag-parse loop where `--print-affected-set` sets `_PRINT_AFFECTED`/`_ENUMERATE`; the bare-repo guard block (`git rev-parse --is-bare-repository`); `_shard_selects` (the single per-registration chokepoint — verify `run_suite` and `skip_suite` are its only call sites); `_affected_derive`'s closure `while` loop; the `_ENUMERATE == 1` terminal block (`[shard] enumerate complete` + `trap - EXIT`).
  - Test: none (orientation task)
- [ ] 0.2 Verify no receipt consumer does a whole-stream equality assert that a stray `ERROR:` stdout line would break (`git grep -n "AFFECTED_CLASS\|SUITE_COMMAND" -- 'scripts/*.sh' 'plugins/*/test/*.sh'`), and confirm consumers prefix-select.
  - Test: none

## Phase 1 — Runner changes (scripts/test-all.sh)

- [ ] 1.1 Add the up-front checkout guard after the bare-repo guard: `git rev-parse --show-toplevel` must succeed AND `[[ -d "$PWD" ]]` must hold; else print `ERROR: working tree missing (deleted worktree?)` to stderr AND stdout, `exit 4`. Probe MUST be path-based — `[[ -e . ]]`/`stat .` stay true on a deleted cwd (measured). Parse `SOLEUR_ENUM_DEADLINE_S` (default 300, `=~ ^[0-9]+$`-validated) nearby.
  - Test: pre-deletion-start arm in the suite (task 2.2)
- [ ] 1.2 At the top of `_shard_selects` (after the arg-count refusal, before the ordinal increment): `[[ -d "$PWD" ]] || { <same error>; exit 4; }` — `exit`, never `return` (call sites are `|| return 0`). Add the enumerate deadline: `(( _ENUMERATE == 1 && SECONDS > _ENUM_DEADLINE_S )) && { <deadline error>; exit 4; }`.
  - Test: mid-walk deletion arm (task 2.1)
- [ ] 1.3 Add the same `[[ -d "$PWD" ]]` die as the first statement inside `_affected_derive`'s closure `while` loop.
  - Test: mid-walk deletion arm (task 2.1)
- [ ] 1.4 Arm the pure-bash watchdog subshell after flag validation when `_ENUMERATE == 1`: capture `_ENUM_TOP_PID=$$`, spawn `( sleep "$_ENUM_DEADLINE_S"; printf '<deadline error>\n' >&2; kill -TERM "$_ENUM_TOP_PID" 2>/dev/null; sleep 5; kill -KILL "$_ENUM_TOP_PID" 2>/dev/null ) &`, record `_ENUM_WD_PID`. No `timeout(1)` — absent on stock macOS.
  - Test: spliced-spin arm (task 2.3)
- [ ] 1.5 Disarm the watchdog in the `_ENUMERATE == 1` terminal block before `trap - EXIT` (`kill "$_ENUM_WD_PID"` guarded).
  - Test: healthy-path arm asserts no deadline line (task 2.4)

## Phase 2 — Regression arms (scripts/test-all-affected.test.sh)

- [ ] 2.1 Mid-walk deletion arm: fixture `git init` repo in TESTROOT, `build_sandbox` runner + libs copied in, `git worktree add` a subdir, launch `--print-affected-set` inside it, `rm -rf` the subdir mid-walk, `wait` under an outer bound; assert rc != 0 and `working tree missing` in output.
  - Test: this arm
- [ ] 2.2 Pre-deletion-start arm: run launched with cwd already deleted; assert fast non-zero with the named error.
  - Test: this arm
- [ ] 2.3 Watchdog arm: splice `while :; do :; done` into the sandbox runner's walk (existing python-splice machinery), run with small `SOLEUR_ENUM_DEADLINE_S`; assert death within deadline+grace and the deadline error line.
  - Test: this arm
- [ ] 2.4 Must-pass arms: intact fixture worktree exits 0 with programmatically-counted full receipts (no hardcoded count), plus a symlinked-cwd-path variant; assert no guard/deadline line fires.
  - Test: this arm
- [ ] 2.5 At least one sibling flag spelling exercised (`--enumerate` or `--affected --print-affected-set`) through the deletion arm.
  - Test: this arm

## Phase 3 — Sweep gates

- [ ] 3.1 `bash scripts/test-all-affected.test.sh` green (new arms + all existing arms).
- [ ] 3.2 Sibling runner suites green: `test-all-enumerate-toolchain`, `test-all-group-affected`, `test-all-killed-classification`, `test-all-capacity-signal`, `test-all-runtime-ceiling`, `test-all-infra-coverage-notice`, `test-all-webplat-gate`.
- [ ] 3.3 `bash scripts/lint-orphan-test-suites.sh` green (no new suite registered; receipt stream still parses).
- [ ] 3.4 `bash -n scripts/test-all.sh` and `bash -n scripts/test-all-affected.test.sh` clean.
