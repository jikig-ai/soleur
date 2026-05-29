---
feature: fix-kb-drift-messages-schema
issue: 4579
branch: feat-fix-kb-drift-messages-schema
pr: 4580
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-29-fix-kb-drift-messages-schema-plan.md
status: deepened
---

# Tasks: Map KB-drift findings onto the workspace-scoped `messages` model

Derived from the deepened plan. Phase order is load-bearing (contract → consumers).

## Phase 0 — Live-prod precondition gate (BLOCKING, read-only)

- [ ] 0.1 `information_schema.columns` for `messages` (5 cols): record is_nullable + column_default. prod ≠ files → PAUSE.
- [ ] 0.2 0 discriminator violators (chat-branch OR user_id-free draft-branch).
- [ ] 0.3 Operator SOLO workspace exists: `workspaces.id='<founderId>'` with `id=owner_user_id`, own org; AND `workspace_members(self,self)` exists.
- [ ] 0.4 Sibling-row probe (`source IN ('github','stripe') AND status='draft'`).
- [ ] 0.5 Dedup index predicate is partial-on-draft.
- [ ] 0.6 Anonymization-safety: `count(*) WHERE user_id IS NULL AND conversation_id IS NULL` = 0.

## Phase 1 — Migration 082 (RED-first)

- [ ] 1.1 Assert 082 is the strict max (`ls | grep -oE '^[0-9]+' | sort -n | tail -1` = 081, no 082_*); re-check at rebase.
- [ ] 1.2 `082_...sql`: DROP NOT NULL conversation_id/role/content; `DROP CONSTRAINT IF EXISTS messages_row_kind_chk`; `ADD CONSTRAINT ... NOT VALID` with card branch = `(source IS NOT NULL AND owning_domain IS NOT NULL AND draft_preview IS NOT NULL)` (user_id-free, erasure-safe); `VALIDATE`; `COMMENT ON CONSTRAINT`. Comment: single-txn lock + Decision A + future-DROP-NOT-NULL warning.
- [ ] 1.3 `.down.sql`: DO-block guard (RAISE if draft rows exist) BEFORE drop+SET NOT NULL.
- [ ] 1.4 Migration contract test (7.1) RED→GREEN.

## Phase 2 — Shared `insertDraftCard` helper

- [ ] 2.1 RED: `test/server/insert-draft-card.test.ts`.
- [ ] 2.2 `server/messages/insert-draft-card.ts`: header note (import tenant client from `@/lib/supabase/tenant`, Next-free); `workspace_id = founderId` (SOLO-PIN, NOT resolveCurrentWorkspaceId); narrow source/owning_domain to MESSAGE_* unions; template_id='default_legacy'; redact draft_preview in-helper; 23505→deduped else Sentry+throw; source_ref-must-be-structured invariant.
- [ ] 2.3 GREEN.

## Phase 3 — kb-drift route adopts helper + digest

- [ ] 3.1 Remove createServiceClient() (+ allowlist sweep); leave auth/cap block :82-104 untouched.
- [ ] 3.2 Empty-findings guard → 200.
- [ ] 3.3 Strip URL query string from each finding `target`; build digest preview; full-sha256 `source_ref="digest-"+sha256(...)` (no slice).
- [ ] 3.4 One insertDraftCard(... action_class:"knowledge.kb_drift", tier external_low_stakes); map deduped/inserted.
- [ ] 3.5 Fix :12 "051"→"052".

## Phase 4 — Sibling refactors

- [ ] 4.1 github-on-event → insertDraftCard (source_ref, tier external_low_stakes, no action_class).
- [ ] 4.2 cfo-on-payment-failed → insertDraftCard (tier MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL; action_class: payload.action_class ?? "finance.payment_failed" resolved at call site; no source_ref); confirms silent-swallow closed.

## Phase 5 — Digest card operator-action path (UI)

- [ ] 5.1 KbDriftCard: digest detect (source_ref startsWith "digest-") → Dismiss button → existing /discard; suppress spawn button for digests.

## Phase 6 — Observability

- [ ] 6.1 Sentry dedup-skip mirror (op:"dedup-skip", info, include source_ref).
- [ ] 6.2 Structured success log: workspace_id, finding_count, deduped.

## Phase 7 — Tests (RED→GREEN)

- [ ] 7.1 Migration contract (draft row inserts; user_id=NULL cardless row passes CHECK; neither-branch rejected; chat row inserts; re-apply idempotent).
- [ ] 7.2 Helper unit (workspace_id===founderId solo-pin; 23505/23514; template_id; redaction; type-narrowed; brand-critical tier passes external_tier_status_check).
- [ ] 7.3 Cross-tenant + SOLO-PIN: (a) foreign workspace_id rejected, JWT role=authenticated/sub=founderId; (b) stale current_workspace_id (foreign, operator is member) → write STILL targets solo workspace.
- [ ] 7.4 Route digest (one insert; full-sha256 source_ref; re-POST→deduped:1; empty→no insert; action_class set).
- [ ] 7.5 Dismiss-then-recur (archived row frees dedup slot → new card).
- [ ] 7.6 Redaction incl. URL-query strip (`?X-Amz-Signature=` removed) + token in source_path scrubbed.
- [ ] 7.7 Digest no-spawn regression (digest card renders no send-capable affordance).
- [ ] 7.8 Write-boundary sweep: documented grep in PR body.

## Phase 8 — Gates & ship

- [ ] 8.1 /soleur:gdpr-gate on diff (confirm redaction covers URL-query token shape).
- [ ] 8.2 tsc --noEmit + vitest run (touched packages) green.
- [ ] 8.3 Follow-ups (Ref): ADR (next free integer by filename; fix ADR-037 stale frontmatter); sibling upstream; drill-down UI; (conditional) latent chat-insert omission.
- [ ] 8.4 Post-merge (ship): verify migrate/verify-migrations; `gh workflow run "KB-drift walker"` → conclusion success; digest row scoped to operator SOLO workspace; Dismiss works.
