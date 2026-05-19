---
date: 2026-05-12
module: session-state (bash hooks lib)
problem_type: integration_issue
component: bash_concurrency_primitives
symptoms:
  - "Sibling cleanup-merged reaps an operator's active worktree mid-flight"
  - "Wrapped CLI invocations bypass PreToolUse hook regex"
  - "PID-reuse race when releasing key=value pidfile-style leases"
  - "date -d natural-language input causes forever-active lease (DoS)"
  - "Bash signal traps don't fire when blocked on a foreground child"
root_cause: cross-process-coordination-primitives-need-careful-pairing-with-existing-hook-and-test-infrastructure
severity: high
tags:
  - concurrency
  - flock
  - bash-traps
  - hooks
  - leases
  - claude-bg
  - sibling-race
related:
  - 2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md
  - 2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md
pr: 3689
issue: 3690
plan: knowledge-base/project/plans/2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md
---

# Cross-Session Lock + Lease Bash Primitives — Implementation Gotchas

## Problem

The 2026-04-21 incident class — a sibling Claude Code SessionStart hook (or `cleanup-merged` workflow gate) reaping an operator's active worktree — only protected itself via a `$PWD`-equals-worktree-path check. Sibling processes hit a different `$PWD`, so they happily reaped a live worktree. With `claude --bg` (Agent View) shipping, that "rare" race becomes a routine failure mode.

Implementing the fix surfaced six **non-obvious** integration gotchas across hooks, tests, and skill prose. None were caught at plan-review time (DHH + Kieran + code-simplicity + spec-flow-analyzer); all surfaced only at implementation + 11-agent post-implementation review.

## Solution

`.claude/hooks/lib/session-state.sh` adds: per-name `flock` locks (dynamic `exec {fd}>>file` FDs), key=value lease files (`mktemp + mv` atomic write, validated worktree-name path, `started_at`-pinned release-guard), `headless_or_stderr` routing (TTY-aware), and a `with_lock <name> <timeout> -- <cmd>` CLI shim for SKILL.md callers. `worktree-manager.sh` calls `acquire_lease + _register_lease_release_trap + git push -u + ls-remote verify` on `feature` creation; `cleanup_merged_worktrees` wraps in `cleanup-merged` lock + reap loop checks `is_lease_active` + 10-min recent-commit grace. Four skills wrap `gh pr merge --auto` in `with_lock merge-main 600`; `pre-merge-rebase.sh` wraps `git merge origin/main` in `rebase-main` lock and routes 4 stderr emissions through `headless_or_stderr`.

## Key Insights — Sharp Edges discovered

### SE1 — Shell wrappers bypass PreToolUse hooks unless regex includes `--`-separator

`pre-merge-rebase.sh`'s command-detection regex anchored to `(^|&&|\|\||;)\s*gh\s+pr\s+merge`. The new wrapped form is:

```bash
bash .claude/hooks/lib/session-state.sh with_lock merge-main 600 -- gh pr merge ...
```

The `gh pr merge` substring is preceded by ` -- `, not by `^` or a chain operator. The regex doesn't match → hook exits 0 → review-evidence gate AND origin/main auto-sync are silently bypassed. This was the #1 P1 finding at review time.

**Fix:** extend regex alternation to include `\s--\s`:

```bash
(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)
```

**Generalizable rule (routed to plan + review skills):** *When a plan introduces a shell wrapper around a command that any PreToolUse hook intercepts, the plan must enumerate every hook whose regex anchors to start-of-string or chain-operators (`grep -nE 'matcher.*\bcmd\b' .claude/hooks/*.sh`) and propose the regex extension. The review phase must verify the regex matches the wrapped form via `echo "$WRAPPED_CMD" | grep -qE "<regex>" || echo BYPASS`.*

### SE2 — pidfile lease release needs `started_at` to survive PID reuse

`release_lease` initially checked only `pid == $$ && hostname == $HOSTNAME`. A new shell that inherits the dead shell's numeric PID (post-crash, PID-namespace recycle) could `release_lease worktree-X` and delete an active sibling's lease. Sibling `cleanup-merged` then sees no lease and reaps the worktree — the very incident class the lease was added to prevent.

**Fix:** stash `started_at` from acquire in a per-shell associative array; compare on release. Three-factor identity (pid + hostname + started_at) closes the PID-reuse window. Same defense applies to any pidfile-style primitive.

### SE3 — `date -d "$X"` accepts natural language; anchor X before passing

`is_lease_active` parsed `started_at` via `date -d "$lease_started" +%s`. An attacker (or stale corrupted file) writing `started_at=next year` yields a future epoch; combined with a "clock-skew = fresh" branch, the lease is **forever-active** and blocks `cleanup-merged` indefinitely.

