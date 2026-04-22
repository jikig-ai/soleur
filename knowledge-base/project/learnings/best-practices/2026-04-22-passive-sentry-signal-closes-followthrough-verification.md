---
date: 2026-04-22
category: best-practices
module: observability
tags: [sentry, verification, follow-through, post-deploy, brainstorm]
triggered_by_pr: 2767
related_issues: [2773, 2774]
---

# Passive Sentry signal closes follow-through verification issues

## Problem

`/ship` Phase 7 Step 3.5 files follow-through issues for post-deploy verification (e.g., `#2773` "verify Sentry issue count unchanged" and `#2774` "verify env var in prod container"). These issues prescribe an **active trigger** — authenticated user session + explicit `POST /api/repo/setup` + wait 10 min + re-query Sentry. Closing them requires an auth handoff to the operator, which frequently costs a separate session.

In practice the active trigger is usually redundant when the passive signal is already overwhelmingly strong.

## Solution

Query Sentry passively first; if the signal is strong, close the follow-through with a comment citing the numeric evidence rather than scheduling an active-trigger session.

**Passive signal is strong when all of:**

- Time since deploy is materially larger than the issue's original firing cadence (e.g., ≥8× the pre-deploy `lastSeen → firstSeen` delta, or ≥4 hours for a low-frequency issue).
- `count` is unchanged from pre-deploy baseline.
- `firstSeen == lastSeen` and both predate the deploy timestamp (no new events have been grouped into the issue).
- `status` is still `unresolved` (not auto-resolved by Sentry heuristics, which would mask a re-fire).

**Example from PR #2767 follow-up (`#2773`, queried 8h38m post-deploy):**

```text
shortId:   SOLEUR-WEB-PLATFORM-H
count:     1                    (unchanged)
firstSeen: 2026-04-22T07:44:03Z (pre-deploy)
lastSeen:  2026-04-22T07:44:03Z (pre-deploy, == firstSeen)
status:    unresolved
```

All four criteria met → close `#2773` with a comment citing the four values. `#2774` (docker exec printenv) closes transitively per its own body ("if `#2773` confirms silence, this check is redundant").

**Passive signal is NOT strong enough when:**

- Any criterion above fails.
- The fix targeted a low-traffic code path that may not fire without the active trigger (e.g., a specific user action gated by auth).
- The issue category is something Sentry re-groups aggressively (rare; usually a separate problem).

## Key Insight

Follow-through verification issues default to prescribing an active trigger because the `/ship` phase-7 template doesn't know which signal will be strongest post-deploy. The operator reviewing the follow-through has more information (actual post-deploy traffic, actual Sentry state) and should bypass the active trigger when the passive signal makes it redundant.

**Do not** close a follow-through "just because it's been a while" — anchor the close to the four numeric criteria above.

**Do not** burn an auth-handoff session on the active trigger when passive is already conclusive. Auth handoffs cost a full operator context-switch; redundant ones are pure overhead.

## Related

- Rule: `cq-for-production-debugging-use` — Sentry API is the primary observability surface for prod debugging.
- Rule: `hr-when-a-workflow-concludes-with-an-actionable-next-step` — bias toward executing the automatable step rather than listing it.
- Prior follow-through pattern: `/ship` Phase 7 Step 3.5 creates these issues via the daily follow-through monitor.
