---
date: 2026-06-15
category: workflow-patterns
tags: [work-skill, cto, architecture-decision, decision-routing, plan-vs-codebase]
issue: 5325
---

# Architectural-fork decisions discovered mid-`/work` route to the CTO agent, not the operator

## Context

During `/soleur:work` on feat-agent-native-outbound-email (#5325, brand-survival
threshold = single-user incident), tracing the actual producer (not the plan's
`[work-verified]` claim) revealed the plan's central mechanism — deepen P0-1's
"reuse `action_sends` for the body-hash-bound approval + send-audit" — was
structurally blocked:

- `action_sends.message_id` is `NOT NULL REFERENCES public.messages(id)` with
  `UNIQUE(message_id)` — built for "founder clicks Send on a draft *message* row."
- Agent MCP tool handlers have no real `messages.id` at execution time (tool_use
  runs inside the SDK iterator; the assistant message is persisted only at the
  `result` event, fresh `randomUUID` at insert; the tool closure carries `userId`
  only).
- `scope_grants` creation is UI-only (`POST /api/scope-grants/grant`); no
  autonomous grant path exists.

The resolution was a genuine architecture fork — (A) dedicated `outbound_sends`
WORM table, (B) gate-only approval with no WORM send-row, (C) full `action_sends`
reuse via agent-runtime plumbing — each with materially different scope, risk,
and GDPR Art. 5(2) accountability posture.

## The mistake

The first instinct was to escalate the fork to the **operator** via
`AskUserQuestion`. The operator is non-technical and correctly pushed back:
*"I shouldn't be the one making that decision but the CTO."* The decision was
then routed to the `soleur:engineering:cto` agent, which ruled Option A (dedicated
WORM table mirroring the proven `action_sends` posture, body-hash-bound via
chokepoint recompute, no shared-runtime blast radius) with a full rationale +
rejected-alternatives for ADR-060.

## The rule (now in `skills/work/SKILL.md` Phase 1)

When mid-work you hit a **plan-vs-codebase contradiction** whose resolution is an
**engineering/architecture decision** (schema/audit substrate, data model,
technology choice, security model, which load-bearing module to disturb), route
the BINDING decision to the `soleur:engineering:cto` agent — NOT to the operator.

- Operator escalation is reserved for **product / scope / preference** decisions
  (what to build), never **how** to build it.
- Hand the CTO: the discovered evidence (`file:line`), the candidate options with
  trade-offs, and the plan's `brand_survival_threshold`.
- Implement exactly what the CTO returns; record the decision + rejected
  alternatives in an ADR (`/soleur:architecture`).
- This is a **routing rule, not an approval gate** — it fires in pipeline mode too.

## Why this matters

Routing architecture to a non-technical operator either (a) stalls autonomous
work on a decision they can't make, or (b) extracts a rubber-stamp that launders
an un-reviewed engineering choice as "operator-approved." The CTO agent already
exists and is auto-consulted in brainstorm/plan domain detection; `/work` simply
had no explicit hook to consult it when a fork surfaced *after* planning. Related:
`cm-challenge-reasoning-instead-of`, `pdr-when-a-user-message-contains-a-clear`
(domain routing), `wg-when-a-workflow-gap-causes-a-mistake-fix`, and the
"trace the ACTUAL producer before coding" Phase-1 rule that surfaced the fork.
