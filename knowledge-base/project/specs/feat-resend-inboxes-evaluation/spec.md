---
title: Inbox-provider-neutral preparation (Resend Inboxes evaluation)
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

- Make the inbound pipeline address-aware (address → workspace, address → agent) without changing the vendor.
- Add threading primitives so a thread view is possible on either stack.
- Put an `InboxProvider` seam in front of ingest and send so a future Resend Inboxes spike is an adapter, not a rewrite.
- Obtain written answers from Resend on region, retention, delete semantics, pricing and sub-processor list.

## Non-Goals

- Adopting Resend Inboxes or migrating any production mail now.
- A user-facing inbox or per-agent inbox UI.
- Agent-autonomous replies (sends stay human-approved through `sendCompliantOutbound`).
- Multi-tenant mailbox connection (Gmail/Proton OAuth), tracked separately (#5527).

## Functional Requirements

- FR1: A routing table maps an inbound address to a workspace and optionally an agent; `EMAIL_TRIAGE_OWNER_USER_ID` becomes the fallback, not the only path.
- FR2: `email_triage_items` records `agent_id` (nullable) and `thread_key` derived from `In-Reply-To`/`References`.
- FR3: An `InboxProvider` interface covers ingest verification, body fetch and send; the current Resend Inbound code is its first implementation.
- FR4: Written vendor questions are sent to Resend and the answers are recorded in the knowledge base.

## Technical Requirements

- TR1: Parse-and-discard stays structural (no body column, body fetched inside one fused step).
- TR2: The existing probe and Sentry cron monitor run unchanged against the routed path; any new failure mode mirrors to Sentry (`cq-silent-fallback-must-mirror-to-sentry`).
- TR3: No trust is derived from `sender` (ADR-055 constraint).
- TR4: The receive-read Resend key stays a separate scope from the send key.
- TR5: Any plan must pass gdpr-gate and carry the `## User-Brand Impact` section forward.

## Revisit Triggers (deferred adoption)

Resend GA with published retention, pricing and delete semantics, or three or more founders asking for an inbox.
