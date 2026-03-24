# Verify Platform Limits During Brainstorm, Not Implementation

**Date:** 2026-03-25
**Context:** Scheduled tasks migration (#1094)
**Category:** product/planning

## Problem

A 9-workflow migration plan was brainstormed, planned, reviewed, and partially implemented before discovering the Max plan only allows 3 Cloud scheduled tasks. This limit changed the entire cost-benefit analysis and migration scope — from "migrate all 9" to "pick the best 3."

## Root Cause

The brainstorm Phase 1.0 (External Platform Verification) fetched Cloud task docs and extracted the billing model ("shares rate limits with subscription"), but did not verify per-plan quantitative limits. The docs said "available to Pro, Max, Team, Enterprise" without prominently listing the 3-task limit for Max plans.

The `RemoteTrigger` API returned a clear error: `"Your plan gets 3 daily cloud scheduled sessions."` — this limit was only discoverable by attempting to create the 4th task.

## Fix

**For brainstorm Phase 1.0 (External Platform Verification):**

When evaluating an external platform migration, add a mandatory limit verification step:

1. **Check plan tier limits** — Not just "is this feature available?" but "how many of X can this plan create?" Limits are often not on the main docs page — check pricing pages, FAQ, or test empirically.
2. **Empirical verification** — For any migration involving creating multiple instances of something (scheduled tasks, environments, connectors, API keys), attempt to create one via the API DURING brainstorm to discover limits before committing to a plan.
3. **Rerun cost-benefit with real limits** — If the limit is lower than the migration scope, recalculate: is it still worth migrating? Which items are highest value within the limit?

**Proposed brainstorm addition:**

After "Does it accept the product category?", add:

- **(4) What are the per-plan quantitative limits?** (number of tasks, storage, API calls, concurrent sessions)
- **(5) Does the limit cover the migration scope?** If not, which items are highest value within the limit?

## Broader Lesson

Platform capability verification ("can we do X?") is insufficient. Platform capacity verification ("can we do X at the scale we need?") must happen in the same brainstorm gate. One `RemoteTrigger list` call during brainstorm would have revealed the limit and saved 4 hours of planning and implementation for 6 workflows that can never be migrated.
