---
title: "Parity of form is not parity of cover — and shipping a protocol fix does not retire the old implementations still writing to that state"
date: 2026-08-09
category: workflow-patterns
tags: [worktree, lease, shared-state, review, mutation-testing, parity]
issue: 5454
---

# Parity of form is not parity of cover

## What happened

`worktree-manager.sh` has two worktree-creating functions. `create_for_feature`
(dispatch `feature|feat`) acquired a session lease. `create_worktree` (dispatch
`create`) did not — and `--yes create` is what every autonomous surface invokes:
one-shot Step 0b, work Phase 1, `fix-issue`, `model-launch-review`, the
grok-fidelity bootstrap, and the cron eval substrate. So every worktree the
pipeline created was reapable by a sibling `cleanup-merged` from the instant it
existed. It happened three times in two days, each time deleting the worktree,
the local branch, the remote branch, and closing the PR.

The fix looked obvious: copy the sibling's block. That is what shipped first,
and **an 8-agent review found it would not have prevented the incident it
cites.**

## Lesson 1 — parity of FORM is not parity of COVER

The copied block sat where the sibling's sat: after `install_deps`. Between
`git worktree add` and that point run verify, config, identity, env copy, and a
full `bun install` per workspace — minutes. During that window:

- the branch is 0 commits ahead of `main`, so `git branch --merged main` **matches**;
- the lease guard has nothing to read yet;
- the 10-minute recent-commit grace reads `origin/main`'s tip, hours old;
- the tree is clean, because `node_modules` and `.env` are gitignored.

Every reap guard falls through. The PR's own motivating evidence was a worktree
that "checked out all 13,354 files and vanished before `verify_worktree_created`
ran" — i.e. *inside the window the fix did not close*.

Copying a sibling's placement inherits the sibling's blind spot. When the fix is
"do what the working one does", ask separately: **does the working one actually
cover the failure?** Here it did not; it had simply never been the entry point
that got reaped.

The lease is keyed by branch name and needs nothing on disk, so nothing ever
forced the late placement. It was there because that is where the other function
put it.

## Lesson 2 — a shipped protocol fix does not retire the old writers

The lease layer's *first* defect (an `EXIT` trap that released on normal exit,
plus `is_lease_active` gating on `kill -0` against a PID designed to exit in
milliseconds) was fixed and merged. That fix is necessary and not sufficient for
a second reason beyond the missing acquire:

**Lease state is shared, and every checkout carries its own copy of the code that
reads and sweeps it.** This machine has ~16 worktrees, several predating the
fix. A sibling session running a pre-fix `worktree-manager.sh`/`session-state.sh`
evaluates `is_lease_active` with the old `kill -0` gate — which reads INACTIVE
for *every* lease the fixed code writes — and its old `sweep_orphan_leases`
deletes on a dead PID alone.

So the protection is bounded by **the oldest checkout still running
`cleanup-merged`**, not by what is on `main`.

Measured this session: a lease was acquired, confirmed on disk, and later
vanished; a sibling session's lease vanished the same way. Current `main` cannot
reap a two-minute-old lease — both `is_lease_active` and `sweep_orphan_leases`
are window-gated — so `main` is not the deleter.

**This attribution is probable, not proven.** The falsifying experiment is to
purge or refresh the stale worktrees and see whether leases still vanish. It was
deliberately NOT run here: the purge is destructive and live sibling sessions
were holding worktrees at the time, including one carrying an open PR.

Why this is a learning and not an issue: the failing component is a *deployed old
implementation*. No change to `main` retires it. The obvious repo-side hardening
— a protocol-version field the sweep respects — is ineffective against this exact
cause, because the old sweep is the thing doing the deleting and will never read
a field it does not know about. Filing would mint an issue no PR could close.

Generalises to any shared-state protocol with independently-deployed writers:
lockfiles, sentinel files, on-disk caches, schema-versioned queues. Shipping the
fix changes what NEW writers do; it does nothing about the old ones already
installed, and the blast radius is the union of every version still running.

## Lesson 3 — the failure modes that matter were unobservable

`acquire_lease` ended in an unconditional `return 0` with an unchecked `mv`. Every
caller is the left side of `acquire_lease … || warn`, which suspends errexit for
the whole call — so ENOSPC/EROFS/EACCES returned **success** with no lease on
disk, and the `|| warn` arm never fired. The caller proceeded believing it was
protected. `rc=0` is not proof; assert the artifact.

And the warn itself was invisible: `headless_or_stderr` appends to a per-PID
logfile under `claude --bg` that nothing reads. The same file, 130 lines below,
already emits `SOLEUR_FEATURE_PUSH_FAILED` on stdout for a *strictly less
destructive* failure, with a comment explaining exactly why stderr does not work
there. The more dangerous failure had the weaker channel.

