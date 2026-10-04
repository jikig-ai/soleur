---
title: Inbound email routing table (Resend Inboxes evaluation prep)
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-resend-inboxes-evaluation
issues: [9458, 9459]
brainstorm: knowledge-base/project/brainstorms/2026-10-03-resend-inboxes-evaluation-brainstorm.md
---

# Spec: Inbox-provider-neutral preparation

## Problem Statement

Resend Inboxes (private beta) offers per-agent addresses, threaded conversations, an MCP server and human collaboration. Soleur's inbound-email stack (ADR-055) is single-tenant: one env-pinned owner, one address, no threading, no agent attribution. Adopting Resend Inboxes now is not advisable (no demand signal, vendor custody of full mail, unpublished region/retention/pricing, unstable API). The same gaps block per-user and per-agent inboxes regardless of vendor, so closing them first keeps both paths cheap.

## Goals

- Make the inbound pipeline address-aware without changing the vendor: resolve an inbound address to a validated workspace and owner through `email_inbox_routes`, with the env-pinned owner as the no-match fallback (plan: `knowledge-base/project/plans/2026-10-03-feat-inbox-provider-neutral-email-routing-plan.md`).
- Obtain written answers from Resend on region, retention, delete semantics, pricing and sub-processors.

## Non-Goals

- Adopting Resend Inboxes or migrating any production mail now.
- A user-facing inbox or per-agent inbox UI.
- Agent-autonomous replies (sends stay human-approved through `sendCompliantOutbound`).
- Multi-tenant mailbox connection (Gmail/Proton OAuth), tracked separately (#5527).
- `agent_id`, `thread_key`, the `InboxProvider` interface and the WORM-trigger rewrite: moved to #9459 at plan review (operator decision, 2026-10-04), together with the multi-tenant hard preconditions.

## Functional Requirements

- FR1: A routing table maps a normalized recipient address to a workspace and owner; `EMAIL_TRIAGE_OWNER_USER_ID` is the fallback when no route matches or no recipients are present.
- FR2: Lookup errors and ambiguous (multi-route) matches throw; they never fall back.
- FR3: Written vendor questions are sent to Resend and the answers recorded in the knowledge base.

## Technical Requirements

- TR1: Parse-and-discard stays structural (no body column, body fetched inside one fused step); no header data is added.
- TR2: The existing probe and Sentry cron monitor run unchanged; route resolution happens inside the `claim-insert` step and its ids are carried forward (replay-safe).
- TR3: No trust is derived from `sender` (ADR-055 constraint).
- TR4: The receive-read Resend key stays a separate scope from the send key.
- TR5: Any plan must pass gdpr-gate and carry the `## User-Brand Impact` section forward.

## Revisit Triggers (deferred adoption)

Resend GA with published retention, pricing and delete semantics, or three or more founders asking for an inbox.
