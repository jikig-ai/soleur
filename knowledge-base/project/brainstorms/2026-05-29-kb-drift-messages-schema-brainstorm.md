---
date: 2026-05-29
topic: KB-drift findings → conversation/workspace-scoped messages mapping
issue: 4579
branch: feat-fix-kb-drift-messages-schema
pr: 4580
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Map KB-drift findings onto the workspace-scoped `messages` model

## What We're Building

A fix for the nightly **KB-drift walker** (`/api/internal/kb-drift-ingest`) so its
HMAC-signed findings finally persist and surface in the operator's knowledge-domain
draft queue. The persist has **never once succeeded**: the `messages` table requires
`conversation_id, role, content, template_id, workspace_id` (NOT NULL, no default),
and the "draft action card" insert supplies none of them.

The decided fix has four parts:

1. **Relax the drift (migration).** `DROP NOT NULL` on `conversation_id, role,
   content, template_id` and add a discriminator `CHECK` that admits a row as
   *either* a chat message (`conversation_id/role/content` present) *or* a draft
   action card (`user_id/source/owning_domain/draft_preview` present).
2. **Shared `insertDraftCard` helper.** Extract the duplicated draft-card insert
   into one helper that resolves `workspace_id` and writes via the RLS-enforced
   tenant client. KB-drift adopts it now; the two stubbed siblings inherit the
   correct shape.
3. **Cross-tenant-safe write path.** Switch KB-drift from `createServiceClient()`
   (RLS-bypassing) to `getFreshTenantClient(operatorFounderId)` with
   `workspace_id = resolveCurrentWorkspaceId(founderId)` (solo workspace `= founderId`).
4. **One digest card per walker run.** A run inserts a single draft row
   ("N KB-drift findings — review") rather than one row per finding, protecting
   the 7-item Today-queue cap from low-stakes flooding.

## Why This Approach

**The NOT NULLs are confirmed drift, not contract.** Live prod check
(PostgREST OpenAPI `definitions.messages.required`, project `ifsccnjhymdmidffkzhl`,
2026-05-29) returned `["id","conversation_id","role","content","created_at","status",
"template_id","workspace_id"]`. Migration archaeology agrees: `conversation_id/role/
content` are NOT NULL from mig 001, `template_id` from mig 053, `workspace_id` from
mig 059 — and **no migration ever relaxed them for draft rows**. Yet the documented
design (ADR-035/037, ADR-030 §I5, the PR-H daily-priorities plan) models draft cards
as **non-conversational, `user_id`-routed rows**; mig 046's own comment says drafts
"route via `user_id` (no `conversation_id` required)" but the author never dropped the
NOT NULL. So the relaxation *finishes what mig 046 intended* rather than inventing new
semantics.

**A separate table is ruled out by ADR.** ADR-037 explicitly rejects per-source
dedicated tables ("keeps `messages` as the canonical row" + shared dedup index).
A singleton "Knowledge drift" conversation (Option A) was rejected because it
re-imposes the conversation binding the design deliberately avoided, pollutes the
operator's chat list with a synthetic conversation, and *still* requires a `role`-CHECK
widen + sentinel `content` + a registry-valid `template_id`.

**The write path is settled, not speculative.** Migration DDL shows the only insert
policy on `messages` is a PERMISSIVE `WITH CHECK (is_workspace_member(workspace_id,
auth.uid()))`; there is **no RESTRICTIVE policy and no column-grant restriction** on
`messages` (the mig-006 column grant targets `users`; the mig-068 jti-deny RESTRICTIVE
targets other tables). So `getFreshTenantClient` direct insert clears both walls with
**no SECURITY-DEFINER RPC** — and gives the cross-tenant DB-level backstop the service
client lacks.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Relax `conversation_id/role/content/template_id` NOT NULL + discriminator CHECK** | NOT NULLs are confirmed drift (live prod + migrations); honors ADR-037 (no new table) + the non-conversational draft-card design. One migration unblocks all 3 inserters. |
| 2 | **Tenant-client write (`getFreshTenantClient(founderId)`), not service-role** | CLO gate: service-role bypasses `is_workspace_member` WITH CHECK → a mis-resolved `workspace_id` cross-posts into a paying tenant's queue with no DB guard (GDPR Art. 5(1)(f)/32). Tenant client = DB-level backstop. Works sessionlessly (ADR-030 §I2). |
| 3 | **`workspace_id = resolveCurrentWorkspaceId(founderId)`** | HMAC cron has no JWT claim; ADR-044 says absent claim → caller's solo workspace (`= founderId`). Resolve explicitly, never from request body (IDOR). |
| 4 | **Shared `insertDraftCard` helper; fix KB-drift now, defer siblings' upstream** | CPO + CTO consensus. `github-on-event`/`cfo-on-payment-failed` are stubbed ("leader loop wires later"); they adopt the helper's shape for free but their upstream stays deferred to their PR-G work. Migration benefits all 3 regardless. |
| 5 | **One digest card per walker run** (not one per finding) | CPO top risk: 7-item Today cap; a noisy run would bury brand-critical CFO/GitHub drafts. Dedup key becomes per-run (run-date / content hash). |
| 6 | **Redact `draft_preview` through the shared redaction helper** | CLO: siblings redact via `redactGithubSourcedText`; KB-drift currently does not. A broken-target URL could carry a token/signed query string. Consistency + defense-in-depth. |

