# Learning: a gitignored run ledger dies with its worktree, so keep a renamed copy

## Problem

The generated `bootstrap.sh` writes its run ledger to `bootstrap-runs.jsonl` beside the script.
That name is gitignored on purpose (`.gitignore`: a tracked ledger conflicts with every branch
that re-runs the bootstrap). After the live #10058 run the only copy of the 82-row record sat in
the `bootstrap-10058` worktree, which `cleanup-merged` reaps once the PR merges. A copy in
`/var/tmp` survived by luck, not by design.

Two artifacts also disagreed about the policy since `384fd2dd3e`: `operator-bootstrap/SKILL.md`
described the ledger as tracked in the spec dir, while the `.gitignore` comment ignored it.

## Solution

- Keep the live ledger gitignored under its fixed name.
- When a run is worth keeping, copy it at archive time to `bootstrap-runs-<issue>.jsonl` beside
  the archived script. The name does not match the ignore rule, so no force-add is needed.
- Point to it from the spec's `tasks.md`, and say in SKILL.md that a kept copy is a record and
  survives the delete-together step that removes the script, live ledger and `.env`.

Audit method that worked on the committed file (public repo): parse every line, group values by
key, print every string of 24 or more characters, then run a secret-shape grep with a known
positive control. The only long strings were plan hashes.

## Key Insight

State the lifetime of a record where it is written. A file that is ignored so it never conflicts is
also a file nothing preserves, and the preservation path has to be named in the same place as the
ignore rule or it will not exist when the worktree is reaped. A 4-seat panel on an 82-line data
file found no data defect; both P2s were the two documents disagreeing about where the record
lives, and only the history seat (not the secret or pattern seats) read the ignore line's blame.

## Session Errors

1. **`git check-ignore` run from the bare repo root failed** ("must be run in a work tree") —
   Recovery: reran from the worktree — Prevention: run path-ignore probes from the worktree
   (`hr-when-in-a-worktree-never-read-from-bare`).
2. **Assumed the ignore rule was a secrecy policy** — Recovery: the history seat read the blame
   and comment; it is conflict avoidance — Prevention: read the rule's own comment and blame
   before choosing a workaround for it.
3. **PR body said `Blast Radius: docs` after a review fix touched `SKILL.md`** — Recovery:
   corrected in the PR body at ship — Prevention: re-derive the blast radius from
   `git diff --name-only origin/main...HEAD` after every review-fix commit, not at PR creation.

## Tags
category: workflow-issues
module: operator-bootstrap
