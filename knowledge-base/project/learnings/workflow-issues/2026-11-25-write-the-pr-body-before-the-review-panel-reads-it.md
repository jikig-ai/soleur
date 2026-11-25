---
title: Write the PR body before the review panel reads it
date: 2026-11-25
category: workflow-issues
module: one-shot pipeline (work -> review -> ship)
tags: [review, pr-body, closing-keywords, docs-only-pr]
issue: 12846
pr: 13016
---

# Learning: write the PR body before the review panel reads it

## Problem

PR #13016 (the H-capture runbook addendum for #12846) had a plan that put the
PR-body lines in its ship phase: `Closes #12846`, `Ref #13003`, and three prose
statements, including "the marker is not posted by this PR". The pipeline runs
review before ship, so the five-seat review panel read a draft whose body was
still the auto-created placeholder.

Three of the five seats independently reported the same P2: no closing
reference, and `closingIssuesReferences` was `[]`. Two of them also had to work
out for themselves where the plan's ruling D2 put the S1 marker status ("in the
PR body"), because the body did not exist yet. None of this was a defect in the
diff. It came only from the phase order.

## Solution

I wrote the body during review, after the security seat had returned. Then I
polled `gh pr view --json closingIssuesReferences` until it printed `[12846]`.
GitHub filled the field on the first poll after the edit. I recorded the
duplicated P2 as resolved.

## Key Insight

When a PR's correctness depends on its body, write the body before review:
- a close keyword that decides which issue merge closes;
- a "not done by this PR" statement that a ruling relies on;
- a negated reference that must not parse as a close.

The body is part of what review judges. A placeholder body turns every seat
that reads `gh pr view` into a reporter of the same missing-field finding.

For a docs-only PR the cost was small: one duplicated finding per seat. For a
PR where a stray close keyword next to a tracker issue would close the tracker
on merge, a review that ran against a placeholder never saw the text that
matters. The panel's clean verdict on `closingIssuesReferences` would then be a
verdict on an empty field.

## Session Errors

1. **`pgrep -f` liveness check blocked by a hook.** Recovery: dropped it and
   used the gate's rc file. **Prevention:** already hook-enforced (pkill
   self-match guard). Wait on an rc file or a captured PID.
2. **Affected gate rc 4 on a fresh worktree.** The `apps/web-platform`
   node_modules (vitest, tsx) were missing. Recovery:
   `npm ci --ignore-scripts --prefix apps/web-platform`. **Prevention:** the
   gate already fails loudly with rc 4. Install app dependencies when the
   worktree is created if the affected selection can reach web-platform suites.
3. **Planning subagent ended without its Session Summary.** Recovery: one-shot's
   partial-artifact arm recovered the plan from disk, keyed on its Acceptance
   Criteria heading. **Prevention:** covered by the existing fallback arm.
4. **A machine restart wiped `/var/tmp` gate logs, stopped the Monitor and left
   two commits unpushed.** Recovery: pushed, merged main, relaunched the gate.
   **Prevention:** push after every commit on a long-running branch, so a
   restart loses only scratch state.
5. **Stray `soleur-run.*` scratch directory created inside `.worktrees/`.**
   Recovery: removed it. **Prevention:** pass an explicit `-p` under the session
   scratchpad or `/var/tmp` to every `mktemp`, never a path relative to the
   worktree parent.
6. **Gate rc 1 from `cloud-init-user-data-size.test.ts` (floor-raise case).**
   Recovery: reproduced it on a clean `origin/main` worktree (same failure) and
   matched it to the existing tracker #12850. CI skips it because CI has no
   terraform. **Prevention:** covered by #12850 and
   `wg-when-tests-fail-and-are-confirmed-pre`.
7. **Ran a suite at a guessed path (`plugins/soleur/test/…`). It lives at
   `scripts/followthroughs/…`.** The run exited 127. Recovery: resolved the path
   with `git ls-files '*<name>'`. **Prevention:** resolve a suite path with
   `git ls-files` before running it; never retype it from memory.
8. **Three review seats reported the placeholder PR body as a P2.** Recovery:
   wrote the body mid-review and verified `closingIssuesReferences == [12846]`.
   **Prevention:** write the body, with close and Ref lines, at the end of the
   work phase, before review (this learning).

## Tags

category: workflow-issues
module: one-shot pipeline
