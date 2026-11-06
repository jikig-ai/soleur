# Learning: a ledger that guards a clobber needs integrity pins of its own, and a "refresh" converges more than the pin

## Problem

Tracker #12146 item 2 asked for a refresh path for the Stage A auto-recovery workflow that
`constraint-scaffold` emits, because the script refuses to overwrite an existing artifact and installed
repos therefore keep a stale claude-code-action pin. The shipped design (CTO-ruled) is
`--refresh-stage-a`: replace exactly one file, and only when its sha256 is in a ledger of every
historical emission of the template; anything else exits 75 with the file untouched.

The 11-seat review found no P1, but every P2 was the same shape: the guard's *premises* were asserted in
prose and pinned by nothing.

## Solution / what the review changed

- **The ledger is a guard, so its integrity is part of the guard.** Row order is the rank (no
  downgrade), but the suite only checked that the current template's hash appeared *somewhere*. A
  duplicate hash makes a legitimate upgrade read as a downgrade; swapping two middle rows inverts the
  rank for installs of those eras; deleting a historical row turns an install into "unknown emission".
  Fixed by pinning in the suite: last row == current template, no duplicates, 64-hex shape, and the
  first five (immutable) rows as literals in order.
- **A refresh converges the file on the current template, which changes more than the pin.** The
  oldest ledger eras installed with `bun install`; the current template runs `npm ci`. The plan
  justified skipping a lockfile precondition with "the sibling `constraint-gates.yml` already runs
  `npm ci`" — false, because that sibling is refuse-only and was never refreshed. Added: refuse (75)
  when the target has no *tracked* `package-lock.json`, checked only when a write would happen so an
  already-current file still exits 0 (idempotent).
- **Check the physical path against a literal, not a re-resolved one.** Resolving `TARGET` with
  `pwd -P` made a symlinked `apps/` satisfy the equality check; the case only exited 67 because git
  refuses paths beyond a symlink. Build the expected directory from the already-physical `REPO_ROOT`
  plus the literal `TARGET_REL`, and rebind `dest` to its physical form after the check.
- **A helper-control block must count toward the row floor.** Unwinding the control rows from `cases`
  made deleting the whole block invisible to `MIN_ROWS`. Convert the deliberate failures to passes
  instead, so the control rows stay in the count.
- **The second-reviewer gate earned its keep.** A planned `deferred-scope-out` for a pre-existing
  `take_run_lock` race got a DISSENT (fix is small and this PR adds a third caller); the inline fix
  was ~8 lines plus three test rows and removed the need for an issue.
- **Ratchets count unproven write operands in production scripts too.** The new write sites needed the
  canonical `assert_fixture_dir` copy in the script; add a `die`-form check for the reachable subset
  (`/proc`, `/sys`, `/dev`) so the guard's silent exit 2 never surfaces.

## Key Insight

When a mode is safe *because* a data file (ledger, allowlist, manifest) says so, the data file's
order, uniqueness and shape are load-bearing and need assertions of their own; and any operation that
"refreshes to current" must list everything the current artifact does differently from the oldest
installed one (toolchain, install command, permissions), not just the value the ticket named.

## Session Errors

1. **`$TMPDIR` is unset in the Bash tool, so `> "$TMPDIR/x.log"` expanded to `/x.log`
   (Permission denied), three times** (a commit, a log fetch, a helper extraction). Recovery: re-ran
   with `mktemp -d -p /var/tmp`. **Prevention:** never write `$TMPDIR/...` in a Bash call; use
   `"$(mktemp -d -p /var/tmp)/name"` and echo the path.
2. **`cd ../../../..` from `scripts/` landed in `plugins/`, not the repo root**, so a relative
   `sed -i` failed (rc 127). Recovery: re-ran from the worktree root. **Prevention:** `cd "$(git
   rev-parse --show-toplevel)"` or absolute paths.
3. **A `grep -c` with an unescaped regex over prose returned 0 for text that was present.** Recovery:
   used a literal Python `count`. **Prevention:** count literals with `grep -F` or Python, never a
   hand-written regex over prose containing `*`, `(`, `.`.
4. **A new floor-bearing suite under a deferred directory grew the vacuity-floor ledger 47→48;
   found only when the affected gate ran.** Recovery: added it to `PROMOTED_FILES`. **Prevention:**
   work-skill bullet 6.7 already says to run `guard-vacuity-floor.test.sh` first, which names the
   `PROMOTED_FILES` remedy in its promotion note; run it before the first commit of any new floor-bearing
   suite under `plugins/soleur/skills/*/test/`, `apps/web-platform/infra/` or `.claude/hooks/`. Extending
   the bullet was tried and dropped: `work/SKILL.md` has 12 bytes of headroom under its
   `lint-skill-body-budget.py` ceiling.
5. **The plan's "no lockfile precondition needed" premise was false for the bun-era ledger rows**
   (found by the user-impact seat). Recovery: lockfile precondition + tests. **Prevention:** when a
   plan skips a precondition because "a sibling already does X", verify the sibling is itself
   refreshed/covered for the *oldest* population the feature targets.
6. **`main` moved two commits during the ~90 minute review; `merge-tree` flipped to a conflict
   (`PROMOTED_FILES`) only after the push**, and GitHub showed `CONFLICTING` for ~20 s. Recovery:
   `git merge origin/main`, kept main's set plus ours. **Prevention:** re-run `git merge-tree
   --write-tree origin/main HEAD` immediately before every push, not only at review start.
7. **A control probe used a valid one-argument shape, so the "fake records a refused argv" control
   failed on the pristine suite.** Recovery: two-argument probe. **Prevention:** a positive control
   must use an input the fake is documented to refuse.

## Tags

category: workflow-patterns
module: constraint-scaffold, guard-vacuity-floor, review