## Lesson 4 — the review found more defects in the fix than in the original bug

Of the findings, most were introduced by the fix, not by the original defect:
the late placement, the trap on re-entry arms (which created a *new* deletion
path — the re-entering process became `release_lease`'s in-process owner, so a
SIGINT would delete a live incumbent's lease), and two comments asserting safety
properties that do not hold.

The mutation battery is what separated real coverage from the appearance of it.
Four mutations survived fully GREEN before the review:

| Mutation | Result before |
|---|---|
| Delete `create_for_feature`'s re-entry acquire | GREEN — no fixture exercised `feature` at all |
| Replace the env reads with literals | GREEN — nothing asserted the vars are read |
| Neuter scenario 4's unasserted `rm` + delete the re-entry acquire | GREEN — the arm read the previous scenario's lease |
| Force the fresh-create path on re-entry | FALSE PASS — the precondition greped the bare token `already exists`, which git itself prints |

The last one is `cq-assert-anchor-not-bare-token` in its purest form: an
assertion whose whole stated job was "prove we took the early return" was
satisfied by the error message of the path it existed to exclude.

## Rules of thumb

- When fixing by symmetry, verify the model covers the failure — do not inherit its placement.
- A guard's placement is part of its correctness, not a style choice.
- `rc=0` from a function whose job is to produce an artifact is not evidence; check the artifact.
- A fix on a destructive path needs a monitored stdout marker, not a warn on a channel nobody reads. Check what the same file already does for less serious failures.
- A trap belongs to the process whose exit ends the work, never to a co-tenant.
- Shared state + independently-deployed readers = protection bounded by the oldest deployed reader.
- Before crediting a mutation battery, ask which AXES it mutates. N mutations of one shape is one mutation.

## Session Errors

Four recurring classes, all mine, all in a session whose subject was "a comment
asserted behaviour the code did not have."

**1. Verified a claim against a convenient SUBSET of a tool's output and reported
the subset as the whole.** I ran `shellcheck | grep -E 'SC2015'`, saw nothing,
and said "shellcheck clean on the new code." `SC2164` was firing on both new `cd`
lines. The consequence was not cosmetic: the suite runs `set -uo pipefail`
WITHOUT `-e`, so a failed `cd` lets the subshell continue and runs
`worktree-manager.sh --yes create` against the developer's REAL repo.
**Prevention:** grep for the ABSENCE of any finding in the changed line range,
never for one rule id. `shellcheck -f gcc <file> | awk -F: '$2>=START && $2<=END'`
— if that is non-empty, the claim "clean" is false whatever rule fired.

**2. A process scan whose own command line matched its own predicate, killing the
invoking shell.** `ps -eo pid,cmd | grep '[t]est-all.sh'` plus a cwd filter
selected the scanning bash itself; the kill loop then killed it (exit 144). The
repo already documents this for `pkill -f <pattern>`; this is the same class one
level out — ANY scan-then-kill whose predicate can match the scanner.
**Prevention:** never filter a kill list by pattern alone. Walk `/proc`, compute
self + ancestry (`awk '{print $4}' /proc/<pid>/stat` to climb ppids), and skip
those pids explicitly before killing. That form worked and spared every sibling.

**3. A `cd A 2>/dev/null || cd B` fallback whose FIRST arm succeeded for the wrong
reason.** It landed in the bare repo root — which carries a stale synced mirror of
every tracked file — and I ran a test suite there and reported it green. It was
green against code that did not contain my edit. The tell was on screen and I
missed it: the bare root runs a different vitest version than the worktree.
**Prevention:** before trusting any test result, echo `pwd` AND assert the change
is present in the tree about to be tested (`grep -c '<the new symbol>' <file>`).
A fallback that can silently select a decoy tree needs a positive identity check,
not an exit code.

**4. Wrote a claim about an artifact into a committed file before creating the
artifact.** A plan addendum said a finding was "recorded instead as a `/compound`
learning"; no such file existed. The gate was cleared by citing something that had
not been written — the repo's own "decisions are INTENT, not accomplishment"
class, committed inside the PR whose entire subject is a comment that asserted
behaviour the code did not have.
**Prevention:** when an artifact is the justification for clearing a gate, create
it FIRST and cite it by path; a `ls <path>` before the commit is the whole check.

**Meta-lesson.** All four are the same shape as the bug being fixed: an assertion
whose evidence was adjacent to, but not identical with, the thing asserted. The
mutation battery is what caught the equivalent in the code — four mutations
survived fully GREEN before the review panel, including a bare-token anchor that
emitted a FALSE PASS on the exact path it existed to exclude, because git prints
that same string. Prose claims have no mutation battery, which is why they need
the mechanical check written down next to them.
