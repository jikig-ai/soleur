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
- [ ] 0.1.1 Read `apps/web-platform/server/byok.ts:decryptKey` — confirm Buffer return type (per Kieran P1.2). If string, refactor in PR-B; document residual exposure here.
- [ ] 0.1.2 `git ls-files` glob verification per `hr-when-a-plan-specifies-relative-paths-e-g` (run all four checks in plan §Files to Create note).

### 0.2 Redaction allowlist extension
- [ ] 0.2.1 [RED] `apps/web-platform/test/server/logger.test.ts` — assert `redact()` strips `apiKey`, `Authorization`, `encryptedKey`, `iv`, `auth_tag` from synthetic log entry.
- [ ] 0.2.2 [RED] `apps/web-platform/test/server/sentry.beforeSend.test.ts` — assert `beforeBreadcrumb` strips the same keys.
- [ ] 0.2.3 Edit `apps/web-platform/server/logger.ts:19` redact array.
- [ ] 0.2.4 Edit `apps/web-platform/sentry.server.config.ts:11-14` `beforeSend` + add `beforeBreadcrumb`.

### 0.3 Brand rename (Command Center → Dashboard / Soleur)
- [ ] 0.3.1 Edit `apps/web-platform/app/manifest.ts:5,8`.
- [ ] 0.3.2 Edit `apps/web-platform/app/layout.tsx:13,16`.
- [ ] 0.3.3 Edit `apps/web-platform/app/(dashboard)/layout.tsx:85` (sidebar nav).
- [ ] 0.3.4 Edit `apps/web-platform/app/(dashboard)/dashboard/page.tsx:368, 512, 545` (page header strings).
- [ ] 0.3.5 Edit `apps/web-platform/components/chat/chat-surface.tsx:403`.
- [ ] 0.3.6 Edit `apps/web-platform/components/chat/conversations-rail.tsx:159`.
- [ ] 0.3.7 Edit `apps/web-platform/components/connect-repo/ready-state.tsx:78,187,198`.
- [ ] 0.3.8 Edit `apps/web-platform/server/cc-dispatcher.ts:833` (error message string).
- [ ] 0.3.9 Edit `plugins/soleur/docs/_data/site.json:5` (meta description).
- [ ] 0.3.10 Verify `rg -i "command\s*center"` against user-visible scope returns zero matches.

### 0.4 Service-role singleton memoization (folds #2962 partial)
- [ ] 0.4.1 Edit `apps/web-platform/lib/supabase/service.ts` — JSDoc warning + memoize `getServiceClient`.

### 0.5 Local verify + ship
- [ ] 0.5.1 `bun run typecheck && bun run test && bun run build` green in `apps/web-platform/`.
- [ ] 0.5.2 Visual smoke: `bun run dev`, log in, screenshot Dashboard label.
- [ ] 0.5.3 Open PR-A. Body: `Ref #3244, Closes #2962 (partial)`.
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

### 1.5 agent-runner migration (11 call-sites)
- [ ] 1.5.1 Migrate `agent-runner.ts:182, 213, 256, 289, 329, 376, 424, 445, 528, 1071, 1315, 1326, 1363, 1373, 1390, 1456, 839 (kbShareTools constructor)` to `getFreshTenantClient(userId)`. (Note: kbShareTools constructor allowlisted per §1.5 plan; do NOT migrate that one.)
- [ ] 1.5.2 Wrap `startAgentSession` body in `runWithByokLease`.
- [ ] 1.5.3 Wire JWT mint at session start.
- [ ] 1.5.4 §1.7 timeout pair: `idle_window` (90s, resets) + `max_turn_duration` (10min, anchored on `firstToolUseAt`, NOT reset). Add `WorkflowEnd { reason: "idle_window" | "max_turn_duration" | "max_turns" }` discriminator.
- [ ] 1.5.5 Auth probe before every migrated query (per `2026-04-12-silent-rls-failures-in-team-names`).
- [ ] 1.5.6 Verify `rg "createServiceClient|getServiceClient" apps/web-platform/server/agent-runner.ts` returns zero matches.

### 1.6 CI grep gate (replaces ESLint rule)
- [ ] 1.6.1 [RED] `apps/web-platform/test/ci/service-role-allowlist.test.sh` — synthetic violator file rejected; allowlisted file accepted.
- [ ] 1.6.2 Write `apps/web-platform/.service-role-allowlist`.
- [ ] 1.6.3 Edit `.github/workflows/lint.yml` — add grep step.
- [ ] 1.6.4 Add allowlist comments: `server/health.ts:15`, `server/byok-lease.ts`, `server/session-sync.ts:133` (transitional), `server/kb-share-tools.ts`.

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
- [ ] 2.5.3 Edit `app/api/webhooks/stripe/route.ts` — handle `invoice.payment_failed` + `charge.failed`; emit Inngest event `{founderId}.finance.payment_failed`.
- [ ] 2.5.4 Write `server/inngest/functions/cfo-on-payment-failed.ts` — under `runWithByokLease` + `getFreshTenantClient`; concurrency-key per `(founderId, domain, eventKey)`; pre-action Stripe state verification.

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
- [ ] 3.3.3 Write `apps/web-platform/supabase/migrations/040_runtime_cost_state.sql` — `users` ALTER + `record_byok_use_and_check_cap` SECURITY DEFINER RPC with atomic INSERT … ON CONFLICT … DO UPDATE … RETURNING.
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
- [ ] 3.7.1 File issues for D1–D11 from plan §Deferred Capabilities, milestoned per re-evaluate column.

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
