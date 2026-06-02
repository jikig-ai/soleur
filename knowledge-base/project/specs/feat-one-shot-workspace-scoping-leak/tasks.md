---
feature: feat-one-shot-workspace-scoping-leak
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-02-fix-workspace-scoping-leak-knowledge-drift-and-feature-audit-plan.md
status: ready
---

# Tasks: Workspace-scoping leak fix + feature scoping audit

Derived from the deepened plan. Implement with TDD (RED → GREEN) where noted.
Plan is the source of truth; this file is the executable breakdown.

## Phase 0 — Preconditions (verify, no edits)

- [ ] 0.1 Confirm `insert-draft-card.ts:66` solo-pin (`workspace_id = input.founderId`).
- [ ] 0.2 Confirm `today/route.ts` has no workspace filter (only `.eq("user_id")`).
- [ ] 0.3 Confirm `resolveCurrentWorkspaceId(userId, supabase)` signature (`workspace-resolver.ts:190`).
- [ ] 0.4 Read the kb-drift-ingest payload Zod schema; confirm it lacks `workspace_id` and locate where to add it.
- [ ] 0.5 Read-only DEV-then-prod probe (Supabase MCP, project per `hr-dev-prd-distinct-supabase-projects`): count `messages` rows where `source = 'kb_drift'` to size the migration-093 decision.
- [ ] 0.6 Locate the KB-drift walker producer (POSTs to `/api/internal/kb-drift-ingest`); confirm it knows the scanned `workspace_id`. Files: `apps/web-platform/infra/kb-drift.tf` + walker source.

## Phase 1 — Fix the read leak (active-workspace scoping) [TDD]

- [ ] 1.1 RED: add a route test under `apps/web-platform/test/api/dashboard/today/` (verify vitest `include:` globs) seeding two workspaces for one owner + a drift card in workspace A; assert it returns only when A is active.
- [ ] 1.2 GREEN: in `today/route.ts`, resolve `activeWorkspaceId = await resolveCurrentWorkspaceId(userId, supabase)` (import from `@/server/workspace-resolver`); add `.eq("workspace_id", activeWorkspaceId)` to the select chain.
- [ ] 1.3 Update the `today/route.ts` docblock to state the active-workspace scoping invariant.
- [ ] 1.4 Audit `today/[id]/{send,edit,discard,cancel,cost,undo}/route.ts`: each scopes by `.eq("id").eq("user_id")` (+RLS). Add an active-workspace guard for consistency OR record per-route rationale (AC3).

## Phase 2 — Fix the write attribution (workspace-correct card) [TDD]

- [ ] 2.1 Add `workspace_id` to the HMAC-signed kb-drift-ingest payload Zod schema + the walker producer that POSTs it.
- [ ] 2.2 RED: assert a KB-drift POST for workspace A writes a `messages` row with `workspace_id = A`.
- [ ] 2.3 GREEN: add an explicit optional `workspace_id` override param to `insertDraftCard` (the docblock at `:12-20` prescribes this exact extension); default stays solo-pin for github/cfo callers.
- [ ] 2.4 `kb-drift-ingest/route.ts`: pass payload `workspace_id` into `insertDraftCard`. Update the `:208` `logger.info` `workspace_id` field for log accuracy (NOT a write site — log field only).

## Phase 3 — Migration 093 decision (optional)

- [ ] 3.1 From the Phase 0.5 count, decide: forward-only writes suffice (record "no migration" + rationale) OR write `093_reattribute_kb_drift_drafts.sql` (+ `.down.sql`) following 090-092 conventions (txn-wrapped, no CONCURRENTLY).

## Phase 4 — Audit: conversations

- [ ] 4.1 `dashboard/page.tsx:240` orphaned-conversation count (`.eq("user_id")`, cross-workspace): scope to active workspace OR document the cross-workspace intent for the reconnect hint.
- [ ] 4.2 `conversations-tools.ts:163` list tool scopes by `repo_url`: audit whether two workspaces can share a `repo_url`; add `.eq("workspace_id", active)` if so. Note the `visibility='private'` default (mig 075) as the second scoping axis.
- [ ] 4.3 Sweep ALL `from("conversations")` sites (per `hr-write-boundary-sentinel-sweep-all-write-sites`); classify each workspace-correct / by-design / needs-fix.

## Phase 5 — Audit: rate limiting + billing

- [ ] 5.1 Rate limiting: document `sessionThrottle` (`ws-handler.ts:1294`) + `user_concurrency_slots` (mig 029) per-user keying. Decide keep-per-user (recommended — coupled to per-user plan_tier; per-workspace would let one user multiply paid capacity) and add an invariant comment, OR file a tracking issue for per-workspace caps (do NOT implement here).
- [ ] 5.2 Billing: fix or relabel the cross-workspace conversation count at `settings/billing/page.tsx:54`. Note the `const workspaceId = user.id` solo-assumption (`:30`) is acceptable for per-user billing. File a per-workspace/per-org billing tracking issue IF on `knowledge-base/product/roadmap.md`, with CPO input.

## Phase 6 — Verify

- [ ] 6.1 Run affected tests via `package.json scripts.test` (vitest); RED→GREEN for Phases 1-2.
- [ ] 6.2 `tsc --noEmit` clean for web-platform.
- [ ] 6.3 Optional Playwright: two-workspace owner, drift card on A, switch to B, confirm absence.

## Post-merge (operator)

- [ ] PM.1 If migration 093 created: applied via `web-platform-release.yml#migrate` (runs on merge — no separate SSH apply). Verify via Supabase MCP read-only that `kb_drift` rows carry the correct `workspace_id`. Use `Ref #<issue>` in PR body; `gh issue close` after verification.

## Gate reminders

- GDPR gate (`/soleur:gdpr-gate`) — `messages` RLS + possible migration; run at review if not already.
- CPO sign-off required (single-user-incident threshold) before `/work`.
- `user-impact-reviewer` invoked at review-time.
- Place tests under `apps/web-platform/test/` (vitest `include:` skips co-located).
