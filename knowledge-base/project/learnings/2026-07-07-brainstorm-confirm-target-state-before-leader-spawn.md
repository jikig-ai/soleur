# Learning: Confirm the target-state premise with the operator BEFORE the first domain-leader spawn

## Problem

Brainstorm of #6178 ("extract inngest to its own HA host"). The issue described a
co-location coupling but did not state the *target web-tier topology*. I inferred
the load-bearing premise — "inngest is single-active by design (web-2 pinned at LB
weight 0), so HA is moot" — from the current runtime state, and spawned the
CPO/CLO/CTO + platform-strategist triad on it. All four returned internally
coherent recommendations premised on that floor: **in-place decouple + close the
host proposal as YAGNI**.

The operator then supplied the actual target: **active-active web-1 + web-2 (and
more backends later), all serving traffic.** That single fact *reversed* the
verdict — under active-active-N, co-located loopback inngest is a guaranteed
N-times cron double-fire (a correctness defect), so extraction to a dedicated
singleton host becomes **mandatory**, not YAGNI. A full leader round had been
spent on a wrong premise.

## Solution

Re-ran the domain re-assessment (platform-strategist) on the corrected premise
and added a `framework-docs-researcher` pass that caught a *second* load-bearing
external fact before it could shape a wrong design: **self-hosted OSS inngest
v1.x is single-writer — active-active HA is unsupported (vendor roadmap item).**
That killed a naive "run an active-active inngest cluster" option and produced
the correct scope: single dedicated host now, failover-pair HA deferred (#6185),
managed Cloud declined (EU-residency).

## Key Insight

For an **architecture** brainstorm, the *target end-state* is the premise every
domain leader reasons from. When the issue doesn't state it, **do not infer it
from current runtime state and spawn leaders** — a snapshot ("web-2 at LB weight
0") is often a temporary bootstrap condition, not the design intent. Surface the
inferred target-state and **confirm it with the operator in one question BEFORE
the first leader spawn.** Leaders build internally-coherent recommendations on
whatever floor you give them; a wrong floor costs a whole parallel round.

Corollary (worked here): when a leader asserts a load-bearing *external* capability
("use inngest Connect / it can run active-active"), verify it against vendor docs
before it shapes the option space (`hr-verify-repo-capability-claim-before-assert`).

## Session Errors

1. **Inferred target-state fed to leaders** — Recovery: operator supplied the real
   target; re-ran the affected leader on the corrected premise.
   **Prevention:** brainstorm Sharp Edge — for architecture issues that don't
   state the target end-state, confirm the inferred premise with the operator via
   one `AskUserQuestion` before the first Phase 0.5 leader spawn.
2. **Concurrent `cleanup-merged` wiped the unpushed worktree** (getcwd error on
   first `draft-pr`) — Recovery: recreated the worktree and pushed immediately.
   **Prevention:** already covered by
   `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` and the skill's
   race-window warning; reinforced — push the branch the instant the worktree
   exists, before any other command.

## Tags
category: workflow-patterns
module: brainstorm
