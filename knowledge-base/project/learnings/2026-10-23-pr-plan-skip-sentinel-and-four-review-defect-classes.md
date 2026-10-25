---
title: "The .pr-plan-skip sentinel pattern and four defect classes its review surfaced"
date: 2026-10-23
type: learning
status: active
issues: [10715, 10714]
pr: 10895
tags: [ci, terraform, workflow, test-integrity, review]
---

## The mechanism

A PR terraform-plan matrix that must exclude roots whose plan can *never* run
green under the PR credential set: `detect-changes` emits a second output
`plan_directories` derived from `directories` by dropping roots carrying a
non-empty regular file `.pr-plan-skip` at the root. `directories` stays
unfiltered — `validate` (offline coverage) still runs on sentinel roots. The
sentinel is self-justifying content, travels on rename, and re-enables by file
deletion. Alternative rejected: `matrix.exclude` / `if:`-hardcode — same
exclusion but hand-maintained, far from the root, and it re-arms on rename.

## Defect class 1: extract-then-classify under `set -euo pipefail` needs `|| true`

`line="$(… | grep -F X | tail -1)"` in a pipeline suite: when the needle is
absent — the exact failure the case arm exists to report — grep exits 1,
pipefail propagates it, the assignment fails, the suite aborts **before** the
`ck`/`fail` runs. Still red, but unverdicted: no gate-named diagnostic, the
remaining rows unasserted, the floor reconciliation never prints. Guard the
extraction (`|| true`), then classify. This suite's own convention at
`go-session-gates.test.sh` (`… | head -1 || true`) already encoded it — the
new copy dropped it.

## Defect class 2: `::warning::` inside `$( )` never becomes an annotation

Commands in a workflow `run:` block are parsed on the step's streams, but the
substitution's stdout is *captured into the variable* — so an `::warning::`
emitted inside `PLAN_DIRS=$(…)` could only go to `>&2`, where it lands as log
text, never an annotation. Emit the annotation in a second pass on real
stdout. And keep the predicate in ONE place: the two-pass shape made the
`-f && -s` test exist twice until `is_plan_skipped()` collapsed it — an
un-pinned duplicate predicate is the drift class the suite pins elsewhere.

## Defect class 3: sentinel predicates — `-f` vs `-s`, and census vs gate asymmetry

`-s` is true for directories (st_size > 0) and follows symlinks to non-empty
targets. A gate that wants "regular file carrying justification" needs BOTH
`[ -f ] && [ -s ]`. The mirror test, the workflow gate, and the census `find`
must then count the same shapes: `find -type f` misses a directory-shaped
sentinel that `-s` would have honored — census must drop `-type f` to stay
wider than the gate. A directory-sentinel fixture row (`TS17`) pins the `-f`
arm load-bearing.

## Defect class 4: pin the copy that runs, not only its mirror and consumer

Three layers: the mirror function (unit-tested), the workflow run-block (the
copy that actually executes), the consumer (`plan` job matrix). Pinning only
the mirror + consumer leaves the middle free to drift — delete the filter from
the step and every assertion stays green while `plan_directories` degenerates
to a `directories` copy. The fix is operand-level text pins on the extracted
run-block (`directories=` ← `$DIRS`, `plan_directories=` ← `$PLAN_DIRS`,
the predicate literal) — presence-of-name is insufficient because the step's
own comments carry the same tokens.

## Session error inventory (this run)

1. `git -C <worktree>` commits picked up a bogus `t <t@t>` author identity
   (bare repo's shared config resolved correctly for `git config`, but the
   commit env produced `t <t@t>`) → `cla-check` reddened; fixed by
   `git filter-branch --env-filter` rewrite + force-push. **Verify
   `git log --format='%ae' origin/main..HEAD` before spawning review seats.**
2. `git -C` was itself the workaround for known defect #8254 (precommit guard
   resolves bare-repo cwd); the guard is what made `-C` necessary and the
   identity bug is what `-C` exposed.
3. Fixture sentinels written empty (`: >`) failed the `-s` gate the review
   had just introduced — the test caught its own defect class; fixtures must
   match the predicate's shape, not merely exist.
4. `test-all.sh --affected` sat ~90 min producing no output — repo-global
   flock serialization behind sibling one-shot sessions; focused suites +
   PR CI covered the affected surface in the interim.
