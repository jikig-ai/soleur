# Decision challenges — feat-one-shot-post-merge-learnings-ship-machinery

Decisions taken during headless planning that depart from the brief, or that are taste calls.
Recorded per ADR-084. `ship` renders this into the PR body.

---

## DC-1 — The brief says an admin-merge broke the #8474 livelock; the evidence says it did not

**Date:** 2026-09-22
**Classification:** User-Challenge (the brief's stated fact is corrected, not followed)

The brief states: "Breaking the loop took an admin-merge, which needs operator approval." GitHub's
timeline for PR #8474 shows no admin-merge. The agent offered one from cycle 5 onward, and no
approval came. The queued auto-merge fired at 23:48:20Z, 5 seconds after the required `test` context
concluded `success` on head `b93f5ad63`. The only `gh pr merge 8474` in the session transcript is
`--squash --auto`.

**Planned:** the learnings record what happened. The loop ended in a quiet window. The admin-merge
was the way out on offer, and it was gated on operator approval because the diff carried code.
The #8458 admin-merge (#8500) is referenced as the separate event it was.

**Operator:** if the brief meant a different admin-merge, name the PR and the learning will be
corrected.

## DC-2 — The settle-then-admin-merge edit shrank to one sentence

**Date:** 2026-09-22
**Classification:** Taste

The first draft told the agent to ask the operator once, at the `hatch_check` line, whether to
admin-merge a code-bearing PR. Plan review (DHH and code-simplicity) cut it: it adds admin-merge
policy for code diffs that the brief did not ask for. The CTO review found that as written it would
re-fire every hour and had no headless path. The shipped sentence says only that on a
`NOT eligible` diff an admin-merge is the operator's decision, never the agent's.

**Operator:** if you want an agent to ask proactively after N syncs on a code PR, that is a separate
policy change with its own once-per-PR and headless rules.
