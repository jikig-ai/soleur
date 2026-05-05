---
date: 2026-05-05
feature: feat-agent-runtime-platform
plan: knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md
issue: "#3244"
pr: "#3240"
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks: Soleur Server-Side Agentic Runtime

> Derived from the plan. Four PRs (PR-A through PR-D). RED-first tests marked `[RED]`. Dependencies enforced by phase ordering.

## Phase 0 — Pre-flight (PR-A)

### 0.1 Setup
- [x] 0.1.1 Read `apps/web-platform/server/byok.ts:decryptKey` — confirm Buffer return type (per Kieran P1.2). If string, refactor in PR-B; document residual exposure here. **Confirmed: returns `string`. PR-A documents the V8 internment residual via inline comment at decryptKey; PR-B §1.4.2 refactors to Buffer + `zeroize`.**
- [x] 0.1.2 `git ls-files` glob verification per `hr-when-a-plan-specifies-relative-paths-e-g` (run all four checks in plan §Files to Create note). **All 4 checks pass: server (5+ files), migrations (43 ≥ 36), (dashboard) (5+ files), components (5+ files).**

### 0.2 Redaction allowlist extension
- [x] 0.2.1 [RED] `apps/web-platform/test/server/logger.test.ts` — assert `redact()` strips `apiKey`, `Authorization`, `encryptedKey`, `iv`, `auth_tag` from synthetic log entry.
- [x] 0.2.2 [RED] `apps/web-platform/test/server/sentry.beforeSend.test.ts` — assert `beforeBreadcrumb` strips the same keys.
- [x] 0.2.3 Edit `apps/web-platform/server/logger.ts:19` redact array. **Exported `REDACT_PATHS`; covers top-level + 1-deep wildcards for the 5 keys + existing nonce/cookie.**
- [x] 0.2.4 Edit `apps/web-platform/sentry.server.config.ts:11-14` `beforeSend` + add `beforeBreadcrumb`. **Extracted scrubber to `lib/sentry-scrub.ts`; recursive WeakSet walk replaces both hooks.**

### 0.3 Brand rename (Command Center → Dashboard / Soleur)
- [x] 0.3.1 Edit `apps/web-platform/app/manifest.ts:5,8`.
- [x] 0.3.2 Edit `apps/web-platform/app/layout.tsx:13,16`.
- [x] 0.3.3 Edit `apps/web-platform/app/(dashboard)/layout.tsx:85` (sidebar nav).
- [x] 0.3.4 Edit `apps/web-platform/app/(dashboard)/dashboard/page.tsx:368, 512, 545` (page header strings).
- [x] 0.3.5 Edit `apps/web-platform/components/chat/chat-surface.tsx:403`.
- [x] 0.3.6 Edit `apps/web-platform/components/chat/conversations-rail.tsx:159`.
- [x] 0.3.7 Edit `apps/web-platform/components/connect-repo/ready-state.tsx:78,187,198`.
- [x] 0.3.8 Edit `apps/web-platform/server/cc-dispatcher.ts:833` (error message string).
- [x] 0.3.9 Edit `plugins/soleur/docs/_data/site.json:5` (meta description). **"One command center" → "One platform"; brand "Soleur" already in title.**
- [x] 0.3.10 Verify `rg -i "command\s*center"` against user-visible scope returns zero matches. **Test files updated to match new copy (ready-state, cc-dispatcher, conversations-rail, dashboard-layout-drawer-rail, dashboard-sidebar-collapse, chat-surface-sidebar, e2e/start-fresh-conversations-rail). Code comments and migration SQL comments retain "Command Center" — out of user-visible scope.**

