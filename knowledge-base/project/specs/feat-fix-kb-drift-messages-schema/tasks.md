---
feature: fix-kb-drift-messages-schema
issue: 4579
branch: feat-fix-kb-drift-messages-schema
pr: 4580
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-29-fix-kb-drift-messages-schema-plan.md
status: ready
---

# Tasks: Map KB-drift findings onto the workspace-scoped `messages` model

Derived from the finalized (post-review) plan. Phase order is load-bearing (contract → consumers).

## Phase 0 — Live-prod precondition gate (BLOCKING, read-only, no code)

- [ ] 0.1 Query `information_schema.columns` for `messages` (`conversation_id/role/content/template_id/workspace_id`): record `is_nullable` + `column_default`. If prod ≠ migration files → PAUSE, re-confirm 082 shape before adding the CHECK.
- [ ] 0.2 Confirm 0 discriminator violators (`SELECT count(*) … WHERE NOT (chat-branch OR draft-branch)` = 0).
- [ ] 0.3 Confirm `KB_DRIFT_OPERATOR_FOUNDER_ID` has `workspace_members(self,self)` = true.
- [ ] 0.4 Sibling-row probe: `SELECT source,count(*) … WHERE source IN ('github','stripe') AND status='draft'`.
- [ ] 0.5 Confirm dedup index predicate is partial-on-draft (`pg_indexes` indexdef contains `WHERE status='draft' AND source_ref IS NOT NULL`).

## Phase 1 — Migration 082 (RED-first)

- [ ] 1.1 Confirm `082` is the next free number (`ls migrations/ | grep '^082'`); renumber on collision at merge/rebase.
- [ ] 1.2 Write `082_relax_messages_draft_card_nullability.sql`: `DROP NOT NULL` on `conversation_id/role/content`; `ADD CONSTRAINT messages_row_kind_chk … NOT VALID`; `VALIDATE CONSTRAINT`. Comment: single-transaction runner → split is cosmetic/forward-portable.
- [ ] 1.3 Write `.down.sql` (drop CHECK; re-SET NOT NULL; document destructive/manual-only).
- [ ] 1.4 Migration contract test (Phase 7.1) — RED then GREEN.

## Phase 2 — Shared `insertDraftCard` helper

- [ ] 2.1 RED: `test/server/insert-draft-card.test.ts` (inserted / 23505-deduped / 23514-throw+Sentry / 2-arg resolver / template_id / redaction / optional field omission).
- [ ] 2.2 Create `server/messages/insert-draft-card.ts` importing tenant client from `@/lib/supabase/tenant` (Next-free); resolve `workspace_id`; `template_id='default_legacy'`; redact `draft_preview` in-helper; map `23505`→deduped, else Sentry+throw.
- [ ] 2.3 GREEN.

## Phase 3 — kb-drift route adopts helper + digest

- [ ] 3.1 Remove `createServiceClient()` (+ `.service-role-allowlist` sweep).
- [ ] 3.2 Empty-findings guard → 200 no insert.
- [ ] 3.3 Build digest: content-hash `source_ref="digest-"+sha256(...).slice(0,16)`; newline-packed `draft_preview`.
- [ ] 3.4 Single `insertDraftCard(... action_class:"knowledge.kb_drift")`; map deduped/inserted → response shape.
- [ ] 3.5 Fix `:12` "migration 051"→"052".
- [ ] 3.6 Route digest test (Phase 7.4).

## Phase 4 — Sibling refactors (github + cfo)

- [ ] 4.1 github-on-event: confirm whether it sets `action_class`; replace inline insert with `insertDraftCard({... source_ref, action_class?})`.
- [ ] 4.2 cfo-on-payment-failed: replace inline insert with `insertDraftCard({... action_class: payload.action_class ?? "finance.payment_failed"})` (resolved at call site; no `source_ref`); confirms silent-error swallow is closed.

## Phase 5 — Digest card operator-action path (UI)

- [ ] 5.1 `KbDriftCard`: detect digest (`source_ref?.startsWith("digest-")`); render Dismiss (reuse StripeCard pattern) → existing `/today/[id]/discard`; suppress spawn button for digests.

## Phase 6 — Observability

- [ ] 6.1 Sentry mirror on dedup-skip path (op:"dedup-skip", info).
- [ ] 6.2 Structured success log: `workspace_id`, `finding_count`, `deduped`.

## Phase 7 — Tests (RED→GREEN)

- [ ] 7.1 Migration contract (insert draft row + external_tier_status pass; neither-branch rejected; chat row still inserts).
- [ ] 7.2 Helper unit (see 2.1).
- [ ] 7.3 Cross-tenant rejection integration (foreign workspace_id rejected; JWT role=authenticated, sub=founderId).
- [ ] 7.4 Route digest (one insert; re-POST→deduped:1; empty→no insert; action_class set).
- [ ] 7.5 Dismiss-then-recur (archived row frees dedup slot → new card inserts).
- [ ] 7.6 Redaction (token/email in finding target scrubbed).
- [ ] 7.7 Write-boundary sweep: documented grep in PR body (Today + chat render safe).

## Phase 8 — Gates & ship

- [ ] 8.1 `/soleur:gdpr-gate` on the diff.
- [ ] 8.2 `tsc --noEmit` + `vitest run` (touched packages) green.
- [ ] 8.3 File follow-up issues (`Ref` from PR): ADR; sibling upstream; drill-down UI; (conditional) latent chat-insert omission.
- [ ] 8.4 Post-merge (ship): verify `migrate`/`verify-migrations`; `gh workflow run "KB-drift walker"` → conclusion success; verify digest row scoped to operator workspace; verify Dismiss works.
