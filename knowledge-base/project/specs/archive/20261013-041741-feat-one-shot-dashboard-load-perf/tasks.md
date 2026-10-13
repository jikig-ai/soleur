---
title: "Tasks — perf: Dashboard load + conversation-list performance"
plan: knowledge-base/project/plans/2026-07-07-perf-dashboard-load-and-conversation-list-plan.md
branch: feat-one-shot-dashboard-load-perf
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

## Phase 0 — Measure (diagnostic gate)
- [ ] 0.1 Capture cold-load network waterfall (Playwright/devtools): bytes + duration for `/api/kb/tree`, `/api/workspace/active-repo` (note it fires twice), `conversations` and `messages` PostgREST calls.
- [ ] 0.2 Query dev `pg_stat_statements` top-10 by total exec time + mean rows for the `messages … IN (…)` call (Supabase MCP, read-only). Rule out H-null (structural Realtime/cron IO).
- [ ] 0.3 Record baseline in PR body; confirm `messages` fetch + `/api/kb/tree` are the dominant contributors before building.

## Phase 1 — Enriched conversation-list RPC (CRITICAL)
- [ ] 1.1 Check whether the rail predicate is already index-covered (`idx_conversations_user_repo`, `idx_conversations_active_unarchived`).
- [ ] 1.2 Write `supabase/migrations/125_list_conversations_enriched.sql` (+ `.down.sql`): `list_conversations_enriched(...)` as `LANGUAGE sql SECURITY INVOKER` (RLS-preserving — diverges from the DEFINER+service_role precedents 027/037 because this is client-callable), `GRANT EXECUTE … TO authenticated` (NOT the precedents' REVOKE-all). LATERAL snippet subqueries over indexed `messages(conversation_id, created_at)` returning first-user / first-assistant / last-content / last-leader; same filters + order + limit as the current hook. Verify no `SECURITY DEFINER` helper is transitively called in the body. Plain `CREATE INDEX` only if a new index is needed (no `CONCURRENTLY`). Escalate to DEFINER + `search_path` pin + explicit tenant WHERE + ADR-101 ONLY if data-integrity review shows INVOKER cannot reach a needed row.
- [ ] 1.3 Rewrite `hooks/use-conversations.ts` `fetchConversations` to call the RPC; feed snippets into unchanged `deriveTitle`/`derivePreview`/`deriveRailTitle`; still resolve/return `workspaceId`+`repoUrl` for realtime.
- [ ] 1.4 Verify `shouldDropForScope`, scope-resolve backfill, and `CONVERSATION_CREATED_EVENT` retry loop are untouched.
- [ ] 1.5 Sweep supabase test mocks (`createQueryBuilder`) for `.rpc()` support (recursive chain).
- [ ] 1.6 Tests: RPC bounded-payload test; tenant-isolation tests — (a) workspace-B user → 0 workspace-A rows, AND (b) same-workspace member → 0 rows + 0 snippets for another member's PRIVATE (non-`workspace`) conversation (LATERAL-correlation isolation proof, since messages RLS is workspace-broad); GRANT hygiene assertion (REVOKE PUBLIC+anon, GRANT authenticated, no service_role); title/preview parity test.

## Phase 2 — De-block + de-over-fetch dashboard render (HIGH)
- [ ] 2.1 Add `app/api/dashboard/foundation-status/route.ts` (existence+size for known paths only; `withUserRateLimit`; Sentry mirror on failure).
- [ ] 2.2 Rewrite `page.tsx` KB-tree consumer → foundation-status; derive `visionExists`/cards; keep light gate + 401/503/404 mapping + ADR-067 warm cache.
- [ ] 2.3 Dedupe the double `/api/workspace/active-repo` fetch (share one SWR entry).
- [ ] 2.4 Tests: foundation-status route; first-run screen still renders when `vision.md` absent; graceful degrade on 5xx.

## Phase 3 — Middleware per-request cost (HIGH, security-gated)
- [ ] 3.1 Only if Phase 0 confirms H3: parallelize provably-independent reads in `middleware.ts` via `Promise.all`, preserving revocation/T&C freshness + fail-closed ordering. security-sentinel gate; split to follow-up if risky.

## Phase 4 — Dashboard bundle (MEDIUM)
- [ ] 4.1 `next/dynamic` code-split `pdfjs-dist`, `@likec4/*`, `@codemirror/*` off the dashboard critical path; verify via `next build` bundle analysis. May split to follow-up.

## Exit
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] `node node_modules/vitest/vitest.mjs run` (worktree-safe) passes for touched specs.
- [ ] Migration applied dev→prd (dev≠prd); function existence verified without ssh before close.
- [ ] Post-deploy waterfall re-measured; improvement vs Phase 0 baseline recorded.
