---
module: scripts/test-all.sh + scripts/test-all-affected.test.sh
date: 2026-09-25
problem_type: logic_error
component: shell_process_hygiene
symptoms:
  - "a deleted-cwd print-affected-set run exited 4 in ~1s but its $( ) consumer blocked ~14 min in anon_pipe_read"
  - "the watchdog's own pgrep -P sweep TERM'd the watchdog subshell before it ever signalled the runner"
  - "_wait_bound inside $( ) waited out its full timeout on a runner that had already exited"
  - "an EXIT-trap-free failure path left a sleep 900 orphaned holding the receipt pipe"
root_cause: subprocess_lifetime_misattribution
resolution_type: code_fix
severity: high
status: closed
tags: [bash, watchdog, fd-inheritance, pipe-eof, signals, pgrep, worktree-deletion, test-harness]
synced_to: [review]
issue: 8761
pr: 8765
---

# The watchdog fixing the spin held the pipe it guarded

#8761: two `test-all.sh --print-affected-set` processes spun ~97% CPU for ~5h
after their worktree was deleted mid-run. The fix (fail-fast on a deleted cwd +
a wall-clock watchdog) was built and reviewed in one session, and the review
panel kept finding the SAME defect class inside the fix: a child that outlives
its owner while holding an inherited fd. The learning is the list of ways that
shape recurs.

## What the incident actually was

Every git probe in the walk (`git diff`, `git ls-files`, `rev-parse`) fails
fast with ENOTDIR on a deleted-but-open cwd — errors swallowed by `|| true`,
so the worktree looked like an empty data source. Two failure shapes result:
silent truncated `exit 0` (reproducible — 267/301 receipts) and the 100%-CPU
spin (never reproduced on this HEAD; the fix targets the contract + a hard
bound, not an unlocated loop site).

