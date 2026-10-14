# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8761-print-affected-set-spin/knowledge-base/project/plans/2026-09-24-fix-test-all-print-affected-set-deleted-worktree-plan.md
- Status: complete

### Errors
- No Skill tool in the planning subagent's harness — `plan` and `deepen-plan` bodies were executed manually from the cached plugin source.
- No Task/subagent tool — research and review fan-outs ran as sequential-fallback; disclosed in the plan's `## Review & Consult Provenance`.
- `scripts/lint-plan-acceptance.py` and `scripts/lint-observability-plan.py` absent at this HEAD — those deepen-plan gates could not run; `lint-guard-contract.py` ran and passed (2 guard entries), stale-marker scan clean, markdownlint clean.
- The literal spin site could not be identified: 15 deletion-offset repro arms on this HEAD all terminated cleanly (exit 2 pre-walk, or truncated exit 0 mid-walk), and every enumerate-path loop is structurally bounded. The plan treats the hang site as unidentified and fixes the contract + adds a wall-clock ceiling instead.

### Decisions
- Fix is structural, three mechanisms: up-front checkout guard (`git rev-parse --show-toplevel` + `[[ -d "$PWD" ]]` → `exit 4`), per-registration liveness+deadline check inside `_shard_selects` (chokepoint for `run_suite`/`skip_suite`), and a pure-bash watchdog subshell for the `_ENUMERATE==1` family (default 300s, `SOLEUR_ENUM_DEADLINE_S` overridable).
- `exec timeout` rejected — `timeout(1)` absent on stock macOS; watchdog is `sleep`+`kill`+`SECONDS` (bash 3.2-safe, `_tc_queue_wait` precedent).
- Probe must be path-based: `[[ -e . ]]`/`stat .` stay TRUE on a deleted-but-open cwd; `[[ -d "$PWD" ]]`/`pwd -P`/`git rev-parse` correctly fail. A mutation row pins this.
- Guard arm must `exit`, not `return` — call sites are `_shard_selects "$label" || return 0`, so return is swallowed as non-selection.
- Regression coverage lands as arms inside the already-registered `scripts/test-all-affected.test.sh` (avoids new `run_suite` registration + lint-orphan `AFFECTED_*_PATHS` declaration). The contract test reds today via the silent truncated exit 0 even without reproducing the literal spin.
- #8621 (selector convergence) explicitly out of scope; noted in Non-Goals.

### Components Invoked
- `gh issue view 8761` / `gh issue view 8621`, `gh issue list --label code-review`
- Skills (manual execution): `soleur:plan`, `soleur:deepen-plan` from the cached plugin
- Repo tools: `git worktree add/remove` repro harness (15 arms), `bash -x` tracing, markdownlint, `scripts/lint-guard-contract.py`, `git commit` (lefthook green)

## Work Phase (post-compaction)
- Status: implemented, committed `0a0e53a1aa` (`fix(test-all): deleted-worktree fail-fast + enumerate watchdog (#8761)`).
- Files: `scripts/test-all.sh`, `scripts/test-all-affected.test.sh`, `tasks.md`.

### Deviations from plan (each verified, not assumed)
- Up-front guard dropped the `git rev-parse --show-toplevel` clause: `test-all-group-affected` arms B3/B6 run `TEST_GROUP=affected` from a NON-git dir under an established "undeterminable diff fails open" contract — rev-parse there refused a legitimate degraded run. `[[ ! -d "$PWD" ]]` alone is the deleted-cwd discriminator.
- Default deadline raised 300 -> 900: a healthy `--print-affected-set` on this box measured >300s under load 16 (deadline is a safety ceiling, not a perf assertion; still caps the 4.5h incident class ~20x under).
- Watchdog subshell restructured to `sleep & wait` + TERM-trap: a bare `( sleep D; kill … ) &` leaks the sleep on disarm, and the orphan inherits the runner's stdout — a `$( )`/pipe consumer then blocks for the rest of the deadline (reproduced live: `--affected` pre-pass child blocked 14min in anon_pipe_read). This is the incident's own shape; arm z5 pins the fix.
- Test helper `_wait_bound` must run in the main shell: inside `$( )` the jobs-table copy never learns the child's exit, so `wait` blocks until the bound fires — both y1/z1 falsely read 124 until fixed.

