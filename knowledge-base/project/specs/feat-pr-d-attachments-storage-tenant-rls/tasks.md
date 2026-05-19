---
feature: pr-d-attachments-storage-tenant-rls
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-16-feat-pr-d-attachments-storage-tenant-rls-plan.md
spec: knowledge-base/project/specs/feat-pr-d-attachments-storage-tenant-rls/spec.md
---

# Tasks: PR-D — Attachments-Storage Tenant RLS

Derived from the plan after multi-agent review (DHH + Kieran + Code Simplicity). Apply tasks in phase order; phase ordering is load-bearing per learning `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

## Pre-PR (separate branch, prerequisite — NOT in this task list)

- [ ] Pre-PR for CI tenant-isolation job filed and merged from `main` (closes #3869 item 6). Without it, PR-D's new tests silent-skip.

## Phase 0 — Prerequisites & Sanity (no code changes)

- [ ] 0.1 Verify pre-PR merged (`gh issue view 3869 --json comments`); CI workflow exporting `TENANT_INTEGRATION_TEST=1` on `main`
- [ ] 0.2 Re-enumerate line refs at /work HEAD (`grep -n "persistAndDownloadAttachments\|Migrated in PR-C" apps/web-platform/server/{cc-dispatcher,agent-runner,attachment-pipeline}.ts`); update spec/plan if drifted
- [ ] 0.3 Apply migrations 001-044 locally: `cd apps/web-platform && doppler run -p soleur -c dev -- bash scripts/run-migrations.sh`
- [ ] 0.4 SQL spike — `storage.foldername()` edge cases (empty, leading slash, trailing slash, typical, traversal); capture results in PR body
- [ ] 0.4b GRANT presence check for `authenticated` role: `has_table_privilege` on storage.objects (INSERT/UPDATE/DELETE) + message_attachments (INSERT); all 4 must return true
- [ ] 0.5 Backwards-compat orphan-path audit query against dev Supabase; orphan_count == 0 OR quarantine plan agreed
- [ ] 0.6 Sentinel sweep with expanded grep (`.move/.copy/.getPublicUrl` patterns); reconcile against expected matches in plan §0.6
- [ ] 0.7 Acceptance check: 0.1-0.6 outputs in PR body; CPO sign-off confirmed (per `requires_cpo_signoff: true`)

## Phase 1 — Migration (`045_attachments_storage_rls.sql`)

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/045_attachments_storage_rls.sql` with the two policies + tight 3-line comment about no-WITH-CHECK semantic
  - [ ] 1.1.1 `storage.objects FOR ALL` for `bucket_id='chat-attachments'` with `(storage.foldername(name))[1] = auth.uid()::text`
  - [ ] 1.1.2 `message_attachments FOR INSERT WITH CHECK` joining `messages → conversations.user_id = auth.uid()`
- [ ] 1.2 Conditional belt-and-suspenders predicate (`name LIKE auth.uid()::text || '/%'`) IF Phase 0.4 surfaced `foldername('a/')` exploitability
- [ ] 1.3 Migration comments — cite `2026-04-18-rls-for-all-using-applies-to-writes.md` for FOR ALL USING decision
- [ ] 1.4 Apply migration locally; verify policy presence via `pg_policy` query (3 policies total on storage.objects + message_attachments)

## Phase 2 — Tenant-Isolation Integration Tests (NEW file)

