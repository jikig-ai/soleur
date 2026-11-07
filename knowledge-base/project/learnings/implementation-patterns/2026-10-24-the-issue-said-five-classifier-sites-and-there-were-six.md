---
module: System
date: 2026-10-24
problem_type: implementation_pattern
component: testing_framework
symptoms:
  - "Issue #10198 scoped the root-anchored-glob grammar to 'FIVE sites' — a sixth classifier mirror (`scripts/ci-pr-affected-replay.py` `edge_hit()`) existed and was missed by the issue's own enumeration"
  - "`glob:*.test.sh` without a dir-less conjunct matches `a/x.test.sh` too — `*` crosses `/` in bash `[[ == ]]` and Python `fnmatch` alike, so every mirror site needs its own `!= */*` guard"
  - "A review-fix comment containing the literal anchor bytes tripped the uniqueness tripwires — the fix had to respell the pattern, not quote it"
  - "Status-token-matching root globs must be DECLINED by the th8 census, not admitted — a census that accepts them invents coverage failures for tokens that were never paths"
root_cause: specification_gap
resolution_type: code_fix
severity: medium
tags: [affected-selection, glob-grammar, mirror-parity, census-the-surface, declared-site-count, fail-wide]
synced_to: [plan, work, review]
---

# Learning: the issue said five classifier sites, and there were six

Issue #10198 / PR #10954 (`Closes #10198`). Root-anchored glob edge form: a `/`-free,
metachar-free leading head (`glob:*.test.sh`, including the empty `glob:*.test.sh` arm) anchors
the whole pattern at the repo root and matches only dir-less diff lines; `/`-in-tail under a
`/`-free head is malformed and mints a verbatim always-match edge (fail-wide).

## Problem

The issue enumerated FIVE classifier sites for the grammar change. Planning censused the
surface anyway and found a SIXTH: `scripts/ci-pr-affected-replay.py` `edge_hit()`, a Python
hit-arm mirror the enumeration missed — plus a derive-battery fixture (`Rg3`'s `glob:*.sh`)
whose well-formedness flips under the new grammar. Both had to fold into Files to Edit or the
mirrors would have diverged silently.

## Solution

1. **Census before partitioning.** A declared site-count in an issue is a claim, not a bound.
   `git grep` the classifier's public seam (`_diff_edge_hit`, `covers()`, `edge_hit`) across
   bash AND Python before assigning the edit list — the mirrors drift precisely where nobody
   counted.
2. **One bash classifier, mirrored explicitly.** `_affected_glob_split` landed in a NEW
   `scripts/lib/affected-glob.sh` with an `_AFF_LIB_OK` fold so a missing lib degrades to
   select-all rather than rc 127. The two Python mirrors re-implement the verdict table;
   the differential test (`x.test.sh` / `a/x.test.sh` / dir ref / `README.md` → `1 0 0 0`)
   pins bash-vs-Python parity.
3. **The `*`-crosses-`/` trap is the central defect class.** The dir-less conjunct
   (`!= */*` in bash; equivalent in `fnmatch`) is load-bearing at EVERY site — hit arm,
   `covers()`, `edge_hit`. Omitting it anywhere re-widens a root-anchored edge to every
   same-extension file in the tree; that is the widening regression Guard 2 exists to catch.

## Key Insight

A widened edge and a narrowed census fail in OPPOSITE directions: a too-wide edge selects
extra suites (slow, visible), while a census that ADMITS a status-token-matching root glob
invents coverage REDs for tokens that were never paths (loud, false). The correct posture is
asymmetric: mint malformed edges fail-WIDE, and decline non-path tokens at the census.

## Session Errors

1. **Two `git commit` rejections by tool-level guards** (doc-freshness trailer tripwire; a
   worktree-blind main/master check resolving against the bare repo). — Recovery: `git -C
   <worktree> commit` for the plan artifacts. — **Prevention:** `git -C` itself false-denies under
   `context-reviewed-gate` on the dirty bare-root index (item 2); the durable fix is hook-side
   cwd resolution, tracked upstream as #8254 — until then `cd <worktree> && git commit` is the
   only safe form.
2. **`context-reviewed-gate` misfire**: the bare-root shared index carried a sibling session's
   staged `last_reviewed` deltas, so the hook resolved cwd to the bare root and denied a
   legitimate worktree commit. — Recovery: `cd <worktree> && git commit`. — **Prevention:**
   recurring hook defect, file-tracked (#8254 covers the envelope `.cwd` omission); the
   gotcha is already recorded in devin/INSTRUCTIONS.md.
3. **Premise drift**: issue #10198's stated re-evaluation triggers did NOT fire (dir-less
   corpus count still 0, `SUITE_GLOBS` unchanged). — Recovery: recorded in plan Premise
   Validation and decision-challenges.md; proceeded on operator priority. — **Prevention:**
   plan-time premise validation already exists — this is the gate working as designed.
4. **`git push` HTTP 408 mid-transfer disconnect** (resume session): remote stayed at the
   pre-rebase SHA while the local branch was rebased. — Recovery: verified remote SHA via
   `git ls-remote`, retried with `--force-with-lease=<branch>:<old-sha>`. — **Prevention:**
   transient; always confirm the remote ref after a mid-push disconnect — the follow-on
   "Everything up-to-date" line reads as success but described a state that did not hold.
5. **No agent roster on this harness** — plan research, plan-review, and deepen fan-out ran
   inline. — Recovery: disclosed in session-state.md. — **Prevention:** structural on Devin CLI;
   `Reviewed-Coverage: sequential-fallback` semantics already defined for this class.

## Prevention

- Census seams, don't trust enumerated site counts (`git grep` the public entry points in
  every implementation language).
- Mutation-test classifier changes: deleting the dir-less conjunct must RED at least one
  battery, in each mirror.
- Never put literal sentinel bytes (`last_reviewed`-class tokens, bare `*) return 0 ;;` case
  arms) in comments or prose — uniqueness tripwires scan comments too.