**Fix:** anchor `started_at` to strict ISO-8601-Z (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`) BEFORE passing to `date -d`. Drop the negative-age "fresh" branch — treat skew as stale (let the 24h orphan sweep handle it). Same class as URL/regex input validation.

### SE4 — Bash signal traps don't fire when bash is blocked on a foreground child

T7 (SIGTERM trap) initially failed: bash with `trap '...' TERM` then `sleep 30` (foreground) does NOT run the trap on SIGTERM — bash dies before processing the signal because it's waiting on the foreground `sleep`.

**Fix:** `sleep 30 & wait` — wait is interruptible and returns control to bash before the trap runs.

**Generalizable:** any bash script using `trap '...' EXIT INT TERM HUP` and a long-running operation must use `<op> & wait`, OR ensure the script exits naturally after a short operation. Tests asserting trap behavior need this pattern.

### SE5 — `script -q -c "... 2>FILE"` defeats TTY checks inside the pty

T8 foreground branch initially tested via `script -q -c "headless_or_stderr ... 2>$ERR_FILE" /dev/null`. Inside the pty, the per-call `2>$ERR_FILE` redirected fd 2 to a regular file — `[[ -t 2 ]]` saw a file, not a TTY, and chose the headless branch. Test failed for the wrong reason.

**Fix:** capture the FULL pty output via the typescript file (`script -q -c "..." "$TYPESCRIPT"`), then grep that. Don't redirect fds inside the pty.

### SE6 — Env-var assignments before a pipe apply only to the left side

```bash
A=1 B=2 cmd1 | cmd2  # A/B set only for cmd1
```

The headless reproducer test set `CLAUDECODE=1 SOLEUR_SESSION_STATE_ROOT=...` before `merge_payload "$WORK" | "$HOOK"`. Only `merge_payload` saw the env; `$HOOK` ran with the parent's env. Test failed (log file never written).

**Fix:** `export` before the pipe; `unset` after if needed.

## Session Errors

1. **T6 (flock-missing test) failed with rc=127** — `PATH=/empty/dir bash -c` couldn't find `bash` itself. **Recovery:** build sandbox PATH with all standard tools (`ln -s $(command -v X) $SANDBOX/`) minus flock. **Prevention:** sandbox-PATH pattern for "missing binary" tests, not empty-PATH.

2. **T7 SIGTERM trap not firing** — see SE4 above. **Prevention:** documented; tests use `sleep & wait`.

3. **T8 foreground branch test failure** — see SE5 above. **Prevention:** documented.

4. **Lease reproducer passed vacuously** — invocation from inside victim worktree hit the existing `$PWD`-equals-worktree-path guard. **Recovery:** create a sibling actor worktree, invoke `cleanup-merged` from there. **Prevention:** RED tests for "sibling reaps X" must run from a sibling context, not from X itself.

5. **Recent-commit grace masked the lease guard** — adding both `is_lease_active` AND a 10-min recent-commit grace means removing only the lease still leaves the recent-commit guard active, producing vacuous green. **Recovery:** date the test's commit `2025-01-01` to bypass the 10-min window and isolate the lease guard under test. **Prevention:** mirrors the existing `cq-write-failing-tests-before` rule — when multiple guards exist, RED tests must isolate the gate under test.

6. **log-rotation.test.sh Test 14 regression** — after stderr conversion, CLAUDECODE=1 (Claude Code env) + non-TTY stderr → headless route → test grep'd empty stderr. **Recovery:** unset CLAUDECODE inside the test block + update grep to match new `failed to archive` format. **Prevention:** when refactoring stderr semantics, sweep all dependent test files for grep-against-stderr patterns.

7. **Headless reproducer env-var dropping** — see SE6. **Prevention:** documented.

8. **Headless reproducer used wrong command** — initial payload was `git merge origin/main`, but `pre-merge-rebase.sh`'s early-exit filter only matches `gh pr merge`. **Recovery:** change payload. **Prevention:** read a hook's command-filter regex before authoring its test.

9. **TS test compat regression** — 5 failures in `test/pre-merge-rebase.test.ts` because `process.env.CLAUDECODE` propagated through `cleanEnv` into spawned hooks. **Recovery:** strip `CLAUDECODE` from cleanEnv alongside the existing GIT_DIR/etc. **Prevention:** when adding env-driven routing to a hook, audit existing test harnesses for env-propagation patterns.

10. **concurrent-ship.test.sh T1 grep too strict** — pattern `gh pr merge --auto` missed the actual SKILL.md ordering `--squash --auto`. **Recovery:** order-agnostic grep. **Prevention:** grep patterns asserting against config text should be flag-order-agnostic.

11. **Hook bypass found at review time, not implementation time** — see SE1. The bypass was invisible during plan + implementation because the plan documented the wrapped invocation pattern but didn't trace it through the existing hook's regex. **Prevention:** route SE1 to plan + review skills (see Routing below).

## Cross-references

- Seed incident: [`2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`](./2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md) — the original `$PWD`-only-guard that this PR closes.
- Adjacent class: [`2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`](./2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md) — same "consumer doesn't enforce producer's contract" failure mode but for TypeScript types.
- Plan + implementation: PR #3689 / issue #3690 / plan `knowledge-base/project/plans/2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md`.

## Routing

- **SE1 (wrapped-CLI hook bypass)** — routed to `plugins/soleur/skills/plan/SKILL.md` Sharp Edges + `plugins/soleur/skills/review/SKILL.md` Sharp Edges. Domain-scoped per AGENTS.md placement gate (specific to PreToolUse hooks + shell wrappers, not a cross-cutting session invariant). AGENTS.md is over budget (24622 > 22000 critical threshold) — adding new top-level rules is forbidden until existing rules are demoted.
- **SE4 (sleep & wait for traps)** — bash-testing reference (no canonical location yet; bundled here).
- SE2 / SE3 / SE5 / SE6 — covered in this learning; no skill edits needed (specific to this primitive's design, not a recurring pattern across other skills).
