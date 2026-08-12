---
date: 2026-08-12
issue: 7484
source: plan-review (4 of 6 reviewers; kieran + architecture-strategist died on the weekly API limit)
---

# Decision challenges — instrument the advisory-lock wait

## UC-1 — the persistence channel does not exist, and the panel disagrees on whether to build it

**decisionClass:** user-challenge

**The verified fact.** `TEST_TIMING_LOG` is set nowhere in any automated path — four independent
confirmations (CTO, DHH, spec-flow, orchestrator grep). Every assignment in the tree is a test arm
redirecting it to a sandbox so rows never reach the operator's log. So the plan's property P2 ("the
ratio is derivable across runs") cannot be delivered by writing a row to that channel.

**Why this is the operator's call, not the reviewers'.** The four reviewers split on the remedy, and
each remedy is a different-sized PR:

| Position | Reviewer | What it costs |
|---|---|---|
| **Drop the row.** Print the measured duration in the existing banners; per-run data lives in the terminal and the agent transcript. P2 is explicitly not delivered; persistence is a separate PR with its own blast-radius argument (defaulting a shared env var). | DHH | ~15 lines. Smallest honest version. |
| **Default `TEST_TIMING_LOG`** in `test-all.sh` to a stable untracked path when unset and `CI` is empty. | spec-flow (candidate i) | Changes a shared default for every run and every sibling worktree; needs a run-id or per-worktree path, since worktrees share `.git/common`. |
| **Stdout marker + evaluator.** Emit `SOLEUR_TEST_LOCK_WAIT …` in place of the banner text, keep the TSV as redundancy, and ship `scripts/followthroughs/lock-wait-ratio-7484.sh` to evaluate the bar. | CTO | Largest. Note the evaluator still needs a persisted source, which stdout is not — so this may inherit the same hole unless paired with one of the above. |

**Recommendation if no answer is given:** take DHH's position. It is the only one that ships nothing
false — it delivers P1, P3 and P4 honestly and declines to claim P2 rather than claiming it via a
channel nobody reads. The plan has been rewritten on that basis; the other two remain available as a
follow-up whose scope is "make the data arrive", argued on its own merits.

## UC-2 — the plan's stated purpose overreaches what any row can deliver

**decisionClass:** user-challenge

The plan's Overview justified itself as producing data that decides between **(a)** raising
`TC_LOCK_TIMEOUT` and **(b)** short-circuiting a futile wait on holder age. spec-flow falsified this:

- Contended observations are **right-censored** at the fixed 900 s timeout, so they cannot answer
  "would a longer wait have succeeded?" — which is exactly option (a).
- Option (b)'s parameter is the **holder's** age; the row measures the **waiter**. The Cut List
  removed the only mechanism carrying it.

What the data honestly answers is *"does the wait ever pay off, and what is the longest wait that was
redeemed?"* — which most directly supports **lowering** the timeout, an option the current Non-Goals
list bars.

**Applied:** the Overview has been rewritten to claim only what the measurement delivers. The operator
may prefer instead to widen scope so the follow-up decision is actually reachable — that would mean
recording the holder's age, which spec-flow argues is a `printf` rather than the control-flow change
the Cut List rightly excluded. Not taken unilaterally, because the Cut List's exclusion was a
deliberate scope boundary set at brainstorm time.
