---
title: "Close-authority boundary for the action-required SLA lifecycle cron"
status: accepted
date: 2026-07-22
issue: 6836
supersedes: null
---

# ADR-138: Close-authority boundary for the action-required SLA lifecycle cron

## Context

`action-required` is the agent pipeline's escalation channel to the non-technical operator.
It had a ~0% resolution rate on its oldest items (30 open, oldest 131 days). Root-causing (#6836,
supersedes closed #6769) showed the channel delivers weekly but is untriaged, undelivered, and
polluted — not dead. Part of the fix (`cron-action-required-sla` + `sla-issue-process`) grants an
automated cron the authority to **auto-close** some of these operator-escalation issues. Because
the operator is non-technical and this is the channel that surfaces production emergencies,
auto-closing a genuine unresolved emergency is a `single-user incident` (brand-survival). The
question is: what may the cron close, and how is that boundary made fail-safe?

## Decision

The cron's close authority is bounded by an **allowlist, never a denylist**:

1. **OPS is the default class and is NEVER closed** — only escalated (priority bumped as the issue
   ages). Any issue that does not match an explicit expirable class, and any *unclassified* issue,
   is OPS. A new/unknown label can therefore never make an issue closeable.
2. **Only two structurally-dead classes are expirable:** `dead-content` (keyed on the AGENT-owned
   `content-publisher` label — NEVER the human-attachable broad `content` label) and
   `decision-challenge`. `content-starvation` is explicitly OPS (a genuine standing signal).
3. **Expiry is gated by three additional fail-safes:** a human-engagement veto (a non-bot assignee
   or a recent non-bot touch aborts the close), a last-**non-bot**-activity inactivity clock (bot
   noise cannot keep an issue "fresh" and thereby immortal), and a TOCTOU re-assert (abort if the
   issue's `updatedAt` drifted since the dispatcher's list snapshot).
4. **The feared case self-reports:** every close emits a structured `op:action-required-sla` event;
   a Sentry alert fires only on an expire where `human_engaged=true` — i.e. the veto failed. We do
   NOT alert on out-of-allowlist expire because the allowlist makes that unreachable.

The classification, thresholds, and veto live in a pure module (`action-required-sla-policy.ts`)
so the boundary is exhaustively unit-tested independently of all I/O.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| **Aggressive SLA auto-close** — close any action-required item past its SLA regardless of class | Directly risks silently closing a live emergency the operator hasn't reached. The catastrophic failure this ADR exists to prevent. |
| **Nag/escalate only, never auto-close** | Safe, but the structurally-dead chores (manual social-posting the non-technical operator will never do) accumulate forever and keep polluting the channel — the original defect is only half-fixed. |
| **Key expiry on the broad `content` label** | `content` is human-attachable; an ops emergency about the content pipeline can carry it and would be wrongly expired. Keying on the agent-only `content-publisher` label closes this hole (deepen-plan finding D1). |
| **Measure staleness from raw `updatedAt`** | This cron's own escalation comments and sibling crons bump `updatedAt`, so a neglected issue attracting routine bot noise would never reach the inactivity threshold — expiry becomes dead code for exactly the backlog it targets (deepen-plan finding D3). Rejected in favor of the last-non-bot-activity clock. |

## Consequences

- The cron can drain the structurally-dead classes without operator effort, while a genuine ops ask
  is escalated (louder) but never closed — the exact asymmetry `hr-weigh-every-decision-against-target-user-impact`
  demands at the `single-user incident` threshold.
- The auto-close precedent is `cron-content-publisher.ts` (already auto-closes the content-starvation
  issue on recovery); this ADR generalizes that pattern with an explicit fail-safe boundary.
- If a future class is added to the expirable allowlist, it MUST be an agent-owned label (never a
  human-attachable one) and MUST be added to `action-required-sla-policy.ts` with unit coverage.

## C4 impact

None. The `founder` actor (`model.c4:8`) and the `inngest` container (`model.c4:188`) are already
modeled; the new cron is a Component within the already-modeled Inngest container (the model is
Container-granularity), and the "Inngest cron → GitHub issues" relationship already exists via the
sibling `cron-content-publisher`. No new external actor, system, or access relationship.