- [ ] 2.1 Create `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` mirroring `cc-dispatcher.tenant-isolation.test.ts:1-50` shape (env gating, synthetic email pattern, `assertSynthetic`, `requireEnv`, `mintFounderJwt` import)
- [ ] 2.2 Cross-tenant Storage SELECT deny test (Founder A downloads Founder B's seeded path; assert `data === null`)
- [ ] 2.3 Same-tenant positive control (Founder B downloads own file)
- [ ] 2.4 Cross-tenant `message_attachments` INSERT deny test (seed messageB first; assert `err?.code === "42501"`, NOT 23503); use `randomUUID()` for message_id
- [ ] 2.5 Cleanup via `afterAll`: `service.auth.admin.deleteUser` for synthetic users + `service.storage.from("chat-attachments").remove([victimPath, ...])` for seeded objects (FK cascade does NOT cover Storage bytes)
- [ ] 2.5a Policy-shape assertion: query `pg_policy` and assert `polcheck IS NULL` and `polqual IS NOT NULL` for the new storage.objects policy
- [ ] 2.6 Local test run: `TENANT_INTEGRATION_TEST=1 bun test apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` — all assertions pass

## Phase 3 — Code migration (tenant client swap)

- [ ] 3.1 `cc-dispatcher.ts:1435` — REUSE existing `tenant` mint from `:1396-1410`; pass as `supabase: tenant` to `persistAndDownloadAttachments` (single RTT per Kieran P2-2 decision)
- [ ] 3.2 `agent-runner.ts:2305` swap to `getFreshTenantClient(userId)` with try/catch + `reportSilentFallback` wrap
- [ ] 3.3 Fix stale `agent-runner.ts:2300` comment (replace "Migrated in PR-C" with PR-D-correct text citing migrations 019+045)
- [ ] 3.4 `bun run tsc -p apps/web-platform` passes
- [ ] 3.5 Existing `test/cc-attachment-pipeline.test.ts` still passes

## Phase 4 — Sentry mirror on silent download failure

- [ ] 4.1 Import `mirrorWithDebounce` from `@/server/observability` in `attachment-pipeline.ts`
- [ ] 4.2 Replace silent fallback at `:139-149` with `mirrorWithDebounce(err, ctx, userId, "attachment_download_failed")`; preserve `log.error` message string `"Failed to download attachment"`
- [ ] 4.3 Verify no double-mirror with cc-dispatcher outer dispatch catch
- [ ] 4.4 Add ONE message-string regression assertion to existing `test/cc-attachment-pipeline.test.ts` (no mock theater — integration tests cover RLS behavior)

## Phase 5 — UI permanent-skeleton fix

- [ ] 5.1 Edit `apps/web-platform/components/chat/attachment-display.tsx` — add `loadFailed` state
- [ ] 5.2 Replace `.catch(() => {})` with `reportSilentFallback` from `@/lib/client-observability` (NOT server) + `setLoadFailed(true)`; NO userId in client extras (ClientExtra brands as `never`)
- [ ] 5.3 Render "Preview unavailable" + "Retry" button when `loadFailed === true`; retry handler resets state + invalidates cache
- [ ] 5.4 Playwright smoke test: simulate `/api/attachments/url` 4xx; assert "Preview unavailable" + "Retry" renders; click → re-fetch attempt
- [ ] 5.5 `bun run tsc` passes

## Phase 6 — Allowlist shrink (single atomic commit; internal order MATTERS)

- [ ] 6.1 Remove lines 78-84 from `apps/web-platform/.service-role-allowlist` (working tree only)
- [ ] 6.4 Sentinel sweep on `cc-dispatcher.ts` for residual `createServiceClient()` / `supabase()` calls — any survivor gets `// SERVICE-ROLE: <reason>` annotation (sweep BEFORE commit per Kieran P2-4)
- [ ] 6.3 Run allowlist-check script locally; verify CI gate passes with cc-dispatcher.ts removed
- [ ] 6.2 Single dedicated commit: `feat(runtime): shrink allowlist 14 → 13 (PR-D §6)` — separate from Phase 1-5 commits per PR-C precedent

## Phase 7 — Article 30 PA2 amendment

- [ ] 7.1 Edit `knowledge-base/legal/article-30-register.md` PA2 row (Conversation Data):
  - [ ] 7.1.1 (c) Categories: append `message_attachments` + chat-attachments bucket content (image/PDF; Art. 9 incidental)
  - [ ] 7.1.2 (g) TOMs: append per-user folder prefix, Storage RLS policy, IDOR check, content-type allowlist, filename sanitisation, service-role presigned URL upload
  - [ ] 7.1.3 (f) Retention: append FK cascade chain

## Phase 8 — Post-merge ack-gated `supabase db push` (operator)

- [ ] 8.1 After PR-D merges to main, operator runs `doppler run -p soleur -c prd -- bash scripts/run-migrations.sh` with per-command ack
- [ ] 8.2 Verify migration 045 applied (REST probe via Supabase MCP `list_migrations` or psql `SELECT * FROM supabase_migrations.schema_migrations WHERE version = '045'`)
- [ ] 8.3 Verify policies present in prod via `pg_policy` query (3 attachment policies total)
- [ ] 8.4 Read-only RLS verification (NO synthetic-user creation in prod per `hr-dev-prd-distinct-supabase-projects`):
  - [ ] 8.4.1 Policy-shape assertion: `pg_policy` shape check (FOR ALL, has USING, no WITH CHECK)
  - [ ] 8.4.2 Dry-run RLS predicate eval inside `BEGIN; SET LOCAL ROLE authenticated; SET LOCAL "request.jwt.claims"; ... ROLLBACK;`
- [ ] 8.5 Close #3869 items 4-5 (`gh issue edit 3869 --body-file -`)

## Phase 9 — File PR-E confirmation + AUP follow-up + compound (post-merge)

- [ ] 9.1 Comment on PR-E tracking issue #3887 confirming PR-D merged and PR-E is unblocked
- [ ] 9.2 File AUP follow-up issue inline: `gh issue create --title "legal: Acceptable Use Policy review for chat-attachments Art. 9 incidental upload warning (post-PR-D)" --label "domain/legal,priority/p3-low,type/improvement"`
- [ ] 9.3 Run `/soleur:compound` to capture learnings; `/soleur:ship` Phase 5.5 preflight

## Notes

- Pre-PR for CI tenant-isolation job (#3869 item 6) is a HARD PREREQUISITE (AC1) — not part of this task list
- `requires_cpo_signoff: true` in plan frontmatter — confirm CPO has reviewed before /work begins (Phase 0.7)
- user-impact-reviewer agent invoked at PR-ready-for-review per `single-user incident` threshold (AC18)
- PR title uses `Ref #3244 / Closes #3869` (NOT auto-close `Closes #3244`) — umbrella stays open until PR-E (#3887) lands
- gdpr-gate Phase 2.7 invoked at plan time; findings folded into AC11 (policy shape), AC20a (dev DSAR smoke), Phase 2.5 (storage cleanup), Phase 9.2 (AUP follow-up)
