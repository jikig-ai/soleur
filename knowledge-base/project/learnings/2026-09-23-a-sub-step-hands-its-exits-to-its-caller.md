---
title: A sub-step hands its exits to its caller, and my cost example was the one case that cost nothing
date: 2026-09-23
category: logic-errors
module: workflow-fidelity
tags: [adr-229, classifier, sub-step, measurement, review-panel]
pr: 8627
---

# Learning: a sub-step hands its exits to its caller

## Problem

ADR-229 recorded ship's in-ship `review` call as a "known unmodelled designed call": a session
logging `ship review compound postmerge` read as the phantom pairs `ship → review` plus
`compound → postmerge`, noise in the log the #8470 re-measure reads. PR #8627 declared `review`
as a `ship` sub-step (`DECLARED_SUB_STEPS`, TS const first, then the JSON mirror, then the
parity pin). Undeclared pairs fell 324 → 291 on one frozen copy of the log.

## Solution

- `ship: ["compound", "review"]`, with a per-entry `ANCHORS` map pinning each sub-step to the
  SKILL.md sections that invoke it (ship Phase 1.5 and Phase 5.5 for `review`), plus an exact
  heading total.
- Classifier cases 39 (the ADR's example collapses), 40 (control: `work review ship` still
  reports exactly `review -> ship`) and 41 (the accepted cost, pinned).
- Review found that `review/SKILL.md` did not treat `ship` as a parent, so a ship-invoked review
  ran its standalone exit (compound, then ship again), nesting a second ship run. Ship now passes
  `--parent ship` at all three call sites, and review honours it: it emits the trailer ship
  re-reads, then returns. Both sides are pinned by a workflow-fidelity test.

## Key Insight

**A sub-step entry `K: [V]` does not just delete V; it hands V's outgoing edges to K.** After the
collapse, every successor of K that is NOT a successor of V reads as declared. So the cost of an
entry is `successors(K) \ successors(V)`, which you can compute before measuring. For
`ship: review` that set is `{postmerge}`: `ship review postmerge` (4 sessions, none with a
compound between ship and postmerge) now reads as the declared `ship → postmerge`.

The plan's own cost example, `ship review work`, was the one case that costs NOTHING:
`review → work` was already declared, so the collapse hides only the designed call. I picked the
example by what came to mind, not by computing the set, and the review panel's data-integrity
seat found the real one by synthesising shapes against the classifier.

A companion: a claim of the form "no pair INTO X changes" is falsified by the same bullet's own
deltas whenever X is the collapse's key. The collapse only rewrites a pair's `from` to K, so the
honest invariant is "no pair into K from ANOTHER node changes". Three review seats converged on
this. The sentence was written from intuition about what the collapse "protects", not from the
delta table sitting four lines above it.

## Session Errors

1. **Step 0a's Linear-ID regex matched `ADR-NNN` ordinals.** Recovery: skipped the fetch by
   hand. **Prevention:** already fixed on main (#8511). The session had loaded a stale installed
   plugin copy; read skills from the worktree when the two differ.
2. **The planning brief attributed ADR-229 to #8302 instead of #8301** (forwarded from
   session-state). **Prevention:** `gh pr view N --json title` every `#N` a brief cites before
   sending it; the plan never propagated it.
3. **A Bash `cd` to the bare repo root moved the session's primary cwd out of the worktree.**
   Recovery: cd back. **Prevention:** use `git -C` or absolute paths for reads against the main
   checkout; never a bare `cd` in a compound command.
4. **The first full-gate attempt was REFUSED (rc=4) by sibling runs, and the override run queued
   about 50 minutes on the lock.** Recovery: `SOLEUR_ALLOW_FULL_GATE=1` shards under `setsid`,
   with the review panel spawned read-only against the pinned SHA while the gate queued.
   **Prevention:** documented (work/SKILL.md contention passages). Overlapping read-only review
   with a queued gate is the cheap move.
5. **The plan's evidence counts (13 within 300 s, 10 after preflight) did not reproduce** (my scan
   gave 11/12 of 28, the architecture seat 12/6 plus 11 not ship-invocable). Recovery: the ADR
   states an honest approximate split. **Prevention:** a count that goes into an ADR comes from a
   command published beside it, or it is stated as approximate.
6. **"No pair INTO `ship` changes" contradicted `review → ship −3` four lines above it.**
   Recovery: restated as the rewrite property. **Prevention:** after writing any invariant
   sentence into a re-baseline, check it against the delta table in the same bullet.
7. **The joined-text AC grep printed 0** because `[Modelled` and `2026-09-23` straddled a line
   wrap (the join produced two spaces). Recovery: rewrapped. **Prevention:** an AC that greps
   joined text must be run after the final reflow, not before.
8. **I wrote a guessed issue number into the ADR before filing it.** Recovery: a placeholder,
   then the filing was refused and the fix went inline, so the reference became "fixed in PR
   #8627". **Prevention:** existing rule (never write a `#N` before `gh issue create` returns it);
   use a placeholder token from the start.
9. **`gh issue create` was denied three times:**
   - missing `User-Impact`;
   - my heredoc append rode in the same denied Bash call and was discarded (documented trap);
   - the fix size was inside the inline threshold, so the gate required the fix inline.

   **Prevention:** documented. Write the body with a separate call, and compute Fix-Size before
   choosing filing over fixing.
10. **Plan review cut the literal heading total as "consistency, not integrity"; review then showed
    it was the only assertion killing a surviving mutant** (deleting the Phase 5.5 heading from
    `ANCHORS` stayed green). Recovery: `expect(checks).toBe(6)`. **Prevention:** before deleting
    an assertion as redundant, run the mutation it would kill against the remaining ones.
11. **The ADR's accepted-cost example was vacuous** (see Key Insight). **Prevention:** compute
    `successors(K) \ successors(V)` and cite a member of that set as the example. The rule is now
    in the `DECLARED_SUB_STEPS` docblock.
12. **A ship-invoked review re-ran compound → ship.** Recovery: the `--parent ship` contract, fixed
    inline and pinned. **Prevention:** when a callee is declared as a sub-step, check that the
    callee's own exit logic returns to the caller.

## Tags

category: logic-errors
module: workflow-fidelity
