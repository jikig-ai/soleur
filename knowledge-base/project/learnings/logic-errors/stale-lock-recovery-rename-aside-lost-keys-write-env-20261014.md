---
module: community setup scripts (write-env)
date: 2026-10-14
problem_type: logic_error
component: tooling
symptoms:
  - "write-env with 3+ concurrent writers against a dead-owner lock exits 0 for all of them but the .env lost keys"
  - "stress harness reported lost keys that were really harness artifacts (subshells sharing $$)"
  - "dead-pid fixture was read as an ownerless lock: each round waited ~3.5 s, owner re-read never exercised"
root_cause: async_timing
resolution_type: code_fix
severity: high
tags: [concurrency, mkdir-lock, stale-lock, test-harness, review-seats, argv-bearer-sweep]
---

# Learning: stale-lock recovery by rename-aside lost keys; the harness lessons around it

PR #10185 (PR A of the argv-bearer follow-ups, umbrella #9757).

## Problem

`_wenv_write` (byte-identical in four community setup scripts) serialized `.env` edits with an owner-pid
`mkdir` lock. The first stale-lock recovery claimed the lock by renaming it aside and putting it back. With
three or more waiters against a dead-owner lock two of them could both believe they held it: every writer
exited 0 and keys were lost. A two-writer row could not see it.

## Solution

- Recovery is serialized by a second `mkdir` mutex `<.env>.lock.d.recover`. The winner re-reads the lock's
  owner under the mutex and removes the lock only if that read is a dead pid, or if the snapshot and the
  re-read (after a short pause) both found no pid. A lock whose owner turned from a dead pid into nothing
  has changed hands and is left alone (fixes the 0.3 s-pause deletion of a live lock under load).
- Nothing is renamed away. The re-read narrows the race window; it is not a compare-and-swap, and the
  comments now say so.
- `env_lock_not_dir` uses one stat (`-L || -f`): `-e && ! -d` reported a lock directory removed between the
  two stats as "not a directory".

## Key Insight

1. A lock-recovery design is only proven by N>=3 writers as separate processes against a dead-owner lock,
   with the unmutated control run first and each mutation shown to land. Measured after the fix: 0 lost over
   1,400 rounds (3/5/8 writers), and 0 lost in 25 rounds of 8 writers under 16 CPU spinners.
2. In bash a `( ... ) &` subshell shares `$$` with its parent, so writers must be separate `bash` processes
   or the owner-pid logic is not exercised.
3. A fixture that writes a pid must end in a newline: `read -r` returns non-zero at EOF and discards the
   value, so the lock took the ownerless path (30 polls, ~3.5 s per round, ~230 s of a 400 s suite) and the
   dead-pid branch with several racers was never run.
4. A mutation that cannot move a row is un-run, not survived: the test-design seat showed that removing the
   owner re-read stayed green until the fixture was fixed.

## Session Errors

- **Rename-aside recovery lost keys with 3+ waiters (P1, found by review)** - Recovery: second mkdir mutex with owner re-read - Prevention: stress any lock-recovery design with N>=3 separate-process writers before review.
- **First stress harness used `( ... ) &` subshells sharing `$$`** - Recovery: one `bash` process per writer - Prevention: see Key Insight 2.
- **Dead-pid fixture had no trailing newline** - Recovery: `printf '%s\n'` - Prevention: assert the precondition the fixture claims (the lock is read as a dead pid, not as ownerless).
- **0.3 s empty-owner pause deleted a live lock under load** - Recovery: snapshot-vs-re-read rule - Prevention: when a re-read under a mutex disagrees in kind with the snapshot, treat the lock as changed hands.
- **Fix agent died on a rate limit with partial work** - Recovery: reconciled the tree by hand and re-verified with the stress harness and mutations - Prevention: re-verify a half-landed agent edit before trusting any of it.
- **`/usr/bin/time` missing, background runs wrote RC=127** - Recovery: bash `$SECONDS` - Prevention: time with `$SECONDS`.
- **Review seats had side effects: one polluted the worktree `.env`, one ran a real read-only Sentry GET** - Recovery: `.env` repaired, disclosed in the PR body - Prevention: brief seats report-only on scratch copies and forbid live credentialed probes (the brief did; the seat's own tooling still reached them).
- **Ratchet lane REDs were scratch-environment artifacts** (`operator-script.test` template-trap rows and `fixture-dir-operand-assert` GUARD 3 fail identically on pristine main when the scratch sits under `~/.cache` with a `~/.git`) - Recovery: re-ran on a `git archive` of origin/main, 4 failed there too; ran the other suite in-tree, green - Prevention: re-measure on the base before blaming the diff.
- **Technical-ruling gate failed on malformed Class cells** - Recovery: normalised the cells and obtained a CTO ruling - Prevention: run the gate's own lint on the table before the gate.
- **CONCUR gate DISSENTed on a bundled follow-up filing** - Recovery: dropped one item, converted cheap strings inline, filed two corrected issues (#10274, #10275) - Prevention: one cause per follow-up issue.
- **`pgrep -f` blocked by a hook; a stray `cd` shifted the cwd** - Recovery: pgrep without `-f`, absolute paths - Prevention: absolute paths in every Bash call.