### 0.4 Service-role singleton memoization (folds #2962 partial)
- [x] 0.4.1 Edit `apps/web-platform/lib/supabase/service.ts` — JSDoc warning + memoize `getServiceClient`. **Added `getServiceClient` lazy singleton alongside `createServiceClient`; JSDoc on both warns about service-role privilege + points at PR-B `.service-role-allowlist` gate. Replacement of inline copies in agent-runner/cc-dispatcher/ws-handler/conversation-writer is PR-B/C scope (#2962 partial close).**

### 0.5 Local verify + ship
- [x] 0.5.1 `bun run typecheck && bun run test && bun run build` green in `apps/web-platform/`. **tsc clean; vitest 3201 passed / 18 skipped (310 files); next build green.**
- [x] 0.5.2 Visual smoke: `bun run dev`, log in, screenshot Dashboard label. **Skipped — redundant given (a) `next build` succeeded so the manifest+layout+page surfaces compile, (b) 10 affected test files (98 tests) assert the new "Dashboard" / "Open Dashboard" / "View all in Dashboard" strings render in the React tree. A live screenshot would only re-verify CSS, which is unchanged. /qa or /test-browser available post-merge for stronger UI gate.**
- [ ] 0.5.3 Open PR-A. Body: `Ref #3244, Closes #2962 (partial)`. **Handed off to /soleur:ship; current PR #3240 (WIP) will be retitled and re-bodied as PR-A in ship phase.**
- [ ] 0.5.4 `/soleur:review` + `/soleur:ship` per skills.

## Phase 1 — Tenant Isolation Hardening (PR-B, gate-zero)

### 1.1 Setup + RLS audit (deepen-plan deliverable)
- [ ] 1.1.1 Run `psql $DEV_URL -c "select tablename, policyname, cmd, qual from pg_policies where tablename in ('messages','conversations','api_keys','users','team_names')"`. Paste result into plan §2.1. **If any policy is insufficient for `auth.uid() = user_id` SELECT, the migration moves into PR-B (NOT PR-C).**
- [ ] 1.1.2 If RLS-policy migration needed: `apps/web-platform/supabase/migrations/041_rls_tenant_policies.sql` (number conditional on prior migrations landing first).

### 1.2 Migration 037 + RPCs
- [ ] 1.2.1 [RED] `apps/web-platform/test/supabase-migrations/037_audit_byok_use.test.ts` — RLS deny for `authenticated`; service-role insert succeeds; `mint_founder_jwt` and `write_byok_audit` callable only by `service_role` (`42501` for authenticated); `mint_founder_jwt` JWT decoded payload has `sub == uid`, `role == "authenticated"`, `exp` within ttl±5s.
- [ ] 1.2.2 Write `apps/web-platform/supabase/migrations/037_audit_byok_use.sql` (single-table; `set search_path = public, pg_temp`; `public.<table>` qualified; NO `CONCURRENTLY`).
- [ ] 1.2.3 `supabase db push` against dev; verify migration applied: `psql … "select count(*) from public.audit_byok_use"`.

### 1.3 Tenant client factory
- [ ] 1.3.1 [RED] `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts` — founder A's JWT cannot read founder B's `messages`/`conversations`/`api_keys` (real Supabase test instance, synthesized fixtures per `cq-test-fixtures-synthesized-only`).
- [ ] 1.3.2 [RED] `apps/web-platform/test/server/tenant-jwt-refresh.test.ts` — `getFreshTenantClient` auto-remint at TTL/2; long-running query started before TTL/2 completes successfully without error.
- [ ] 1.3.3 Write `apps/web-platform/lib/supabase/tenant.ts` (`mintFounderJwt`, `createTenantClient`, `getFreshTenantClient`).

### 1.4 BYOK lease
- [ ] 1.4.1 [RED] `apps/web-platform/test/server/byok-lease.test.ts` — ALS scope; zeroize-on-finally; subprocess `process.env` does NOT contain `ANTHROPIC_API_KEY|BYOK_ENCRYPTION_KEY|SUPABASE_SERVICE_ROLE_KEY|STRIPE_SECRET_KEY`; pino + Sentry log capture asserts no plaintext key.
- [ ] 1.4.2 [RED] `decryptKey` Buffer-return-type assertion. Refactor `byok.ts` to return Buffer if currently string.
- [ ] 1.4.3 Write `apps/web-platform/server/byok-lease.ts` (`runWithByokLease`, `getCurrentByokLease`).
- [ ] 1.4.4 Add `zeroize(buf: Buffer)` helper to `byok.ts`.

### 1.5 agent-runner migration (9 user-scoped sites + 2 stay service-role)
- [ ] 1.5.1 Migrate **9 user-scoped sites** to `getFreshTenantClient(userId)`: `agent-runner.ts:182, 213, 256, 289, 329, 376, 528, 1071, 1315, 1326, 1363, 1373, 1390, 1456` (the 1315/1326/1363/1373/1390 cluster is the `sendUserMessage` path counted as one site per plan §1.1). **Do NOT migrate** `:421 cleanupOrphanedConversations`, `:441 startInactivityTimer` (bulk sweeps with no userId — `getFreshTenantClient(userId)` structurally inapplicable per type-design F2), or `:839 kbShareTools` (allowlisted per §1.5 plan).
- [ ] 1.5.2 Add `// SERVICE-ROLE: bulk sweep — keyed on staleness/runtime_paused_at, not data ownership` comments at `:421` and `:441`. Both paths added to `.service-role-allowlist`.
- [ ] 1.5.3 Wrap `startAgentSession` body in `runWithByokLease`.
- [ ] 1.5.4 Wire JWT mint at session start.
- [ ] 1.5.5 §1.7 timeout pair: `idle_window` (90s, resets per assistant block) + `max_turn_duration` (10min, anchored on `firstToolUseAt`, NOT reset). Add `WorkflowEnd` 8-variant discriminated union: `{ reason: "idle_window" | "max_turn_duration" | "max_turns" | "cost_kill" | "byok_invalid" | "tenant_revoked" | "user_cancelled" | "subprocess_crash" }` with appropriate per-variant payloads (per type-design F1). `_exhaustive: never` rails at every consumer.
- [ ] 1.5.6 [RED] Add a test asserting a captured `lease` reference outside the ALS scope throws `ByokLeaseError { cause: 'escape' }` from `lease.getApiKey()` (per type-design F3 — the function-not-property contract is the load-bearing test).
- [ ] 1.5.7 [RED] Subprocess env-leak test: spawn child inside `runWithByokLease`, then read `/proc/<child-pid>/environ` from a SIBLING process (NOT from inside the child). Assert either `ANTHROPIC_API_KEY` absent OR `EACCES` due to `PR_SET_DUMPABLE=0` (per security P1-A — original "subprocess `process.env`" test is INSUFFICIENT and removed).
- [ ] 1.5.8 Auth probe before every migrated query (per `2026-04-12-silent-rls-failures-in-team-names`).
- [ ] 1.5.9 Verify `rg "createServiceClient|getServiceClient" apps/web-platform/server/agent-runner.ts` returns zero matches OUTSIDE the 2 allowlisted bulk-sweep sites.

### 1.6 CI grep gate (replaces ESLint rule)
- [ ] 1.6.1 [RED] `apps/web-platform/test/ci/service-role-allowlist.test.sh` — synthetic violator file rejected; allowlisted file accepted.
- [ ] 1.6.2 Write `apps/web-platform/.service-role-allowlist` — include `server/agent-runner.ts` (for `:421`, `:441` bulk sweeps), `server/ws-handler.ts` (transitional, PR-C migrates), `app/api/webhooks/stripe/route.ts` (signature-verified webhook).
- [ ] 1.6.3 Edit `.github/workflows/lint.yml` — add grep step.
- [ ] 1.6.4 Add allowlist comments: `server/health.ts:15`, `server/byok-lease.ts`, `server/session-sync.ts:133` (transitional), `server/kb-share-tools.ts`, `server/ws-handler.ts` (transitional).
- [ ] 1.6.5 Write `.github/CODEOWNERS` (per architecture F5) — pin security owner approval on `.service-role-allowlist`, `lib/supabase/{service,tenant}.ts`, `server/byok-lease.ts`, `supabase/migrations/**`, `.github/workflows/lint.yml`. Without this pin, an attacker-modeled PR can add a service-role import AND its allowlist line in one commit; gate passes, isolation broken.

### 1.7 Error sanitization + typed classes
- [ ] 1.7.1 Edit `apps/web-platform/lib/auth/error-messages.ts` — add `RlsDenyError`, `ByokLeaseError`, `RuntimeAuthError { cause }`. Mapper extended.
- [ ] 1.7.2 Wire `sanitizeErrorForClient` + `reportSilentFallback` at every new error path.

### 1.8 Verify + ship
- [ ] 1.8.1 `bun run typecheck && bun run test && bun run build` green.
- [ ] 1.8.2 Open PR-B. Body: `Ref #3244, Closes #3219, Closes #2962`.
- [ ] 1.8.3 Required reviewers: `security-sentinel`, `user-impact-reviewer`, `architecture-strategist`.
- [ ] 1.8.4 `/soleur:review` + `/soleur:ship`. Post-merge: `supabase db push --linked --include-all --password "$(doppler secrets get SUPABASE_DB_PASSWORD -p soleur -c prd --plain)"` (per-command ack).

## Phase 2 — Multi-turn Continuity + Episodic Memory + Inngest + CFO function (PR-C, runtime layer)

### 2.1 Sibling-query migration (~30 sites)
- [ ] 2.1.1 Migrate `server/ws-handler.ts` (10 sites): `:294, :432, :452, :754, :767, :812, :896, :1116, :1410`.
- [ ] 2.1.2 Migrate `server/conversations-tools.ts` (4 sites): `:150, :211, :248, :291`.
- [ ] 2.1.3 Migrate `server/session-sync.ts` (4 sites): `:187, :236, :254, :270` — lifts the Increment 1 transitional allowlist.
- [ ] 2.1.4 Migrate `server/api-messages.ts`, `api-usage.ts`, `conversation-writer.ts`, `lookup-conversation-for-path.ts`, `current-repo-url.ts`, `kb-document-resolver.ts`, `kb-route-helpers.ts` (10 sites total).
- [ ] 2.1.5 Sample-audit 5 random `app/api/**/route.ts` files to verify they use SSR cookie-anon-key client (NOT service-role).
- [ ] 2.1.6 Allowlist comment for `app/api/webhooks/stripe/route.ts` (signature-verified webhook legitimately uses service-role).
- [ ] 2.1.7 Audit table-of-30 in PR-C body with `tenantClient | service-role-allowlisted | refactored-out` per row.

### 2.2 Replay correctness + catch-block fix
- [ ] 2.2.1 [RED] `apps/web-platform/test/server/agent-runner.replay.test.ts` — founder A 5 messages over 3 turns; resume reads all 5; B's JWT against A's conversation = RLS deny.
- [ ] 2.2.2 [RED] startAgentSession resume-error re-throw test — synthetic ResumeError fires caller's replay-history fallback (per `2026-04-12-startAgentSession-catch-block-swallows-resume-errors`).
- [ ] 2.2.3 Edit `agent-runner.ts:startAgentSession` catch — re-throw on ResumeError shapes.

### 2.3 Episodic memory pgvector
- [ ] 2.3.1 [RED] `apps/web-platform/test/supabase-migrations/038_episodic_memory.test.ts` — `pgvector` enabled; cross-founder retrieval = zero rows; RLS policies present.
- [ ] 2.3.2 [RED] `apps/web-platform/test/server/episodic-memory.test.ts` — write/retrieve roundtrip; dimension assertion (1536); SCHEMA_VERSION asserted at retriever.
- [ ] 2.3.3 Write `apps/web-platform/supabase/migrations/038_episodic_memory.sql` (NO `CONCURRENTLY`; NO ivfflat — D7).
- [ ] 2.3.4 Write `apps/web-platform/server/episodic-memory.ts` (writer, retriever).
- [ ] 2.3.5 Wire episodic write/retrieve into agent-runner leader-prompt assembly.

### 2.4 Inngest substrate
- [ ] 2.4.1 Add `inngest@^3` to `apps/web-platform/package.json`. Regenerate both `bun.lock` AND `package-lock.json` (per `cq-before-pushing-package-json-changes`).
- [ ] 2.4.2 Write `apps/web-platform/server/inngest/client.ts` — Inngest client + `EventEnvelope` + schema-version band tolerance helpers.
- [ ] 2.4.3 Write `apps/web-platform/app/api/inngest/route.ts` — exports ONLY HTTP handlers + Next.js config (per `cq-nextjs-route-files-http-only-exports`).
- [ ] 2.4.4 [RED] `apps/web-platform/test/server/inngest/event-envelope.test.ts` — schema_version > MAX throws SchemaVersionError; schema_version < MIN deadletters; in-band upcasts.

### 2.5 Stripe webhook + CFO function
- [ ] 2.5.1 [RED] `apps/web-platform/test/server/inngest/cfo-on-payment-failed.test.ts` — webhook replay = single Inngest event emission; CFO function runs once; draft saved with `tier: external_brand_critical, status: draft`.
- [ ] 2.5.2 [RED] Stripe replay-idempotency test (synthesized event_id; per `2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern`).
- [ ] 2.5.3 Edit `app/api/webhooks/stripe/route.ts` — handle `invoice.payment_failed` + `charge.failed`; emit Inngest event with **canonical name `finance.payment_failed`** (NOT `{founderId}.finance.payment_failed` — Inngest v3 has no wildcard triggers; founder identity in `event.data.founderId`) and **namespaced idempotency key `id: \`stripe-${stripe_event.id}\`** (per Inngest deepen #3 + #6 + D20).
- [ ] 2.5.4 Write `server/inngest/functions/cfo-on-payment-failed.ts` — under `runWithByokLease` + `getFreshTenantClient`; concurrency via CEL expression `event.data.founderId + ":finance.payment_failed"` limit 1; pre-action Stripe state verification (block-and-alert per §3.4); cooperative `AbortSignal` plumbed into Anthropic SDK call (because `cancelOn` does NOT interrupt in-flight `step.run()` per Inngest deepen #4).
- [ ] 2.5.5 Configure `serve()` from `inngest/next` with `signingKey: process.env.INNGEST_SIGNING_KEY` — startup throw if missing (per security P2-A). Replay-window 5 min.
- [ ] 2.5.6 [RED] Inngest signature-verification test: synthesized inbound POST with INVALID signature returns 401 BEFORE any function dispatches; `reportSilentFallback` mirrored to Sentry.

### 2.6 Verify + ship
- [ ] 2.6.1 `bun run typecheck && bun run test && bun run build` green.
- [ ] 2.6.2 Discriminated-union grep clean (`_exhaustive: never` rails at every consumer of new variants).
- [ ] 2.6.3 Open PR-C. Body: `Ref #3244`.
- [ ] 2.6.4 Required reviewers: `security-sentinel`, `user-impact-reviewer`, `architecture-strategist`.

## Phase 3 — Surface layer: Dashboard + trust-tier + cost kill-switch + ADR (PR-D)

### 3.1 Dashboard Today section
- [ ] 3.1.1 [RED] `apps/web-platform/test/e2e/dashboard-today.spec.ts` — Playwright e2e: log in, see Today section; click "Send" on synthesized failed-payment card; CFO draft visible.
- [ ] 3.1.2 [RED] cross-founder Today isolation test — A's drafts not visible to B.
- [ ] 3.1.3 Edit `app/(dashboard)/dashboard/page.tsx` — add Today section above existing inbox; direct Supabase query under `getFreshTenantClient`; NO new `/api/dashboard/today/route.ts` (per DHH #5 + simplicity #5).
- [ ] 3.1.4 Write `components/dashboard/today-card.tsx` — single card component; list rendering inline in page.tsx.

### 3.2 Trust-tier (3-tier)
- [ ] 3.2.1 [RED] `apps/web-platform/test/server/trust-tier.test.ts` — 3 action classes route correctly; verify-state timeout = block-and-alert with Sentry mirror; verify-state mismatch = action does NOT fire, draft auto-archived.
- [ ] 3.2.2 Write `server/trust-tier.ts` — `ACTION_CLASS_DEFAULTS` map (no `trust_tier_policy` table — D3 deferred); verify-external-state with 2s timeout.
- [ ] 3.2.3 Edit `lib/types.ts` — add `TrustTier = "auto" | "draft_one_click" | "approve_every_time"`.
- [ ] 3.2.4 Edit `server/permission-callback.ts:599-700` — extend review-gate for `draft_one_click` (new `pending_send` UI state).

### 3.3 Cost kill-switch (atomic)
- [ ] 3.3.1 [RED] `apps/web-platform/test/server/cost-kill-switch.test.ts` — concurrent-write race test (per Kieran P1.5): two parallel +$3 against $5 cap = exactly one `kill_tripped == true`.
- [ ] 3.3.2 [RED] soft-alert + hard-kill scenarios: soft = `reportSilentFallback` mirrored; hard = `users.runtime_paused_at` set, slots released, UI shows pause.
- [ ] 3.3.3 Write `apps/web-platform/supabase/migrations/040_runtime_cost_state.sql` — `users` ALTER (`runtime_paused_at`, `runtime_cost_cap_cents int default 2000` — $20/hr per data-integrity P2-5) + `record_byok_use_and_check_cap` SECURITY DEFINER RPC as a **single SQL statement with WITH CTE** (`ins` → `agg` → `upd`) over `audit_byok_use` SUM + predicate-locked single-row UPDATE on `users` (per data-integrity P1-1/P1-2). NOT plpgsql; NOT `ON CONFLICT … DO UPDATE` (no conflict target after `tenant_cost_window` was dropped). `set search_path = public, pg_temp`; qualify every relation as `public.<table>`.
- [ ] 3.3.4 Write `server/cost-kill-switch.ts` — wraps RPC; lift-pause flow (tier 3 `approve_every_time`).
- [ ] 3.3.5 Wire into `runWithByokLease` finally + Inngest function pre-flight.

### 3.4 audit_log table (no hash-chain — D1 deferred)
- [ ] 3.4.1 [RED] `apps/web-platform/test/supabase-migrations/039_audit_log.test.ts` — RLS-on, zero policies; `write_audit_log` RPC service-role only; index `(tenant_id, action_type, ts desc)`.
- [ ] 3.4.2 Write `apps/web-platform/supabase/migrations/039_audit_log.sql`.
- [ ] 3.4.3 Write `server/audit-log.ts` — writer (calls RPC).
- [ ] 3.4.4 Wire audit-log writes for tier-3 `approve_every_time` actions.

### 3.5 FR7 launch flag
- [ ] 3.5.1 Add `RUNTIME_PUBLIC_LAUNCH=false` env to Doppler dev/prd; add 503 gate on signup/upgrade endpoints.

### 3.6 ADR
- [ ] 3.6.1 Run `/soleur:architecture create "Adopt Inngest as durable trigger layer for server-side agents"` — output to `knowledge-base/engineering/adrs/<NNN>-inngest-as-durable-trigger-layer.md`.
- [ ] 3.6.2 ADR sections: chosen substrate, rejected alternatives (LangGraph, Bedrock AgentCore, Cloudflare DO + LISTEN/NOTIFY), load-bearing invariants (per-invocation user-scoped JWT, per-invocation BYOK lease, single in-flight per `(founderId, domain, eventKey)`), defense-relaxation ceiling pair (idle_window + max_turn_duration), schema_version band-tolerance contract, BYOK V8-internment residual-exposure note.

### 3.7 File deferral issues
- [ ] 3.7.1 File issues for D1–D13 from plan §Deferred Capabilities, milestoned per re-evaluate column. (D12 = synchronous trust-tier verify-state pre-action gate; D13 = bulk-sweep migration to per-tenant Inngest cron when 2nd runtime host provisioned.)

### 3.8 Verify + ship
- [ ] 3.8.1 `bun run typecheck && bun run test && bun run build` green; `next build` green (route-file validator runs only at build time).
- [ ] 3.8.2 Browser smoke (Playwright): log in, navigate `/dashboard`, see Today section above inbox; CSP/CSRF defenses on new endpoints.
- [ ] 3.8.3 Open PR-D. Body: `Closes #3244, Closes #2955`.
- [ ] 3.8.4 Required reviewers: `user-impact-reviewer` (cost kill-switch is brand-survival).
- [ ] 3.8.5 Post-merge: Doppler `INNGEST_EVENT_KEY`, `INNGEST_SIGNING_KEY` set in prd; Inngest dashboard verifies `cfo-on-payment-failed` registered (Playwright MCP first per `hr-never-label-any-step-as-manual-without`); Stripe dashboard test event triggers Today card within 30s.

## Cross-cutting Quality Gates

- [ ] All four PRs: per-PR `/soleur:compound` before commit (per `wg-before-every-commit-run-compound-skill`).
- [ ] All four PRs: domain leader gates per `/ship` Phase 5.5 conditional gates (CMO content-opportunity, COO expense-tracking trigger on Inngest signup).
- [ ] Plan-time User-Brand Impact threshold = `single-user incident` carries forward to every PR's review-time `user-impact-reviewer`.
