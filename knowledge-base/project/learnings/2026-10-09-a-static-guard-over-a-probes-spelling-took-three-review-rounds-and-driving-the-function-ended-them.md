# Learning: a static guard over a probe's spelling took three review rounds; driving the extracted function ended them

## Problem

The `rehearse (classic)` leg of `zot-image-mirror.yml` failed once with "dockerd could still pull from
ghcr.io after the deny" (run 37863203385, attempt 1; attempt 2 passed). The probe was
`if timeout 120 sudo docker pull ... >/dev/null 2>&1; then die ...`, so the pull's output was discarded and the
cause was never recorded. Go's `net` package caches the hosts file for 5 s without a stat
(`src/net/hosts.go`, `cacheMaxAge = 5 * time.Second`), which fits a deny written within 5 s of a dockerd read,
but nothing measured that: the hypothesis is unconfirmed.

The fix was small (`assert_dockerd_denied`: a 7 s wait, a captured pull, diagnostics on a successful pull). The
guard for it was not. The operator brief said to add rows to "the existing suite if one exists"; none existed for
the probe, so the first guard was a static `chk_probe` inside `web-ghcr-deny.test.sh` (one pull, no `/dev/null`,
a sleep before it). Three review rounds then found it was pinning spelling, not wiring:

1. Round 1 (8 seats): `|| true` at the call site, a `dk pull` second pull, a sleep in a dead branch and a pull
   status forced to success all passed it; no mutation rows existed.
2. Fix round (3 seats): after the rewrite, deleting the final `return 1`, inverting the status test and deleting
   the timeout branch still passed, because the timeout branch the fix added carried its own `return 1`.
3. Verification pass: a `function`/alias/`eval` redefinition of the probe passed, and four mutations had no row.

## Solution

Keep the cheap static pins that give a readable message (single pull, no `/dev/null`, one `HOSTS_CACHE_WAIT_S`
assignment, anchored deny and call lines, `|| die` on the continuation line, the probe name on exactly two code
lines), and add `chk_probe_run`: source the extracted `assert_dockerd_denied` and DRIVE it against shimmed `sudo`,
`docker`, `sleep` and `timeout`. A refused pull must return 0 after a sleep of at least 6 s that precedes the pull;
a successful pull and a timed-out pull must return 1. Mutation rows 28-44 each revert one property; the suite is
56/0 with an exact floor.

## Key Insight

A static check over a function's text can only ever pin the spellings its author imagined, and each review round
finds another spelling. When the property is "this function returns X for input Y after doing Z first", extract
the function and run it: one shimmed run covers the whole family of edits (deleted branch, inverted test, forced
status, dead-branch sleep, reassigned wait) at once, where the static pins needed one regex per edit. Keep the
static pins only for what execution cannot see (the call site and the definition count).

Two corollaries seen in the same PR. A fix that adds a branch can satisfy an existing coarse assertion on its own
(the timeout branch's `return 1` satisfied "has a `return 1`"), so re-run the previous round's survivors against
the new tree rather than assuming they still survive or die. And a mutation row whose `sub` anchor is the first
occurrence of a string can land in a comment (`&& rc=0 || rc=$?` appeared in the header comment first), so the
row survives for the wrong reason; anchor rows on the code line.

## Session Errors

1. **Planner's first plan write blocked by a hook matching prose text** (forwarded from session-state.md). —
   Recovery: reworded the prose. — **Prevention:** none beyond the hook working; do not paste command strings
   into plan prose.
2. **Planner skipped community discovery and the full deepen fan-out** (forwarded). — **Prevention:** the
   post-implementation panel covered the same lenses; no rule change.
3. **A Monitor `until` loop used `pgrep -f "print-selection"`, which matched its own command line and never
   exited (expired after 5 min with no events).** — Recovery: read the background task's output file directly. —
   **Prevention:** already documented in `work/SKILL.md` Common Pitfalls (rc/marker files, never `pgrep -f`);
   the `pkill-self-match-guard.sh` hook covers Bash, not Monitor commands. One-off here.
4. **`sleep 45` followed by a `cat` was blocked by the foreground-sleep hook.** — Recovery: ended the turn with
   a `<stop>BLOCKED` tag and waited for the task notification. — **Prevention:** none needed; the hook did its job.
5. **A chained command containing `git stash list` was blocked.** — Recovery: dropped it. — **Prevention:**
   none needed (`hr-never-git-stash-in-worktrees` hook).
6. **An unbounded repo-wide `grep -rIl "explicit go"` hit the 120 s limit and moved to background.** — Recovery:
   discarded the result; read the issue body instead. — **Prevention:** scope searches to the paths that can hold
   the answer (`hr-never-run-commands-with-unbounded-output`).
7. **Mutation row 34's anchor landed in a header comment, so it SURVIVED.** — Recovery: re-anchored on the code
   line. — **Prevention:** `row()` already reports a survivor; anchor `sub` strings on code lines and check the
   first occurrence with `grep -n` before adding the row.
8. **First guard design (static only) needed three review rounds.** — Recovery: added the behavioural drive. —
   **Prevention:** when the property is a function's behaviour, write the shimmed drive first and the static pins
   second. Recorded here; no new AGENTS.md rule (the review skill already lists the "fix's verification inherits
   the defect's framing" class).
9. **The session ended mid-way through a suite run, losing its result.** — Recovery: confirmed the on-disk edit
   and re-ran. — **Prevention:** after a session restart, re-run the last unknown tool call instead of assuming
   it passed.

## Tags
category: workflow-issues
module: apps/web-platform/infra