The deleted-cwd probe MUST be path-based: `[[ -e . ]]`/`[[ -d . ]]`/`stat .`
resolve the retained inode and stay TRUE on a deleted-but-open directory.
`[[ -d "$PWD" ]]` resolves the path → fails. `git rev-parse --show-toplevel`
cannot join the guard: a LIVE non-git cwd is a legitimate degraded run
(test-all-group-affected's B3/B6 fail-open arms) — only the path being gone
is the refusal.

## The watchdog's own failure modes (each found by a different seat)

A `( sleep D; kill TERM top ) &` watchdog is naive in five directions:

1. **Killing the subshell does not kill its `sleep` child.** Disarm-by-kill
   orphans the sleep, which holds the inherited stdout pipe → the `$( )`
   consumer blocks until the deadline on a run that already exited. The fix
   is the `_tc_wait_heartbeat` pattern: `sleep & _wd_sleep=$!` + a TERM trap
   that kills the tracked child + `wait` gating the fire phase on a NATURAL
   sleep exit. (Observed live: an arm's `--affected` child blocked 14 min in
   anon_pipe_read on an orphaned `sleep 900`.)

2. **Disarm at the terminator only covers the clean exit.** `_wt_missing_die`
   — the fix's own primary path — exits 4 mid-walk, leaving the watchdog
   armed. The disarm belongs in the EXIT trap chain (`_enum_wd_disarm`), and
   the wholesale `trap - EXIT` at the terminator must still run the other
   cleanup members explicitly (that clear was silently skipping
   `_soleur_inc_cleanup` — every enumerate run leaked a tmpdir).

3. **`pgrep -P $TOP` lists the watchdog itself.** The watchdog subshell is a
   direct child of the runner. A children sweep that TERM'd "the walk's
   in-flight children" killed the watchdog first; its trap exited it, and the
   parent's TERM was never sent. Exclude `$BASHPID` — `$$` inside a subshell
   is the PARENT's pid.

4. **Kill-first, print-after.** A dead/undrained consumer pipe SIGPIPEs or
   stalls a `printf` — if it precedes the kill, the deadline never reaches the
   runner. `trap '' PIPE` + `|| true` on the prints makes the fire path
   output-independent.

5. **`kill -0` answers true on an unreaped zombie.** A parent that exits but
   isn't reaped keeps the liveness poll alive to the deadline. `ps -o stat=`
   `Z*` excludes the corpse; the same check in the disarm's reap-poll is what
   keeps the fast path fast (a zombie watchdog would otherwise burn the full
   2s bounded reap).

6. **TERM is maskable.** A caller that blocks SIGTERM leaves the watchdog's
   TERM trap undelivered — a bare `wait` in the disarm hangs to the deadline,
   then the watchdog's own blocked TERM fails and the KILL lands on a healthy
   run. Disarm = TERM + ~2s `kill -0`/stat poll + KILL escalation.

7. **Identity before kill.** `ps -o lstart=` captured at arm, compared at
   fire — a recycled pid never takes the kill. Polarity both ways matters:
   ps absent at arm → fire anyway (the deadline is the contract); baseline
   set but fire-time read empty while the pid lives → identity unverifiable,
   but the deadline still wins (ESRCH on a dead pid is harmless).

8. **The walk's children outlive the walk.** A wedged `git`/`cksum` child
   keeps burning CPU and holds the pipe. Kill fan-out must sweep `pgrep -P`
   children (see #3) — the runner shares the caller's process group, so
   `kill -- -$pgid` would take the harness with it.

## Test-side traps that cost cycles

- **`wait` inside `$( )` cannot observe the parent's jobs.** A bounded-wait
  helper invoked as `rc="$(_wait_bound $pid)"` runs in a subshell whose jobs
  table doesn't contain the child — it blocks to the timeout and reports 124
  on a run that exited cleanly. Bound-helpers must run in the main shell and
  return via a global.
- **`kill -0` polling can't see a zombie child** — the suite's own
  `_wait_bound` comment documents it; the same blindness applied to the
  watchdog's parent poll (finding 5 above).
- **A fixed `sleep N` offset for mid-walk deletion is load-fragile.** Poll an
  observable receipt instead; when the consumer is a `$( )` capture, interpose
  `| tee file` — the read-end still waits on every upstream writer (leaked
  sleep included) while making the first receipt visible.
- **`SECONDS` is inheritable.** An exported `SECONDS=99999` pre-trips any
  absolute-time deadline — baseline it (`_ENUM_T0=$SECONDS`) or scrub it.
- **`10#` or it isn't a number.** `(( 08 ))` is an octal error; the file's own
  TC_RUNTIME_CEILING_S parse documents this and the new knob had to carry the
  idiom over. `0` and >9-digit values needed explicit semantics too.

## Session Errors

1. **z6's fixed `sleep 2` deletion offset raced the trimmed walk** — landed
   after it finished, rc=0. **Prevention:** poll an observable event (tee'd
   receipt) rather than a wall-clock guess for "mid-walk".
2. **The `pgrep -P` self-kill shipped through a commit before a standalone
   repro caught it.** **Prevention:** any fan-out kill must name its own pid
   as a member of the victim set on first run — verify with xtrace before
   believing it.
3. **`/proc/*/cmdline` scanning matched the invoking `bash -c` wrapper and
   killed my own shell.** **Prevention:** the existing proc.sh rule already
   forbids `-f` self-matching — captured-PID plumbing (`& pid=$!`) is the only
   safe handle.
4. **`gh issue create` needed three retries** (unreadable --body-file path,
   fenced-directive vs HTML-comment format, missing meta/machinery label).
   **Prevention:** the directive grammar is `<!-- soleur:followthrough
   script=… earliest=… -->` as ONE comment; machinery findings take the
   `meta/machinery` label.
5. **A batched python replace died on a mismatched anchor mid-script** —
   misremembered `printf` vs `echo` — writing nothing. **Prevention:** grep
   the exact text before composing replaces, or apply edits incrementally.

## Prevention

- The class rule: **every backgrounded child inherits the parent's fds —
  enumerate what each inherits, and disarm means "kill the child AND its
  children," recursively if needed.** A subshell's own TERM trap is the only
  reliable reaper; the parent's EXIT trap is the only reliable disarm site.
- A bound that can be silenced is no bound: graceful check at the work
  boundary (named exit, attribution) + watchdog subshell (signal death) +
  parent-liveness poll inside the watchdog (consumer pipe release on
  untrappable death). All three are load-bearing; deleting any one reopens a
  distinct hole.
- `SOLEUR_ENUM_DEADLINE_S` (default 900s) is documented in `--help` and named
  inside the deadline error lines — a bound the operator can't discover is a
  bound the operator can't raise.

## Related

- Issue #8761, PR #8765; scope-out #8800 (census-sandbox write-through).
- 2026-09-22 fd-inheritance learning (#8579/PR #8596) — the same "enumerate
  every child that inherits the fd" lesson; this session added the
  "enumerate every child you'd KILL" corollary (the watchdog is one).
- `_tc_wait_heartbeat` in scripts/lib/test-contention.sh — the established
  tracked-sleep + TERM-trap pattern this converged on.
- #8621 (selector convergence) remains open and out of scope.