## Open Questions (for the plan)

1. **Discriminator CHECK exhaustiveness.** Confirm no *existing* prod row violates the
   new `messages_row_kind_chk` (all current rows are chat rows with `conversation_id`).
   Validate the constraint is `NOT VALID`-then-`VALIDATE` safe on the populated table,
   or add as `NOT VALID` first.
2. **`template_id` for draft cards.** Relaxed to nullable for draft rows — but does the
   `dashboard/today/[id]/send` flow or the `template_authorizations` WORM ledger assume
   a non-null `template_id`? If KB-drift cards are review/acknowledge-only (never
   "sent"), nullable is fine; if sendable, they need a registry key. Decide whether
   drift cards are sendable at all.
3. **Digest detail view.** The digest card needs a drill-down (the 12 findings) and
   per-finding dismissal. Does the existing Today card detail/edit modal support a
   list payload, or is a new detail surface needed? (Minor UI — design at plan time.)
4. **Digest dedup semantics.** Per-run `source_ref` (date vs content hash). A content
   hash means an unchanged KB produces an idempotent skip (no duplicate nightly card);
   a date key means one card per night regardless. Likely content-hash for quiet nights.
5. **`role`-CHECK consumer sweep (lower priority under Relax).** Relax leaves `role`
   nullable rather than widening its enum, so chat renderers that assume `user|assistant`
   only see those values on chat rows. Still: confirm no reader does `role NOT NULL`
   assumptions on a query that could return draft rows (`hr-write-boundary-sentinel-sweep`).

## User-Brand Impact

- **Artifact:** draft action-card rows in `messages`; the operator's knowledge-domain
  "Today" queue.
- **Vector:** KB-drift writes via service-role (`createServiceClient`), which **bypasses**
  the `is_workspace_member(workspace_id, auth.uid())` WITH CHECK policy. A mis-resolved
  `workspace_id` lands an operator-internal infra draft in a **paying tenant's** queue
  with no database-level guard.
- **Threshold:** `single-user incident`. A single cross-tenant draft leak is a trust
  breach; GDPR Art. 5(1)(f) integrity/confidentiality + Art. 32 isolation (no statutory
  clock unless a leak actually occurs).
- **Mitigation (decided):** tenant-client write (Decision 2) makes membership the DB
  backstop; `workspace_id` resolved explicitly from `founderId` (Decision 3), never
  request-derived; `draft_preview` redacted (Decision 6).

## Domain Assessments

**Assessed:** Engineering, Product, Legal

### Engineering (CTO)

**Summary:** Confirmed `messages` is the deliberate draft-card home (ADR-051 action_class
work committed to the overload). Flagged that `role IN ('user','assistant')` blocks naive
column-setting and that relaxing NOT NULL on the hot table needs a reader blast-radius
sweep; recommended this be captured as an ADR (canonical draft-card home: `messages` vs
dedicated table). Keep KB-drift fix scoped now; siblings as tracked follow-up.

### Product (CPO)

**Summary:** The Today queue consumer is shipped (PR-H Phase 6), so a successful insert
delivers immediate operator value — not rows nobody sees. Recommended KB-drift-only scope
with a shared helper siblings inherit, and **batching a run into one digest card** to
avoid queue starvation (the single product risk flagged).

### Legal (CLO)

**Summary:** GATE the PR on a cross-tenant-safe write path — service-role bypass of the
workspace-member WITH CHECK is the operator's stated "cross-tenant leak" worst-outcome,
with no DB guard. Switch to `getFreshTenantClient` or assert workspace ownership before
insert. Route `draft_preview` through redaction. No statutory clock; trust/isolation
hygiene (GDPR Art. 5(1)(f)/32), below the legal-specialist threshold.

## Capability Gaps

- **No shared draft-card insert helper exists.** Evidence: the identical column set is
  duplicated inline at `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts:137`,
  `apps/web-platform/server/inngest/functions/github-on-event.ts:237`, and
  `cfo-on-payment-failed.ts:229`; no `insertDraftCard`/`findOrCreate*` helper found
  (`grep -rniE "insertDraftCard|find.?or.?create.*conversation"` → no matches). This is
  an extraction the plan creates, not a missing dependency.

## ADR Follow-up

CTO recommends capturing the boundary call ("draft action cards persist in `messages`
vs a dedicated table; NOT NULL relaxation finishes the mig-046 intent") via
`/soleur:architecture create`. The relaxation amends the de-facto contract set by
ADR-035/037 — record it so the next workspace sweep doesn't re-introduce the NOT NULL.
