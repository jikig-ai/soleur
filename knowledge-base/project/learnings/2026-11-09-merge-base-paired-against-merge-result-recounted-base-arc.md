---
module: CI
date: 2026-11-09
problem_type: review_finding
component: ci-oracle-lane
symptoms:
  - "The fix for a stale HEAD^1 diff base itself re-opened the defect class in the mirror direction"
  - "Every fixture had merge-base >= HEAD^1, so the common topology (merge-base behind HEAD^1) was never exercised"
  - "diff(D, merge_result) unions the PR delta with the base-side arc whenever the merge ref's parent is ahead of the fork point"
  - "Three seats (architecture, performance, agent-native) converged on the same ordering defect from different lenses"
root_cause: incomplete_invariant
resolution_type: design_fix
severity: high
synced_to: [review, work]
tags: [merge-ref, three-dot, git-diff, fixture-topology, mirror-direction, oracle-lane, #12418, #12480]
---

# The merge-base must pair with HEAD^2, never the merge result — and every staleness fixture must cover both directions

## Problem

`scripts/ci-oracle-lane.sh` classified a pull_request diff as `git diff HEAD^1 HEAD` — the merge ref's
frozen first parent against the merge result. The #12418 fix changed the base to
`git merge-base HEAD^2 FETCH_HEAD` (live base ref) — but left `diff_head=HEAD`. The architecture seat
caught it at review: pairing the merge-base against the merge *result* `M = merge(B_old, P)` re-opens
the same miscount in the mirror direction. Whenever `D = merge-base(P, live) < B_old` — the ordinary
case for any PR that has not synced main since forking — `git diff D M` unions the PR delta with the
base-side arc `D→B_old`, because the merge result's tree carries the base's content for every file the
PR side did not touch. A docs-only PR in that state classifies `outside_surface` → full battery: the
lane would almost never fire for its target workload.

The correct pairing is true GitHub three-dot: `diff(merge-base(HEAD^2, live), HEAD^2)`. Merge refs only
exist for auto-mergeable PRs, so diffing the PR head loses nothing — and it makes `head_sha`/`base_sha`
literally the diff's two endpoints.

## Why the sentinel missed it

Every pre-existing fixture had `D == HEAD^1` (branch forked at base, merged immediately), and the new
`stale` fixture covered only `D > HEAD^1`. The `D < HEAD^1` direction — the common case — had no
fixture, so both pairings were verdict-identical on the whole suite. The `behind` fixture now pins it:
main advances a code file after the fork, the branch never syncs, and only `diff(D, P2)` classifies
the doc-only delta correctly. A `diff_head="HEAD"` revert mutation is killed by exactly that fixture.

## Lesson

- When replacing ONE endpoint of a diff pair, re-derive the other endpoint against the new base's
  semantics. `merge-base` is a fork-point concept; the merge result is a post-merge tree. They belong
  to different frames — pairing them is the bug.
- A staleness class has TWO directions (frozen-behind and frozen-ahead). Fixtures that only construct
  one direction cannot discriminate the pairings — write the mirror fixture first, not as an
  afterthought.
- The three-dot equivalence is the oracle: when in doubt, ask "what does GitHub's Files tab show for
  this PR" — `diff(merge-base(base, head), head)` — and match that, not a hand-rolled alternative.

## Prevention

- In this suite's fixture taxonomy, any new diff-base mechanism gets both `<` and `>` fixtures against
  the merge ref's parent before implementation.
- The `O-BASE` mutation battery now reverts both endpoints independently (`HEAD^1` revert, merge-result
  revert, `base_sha` revert) — a pairing defect cannot survive all three.
