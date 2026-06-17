---
title: "Never assert live prod flag/membership state from a migration-header snapshot — check Flagsmith + Supabase"
date: 2026-06-18
category: workflow-patterns
tags: [prod-state, flagsmith, supabase, verification, stale-snapshot, plan-precondition]
issue: PR #5494 (feat-shared-workspace-email-triage-inbox)
---

## What happened

While planning the shared-workspace email-triage inbox, I asserted a
load-bearing precondition — "prod has solo workspaces only; team-workspace
sharing is OFF" — and built it into the plan as a blocker, sourced from the
**header comment of migration `068_attachments_workspace_shared.sql`**:

> "shipped behind the runtime flag TEAM_WORKSPACE_INVITE_ENABLED (currently OFF
> in prd) … In a prd snapshot with no multi-user workspaces, the new co-member
> branch is empirically dormant."

The operator corrected it: *"team workspaces is enabled through flagsmith and
jean.deruelle is already co owner in prod. Where did you get that stale info
from?"* A read-only Supabase probe confirmed: workspace `754ee124` (the one that
owns the email-triage items) has FOUR members including `jean.deruelle@` as a
second `role='owner'`. The migration comment was a ~3-week-old point-in-time
snapshot, and runtime flag state lives in **Flagsmith**, not in a code comment
or a Doppler env.

The cost: a plan built around a false "necessary-but-not-sufficient / needs a
membership change" framing, surfaced to the operator as a decision that wasn't
actually open. The feature was simply shippable.

## The rule

A migration header / code comment that states a **runtime fact** (a flag is
OFF, "no multi-user workspaces exist", "this branch is dormant in prd") is a
*point-in-time snapshot from authoring day*, NOT current truth. Runtime state
has authoritative sources — query them:

- **Feature-flag state** → Flagsmith (or the `/soleur:flag-list` skill), never a
  Doppler env or a code comment.
- **Membership / row / identity state** → prod Supabase read-only (Supabase MCP,
  or `DATABASE_URL_POOLER` + a read-only query). `hr-no-dashboard-eyeball-pull-data-yourself`.

This is the runtime-state sibling of the existing "plan-quoted numbers are
preconditions to verify, not facts" rule — extended from measurements to
flag/membership/identity state, and specifically to the trap of trusting a
**migration header's prod-snapshot prose**.

## How to apply

When a plan's load-bearing precondition is a statement about live prod (a flag,
a count, an identity, a membership), verify it against the source of truth
BEFORE building the plan around it — especially if the source you have is a code
comment. A read-only probe is cheap; a plan built on a stale snapshot wastes the
whole downstream effort and can manufacture a non-existent operator decision.