### Verification
- `test-all-affected.test.sh`: 42/42 (11 new arms y1-y4, z1-z7 + all existing).
- Siblings: enumerate-toolchain 37/37, group-affected 50/50, killed-classification 77/77, capacity-signal 80/80, runtime-ceiling 23/23, infra-coverage-notice 131/131, webplat-gate 16/16.
- `lint-orphan-test-suites.sh`: rc=0, 543 covered / 0 orphaned; its `aff_set_rc` arm already surfaces print failures (AC6).
- Standalone repros: deleted cwd -> rc=4 in 13ms; `SOLEUR_ENUM_DEADLINE_S=3` -> SIGTERM at 3.3s with deadline error; disarm leaves no orphan holding the consumer pipe.
- y1 RED-side observed the incident shape on pre-fix code (run outlived 45s bound after mid-walk deletion).


## Review Phase (pipeline: soleur:review, code-class + design-risk + guard-shaped)
- Panel: design pass (code-simplicity + architecture) -> 8-seat panel (git-history,
  structural-enumeration [replacing pattern-recognition per guard-shaped rule],
  security, performance, data-integrity, agent-native, code-quality, test-design)
  + shellcheck deterministic gate (semgrep substituted — bash-only PR) +
  coverage-consult seat.
- Convergent HIGH (both design seats): watchdog disarm covered only the clean
  terminator -> moved into the EXIT trap chain (_enum_wd_disarm).
- Security MEDIUM: watchdog pid-reuse kill + SIGKILL-orphan pipe-hold ->
  kill -0 liveness poll at 1s granularity + lstart identity check + zombie
  parent detection (ps stat= Z*).
- Structural seat: arm moved ahead of the preamble (bounded wedge coverage);
  printf-before-kill reordered (SIGPIPE/stall); grace sleep tracked; ps-absent
  fires anyway; untracked sleep-5 -> _wd_sleep.
- Consult-found class: pgrep -P sweep must exclude $BASHPID (the watchdog is
  itself a child of the runner — first version killed itself before TERMing
  the parent; caught by a standalone repro, fixed).
- TERM-masked-caller class: _enum_wd_disarm now polls ~2s then SIGKILLs (a
  masked TERM leaves the trap undelivered -> bare wait would hang the exit).
- Contract: exit-4 header lists all six producers + watchdog signal-death;
  mid-execution cwd loss exits 3 (coverage unresolved). SOLEUR_ENUM_DEADLINE_S
  normalized with 10#/{1,9}/>0 (TC_RUNTIME_CEILING_S precedent); baseline
  _ENUM_T0 so an inherited SECONDS cannot pre-trip it.
- New arms from review: z6 (pipe-EOF on the exit-4 path), y4 (executing-mode
  exit 3 + no summary marker), z7 (graceful deadline isolated via spliced-out
  watchdog). MIN_CASES 31 -> 42.
- Scope-out filed: #8800 census-sandbox cp -al/symlink write-through
  (pre-existing, meta/machinery, deferred-scope-out, date re-eval 2026-11-01,
  probe scripts/followthroughs/census-sandbox-writethrough-8800.sh).
- Inline extras: lint-orphan relays child ERROR/FATAL lines on enumerate
  failure; its child invocations now scrub SOLEUR_ENUM_DEADLINE_S.
- Wontfix (recorded): trap-install micro-race at subshell fork (unreachable
  in practice); sleep-absent watchdog spin (sleep absence breaks the whole
  runner); deleted-then-recreated same-path cwd (documented residual).
