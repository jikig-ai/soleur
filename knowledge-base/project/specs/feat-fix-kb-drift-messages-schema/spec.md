---
feature: fix-kb-drift-messages-schema
issue: 4579
branch: feat-fix-kb-drift-messages-schema
pr: 4580
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-05-29-kb-drift-messages-schema-brainstorm.md
---

# Spec: Map KB-drift findings onto the workspace-scoped `messages` model

## Problem Statement

The nightly KB-drift walker POSTs HMAC-signed findings to
`/api/internal/kb-drift-ingest`, which persists each as a "draft action card" row in
`messages`. The insert has **never succeeded**: `messages` requires (NOT NULL, no
default) `conversation_id, role, content, template_id, workspace_id` — confirmed live
on prod (PostgREST OpenAPI `definitions.messages.required`, 2026-05-29) — but the
draft-card insert supplies none of them, so it fails with HTTP 500 `Persist failed`.
The same latent gap exists in two sibling draft-card producers
(`github-on-event`, `cfo-on-payment-failed`), which share the identical insert shape
but are stubbed and have likewise never persisted.

The NOT NULL columns are **drift**: ADR-035/037, ADR-030 §I5, and the PR-H plan model
draft cards as non-conversational, `user_id`-routed rows; mig 046 added the draft-card
columns and commented "no `conversation_id` required" but never dropped the NOT NULL.

## Goals

- The nightly KB-drift walker run concludes `success` (a correctly-signed POST → 2xx).
- A finding persists and surfaces in the operator founder's knowledge-domain Today
  queue, scoped to the operator's own workspace.
- The cross-tenant leak vector (service-role RLS bypass) is closed.
- The fix generalizes structurally to the two sibling inserters via a shared helper +
  the schema relaxation.

## Non-Goals

- Wiring the stubbed upstream of `github-on-event` / `cfo-on-payment-failed` (their
  "leader prompt loop" remains deferred to their PR-G work). Tracked as follow-up.
- A dedicated `draft_action_cards` table (rejected by ADR-037).
- A singleton "Knowledge drift" conversation (Option A, rejected in brainstorm).
- Reworking the Today queue ranking / per-source caps.

## Functional Requirements

- **FR1 — Schema relaxation.** New migration: `DROP NOT NULL` on `messages.conversation_id`,
  `role`, `content`, `template_id`; add `CHECK messages_row_kind_chk` admitting a row as
  *either* a chat row (`conversation_id/role/content` NOT NULL) *or* a draft-card row
  (`user_id/source/owning_domain/draft_preview` NOT NULL). Provide a `.down.sql`.
- **FR2 — Shared `insertDraftCard` helper.** Extract the draft-card insert into one helper
  taking `{ founderId, source, source_ref, owning_domain, draft_preview, tier, urgency,
  trust_tier }`; resolves `workspace_id` and writes via the tenant client; maps `23505`
  (dedup index) to an idempotent skip. KB-drift adopts it; siblings refactored to call it.
- **FR3 — Cross-tenant-safe write.** KB-drift writes via `getFreshTenantClient(operatorFounderId)`
  (not `createServiceClient`), with `workspace_id = resolveCurrentWorkspaceId(operatorFounderId)`.
- **FR4 — Digest card per run.** A walker run inserts **one** draft row summarizing N
  findings (`draft_preview = "N KB-drift findings — review"`), with the finding list in a
  detail payload; dedup keyed per-run (content hash preferred so unchanged KB → idempotent skip).
- **FR5 — Redaction.** `draft_preview` (and finding detail) routed through the shared
  redaction helper before insert.
- **FR6 — Acceptance verification.** `gh workflow run "KB-drift walker"` concludes `success`;
  the digest row is visible in the operator's Today queue scoped to the correct workspace;
  re-runs over an unchanged KB hit the dedup skip (no duplicate card).

## Technical Requirements

- **TR1 — Migration safety.** Add the discriminator CHECK `NOT VALID` then `VALIDATE` on the
  populated `messages` table; confirm all existing rows are chat rows (carry `conversation_id`)
  so validation cannot fail. No data backfill required.
- **TR2 — Write-boundary sweep** (`hr-write-boundary-sentinel-sweep-all-write-sites`,
  `hr-type-widening-cross-consumer-grep`). Grep all `messages` readers for `role`/`content`/
  `conversation_id` NOT-NULL assumptions that could now see draft rows; confirm the Today
  consumer and chat render path are unaffected (verified in brainstorm: readers filter by
  `user_id/tier/status`; chat render ignores no-conversation rows).
- **TR3 — Observability** (`hr-observability-as-plan-quality-gate`,
  `cq-silent-fallback-must-mirror-to-sentry`). The existing Sentry `op:"persist"` capture
  stays; add structured fields (resolved `workspace_id`, finding count, dedup-skip count).
  All failure paths reachable from Sentry/Better Stack without SSH.
- **TR4 — No RPC needed.** Tenant-client direct insert clears grants + RLS (migration DDL:
  PERMISSIVE workspace-member WITH CHECK only, no RESTRICTIVE policy, no column-grant on
  `messages`). Do not introduce a SECURITY-DEFINER RPC unless a runtime 42501/RLS failure
  proves otherwise.
- **TR5 — GDPR gate** (`hr-gdpr-gate-on-regulated-data-surfaces`). Run `/soleur:gdpr-gate`
  on the diff: workspace-scoped write + redaction are the regulated surfaces.

## Acceptance Criteria (carry from issue #4579)

- [ ] `gh workflow run "KB-drift walker"` concludes `success` (correctly-signed POST → 2xx).
- [ ] A finding (digest) row persists and surfaces in the operator's knowledge-domain Today
      queue, scoped to the correct workspace.
- [ ] Dedup path works (`messages_active_draft_dedup_idx` → `23505` skip on re-runs).
- [ ] Sibling generalization addressed: shared helper extracted; upstream wiring explicitly
      scoped out with a follow-up issue.

## Brand-Survival / User-Brand Impact

Threshold: **single-user incident**. The decisive control is FR3 (tenant-client write):
service-role bypass of `is_workspace_member` is the cross-tenant leak vector. The
`user-impact-reviewer` agent must verify FR3 + FR5 at PR review. See brainstorm
`## User-Brand Impact`.

## Follow-up

- ADR via `/soleur:architecture create`: canonical draft-card home = `messages`; NOT NULL
  relaxation finishes the mig-046 intent (amends the de-facto ADR-035/037 contract).
- Issue: wire `github-on-event` / `cfo-on-payment-failed` upstream onto the shared helper
  when their leader-loop (PR-G) work lands.
