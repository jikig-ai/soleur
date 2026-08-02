# Tasks: feat-one-shot-7166-memory-backstop-systemd-slice

Plan: `knowledge-base/project/plans/2026-08-02-feat-memory-backstop-systemd-transient-scope-plan.md`
Issue: #7166 · Threshold: `single-user incident` (CPO sign-off recorded in the plan's Domain Review)

Ordering is load-bearing: the class gate ships before the file it gates, and the hook (contract)
ships before `settings.json` (consumer).

## Phase 0: Preconditions (re-verify on the box; do not re-derive)

- [ ] 0.1 `systemctl --version` -- systemd >= 257 (plan measured 259)
- [ ] 0.2 `StartTransientUnit` adopting a throwaway `sleep` PID returns rc=0
  - [ ] 0.2.1 Capture probe PIDs with `$!` -- NEVER `pgrep -f <pattern>` (matches the probing shell's own command line; produced a false negative at plan time)
  - [ ] 0.2.2 Never probe with a live `claude` PID
- [ ] 0.3 Confirm `OOMPolicy` default on a transient scope reads `stop`; if it reads `continue`, correct the rationale comment rather than deleting it
- [ ] 0.4 `SetUnitProperties(runtime=true)` writes only `/run/user/<uid>/systemd/user.control/`; `~/.config/systemd/user.control/` untouched (clear stale `soleur*` drop-ins first)
- [ ] 0.5 `BindsTo=` reap behaviour in a synthetic parent/child pair
- [ ] 0.6 Multi-PID adoption moves every PID passed
- [ ] 0.7 Record `free -m` and the `claude` fleet RSS total into the PR body (the cap arithmetic needs a stated baseline)
- [ ] 0.8 `oomctl` -- record monitored-cgroup lists and swap-used %; confirm `ManagedOOMPreference=avoid` is accepted on a `--user` transient scope
- [ ] 0.9 Confirm every hook path named in `.claude/settings.json` is `100755`; fix any regression in this PR rather than weakening the gate
- [ ] 0.10 `rmdir` any orphaned raw cgroup dirs under `app.slice` (a leaked dir makes the AC7 sweep read dirty)
- [ ] 0.11 Cleanup contract: stop every probe unit and remove any `soleur*` drop-in under both `user.control` locations

## Phase 1: Exec-bit class gate (AC1)

- [ ] 1.1 Create `.claude/hooks/settings-hook-exec-bit.test.sh`
  - [ ] 1.1.1 Assert the INDEX mode via `git ls-files -s`, not `test -x`
  - [ ] 1.1.2 Fail loudly on an empty listing (anti-vacuous guard)
  - [ ] 1.1.3 Minimum-cardinality floor of 25
- [ ] 1.2 Derive the hook list across ALL hook events with `jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command'` then strip the `"$CLAUDE_PROJECT_DIR"/` prefix
- [ ] 1.3 Assert every derived path is tracked AND mode `100755` (an untracked named path is also a failure)
- [ ] 1.4 Confirm green on the current tree, then prove non-vacuity by flipping one hook to `100644` in a scratch copy and observing RED; restore
- [ ] 1.5 Do NOT widen `scripts/followthrough-exec-bit.test.sh` (scope pinned; five `.claude/hooks/**` files are legitimately `100644`)

## Phase 2: Backstop suite (RED)

- [ ] 2.1 Create `.claude/hooks/memory-backstop.test.sh` against the not-yet-written hook; confirm it fails for the right reason
- [ ] 2.2 Live-arm gate: probe the user bus once; on absence print `SKIP: no user systemd bus -- <N> live assertions not run` and run the pure-fixture arm
  - [ ] 2.2.1 `RESULT:` line carries `[live: yes|SKIPPED]` so a permanently-skipped arm is visible
- [ ] 2.3 All test units in a namespaced `soleurtest-agents.slice` with `soleurtest-*` scope names; `trap`-based teardown stops every unit and removes every drop-in created

## Phase 3: The hook (GREEN, contract)

- [ ] 3.1 Create `.claude/hooks/memory-backstop.sh` mirroring `supabase-loopback-warn.sh`: `#!/usr/bin/env bash`, `set -uo pipefail` (NOT `-e`), `PROJECT_DIR` fallback, why-comments, `exit 0` on every path
- [ ] 3.2 Honour `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` first; declare all four cap values in one `readonly` block
- [ ] 3.3 Early silent exits with distinct logged reasons: no `busctl`; no bus socket (`[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]`); bus probe fails
- [ ] 3.4 Discover the `claude` PID: label-anchored `PPid:` from `/proc/<pid>/status`, walk bounded to 8 hops
  - [ ] 3.4.1 Positive identity match across exe glob / `$CLAUDE_CODE_EXECPATH` / `comm`; log which signal matched
  - [ ] 3.4.2 Treat an empty `readlink /proc/<pid>/exe` as no-match; adopt nothing on failure
  - [ ] 3.4.3 Reject PID 0, PID 1, self, and the terminal scope leader
- [ ] 3.5 Collect the full descendant PID set in one bounded `/proc` pass (max 256 PIDs)
- [ ] 3.6 Discover the terminal scope from `/proc/<claude-pid>/cgroup` basename; require a `.scope` suffix; quote the name
- [ ] 3.7 Re-entry branches
  - [ ] 3.7.1 On `rc=1`, verify membership: `/proc/<claude-pid>/cgroup` basename must equal the scope name
  - [ ] 3.7.2 On membership mismatch (PID reuse), append `/proc/<pid>/stat` field 22 start-time to the scope name and retry once; log `reason=pid_reuse_disambiguated`
  - [ ] 3.7.3 When already adopted, read `BindsTo` from the existing unit and preserve it -- never re-derive the terminal scope from our own scope
- [ ] 3.8 Read `memory.events` + `memory.peak` in one pass for kill attribution and near-miss
- [ ] 3.9 Validate all four cap values BEFORE any D-Bus call; refuse-and-log on out-of-range
- [ ] 3.10 Apply slice properties first: `SetUnitProperties(slice, runtime=true, MemoryHigh, MemoryMax, MemorySwapMax, ManagedOOMPreference=avoid)`
- [ ] 3.11 Then `StartTransientUnit(scope, ...)` with `PIDs`(tree), `Slice`, `MemoryHigh`, `MemoryMax`, `MemorySwapMax`, `OOMPolicy=continue`, `BindsTo`, `After`
- [ ] 3.12 Redirect every `busctl` call's stdout to `/dev/null` (it prints the job object path, which a SessionStart hook injects into session context)
- [ ] 3.13 Wrap every external call in the portable `timeout` idiom (`TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 5)`)
- [ ] 3.14 Append one JSON line to `.claude/.memory-backstop.jsonl` after `rotate_if_needed`; never record the session id
- [ ] 3.15 Emit `systemMessage` only on the edge-triggered conditions, stamped on (host, hook-version, limit-set); name the raise command and the disable variable in the kill message
- [ ] 3.16 Commit executable with `git update-index --chmod=+x .claude/hooks/memory-backstop.sh` -- exact path, NEVER a glob; verify `git ls-files -s` reports `100755`
- [ ] 3.17 `shellcheck` clean

## Phase 4: Wire the consumer

- [ ] 4.0 `export SOLEUR_DISABLE_MEMORY_BACKSTOP=1` in the `/work` shell for the rest of the session (self-hosting hazard); do not start this phase until 3.17 is green
- [ ] 4.1 Append to the existing `SessionStart` block in `.claude/settings.json` using the exact sibling shape (bare path, no interpreter, no args)
- [ ] 4.2 Re-run the Phase 1 gate: now 34 paths, still green
- [ ] 4.3 Exercise the production invocation: reconstruct the command string FROM `settings.json`, substitute `$CLAUDE_PROJECT_DIR`, run with a SessionStart payload on stdin
  - [ ] 4.3.1 Read back `systemctl --user status soleur-agent-<pid>.scope`
  - [ ] 4.3.2 Read back `/proc/<mcp-pid>/cgroup` for a live MCP child (tree-adoption proof)

## Phase 5: AC7 sweep + mutation battery

- [ ] 5.1 Implement the before/after sweep: `memory.{high,max,swap.max,low,min}` for every cgroup under `/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/`, plus a directory inventory, plus a checksum of `~/.config/systemd/user.control/`
- [ ] 5.2 Run mutants M1-M9; every mutant killed by a NAMED assertion, recorded per mutant
- [ ] 5.3 Explicitly verify the cap-the-parent-slice mutant (`SetUnitProperties("app.slice"...)`, `...("user@<uid>.service"...)`) turns the sweep RED

## Phase 6: ADR + C4 + docs

- [ ] 6.1 Write `knowledge-base/engineering/architecture/decisions/ADR-155-memory-backstop-via-systemd-transient-scopes.md`
  - [ ] 6.1.1 `## Alternatives Considered` names raw-cgroup writes, `ulimit -v`, `memory.high`-only, `oom_score_adj`, the `soleur-claude` wrapper, and the static slice unit file -- each with the measurement that refuted it
  - [ ] 6.1.2 If `/ship` renumbers the ordinal, sweep plan + tasks + AC14 in the same edit
- [ ] 6.2 Apply the five `.c4` edits to `model.c4` and `views.c4`
  - [ ] 6.2.1 Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`
- [ ] 6.3 Add hook rows to `.claude/hooks/README.md` (SessionStart, telemetry sink, kill switch) and document the `systemctl --user stop soleur.slice` fallback kill path
- [ ] 6.4 Add `.claude/.memory-backstop*` to `.gitignore` (per-sink wildcard convention)

## Phase 7: Validation

- [ ] 7.1 `bash scripts/test-all.sh` fully green; log shows both new suites ran (no `run_suite` line needed -- the `.claude/hooks/*.test.sh` glob covers them)
- [ ] 7.2 Record the live arm on the operator's box into the PR body: unit list, the slice's four properties, `oomctl`, an MCP child's cgroup, the last log line
- [ ] 7.3 Kill-mechanism proof at 256 MB -- never at the real cap
- [ ] 7.4 PR body states the residual (~45 s of 100 % CPU under a cap), the D11 denominator gap, and the D3 `active (abandoned)` hole; `Closes #7166`
- [ ] 7.5 File tracking issues for every deferral in the plan's Non-Goals section (sweep-all adoption, plugin-surface promotion, operator-digest line)
