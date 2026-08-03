# Tasks: feat-one-shot-7166-memory-backstop-systemd-slice

Plan: `knowledge-base/project/plans/2026-08-02-feat-memory-backstop-systemd-transient-scope-plan.md`
Issue: #7166 · Threshold: `single-user incident` (CPO sign-off recorded in the plan's Domain Review)

**Ordering is load-bearing.** The class gate ships before the file it gates; the hook (contract)
ships before `settings.json` (consumer); and **wiring `settings.json` is deliberately LAST** (after
Phase 7 verification) because `compact` fires automatically and would self-arm the hook against the
`/work` session mid-implementation. Read the plan's `## Plan Review Revisions (R1-R12)` before
starting -- those are requirements, not commentary.

## Phase 0: Preconditions (four probes only -- see the plan for why the other six were cut)

- [ ] 0.1 `systemctl --version` -- systemd >= 257 (plan measured 259)
- [ ] 0.2 Smoke test the whole approach before writing ~200 lines: `StartTransientUnit` adopting a throwaway `sleep` PID returns rc=0
  - [ ] 0.2.1 Capture probe PIDs with `$!` -- NEVER `pgrep -f <pattern>` (it matches the probing shell's own command line; this produced a false negative at plan time)
  - [ ] 0.2.2 Never probe with a live `claude` PID
- [ ] 0.3 Record `free -m` and the `claude` fleet RSS total into the PR body (the D1 cap arithmetic is only defensible against a stated baseline)
- [ ] 0.4 `rmdir` any orphaned raw cgroup dirs under `app.slice` (a leaked dir makes the AC7 sweep read dirty)
- [ ] 0.5 Cleanup contract: stop every probe unit and remove any `soleur*` drop-in under BOTH `~/.config/systemd/user.control/` and `/run/user/<uid>/systemd/user.control/`

## Phase 1: Exec-bit class gate (AC1)

- [ ] 1.1 Create `.claude/hooks/settings-hook-exec-bit.test.sh`
  - [ ] 1.1.1 Assert the INDEX mode via `git ls-files -s`
  - [ ] 1.1.2 ALSO assert `test -x` on every derived path -- index and on-disk mode diverge under `core.fileMode=false`, on a `noexec` mount, or when a fix lands in the index but not on disk, and the runtime execs the ON-DISK file
  - [ ] 1.1.3 Fail loudly on an empty listing (anti-vacuous guard)
- [ ] 1.2 Derive the hook list across ALL hook events with `jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command'` then strip the `"$CLAUDE_PROJECT_DIR"/` prefix
- [ ] 1.3 Cardinality asserted THREE ways, not by a loose floor (a floor of 25 against 34 paths still passes a filter that drops an entire hook event)
  - [ ] 1.3.1 Listing is non-empty
  - [ ] 1.3.2 Every top-level key under `.hooks` contributes >= 1 path (so dropping `PostToolUse` fails)
  - [ ] 1.3.3 Derived count equals the count of `"type": "command"` entries -- self-consistent, no hand-maintained magic number
- [ ] 1.4 Assert every derived path is tracked (an untracked path named in settings.json is also a failure)
- [ ] 1.5 Confirm green on the current tree, then prove non-vacuity by flipping one hook to `100644` in a scratch copy and observing RED; restore

## Phase 2: Backstop suite (RED)

- [ ] 2.1 Create `.claude/hooks/memory-backstop.test.sh` against the not-yet-written hook; confirm it fails for the right reason
- [ ] 2.2 Live-arm gate: probe the user bus once; on absence print `SKIP: no user systemd bus -- <N> live assertions not run` and run the pure-fixture arm
  - [ ] 2.2.1 `RESULT:` line carries `[live: yes|SKIPPED]`
  - [ ] 2.2.2 Assert the skipped-assertion count equals the number of live-arm tests, so a DELETED live test is distinguishable from a skipped one
- [ ] 2.3 All test units in a namespaced `soleurtest-agents.slice` with `soleurtest-*` scope names; `trap`-based teardown stops every unit and removes every drop-in created

## Phase 3: The hook (GREEN, contract)

- [ ] 3.1 Create `.claude/hooks/memory-backstop.sh` mirroring `supabase-loopback-warn.sh`: `#!/usr/bin/env bash`, why-comments, `exit 0` on every path
  - [ ] 3.1.1 Split into functions plus `main`, guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"` -- tests source and call directly, so there is NO production-reachable injection path (D10)
  - [ ] 3.1.2 `set -uo pipefail` (NOT `-e`) inside `main`, so sourcing does not leak shell options into the harness
- [ ] 3.2 Honour `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` first; declare all four cap values in one `readonly` block
- [ ] 3.3 Early silent exits with distinct logged reasons: no `busctl`; no bus socket (`[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]`); bus probe fails; `no_jq` (R8)
- [ ] 3.4 R2: take a per-PID `flock` around discover -> apply -> log, mirroring `.claude/hooks/agent-token-tee.sh` verbatim
  - [ ] 3.4.1 `flock -w 5 -x <fd>`; on timeout log `concurrent_apply` and exit 0 (emit a drop sentinel -- a silent drop is the failure class this plan avoids everywhere else)
  - [ ] 3.4.2 Canonicalize the repo root via `cd -P` + `pwd -P` before deriving the lock path -- a symlinked path otherwise yields TWO disjoint flock inodes and the lock silently does nothing (that hook's header records this)
- [ ] 3.5 Discover the `claude` PID: label-anchored `PPid:` from `/proc/<pid>/status`, walk bounded to 8 hops
  - [ ] 3.5.1 Positive identity match (`$CLAUDE_CODE_EXECPATH` or `comm`); log which signal matched
  - [ ] 3.5.2 Treat an empty `readlink /proc/<pid>/exe` as no-match; adopt nothing on failure
  - [ ] 3.5.3 Reject PID 0, PID 1, self, and the terminal scope leader
- [ ] 3.6 Collect the full descendant PID set in one bounded `/proc` pass (max 256 PIDs)
- [ ] 3.7 Discover the terminal scope from `/proc/<claude-pid>/cgroup` basename; require a `.scope` suffix; quote the name
- [ ] 3.8 Re-entry state machine
  - [ ] 3.8.1 R3: on `rc=1`, verify the scope is OURS -- its `cgroup.procs` contains our PID AND its `BindsTo` matches the terminal scope just discovered
  - [ ] 3.8.2 R3/R4: key the scope name on PID + start time. Read start time by splitting `/proc/<pid>/stat` on the LAST `)` and indexing from there -- `comm` is the only field that can contain the delimiter
  - [ ] 3.8.3 R5: if the preserved `BindsTo` target is `not-found`/`inactive`, do NOT preserve it; prefer the `terminal_scope` recorded in the jsonl at first apply, validated as still-loaded
  - [ ] 3.8.4 R6: if the unit exists but our PID is NOT in it, re-adopt via `AttachProcessesToUnit` -- never merely refresh (refreshing reports `applied` while nothing is capped)
  - [ ] 3.8.5 Never re-derive the terminal scope from our own scope (self-binding bug -- mutant M7)
- [ ] 3.9 Read `memory.events` + `memory.peak` in one pass; message on INCREASE vs the last recorded counts, never on non-zero (the counters are monotonic and never reset)
- [ ] 3.10 Validate all four cap values BEFORE any D-Bus call; refuse-and-log on out-of-range
- [ ] 3.11 Apply slice properties first: `SetUnitProperties(slice, runtime=true, MemoryHigh, MemoryMax, MemorySwapMax, ManagedOOMPreference=avoid)`
- [ ] 3.12 Then `StartTransientUnit(scope, ...)` with `PIDs`(tree), `Slice`, `MemoryHigh`, `MemoryMax`, `MemorySwapMax`, `OOMPolicy=continue`, `BindsTo`, `After`, and **`Delegate=true`**
  - [ ] 3.12.1 R1 (BLOCKING): without `Delegate=true`, `AttachProcessesToUnit` fails with `Process migration not available on non-delegated units` and the re-entry re-sweep is unimplementable
- [ ] 3.13 Re-entry re-sweep: move newly-found descendants with `AttachProcessesToUnit`
- [ ] 3.14 Redirect every `busctl` call's stdout to `/dev/null` (it prints the job object path, which a SessionStart hook injects into session context)
- [ ] 3.15 Wrap every external call in the portable `timeout` idiom (`TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 5)`)
- [ ] 3.16 Append one JSON line to `.claude/.memory-backstop.jsonl` after `rotate_if_needed`; never record the session id
  - [ ] 3.16.1 R7: also log `slice_high_before` / `slice_max_before` so the mixed-worktree slice flap is detectable
  - [ ] 3.16.2 Record last-seen `oom_kill` / `high` counts for the increase comparison
- [ ] 3.17 Messaging
  - [ ] 3.17.1 R10: refusal ALWAYS messages, naming the variable, the value, the accepted band, and `git checkout -- .claude/hooks/memory-backstop.sh`
  - [ ] 3.17.2 R9: remedies in narrow-first order -- `systemctl --user stop soleur-agent-<pid>.scope`, then `systemctl --user set-property --runtime soleur-agent-<pid>.scope MemoryHigh=infinity MemoryMax=infinity` (the `--runtime` flag is MANDATORY), and only last the fleet-wide `systemctl --user stop soleur.slice` with its consequence stated
  - [ ] 3.17.3 R11: fourth edge-trigger -- first SessionStart where the hook is present, a user bus exists, and the outcome is `skipped` emits one message (the never-worked case)
  - [ ] 3.17.4 Attribution wording must not claim causation (a slice-level kill can hit a bystander session)
- [ ] 3.18 Commit executable with `git update-index --chmod=+x .claude/hooks/memory-backstop.sh` -- exact path, NEVER a glob; verify `git ls-files -s` reports `100755`
- [ ] 3.19 `shellcheck` clean
- [ ] 3.20 Commit Phases 1-3 before anything arms the hook

## Phase 5: AC7 sweep + mutation battery

- [ ] 5.1 Implement the before/after sweep (T10): `memory.{high,max,swap.max,low,min}` for every cgroup under `/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/`, plus a directory inventory, plus a checksum of `~/.config/systemd/user.control/`
- [ ] 5.2 Run mutants M1-M7; every mutant killed by a NAMED assertion, recorded per mutant
- [ ] 5.3 Confirm M4 (cap the parent slice via `SetUnitProperties("app.slice"...)`) turns the sweep RED -- this is the mutant that defeated #7151's check

## Phase 6: ADR + C4 + docs

- [ ] 6.1 Write `knowledge-base/engineering/architecture/decisions/ADR-158-memory-backstop-via-systemd-transient-scopes.md`
  - [ ] 6.1.1 `## Alternatives Considered` names raw-cgroup writes, `ulimit -v`, `memory.high`-only, `oom_score_adj`, the `soleur-claude` wrapper, and the static slice unit file -- each with the measurement that refuted it
  - [ ] 6.1.2 Record that `ManagedOOMPreference=avoid` is a property-level mitigation whose runtime efficacy is UNVALIDATED (oomctl monitors zero cgroups); do not present it as verified
  - [ ] 6.1.3 If `/ship` renumbers the ordinal, sweep plan + tasks + AC14 in the same edit
- [ ] 6.2 Apply the five `.c4` edits to `model.c4` and `views.c4`
  - [ ] 6.2.1 Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`
- [ ] 6.3 Add hook rows to `.claude/hooks/README.md` (SessionStart, telemetry sink, kill switch)
  - [ ] 6.3.1 Document remedies in narrow-first order (R9)
  - [ ] 6.3.2 R12: state literally that if `SOLEUR_DISABLE_MEMORY_BACKSTOP` is set, you are unprotected and nothing will tell you
- [ ] 6.4 Add `.claude/.memory-backstop*` to `.gitignore` (per-sink wildcard convention)

## Phase 7: Validation

- [ ] 7.1 `scripts/test-all.sh` log shows both new suites ran by name (AC12a: green with `[live: SKIPPED]` and the skipped-count assertion; AC12b on the operator box: green with `[live: yes]`)
- [ ] 7.2 Kill-mechanism proof at 256 MB with a SENTINEL process in the scope (T14) -- never at the real cap
- [ ] 7.3 Record the live arm into the PR body VERBATIM as command-plus-output: unit list, the slice's four properties, an MCP child's cgroup, the last log line

## Phase 4 (MOVED -- runs LAST): wire the consumer

- [ ] 4.1 Append to the existing `SessionStart` block in `.claude/settings.json` using the exact sibling shape (bare path, no interpreter, no args)
  - [ ] 4.1.1 Do NOT attempt `export SOLEUR_DISABLE_MEMORY_BACKSTOP=1` from a Bash tool call -- it is a NO-OP (hooks inherit the Claude Code process env, not a tool subshell's). If a kill switch is needed, use the `env` block already in `.claude/settings.json`
- [ ] 4.2 Re-run the Phase 1 gate: now 34 paths, still green (pure static check -- arms nothing)
- [ ] 4.3 Exercise the production invocation: reconstruct the command string FROM `settings.json`, substitute `$CLAUDE_PROJECT_DIR`, run with a SessionStart payload on stdin
- [ ] 4.4 AC17 -- trigger a REAL SessionStart (fresh `claude` launch or `/clear` in a live session) and assert a new jsonl line whose `pid` is a `claude` PID not spawned by the harness or by 4.3, with `ts` postdating the wiring. This is the only check that reads the actual invariant
- [ ] 4.5 AC18 -- spawn a child AFTER first adoption, re-run the hook, assert the new child's cgroup equals the scope (re-sweep proof)

## Phase 8: Close-out

- [ ] 8.1 PR body states the residual (~45 s of 100 % CPU under a cap), the D11 denominator gap, the D3 `active (abandoned)` hole, the bystander-attribution caveat, and the older-worktree convergence gap; `Closes #7166`
- [ ] 8.2 File tracking issues for every deferral in the plan's Non-Goals section (sweep-all adoption, plugin-surface promotion, operator-digest proof-of-life line)
