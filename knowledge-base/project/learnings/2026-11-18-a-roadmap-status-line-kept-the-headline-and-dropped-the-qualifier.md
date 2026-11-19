---
title: "A roadmap status line kept the headline and dropped the qualifier"
date: 2026-11-18
category: workflow-patterns
module: product-roadmap
tags: [roadmap, status-claims, adr, review, correction-round]
related:
  - knowledge-base/project/learnings/2026-07-20-a-correction-pr-verified-the-old-claim-was-gone-not-that-the-new-one-was-supported.md
  - knowledge-base/project/learnings/2026-09-20-every-correction-i-shipped-needed-correcting.md
---

# Learning: a roadmap status line kept the headline and dropped the qualifier

## Problem

PR #12899 refreshed `knowledge-base/product/roadmap.md`: row 4.6 now cites epic #9842, new rows
4.6a (#12517) and 4.6b (#12601) were added, and Current State moved from 2026-08-11 to 2026-11-18.
`roadmap-reconcile.sh validate` was clean and every cited issue and PR state was checked with `gh`.
The review panel still found 2 P1 and 12 P2 findings. Most were true-but-incomplete status lines; one was a false flag name:

- "ADR-325 keeps gVisor per session as the isolation path". This wording was inherited from epic #9842's
  title. ADR-325 actually decides credential injection apart from the runtime: it keeps bwrap now,
  lists gVisor as option C, and treats a managed sandbox as the contingency.
- "GO: keep bwrap". This dropped two facts: the spike ran off the production host, and production rollout is #11637 (open).
- "First customer run waits on the annex". This dropped that the annex is an AI-prepared draft and
  the owner is proceeding without qualified counsel review.
- `BYOK_DELEGATIONS_ENABLED`. This prose name was carried over from main; the code key is `FLAG_BYOK_DELEGATIONS`.

The correction round then shipped three new overstatements, all caught by a verification seat or by re-reading:
"gVisor stays the planned path", "ADR-325 makes a managed sandbox primary", and "Next review
2026-11-25 (weekly)", which is a Wednesday when the cadence section says "every Monday".

## Solution

For each status claim, read the source's DECISION section (not its title) and carry its
qualifier into the row:

- the decision scope (what the ADR does *not* decide);
- the owner of not-yet-in-production work (#11637);
- draft or counsel status;
- the flag default.

Then run a verification seat on the fix commit alone, asking for VERIFIED / FALSE / OVERSTATED on every
sentence the fix adds.

## Key Insight

`validate` and `gh` state checks prove a row's *numbers and states*. They do not check the *meaning* of
the sentence written next to them. A status line copied from an issue title or a headline outcome is an
inherited framing. Check it against the decision text, and do the same for each sentence a
correction adds, including dates (`date -d <d> +%A`).

## Session Errors

1. **Inherited framing in row 4.6.** The wording came from #9842's title, not from ADR-325's decision.
   Recovery: rewrote it from ADR-325 Decisions 1, 2 and 5. **Prevention:** add a product-roadmap skill
   bullet: write status from the source's decision text, and keep its qualifiers.
2. **Dropped qualifiers in 4.6a, 4.14 and the MU gates** (rollout owner, counsel status, flag defaults).
   Recovery: added each one. **Prevention:** the same skill bullet.
3. **Wrong flag name.** `BYOK_DELEGATIONS_ENABLED` was inherited from main's prose. Recovery: grepped `server.ts`.
   **Prevention:** before writing a flag name, grep its code key in `apps/web-platform/lib/feature-flags/server.ts`.
4. **File-indexed sweep missed twins in the same file.** These were the Pricing Gates `$223.39` and
   "Next review 2026-07-13". Recovery: the pattern seat swept by claim. **Prevention:** when a figure or
   date changes, grep the value across the whole roadmap, not only the cell being edited.
5. **The correction round added three overstatements**, including a review date on the wrong weekday.
   Recovery: a verification seat plus `date -d`. **Prevention:** always run a fix-round seat on the fix commit, and compute dates.
6. **The fix commit message repeated the overstatement** ("ADR-325 does not pick the isolation
   runtime"). Recovery: the next commit body records the correction. **Prevention:** write commit bodies after the verification seat.
7. **Tally writes landed in the wrong worktree.** Bash `cwd` resets to the session's primary worktree,
   so `pipeline-tally.sh incr seats` calls without `cd` wrote to the sibling branch's ledger.
   Recovery: re-recorded the seats on this branch. **Prevention:** prefix every Bash call with `cd <worktree> &&` when the
   active worktree is not the session's primary directory.
8. **`gh pr view 12827` exited 1**, because #12827 is an issue. Recovery: used `gh issue view`. **Prevention:** one-off;
   use `gh issue view` when the number's kind is unknown: it accepts both issues and PRs (gh 2.105.0).
9. **Worktree creation outran the Bash timeout.** Recovery: re-ran it in the background. **Prevention:** one-off;
   run `worktree-manager.sh` with `run_in_background`.
10. **The flag-name fix missed its twin in the MU4.1 row.** This is the same file-indexed sweep miss as item 4, and the
   delta review of the compound commit caught it. Recovery: fixed the MU4.1 row. **Prevention:** after any rename-shaped fix, grep
   the wrong token across the whole repo (`git grep -n <old>`), not only the cell you edited or its directory. The old
   `BYOK_DELEGATIONS_ENABLED` name also survives in historical "Last Updated" notes of the published legal docs, which a
   directory-scoped grep misses.
