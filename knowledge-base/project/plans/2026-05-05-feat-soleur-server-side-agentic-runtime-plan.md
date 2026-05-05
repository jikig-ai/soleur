---
date: 2026-05-05
type: feat
title: Soleur Server-Side Agentic Runtime
issue: "#3244"
pr: "#3240"
branch: feat-agent-runtime-platform
worktree: .worktrees/feat-agent-runtime-platform/
brainstorm: knowledge-base/project/brainstorms/2026-05-05-command-center-runtime-brainstorm.md
spec: knowledge-base/project/specs/feat-agent-runtime-platform/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan: Soleur Server-Side Agentic Runtime

> **Branding (decided 2026-05-05).** Single brand "Soleur" across CLI plugin + Web Platform; no "Command Center" sub-brand. The runtime ships under the existing Soleur brand. References to "Command Center" inside source/UI are renamed to "Dashboard" or removed — see Increment 0.

## Overview

Three sequenced increments inside `apps/web-platform/`, each independently shippable as a sub-PR but planned as one feature:

| # | Increment | Spec FRs | Why this order |
|---|-----------|----------|----------------|
| 0 | Pre-flight: Sentry/pino redaction allowlist + brand rename + fold #2962 | (TR2/FR2 prep) | Independently shippable; reduces blast-radius of FR2 deploy. |
| 1 | **Tenant isolation hardening** — per-invocation user-scoped Supabase JWT, BYOK lease in `AsyncLocalStorage`, `audit_byok_use` table, lint guard `no-service-role-in-runtime`, forensic audit-log scaffold | FR1, FR2, TR2, TR5 (scaffold) | Gate-zero. The single brand-ending vector across all 5 domain assessments. Today's `createServiceClient` use is the live exposure. Lands FIRST so Increments 2 + 3 inherit RLS as the enforced boundary, not paper. |
| 2 | **Multi-turn continuity + episodic memory** — verify #1044 SDK-resume correctness under RLS, scope conversations on `(founder, domain)`, install pgvector, episodic store, sibling-query audit | FR3, TR3 | #1044 is technically CLOSED but the SDK-resume + replay fallback paths were written under service-role assumptions. Switching agent-runner to user-scoped JWT (Increment 1) WILL break replay if RLS denies the historical messages query. Increment 2 verifies and hardens. Episodic memory adds retrieval beyond raw replay. |
| 3 | **Daily Priorities + Inngest + trust-tier + cost kill-switch + ADR** — Inngest substrate, Stripe `payment_failed` → CFO end-to-end, `/dashboard` Today aggregator, 5-tier autonomy policy, per-tenant cost attribution + kill-switch, observability extension, ADR capture | FR4, FR5, FR6, FR7, FR8, TR1, TR6, TR7, TR9 | Demo target. Cannot ship before Increments 1 + 2 (background trigger amplifies whatever signal it emits — amnesia + service-role would compound). FR7 launch gate ships gating LOGIC only; the 9 legal artifacts (E&O, DPA, etc.) are tracked separately under CLO. |

The existing `server/agent-runner.ts` (durable Claude Agent SDK on Hetzner) stays. Inngest layers on top as a library, not a replacement. Bedrock / LangGraph / Cloudflare DO are non-goals (spec §Non-Goals).

## User-Brand Impact

**If this lands broken, the user experiences:**

1. **Cross-tenant data leak.** Founder A's KB / chat history / agent memory / BYOK keys leak to Founder B because the runtime's RLS enforcement misfires on a path that was previously service-role-shielded. Today's `SUPABASE_SERVICE_ROLE_KEY` use in `server/agent-runner.ts` is the live exposure being remediated.
2. **BYOK credential leak.** Long-running agent holds plaintext Anthropic/Stripe keys in heap or in subprocess `process.env`; pino/Sentry leak; `/proc/<pid>/environ` exfiltration. Brand-ending; founder financially harmed.
3. **Agent fires wrong action while founder sleeps.** Inngest-driven CFO/CRO acts on stale or hallucinated context (no replay fix → amnesia; no trust-tier gate → unbounded action class; no cost kill-switch → runaway). One bad customer email or one wrong invoice ends trust.

**If this leaks, the user's data / workflow / money is exposed via:** any of the three vectors above. Confirmed by the founder this session (carried from brainstorm `## User-Brand Impact`).

**Brand-survival threshold:** `single-user incident`. One incident on any of the three vectors is brand-ending for a solo-founder-operated startup. CPO sign-off required at plan-time before `/work`. `user-impact-reviewer` invoked at review-time per `plugins/soleur/skills/review/SKILL.md`. Preflight Check 6 fires on `apps/web-platform/server/**`, `apps/web-platform/supabase/migrations/**`, BYOK custody surfaces.

**Mitigations (load-bearing for plan):** see Increments 1–3 below; cross-referenced into individual ACs.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| FR1: replace `SUPABASE_SERVICE_ROLE_KEY` in `server/agent-runner.ts` | No direct env-read in `agent-runner.ts`; goes through `createServiceClient()` (`lib/supabase/service.ts:25-36`). 17+ call-sites in `server/` ride the same singleton. | Replace at the factory boundary (new `createTenantClient(jwt)` + `mintFounderJwt(userId)`). Lint rule `no-service-role-in-runtime` flags new `createServiceClient` import sites in `server/agent-runner.ts`, `server/session-sync.ts`, `server/cc-dispatcher.ts`, `server/conversations-tools.ts`, `server/permission-callback.ts` — allowlist via inline comment for the JWT-mint path + audit-row writers. |
| FR3: "domain leaders are stateless one-shots" | Issue **#1044 is CLOSED**. `agent-runner.ts:953-961` persists `message.session_id`; `:1421` reads it back via `startAgentSession(... resumeSessionId, ...)`. Replay fallback at `:373 loadConversationHistory` + `:402 buildReplayPrompt`. | Reframe FR3 as **verify-and-harden**, not ship-from-scratch. Risk: Increment 1's switch to user-scoped JWT will cause `loadConversationHistory` (`:376` query) to return empty rows under RLS unless the RLS policy on `messages` allows `auth.uid() = user_id`. Plan adds RLS audit + sibling-query sweep per `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper`. |
| TR3: "per-founder pgvector in their Supabase project" | `vector` extension NOT installed. Single shared Soleur Supabase project (one prd, one dev) per `hr-dev-prd-distinct-supabase-projects`. Spec wording implies a Supabase project PER founder — that's a 10x ops/cost change. | **Default interpretation: shared prd Supabase + per-founder RLS isolation** on a single `episodic_memory` table. Confirmed below as a Plan Open Question; treat as RLS-isolated single-table unless user overrides at deepen-plan time. |
| TR1: "Inngest agent kit … Library installed into existing Hetzner Node host" | Zero substrate today. No `inngest` dep in `apps/web-platform/package.json`. No `app/api/inngest/route.ts`. | Greenfield install in Increment 3. Inngest Cloud free tier for alpha; self-host considered out of scope. |
| TR5: "WORM hash-chained audit log" | `processed_stripe_events` (migration 030) is the only existing service-role-only audit-shape table — RLS-enabled, zero policies. Closest precedent. | Mirror that shape: `audit_log` table with RLS-on, zero policies, server-only insert via SECURITY DEFINER, hash-chain enforced at insert via trigger. Increment 1 lands `audit_byok_use`; Increment 3 generalizes to `audit_log` for action-class events. |
| FR6: "5-tier per-action-class autonomy" | `server/tool-tiers.ts` exists with **3-tier** (`auto-approve | gated | blocked`) per-tool map (15 entries). | Extend `tool-tiers.ts` to the 5-tier action-class taxonomy. Re-key from per-tool to per-action-class; preserve existing `permission-callback.ts:599-700` review-gate UX for tier 4 ("Approve every time"). |
| FR2: "AsyncLocalStorage scope per invocation" | Zero `AsyncLocalStorage` imports across `apps/web-platform/`. | Greenfield. Module: `server/byok-lease.ts`. Lease delivered to subprocess via stdin/fd, NEVER `process.env` (per `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526`). |
| FR4: `/dashboard` "Today" aggregator | `app/(dashboard)/dashboard/page.tsx` exists (716 lines). Currently labeled "Command Center" in copy + sidebar; aggregates conversations + foundation cards. NOT cross-source priority aggregator. | Add a "Today" card section above existing inbox (component, not new route). Rebrand UI strings to "Dashboard" per Increment 0. |
| Spec sub-brand framing ("Soleur Command Center") | Source has user-visible "Command Center" strings in UI (manifest, layouts, page headers, buttons), error messages, marketing site description. | Increment 0 renames every user-visible occurrence to "Dashboard" or context-appropriate Soleur term. Code-internal comments / filenames (e.g., `cc-dispatcher.ts`) stay — non-user-facing. |

## Open Code-Review Overlap

Open code-review issues touching files this plan edits (per `gh issue list --label code-review --state open`, filtered for `agent-runner|session-sync|SUPABASE_SERVICE_ROLE_KEY|BYOK|pgvector|dashboard|inngest|audit`):

- **#3242** (review/Ref #3235): tool_use WS event lacks raw name field for agent consumers. **Disposition: Acknowledge.** Different concern from this plan's FR1/FR2 scope; separate fix surface in `ws-handler.ts`. Stays open.
- **#3219** (review/Ref #3217): inactivity-sweep slot leak at `agent-runner.ts:447`. **Disposition: Fold in.** `agent-runner.ts:445 startInactivityTimer` is one of the 17+ service-role call-sites being audited in Increment 1. Add `Closes #3219` to the Increment 1 PR body once the sweep path is rewritten under user-scoped JWT (the leak goes away when the slot release runs in the per-invocation lease's `finally`).
- **#3039** (review): Sentry mirror + drift-guard coverage for signOut. **Disposition: Acknowledge.** Adjacent observability gap; not in this plan's blast radius.
- **#2963** (review): Supabase typegen for ConversationPatch drift resistance. **Disposition: Acknowledge.** Touches the supabase factory typing layer; not blocking but a typegen pass would benefit the new `createTenantClient` factory. Track as follow-up.
- **#2962** (review): extract memoized `getServiceClient()` shared lazy singleton. **Disposition: Fold in.** Direct collision — the proposed shared singleton becomes the lint target for `no-service-role-in-runtime`. Add `Closes #2962` to Increment 1 PR; the new factory pattern (`createTenantClient` + allowlisted `getServiceClient` for JWT-mint + audit) supersedes the proposal.
- **#2955** (arch): process-local state assumption needs ADR + startup guard. **Disposition: Fold in.** Addressed by FR8's ADR capture (Increment 3) and Inngest's "single in-flight per `(founderId, domain, eventKey)`" invariant (TR1). Add `Closes #2955` to Increment 3 PR.
- **#2590, #2194** (refactor/dashboard): decompose `dashboard/page.tsx` and layout. **Disposition: Acknowledge.** Increment 3 adds a "Today" section above the existing inbox; doesn't decompose the existing structure. Decomposition is a separate concern; leave open.
- **#2223, #2222** (perf/chat): chat-page derivations + auto-scroll. **Disposition: Acknowledge.** Adjacent to `dashboard/chat`; out of plan scope.

## Increment 0 — Pre-flight (small standalone PR)

**Goal.** Land three independently-shippable changes that reduce blast-radius for Increments 1–3:

1. **Sentry + pino redaction allowlist extension.** Today (`server/logger.ts:19`, `sentry.server.config.ts:11-14`) only strips `x-nonce` and `cookie`. Extend to include: `req.headers.authorization`, `req.body.apiKey`, `req.body.encryptedKey`, `*.api_key`, `*.encrypted_key`, `*.iv`, `*.auth_tag`, BYOK plaintext sentinels. Use pino `redact` array; mirror in Sentry `beforeSend` + `beforeBreadcrumb`. Reason for landing FIRST: Increment 1 introduces new BYOK lease error paths. If redaction lags, the first deploy leaks.
2. **Brand rename: user-visible "Command Center" → "Dashboard"/Soleur.** Targets enumerated below in Files-to-Edit (Increment 0). Internal-only comments and filenames (e.g., `cc-dispatcher.ts`, internal type comments) stay; non-user-facing.
3. **Fold #2962 partial — relocate the canonical service-role singleton** into `lib/supabase/service.ts` with a JSDoc warning that all new use sites are subject to the lint rule landing in Increment 1. (Lint rule itself ships in Increment 1.)

**Files to Edit (Increment 0):**

- `apps/web-platform/server/logger.ts:19` — extend `redact` array.
- `apps/web-platform/sentry.server.config.ts:11-14` — extend `beforeSend` + add `beforeBreadcrumb`.
- `apps/web-platform/app/manifest.ts:5,8` — replace `"Soleur Dashboard — Your Command Center"` → `"Soleur Dashboard"`; replace meta description without "command center".
- `apps/web-platform/app/layout.tsx:13,16` — same.
- `apps/web-platform/app/(dashboard)/layout.tsx:85` — sidebar label `"Command Center"` → `"Dashboard"`.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx:368, 512, 545` — page-header strings.
- `apps/web-platform/components/chat/chat-surface.tsx:403` — visible label.
- `apps/web-platform/components/chat/conversations-rail.tsx:159` — `"View all in Command Center"` → `"View all on Dashboard"`.
- `apps/web-platform/components/connect-repo/ready-state.tsx:78, 187, 198` — buttons `"Open Command Center"`/`"View in Command Center"` → `"Open Dashboard"`/`"View on Dashboard"`.
- `apps/web-platform/server/cc-dispatcher.ts:833` — error message string.
- `plugins/soleur/docs/_data/site.json:5` — site description (drop "command center" phrasing).
- `apps/web-platform/lib/supabase/service.ts` — JSDoc warning + named export of `getServiceClient` (memoized) per #2962.

**Acceptance Criteria (Increment 0):**

- [ ] Pre-merge: `rg -i "command\s*center"` against `apps/web-platform/{app,components,public}/**/*.{ts,tsx,json}` and `plugins/soleur/docs/_data/*.json` returns zero matches (excluding code comments and historical KB artifacts).
- [ ] Pre-merge: redaction unit test asserts `redact()` strips `apiKey`, `Authorization`, `encryptedKey`, `iv`, `auth_tag` from a synthetic log entry. Test fixture per `cq-test-fixtures-synthesized-only`.
- [ ] Pre-merge: Sentry breadcrumb test asserts `beforeBreadcrumb` strips the same keys.
- [ ] Pre-merge: `bun run typecheck` + `bun run test` + `bun run build` green in `apps/web-platform/`.
- [ ] Pre-merge: visual smoke — `bun run dev`, log in, sidebar reads "Dashboard", page header reads "Dashboard", manifest/SEO reads "Soleur Dashboard". Screenshot in PR.

## Increment 1 — Tenant Isolation Hardening (gate-zero)

**Why first.** Single brand-ending vector across all 5 brainstorm domain assessments. Live exposure today via `createServiceClient` in `server/agent-runner.ts`. Switching to user-scoped JWT changes the failure mode of every tenant-data path; downstream increments inherit the new contract.

### 1.1 — `mintFounderJwt(userId)` and `createTenantClient(jwt)`

New module: `apps/web-platform/lib/supabase/tenant.ts`.

- `mintFounderJwt(userId: UserId, opts?: { ttlSec?: number, scope?: string }): Promise<string>` — calls a new SECURITY DEFINER Postgres RPC `public.mint_founder_jwt(uid uuid, ttl_sec int)` that signs a short-TTL JWT (default 600s) with the standard Supabase `auth.uid()` claim using the project's JWT secret. The RPC owns service-role; the Node side never touches the secret.
- `createTenantClient(jwt: string): SupabaseClient` — wraps `createClient(url, anonKey, { global: { headers: { Authorization: \`Bearer ${jwt}\` } } })`. NO `setSession` (avoids cookie-storage assumptions); explicit per-call header.
- **`getFreshTenantClient(userId: UserId): Promise<SupabaseClient>` — auto-remint boundary** (per Kieran P1.1). Caches `{ jwt, mintedAt, client }` per-userId in process-local map; if `now - mintedAt > ttlSec/2`, transparently re-mints and returns a fresh client. Caller path is `getFreshTenantClient` (NOT `createTenantClient`) for any code inside long-running agent loops. This is the only public boundary call sites use; `createTenantClient` is private to this module. Long-running tool calls already started under a stale JWT continue to completion (RLS denies new queries; existing in-flight resultsets are unaffected per PostgREST contract); the next query gets a fresh client. Auto-remint MUST succeed transparently — sanitized-error path is for terminal auth failure (user soft-deleted, JWT secret rotated, RPC error) only.

Call sites to migrate inside `agent-runner.ts` (audit list, all line numbers from repo research):
- `:182` `getUserApiKey` (BYOK fetch — see 1.2)
- `:213` RPC `migrate_api_key_to_v2`
- `:256, :289` `getUserServiceTokens`
- `:329` `saveMessage` INSERT
- `:376` `loadConversationHistory` SELECT
- `:424` `cleanupOrphanedConversations` UPDATE
- `:445` `startInactivityTimer` UPDATE (folds #3219 — slot leak)
- `:528` `users` SELECT
- `:839` `kbShareTools` constructor (`serviceClient: supabase()` → tenantClient)
- `:1071` RPC `increment_conversation_cost`
- `:1315, :1326, :1363, :1373, :1390` `sendUserMessage` ownership check, message insert, attachment metadata, user lookup, storage download
- `:1456` `team_names` SELECT

For each migrated call site, add an **auth probe** before the query (per `2026-04-12-silent-rls-failures-in-team-names.md`): explicit `getUser()` call OR check the JWT's `auth.uid()` claim matches the expected `userId`, distinguishing RLS-empty from auth-failure.

### 1.2 — BYOK lease in `AsyncLocalStorage`

New module: `apps/web-platform/server/byok-lease.ts`.

- `runWithByokLease<T>(userId: UserId, fn: (lease: ByokLease) => Promise<T>): Promise<T>` — opens an `AsyncLocalStorage` scope, decrypts BYOK on demand via existing `decryptKey` (`server/byok.ts`), zeroizes the buffer in `finally` (`buf.fill(0)` then `buf = null`).
- **Buffer-vs-string contract verification (per Kieran P1.2).** Plan-time precondition: `server/byok.ts:decryptKey` MUST return `Buffer`. If it returns `string` today, refactor to `Buffer` BEFORE landing the lease module — V8 string-internment makes `string`-shaped zeroize advisory-only. AC-enforced. Residual exposure acknowledged: the moment the lease hands the key to the Anthropic SDK `query({ apiKey: string })`, V8 interns it again — the lease bounds the in-Soleur-heap window, NOT the SDK-side window. This is mitigation, not elimination; documented in §3.1 ADR.
- `getCurrentByokLease(): ByokLease | null` — reads from ALS; throws if called outside a scope.
- Lease is delivered to the Claude Agent SDK subprocess via `query()`'s `apiKey` parameter (string), NEVER via `process.env`. Existing `agent-env.ts` allowlist (per `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526`) is unchanged; `ANTHROPIC_API_KEY` is NOT added to the allowlist. Verified at `agent-runner.ts:891 buildAgentQueryOptions`.
- **Async-contract widening (per `2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy`).** Audit every existing factory signature touched (`buildAgentQueryOptions`, `createTenantClient` callers). If any takes a sync `(args) => T` and now needs an async fetch, widen to `(args) => Promise<T> | T` rather than wrapping in a deferred-construction proxy. Specifically: confirm `query()` accepts `apiKey: string | (() => Promise<string>)` — if not, widen at the boundary in `agent-runner.ts`.
- Before each Anthropic call (or once per session at the SDK boundary), insert an `audit_byok_use` row via SECURITY DEFINER RPC `public.write_byok_audit(...)` — service-role-allowlisted.

### 1.3 — Audit table `audit_byok_use`

Migration `037_audit_byok_use.sql` — single-table migration. The generalized `audit_log` table (action-class events) lands in Increment 3 alongside its writer fn — shipping its shape in Increment 1 without a writer is dead schema (per simplicity + Kieran P1.3: `this_hash NOT NULL` would reject every row OR force manual hash). Hash-chain itself is **deferred to Post-MVP** — closed-preview alpha doesn't have a forensic-tamper threat model; WORM + RLS-zero-policies + service-role-only-insert is the load-bearing isolation; cryptographic chain only matters under DB-compromise. Tracked as a separate deferral issue (see Deferred Capabilities below).

```sql
-- Header: per cq-pg-security-definer-search-path-pin-pg-temp,
-- every SECURITY DEFINER fn pins SET search_path = public, pg_temp
-- and qualifies every relation as public.<table>.

create table if not exists public.audit_byok_use (
  id uuid primary key default gen_random_uuid(),
  invocation_id uuid not null,
  founder_id uuid not null references public.users(id),
  agent_role text not null,
  ts timestamptz not null default now(),
  token_count int,
  created_at timestamptz not null default now()
);

-- RLS-on, ZERO policies — service-role-only writes (mirrors processed_stripe_events).
alter table public.audit_byok_use enable row level security;

create index audit_byok_use_founder_ts_idx
  on public.audit_byok_use (founder_id, ts desc);  -- NOT CONCURRENTLY (per 2026-04-18-supabase-migration-concurrently-forbidden)

create or replace function public.write_byok_audit(
  p_invocation_id uuid,
  p_founder_id uuid,
  p_agent_role text,
  p_token_count int
) returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.audit_byok_use(invocation_id, founder_id, agent_role, token_count)
  values (p_invocation_id, p_founder_id, p_agent_role, p_token_count);
$$;

revoke all on function public.write_byok_audit(uuid, uuid, text, int) from public;
grant execute on function public.write_byok_audit(uuid, uuid, text, int) to service_role;
```

Migration tests (under `apps/web-platform/test/supabase-migrations/`): assert `select` from `audit_byok_use` as `authenticated` returns zero rows (RLS deny); assert `service_role` insert succeeds; assert `write_byok_audit` callable only by `service_role`. Per `2026-04-18-rls-for-all-using-applies-to-writes.md` — copy the test shape from #1449.

### 1.4 — `mint_founder_jwt` RPC

Migration adds `public.mint_founder_jwt(uid uuid, ttl_sec int default 600) returns text` SECURITY DEFINER. Body uses `auth.sign()` (Supabase exposes via `pg-jwt`); claims include `role='authenticated'`, `sub=uid`, `aud='authenticated'`, `exp=now()+ttl_sec`. `set search_path = public, pg_temp`. Granted to `service_role` ONLY. The Node side calls it via the allowlisted `getServiceClient` (memoized per #2962).

### 1.5 — CI grep gate `no-service-role-in-runtime` (replaces custom ESLint rule)

Custom ESLint rule rejected (per DHH cut #1, simplicity #6) — string-match has no AST expressivity to justify the plugin surface, eslint version churn, and fixture overhead. Replaced with a 1-line CI step backed by a checked-in allowlist:

```bash
# .github/workflows/lint.yml step
rg -l 'createServiceClient|getServiceClient' apps/web-platform/server apps/web-platform/lib \
  | grep -vFf apps/web-platform/.service-role-allowlist \
  && echo "ERROR: undisclosed service-role import" && exit 1 || exit 0
```

`apps/web-platform/.service-role-allowlist` (checked-in, one path per line):

```
apps/web-platform/lib/supabase/service.ts
apps/web-platform/server/health.ts
apps/web-platform/server/byok-lease.ts
apps/web-platform/server/session-sync.ts
apps/web-platform/server/kb-share-tools.ts
```

**`kbShareTools` allowlist decision (per Kieran P3.5).** KB share-link writes legitimately impersonate the share — that's the share-link contract, not a tenant-data leak. Allowlist with explicit `// SERVICE-ROLE: kb-share-link impersonation; audit-row required` comment AND wire `write_byok_audit`-shaped audit row (separate `audit_share_use` table — defer to Increment 3 with `audit_log`). For Increment 1, simply allowlist + comment; deferral issue tracks the audit row.

`session-sync.ts` carries a TODO comment: `// SERVICE-ROLE (transitional): Increment 2 #3244 migrates to tenantClient`.

### 1.6 — Error sanitization at every new surface

Per `2026-03-20-websocket-error-sanitization-cwe-209.md`: every new error path (JWT mint failure, RLS deny, BYOK lease fetch failure, audit-row write failure) must go through `sanitizeErrorForClient()` before any WS forward and through `reportSilentFallback()` (per `cq-silent-fallback-must-mirror-to-sentry`) for server-side mirror. Two typed error classes (collapsed per DHH §1.6 — branch on `cause` field for the auth/audit pair):

- `RlsDenyError` — distinct because client-UX-routing differs (founder vs other-founder data probe).
- `ByokLeaseError` — distinct because client message ("BYOK key invalid; rotate") differs from generic auth.
- `RuntimeAuthError { cause: "jwt_mint" | "audit_write" | "rotation" }` — shared shape for paths whose client message is identical ("Authentication unavailable; retry shortly"). Keeps the consumer-side mapper exhaustive (per `2026-05-04-flag-boundary-creates-new-error-class-mapper-must-handle`) without proliferating one class per cause.

Mapper extended in `lib/auth/error-messages.ts`.

### 1.7 — Per-invocation max-turns + idle/absolute timeout pair

Per `2026-03-20-claude-code-action-max-turns-budget.md` AND `2026-05-05-defense-relaxation-must-name-new-ceiling.md`:

- Per-invocation `maxTurns` ceiling configured per-domain (default: 30 turns, ratio 0.75 min/turn → 22.5min absolute).
- TWO discriminated guards:
  - `idle_window` — resets on every assistant block; default 90s (matches recent #3225).
  - `max_turn_duration` — anchored on `firstToolUseAt`, NOT reset by activity; default 10 min.
- `WorkflowEnd { reason: "idle_window" | "max_turn_duration" | "max_turns" }` discriminator at the runner exit.

Plumbed in `agent-runner.ts` alongside `cc-cost-caps.ts`'s existing `maxBudgetUsd: 5.0` per-conversation cap.

### Files to Create (Increment 1)

- `apps/web-platform/lib/supabase/tenant.ts` — `mintFounderJwt`, `createTenantClient`, `getFreshTenantClient` (auto-remint).
- `apps/web-platform/server/byok-lease.ts` — `AsyncLocalStorage` scope.
- `apps/web-platform/.service-role-allowlist` — checked-in path-list for the CI grep gate (no ESLint rule).
- `apps/web-platform/supabase/migrations/037_audit_byok_use.sql` — single-table migration: `audit_byok_use` + `mint_founder_jwt` RPC + `write_byok_audit` RPC. NO `audit_log` (deferred to Increment 3). NO `CONCURRENTLY`.
- `apps/web-platform/test/supabase-migrations/037_audit_byok_use.test.ts` — migration test (RLS deny for authenticated; service-role insert succeeds).
- `apps/web-platform/test/server/byok-lease.test.ts` — ALS scope test, zeroize-on-finally test, no-env-leak test, **`decryptKey` Buffer-not-string return-type assertion (per Kieran P1.2).**
- `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts` — integration test: founder A's JWT cannot read founder B's `messages`/`conversations`/`api_keys` (per `2026-04-18-rls-for-all-using-applies-to-writes.md` test shape).
- `apps/web-platform/test/server/tenant-jwt-refresh.test.ts` — `getFreshTenantClient` auto-remint at TTL/2; transparent (no error surface); long-running tool call survives mid-session expiry.

### Files to Edit (Increment 1)

- `apps/web-platform/server/agent-runner.ts` — replace `supabase()` callers (11 sites enumerated in §2.2 grep table; remaining ~30 in Increment 2) with `getFreshTenantClient(userId)`. Wire `runWithByokLease` around `startAgentSession` body. Add JWT mint at session start. Folds #3219 (`:445` slot leak).
- `apps/web-platform/lib/supabase/service.ts` — JSDoc warning + memoize `getServiceClient` per #2962. Folds #2962.
- `apps/web-platform/server/byok.ts` — confirm/refactor `decryptKey` returns `Buffer` (per Kieran P1.2). Add `zeroize(buf: Buffer)` helper used by `byok-lease.ts`.
- `apps/web-platform/server/health.ts:15` — already on allowlist (`.service-role-allowlist`); add inline comment `// SERVICE-ROLE: health probe`.
- `apps/web-platform/server/session-sync.ts:133` — allowlist comment + `// SERVICE-ROLE (transitional): Increment 2 #3244 migrates to tenantClient`.
- `apps/web-platform/server/kb-share-tools.ts` — allowlist comment `// SERVICE-ROLE: kb-share-link impersonation; audit-row Increment 3`.
- `apps/web-platform/lib/auth/error-messages.ts` — add `RlsDenyError`, `ByokLeaseError`, `RuntimeAuthError` (with `cause` field) and mapper entries.
- `.github/workflows/lint.yml` (or existing CI workflow) — add CI grep step backed by `apps/web-platform/.service-role-allowlist`.
- `apps/web-platform/server/agent-runner.ts` (separate edit set for §1.7) — wire `idle_window` + `max_turn_duration` guards alongside existing cost cap.

### Acceptance Criteria (Increment 1)

#### Pre-merge (PR)

- [ ] **[RED-first]** Migration test: `audit_byok_use` exists, RLS enabled with zero policies for `authenticated`, `service_role` insert succeeds. Verified via `psql` SELECT against the Doppler-resolved dev project ref (per `cq-plan-ac-external-state-must-be-api-verified` — query the table directly, not grep INSERTs).
- [ ] **[RED-first]** Migration test: `mint_founder_jwt` and `write_byok_audit` callable only by `service_role`; `authenticated` call returns `42501`.
- [ ] **[RED-first]** Migration test: `mint_founder_jwt` returns a JWT whose decoded payload has `sub == uid`, `role == "authenticated"`, `exp` within `ttl_sec ± 5s` of `now()`. JWT decoded in test (per `2026-04-29-jwt-fixture-reminting-decode-verify`); decoded form grepped for plaintext leakage.
- [ ] **[RED-first]** Integration test: founder A's session cannot SELECT founder B's `messages`, `conversations`, `api_keys`. Per `2026-04-18-rls-for-all-using-applies-to-writes` test shape; on a real Supabase test instance (not mocked), per `cq-test-fixtures-synthesized-only` (synthesized fixtures, no prod-shape UUIDs).
- [ ] **[RED-first]** BYOK ALS test: lease zeroized in `finally`; subsequent read throws; subprocess `process.env` does NOT contain `ANTHROPIC_API_KEY`; pino + Sentry log capture asserts no plaintext key in any field.
- [ ] **[RED-first]** `decryptKey` return-type assertion: `typeof decryptKey(...) === "object" && Buffer.isBuffer(decryptKey(...))`. If `string`, refactor lands in this PR. (Per Kieran P1.2.)
- [ ] **[RED-first]** Auto-remint test: synthetic 60s-TTL JWT, `getFreshTenantClient` invoked at t=31s returns a fresh JWT (mintedAt advanced); long-running query started at t=10s completes successfully without error.
- [ ] **[scaffolding]** CI grep test: synthetic file with undisclosed `createServiceClient` import is rejected by the grep gate; allowlisted file is accepted.
- [ ] Code: zero use of `supabase()` (the old service-role singleton) in `server/agent-runner.ts`. `rg "createServiceClient|getServiceClient" apps/web-platform/server/agent-runner.ts` returns zero matches.
- [ ] Closes #3219, Closes #2962 in PR body. PR-A body uses `Ref #3244` (NOT `Closes` — see PR Strategy).
- [ ] Per `cq-write-failing-tests-before` (TDD gate): RED-first tests above committed and failing on a clean main; turn green on this PR.

#### Post-merge (operator)

- [ ] Run `apps/web-platform/infra/` Terraform apply if any infra change accompanies the migration (none expected — migrations apply via Supabase CLI). Verify no apply.
- [ ] Apply migration to prd: `supabase db push --linked --include-all --password "$(doppler secrets get SUPABASE_DB_PASSWORD -p soleur -c prd --plain)"` (form verified against `supabase --version` 1.x at plan time; the `--linked` and `--password` flags suppress the TTY-bound interactive prompt that would otherwise hang in the agent's non-interactive shell). Show command, wait for go-ahead per `hr-menu-option-ack-not-prod-write-auth`.
- [ ] Smoke: log in to dev as a real founder, send a message, verify `audit_byok_use` row written (`select * from public.audit_byok_use order by ts desc limit 1` via psql).
- [ ] Confirm canonical Supabase project ref in deployed bundle matches Doppler `prd` (per `2026-04-28-anon-key-test-fixture-leaked-into-prod-build`); run `curl -s https://app.soleur.ai/api/health | jq` and verify `supabase_ref` field.

### Test Scenarios (Increment 1)

- **Cross-tenant SELECT denial.** Founder A logs in, founder B's JWT is minted via `mint_founder_jwt(B.id)`. With `createTenantClient(B.jwt)`, attempt `SELECT * FROM messages WHERE user_id = A.id`. Assert zero rows AND `RlsDenyError` is NOT thrown (RLS-filter is silent — auth probe distinguishes empty from deny).
- **JWT expiry mid-session.** Mint a 5s-TTL JWT; sleep 6s; attempt SELECT. Assert `JwtMintError` (not `RlsDenyError`); assert auto-remint happens at the next call boundary or returns sanitized error to client via `sanitizeErrorForClient`.
- **BYOK lease zeroize.** `runWithByokLease(userId, async (lease) => { ... })` — assert `lease.apiKey` is a non-empty string inside the scope; outside the scope, attempt `lease.apiKey` access throws; the underlying buffer reads zeros (introspect via test-only hook).
- **Subprocess env leak.** Spawn subprocess inside the lease scope; subprocess prints `process.env`; assert NO `ANTHROPIC_API_KEY`, `BYOK_ENCRYPTION_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY` in the dump (the agent-env allowlist is unchanged).
- **WS error sanitization.** Force a `RlsDenyError`; assert WS forward to client is `"Access denied."` (sanitized) AND Sentry has the full error tagged `feature: "agent-runner", op: "tenant-query"`.
- **Replay correctness under JWT.** Create founder A's conversation with 5 messages; resume via `loadConversationHistory(A.userId, conversationId)`. Assert all 5 messages returned. Then resume founder B's JWT against A's conversation; assert RLS-deny + zero rows + `RlsDenyError`-shaped sanitized error.
- **Sibling-query audit (per `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper`).** `rg "from\\(\"(messages|conversations|api_keys|users|team_names)\"" apps/web-platform/server/agent-runner.ts` enumerates queries; each must use `tenantClient`, not `supabase()`. Assert via lint + grep at CI.

### Risks (Increment 1)

- **R1.1 — `loadConversationHistory` returns empty under RLS.** If `messages.user_id` policy doesn't grant `auth.uid() = user_id` (or grants a different shape), the post-cutover replay fails silently — agent loses memory mid-session. **Mitigation:** Increment 1 tests assert SELECT returns prior messages BEFORE Increment 2 starts. Auth probe added.
- **R1.2 — JWT clock skew or RPC latency.** If `mint_founder_jwt` adds >100ms per session start, WS handshake gets slower. **Mitigation:** mint once per WS session, cache via `getFreshTenantClient` per-userId process-local map, transparent auto-remint at TTL/2 (§1.1 contract).
- **R1.6 — JWT signing-secret rotation invalidates all live leases.** Supabase recommends periodic rotation. **Mitigation:** drain-and-remint at deploy boundary; out of MVP scope as a runbook item; flagged for post-launch operations doc.
- **R1.3 — `permission-callback.ts` review-gate UX assumes service-role.** Need to re-audit `:599-700` for `tenantClient` compatibility. Likely OK since review-gate writes to its own table, but verify.
- **R1.4 — `kbShareTools` constructor takes `serviceClient` (`:839`).** If we hand it a `tenantClient`, KB share-link writes (which today bypass RLS) may fail. **Mitigation:** scope decision — if KB share-link writes legitimately need service-role (impersonating the share), add explicit allowlist comment + audit row.
- **R1.5 — Async-contract proxy regression (per `2026-04-27` learning).** If we wrap async BYOK fetch in a sync-factory proxy, KeyInvalidError surfaces under wrong Sentry tag. **Mitigation:** widen the contract upfront; do NOT proxy.

## Increment 2 — Multi-Turn Continuity Hardening + Episodic Memory

**Why second.** #1044 is technically CLOSED, but the codebase paths it landed (SDK-resume + replay fallback) ran under service-role assumptions. Increment 1's switch breaks them unless RLS is correct AND every sibling query is migrated. Increment 2 verifies, hardens, and adds the episodic-memory layer that makes leader retrieval better-than-replay.

### 2.1 — Verify #1044 SDK-resume under user-scoped JWT

- **RLS-audit gate (per Kieran P2.1).** Plan-time audit deferred to `/soleur:deepen-plan` Phase 4.x (deepen-plan's per-section research is the right place for live-DB introspection). Deepen-plan MUST run `psql $DEV_URL -c "select tablename, policyname, cmd, qual from pg_policies where tablename in ('messages','conversations','api_keys','users','team_names') order by 1,2"` and paste the result table into the plan's §2.1. **If any policy is insufficient for `auth.uid() = user_id` SELECT, the corresponding RLS migration moves to Increment 1 (NOT Increment 2)** — Increment 1's tenantClient switch fails open without it. Plan landing with §2.1 RLS table empty is acceptable; landing into `/work` without it is a workflow violation.
- Confirm `agent-runner.ts:953-961` (`session_id` persist) and `:1421` (resume) work under `tenantClient` — covered by Increment 1's replay-correctness test.
- Per `2026-04-12-startAgentSession-catch-block-swallows-resume-errors`: ensure the `startAgentSession` catch RE-THROWS resume errors so the caller's "clear stale session_id, replay history" fallback actually fires. Today's catch may swallow.

### 2.2 — Sibling-query audit (per `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper`)

**Plan-time grep result (executed 2026-05-05).** ~100 call sites total. Pre-classification by client-source:

| Surface | Files | Sites | Disposition |
|---|---|---|---|
| **Service-role custom-server (Increment 1 audit list)** | `server/agent-runner.ts` | 11 | `tenantClient` migration in Increment 1 §1.1. |
| **Service-role custom-server (sibling — Increment 2 in scope)** | `server/ws-handler.ts` | 10 | `tenantClient` migration. The `:432` insert + `:452, :754, :896, :1116` updates and `:294, :812, :1410` user reads are tenant-data paths. |
| **Service-role custom-server (sibling — Increment 2 in scope)** | `server/conversations-tools.ts` | 4 | All `from("conversations")` — tenant-data; migrate. |
| **Service-role custom-server (sibling — Increment 2 in scope)** | `server/session-sync.ts` | 4 | Migrate to `tenantClient` (lifts the Increment 1 transitional allowlist). |
| **Service-role custom-server (sibling — Increment 2 in scope)** | `server/api-messages.ts`, `server/api-usage.ts`, `server/conversation-writer.ts`, `server/lookup-conversation-for-path.ts`, `server/current-repo-url.ts`, `server/kb-document-resolver.ts`, `server/kb-route-helpers.ts` | ~10 | Migrate; each is a single-query helper. |
| **SSR cookie anon-key (already RLS-enforced; verify, do not migrate)** | `app/(auth)/callback/route.ts`, `app/(dashboard)/layout.tsx`, `app/(dashboard)/dashboard/{page,settings,admin}/...`, `app/api/{kb,vision,checkout,services,keys,team-names,billing,workspace,repo,attachments,accept-terms,auth}/**/route.ts` | ~70 | No migration — these use `createClient` from `@/lib/supabase/server` (cookie-based anon-key) and are already under RLS. Increment 2 sample-audits 5 random files to confirm no service-role drift; lint allowlist (§1.5) blocks future regression. |
| **Stripe webhook** | `app/api/webhooks/stripe/route.ts` | 6 | Webhook is unauthenticated by design (signature-verified); legitimately uses `createServiceClient`. Allowlist with explicit comment + the existing dedup/`processed_stripe_events` boundary. |

**Increment 2 migration scope: ~30 sites across 9 server-only files** (the first five rows above). Each call-site gets its own ACE entry in the §2.2 audit table with `tenantClient | service-role-allowlisted | refactored-out` per row. Full audit-table-of-30 lands in the Increment 2 PR description (NOT plan body — too long).

### 2.3 — Episodic memory store (TR3)

Migration `038_episodic_memory.sql`:

```sql
create extension if not exists vector;  -- pgvector

create table if not exists public.episodic_memory (
  id uuid primary key default gen_random_uuid(),
  founder_id uuid not null references public.users(id),
  domain text not null check (domain in (
    'engineering','marketing','operations','product','legal',
    'sales','finance','support','router'
  )),
  ts timestamptz not null default now(),
  vector vector(1536) not null,         -- OpenAI/Anthropic 1536-d embeddings
  payload jsonb not null
);

alter table public.episodic_memory enable row level security;

create policy episodic_memory_owner_select on public.episodic_memory
  for select using (auth.uid() = founder_id);
create policy episodic_memory_owner_insert on public.episodic_memory
  for insert with check (auth.uid() = founder_id);
-- No UPDATE/DELETE policies — memory is append-only at the boundary.

create index episodic_memory_founder_domain_ts_idx
  on public.episodic_memory (founder_id, domain, ts desc);  -- NOT CONCURRENTLY

-- pgvector index uses ivfflat (smaller footprint than hnsw for alpha scale).
-- NOTE: ivfflat requires data before index for good recall; defer ANN index
-- to a separate manual migration once N>1000 rows accumulate per founder.
-- Until then, sequential scan + WHERE founder_id is fine.
```

**Single shared Supabase project — RLS-isolated per founder.** Spec wording "per-founder pgvector in their Supabase project" is interpreted as per-founder ROW isolation in the single shared prd Supabase project, NOT one project per founder. (See Plan Open Questions.) Confirm with user at deepen-plan if needed.

### 2.4 — Episodic memory writer + retriever

New module: `apps/web-platform/server/episodic-memory.ts`.

- `writeEpisode(founderId, domain, payload, embeddingFn): Promise<void>` — runs under `tenantClient` (not service-role); embedding via existing model client (or new helper if absent).
- `retrieveEpisodes(founderId, domain, queryVector, k=5): Promise<Episode[]>` — RLS-filtered SELECT with cosine similarity (`vector <=> $1`).
- Wired into the leader-prompt assembly in `agent-runner.ts` (one new call per turn).

### 2.5 — Catch-block re-throw fix (per `2026-04-12-startAgentSession-catch-block-swallows-resume-errors`)

Edit `agent-runner.ts:startAgentSession` catch — re-throw on `ResumeError`-shape errors so the caller can fall back to replay.

### 2.6 — Discriminated-union exhaustiveness

Process gate, not implementation — moved to the Increment 2 PR-body checklist (per DHH §2.6). Reference: `cq-union-widening-grep-three-patterns`. Applied at every event-variant addition in this plan (§1.7 `WorkflowEnd`, §3.1 Inngest payload variants).

### Files to Create (Increment 2)

- `apps/web-platform/supabase/migrations/038_episodic_memory.sql`
- `apps/web-platform/test/supabase-migrations/038_episodic_memory.test.ts`
- `apps/web-platform/server/episodic-memory.ts`
- `apps/web-platform/test/server/episodic-memory.test.ts`
- `apps/web-platform/test/server/agent-runner.replay.test.ts` — replay correctness under tenantClient.

### Files to Edit (Increment 2)

- `apps/web-platform/server/agent-runner.ts` — `startAgentSession` re-throw fix; `loadConversationHistory` audit; episodic-memory write/retrieve hooks.
- `apps/web-platform/server/session-sync.ts:133` — migrate to tenantClient where viable; expand allowlist comment if not (justify).
- Any sibling-query call-sites discovered in §2.2 audit (list to be enumerated at work-phase from grep output; plan reserves a `Files to Edit (audit-derived)` placeholder).
- Add RLS migration if `messages` or `conversations` policies are insufficient for `auth.uid() = user_id` SELECT.

### Acceptance Criteria (Increment 2)

#### Pre-merge

- [ ] Sibling-query audit table in PR description: every query against `messages|conversations|api_keys|users|team_names` enumerated with `tenantClient | service-role-allowlisted | refactored-out` disposition.
- [ ] Replay correctness test: founder A sends 10 messages across 3 turns; agent resume reads all 10. Founder B's JWT cannot resume A's conversation (RLS deny verified).
- [ ] `pgvector` extension enabled in dev. `select * from pg_extension where extname = 'vector'` returns 1 row (psql-verified, per `cq-plan-ac-external-state-must-be-api-verified`).
- [ ] Episodic memory test: founder A writes 3 episodes; `retrieveEpisodes(A, domain, q, 5)` returns A's only; B's JWT against A's `founder_id` returns zero rows.
- [ ] RLS policies on `episodic_memory`: `for select using (auth.uid() = founder_id)` — verified by attempting cross-founder SELECT.
- [ ] `startAgentSession` re-throw test: synthetic `ResumeError` thrown inside `startAgentSession`; caller's catch-and-replay fallback fires.
- [ ] Discriminated-union grep clean: `_exhaustive: never` at every consumer of new event variants.

#### Post-merge

- [ ] Verify `pgvector` enabled in prd: `psql $PRD_URL -c "select extname from pg_extension where extname='vector'"`. (Operator step; per `hr-menu-option-ack-not-prod-write-auth` — show command, wait for go-ahead.)
- [ ] Smoke: log in as a real founder; send 5 messages across 2 turns over 10 minutes; verify the second turn references the first turn's content (replay working).

### Test Scenarios (Increment 2)

- **Cross-founder retrieval denial.** A writes 5 episodes; B retrieves with `founder_id = B.id`; gets zero. B retrieves with `founder_id = A.id` (forging) → RLS deny.
- **Replay-after-restart.** Restart the Hetzner host; reconnect WS; resume conversation by `session_id`; assert all prior messages present.
- **Resume-error fallback.** Force `session_id` to invalid; assert caller's replay-history fallback fires (not silent failure).
- **Embedding pipeline.** Episode is written with vector dimension 1536; retrieve by similarity returns it as the nearest neighbor.

### Risks (Increment 2)

- **R2.1 — pgvector dimension drift.** Different embedding model = different dimension = silent retrieval failure. **Mitigation:** column dimension is fixed at migration time; runtime asserts `vector.length === 1536` before insert; `SCHEMA_VERSION` field on `payload` per `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary` — assert at retriever, not just writer.
- **R2.2 — ivfflat index recall when N is small.** Recall is poor below ~1000 rows per founder. **Mitigation:** sequential scan acceptable for alpha; defer ANN index migration until per-founder data warrants it.
- **R2.3 — Sibling-query miss.** Audit grep misses a query that uses string concatenation instead of the `.from()` API. **Mitigation:** secondary grep for `from "messages"`, `FROM messages`, raw SQL strings; lint rule extension to flag raw-SQL-strings against tenant tables.

## Increment 3 — Daily Priorities, Inngest, Stripe Trigger, Trust-Tier, Cost Kill-Switch, ADR

**Why last.** Background reactions amplify whatever signal the leaders emit. Without Increments 1 + 2 (tenant isolation + replay correctness + episodic memory), background actions multiply the failure modes. Three orthogonal sub-deliveries inside this increment, each independently testable.

### 3.1 — Inngest substrate (TR1, FR8)

- Add dependency: `inngest@^3` to `apps/web-platform/package.json`. Regenerate both `bun.lock` and `package-lock.json` (per `cq-before-pushing-package-json-changes`).
- New API route: `apps/web-platform/app/api/inngest/route.ts` — Next.js App Router. Per `cq-nextjs-route-files-http-only-exports`, this file exports ONLY the `serve()` HTTP handlers; the Inngest function definitions live in `server/inngest/functions/` (sibling modules).
- `server/inngest/client.ts` — `inngest = new Inngest({ id: "soleur-runtime", env, ... })`.
- `server/inngest/functions/cfo-on-payment-failed.ts` — function bound to event `{founderId}.finance.payment_failed` (event-id keying for idempotency).
- One in-flight per `(founderId, domain, eventKey)` enforced via Inngest concurrency key. Prevents ralph-loop pathology (per `2026-03-13-ralph-loop-idle-detection-and-repetition`).
- Cron lives in Inngest scheduler, NOT GH Actions (per `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs`).
- Inngest event payload envelope: `{ schema_version: 1, founderId, domain, event, payload }`. `schema_version` asserted at the worker per `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary`. **Version-band tolerance (per Kieran P2.3)** — exported constants `MIN_SUPPORTED = 1`, `MAX_SUPPORTED = 1`. Worker logic: `if (v > MAX_SUPPORTED) throw SchemaVersionError(forward-incompat)`; `if (v < MIN_SUPPORTED) deadletter()`; else `upcast(v) -> MAX_SUPPORTED`. Prevents 30-second deploy-window outages where a stale producer (cron) emits v1 against a worker upgraded to v2 (or vice versa). NOT cosmetic — consumer-side gate is load-bearing.
- Discriminated-union for `payload` per variant: `PaymentFailedPayload | LeadInboxPayload | KbDriftPayload | …`. `_exhaustive: never` switch rails at every consumer per `cq-union-widening-grep-three-patterns`.
- Each Inngest function runs under `runWithByokLease` + `createTenantClient(jwt)` — Increment 1 contract carries through.
- ADR captured via `/soleur:architecture create "Adopt Inngest as durable trigger layer for server-side agents"` — output to `knowledge-base/engineering/adrs/<n>-inngest-as-durable-trigger-layer.md`. Includes rejected alternatives (LangGraph, Bedrock AgentCore, Cloudflare DO + LISTEN/NOTIFY) and load-bearing invariants. Closes #2955.

### 3.2 — Stripe `payment_failed` → CFO end-to-end (FR5)

- Edit `apps/web-platform/app/api/webhooks/stripe/route.ts`: extend the existing `processed_stripe_events` dedup + atomic `.in()` UPDATE pattern (per `2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern`) to handle `invoice.payment_failed` and `charge.failed`.
- On dedup-success, emit Inngest event `{founderId}.finance.payment_failed` with the Stripe event_id as Inngest's idempotency key.
- `cfo-on-payment-failed.ts` Inngest function:
  - Mint founder JWT via Increment 1 contract.
  - Open BYOK lease.
  - Run CFO leader (existing `domain-leaders.ts` invocation).
  - Leader output: a draft customer response (saved as a draft in `messages` table flagged `tier: external_brand_critical, status: draft`) + an expense log row.
  - Surface result as a Today card (see §3.3).
- Per `2026-03-23-action-completion-workflow-gap`: the Inngest step MUST drive the action to surface state, not stop at "drafted." The Today card is the executor.
- Per `domain-leader-false-status-assertions-20260323`: before CFO acts on the Stripe event, fetch fresh Stripe charge state via API — don't trust the webhook payload to still be authoritative. Quality telemetry tracks claim-vs-truth divergence.

### 3.3 — Daily Priorities `/dashboard` Today section (FR4)

**Single-source MVP (per simplicity #5 + DHH #5).** Stripe-only for the Today section. GitHub-source and KB-drift-source deferred (separate tracking issues — see Deferred Capabilities). Closes brainstorm Open Question #4.

- Edit `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — add a "Today" section above the existing inbox/foundation cards. Page is a server component already; fetch happens directly in `page.tsx` (NO new `/api/dashboard/today/route.ts`, NO `today-aggregator.ts` module — direct Supabase query under `tenantClient` per DHH #5).
- New component: `apps/web-platform/components/dashboard/today-card.tsx` — renders one card. List rendering inline in `page.tsx`. (Single file; second component appears only when a second Today card *type* surfaces.)
- Today items: drafts emitted by §3.2 CFO function, persisted as `messages` rows flagged `tier: external_brand_critical, status: draft`. Direct query: `tenantClient.from('messages').select(...).eq('user_id', auth.uid()).eq('status','draft').eq('tier','external_brand_critical').order('created_at',{ascending:false}).limit(20)`. RLS handles tenant isolation.
- Each Today card shows: source ("Stripe"), owning leader ("CFO"), draft preview, urgency, "Send" / "Edit" / "Discard" buttons.
- "Send" routes through trust-tier (§3.4 tier 3 `draft_one_click` for external_brand_critical drafts).
- Per `2026-04-23-render-time-scrub-sentinels-and-client-bundle-boundaries`: the new card component is a client component for the action buttons but MUST NOT import `@/server/observability`. Server fetch happens in `page.tsx` (server component). Add any new server packages to `next.config.ts` `serverExternalPackages` only if Inngest's server lib leaks to client.

### 3.4 — Trust-tier policy (FR6) — 3-tier MVP

**Collapsed from 5 to 3 tiers** (per DHH #3 + simplicity #3). MVP has no action sites for `auto_with_digest` (no internal-infra background actions ship in this plan) or `per_command_ack` (lift-pause maps to `approve_every_time`). 5-tier refactor deferred until a second background trigger lands.

- Edit `server/tool-tiers.ts` — extend the existing per-tool 3-tier (`auto-approve | gated | blocked`) with a new per-action-class taxonomy keyed independently. The two coexist; tool-level lookup unchanged for legacy MCP tools.
- New type in `lib/types.ts`: `TrustTier = "auto" | "draft_one_click" | "approve_every_time"`.
- Action-class taxonomy (3 buckets):
  1. Read/research/draft (KB writes, plan writes, internal artifacts) → `auto`.
  2. External-facing draft (draft email, draft customer reply, draft tweet) → `draft_one_click`.
  3. External-facing brand-critical / money / credentials (publish blog, send to customer, charge, BYOK rotation, prod migration, lift-pause) → `approve_every_time` (reuses existing `permission-callback.ts:599-700` review-gate UX).
- Storage: `const ACTION_CLASS_DEFAULTS` map in `server/tool-tiers.ts` (no Postgres table for MVP). Per-founder override is YAGNI until a founder requests one. Column shape on a future `trust_tier_policy` table is documented in the ADR (§3.1) for forward-extensibility — not built.
- `draft_one_click` is the only new UI state — adds `status: 'draft' AND tier: 'external_*'` markers on `messages` rows; founder clicks Send → action fires (exact path used by §3.3 Today cards).
- **Verify-external-state fallback contract (per Kieran K3 / P1.4).** Before any `approve_every_time` action fires (and before §3.2 CFO posts a draft based on a Stripe webhook payload), freshly fetch the relevant external state. Contract:
  - **Timeout: 2s per source** (matches §3.3 R3.3 source timeout).
  - **On timeout: block-and-alert** — action does NOT fire; founder sees "Verifying [source] — try again shortly"; `reportSilentFallback(err, { feature: "trust-tier-verify", op: "<source>" })` mirrors to Sentry.
  - **On verification mismatch (state drifted vs webhook payload):** action does NOT fire; founder sees "Stripe state has changed since this draft — review and re-issue"; the stale draft is auto-archived; new draft re-queued.
  - NO silent proceed-on-error. NO silent proceed-on-stale.
- Per `domain-leader-false-status-assertions-20260323`: trust-tier policy gate AND verify-before-act gate are independent — both fire on every external-class action.

### 3.5 — Per-tenant cost attribution + kill-switch (TR6)

**No new `tenant_cost_window` table** (per DHH #4). Cumulative spend is derived from `audit_byok_use` (Increment 1) — the existing index `audit_byok_use_founder_ts_idx (founder_id, ts desc)` already covers the sliding-window query. Two new columns on `public.users` (small ALTER, no new table):

```sql
-- Migration 040_runtime_cost_state.sql
alter table public.users
  add column if not exists runtime_paused_at timestamptz,
  add column if not exists runtime_cost_cap_cents int default 1000;  -- $10/hr default
```

- **Atomic check-and-record (per Kieran K4).** New SECURITY DEFINER RPC `public.record_byok_use_and_check_cap(p_invocation_id uuid, p_founder_id uuid, p_agent_role text, p_token_count int, p_unit_cost_cents int) returns table(cumulative_cents int, kill_tripped bool)`. Single call inserts the audit row AND aggregates `SUM(token_count * unit_cost_cents) FROM public.audit_byok_use WHERE founder_id=$1 AND ts > now() - '1 hour'` AND atomically sets `users.runtime_paused_at = now()` (`ON CONFLICT … DO UPDATE … WHERE runtime_paused_at IS NULL`) when sum exceeds `users.runtime_cost_cap_cents`. RETURNING is the source of truth for the kill-decision — no separate SELECT-then-UPDATE TOCTOU window. `set search_path = public, pg_temp`. Granted to `service_role` only.
- Soft alert at 50% — emitted as a structured pino log entry mirrored to Sentry via `reportSilentFallback({feature:"cost-kill", op:"soft-alert"})`. No new vendor.
- Hard kill: when `kill_tripped == true`, the runtime BYOK lease release path (`runWithByokLease` `finally`) checks `users.runtime_paused_at` and refuses to mint new leases. Active concurrency slots release via existing `2026-05-04-cc-archive-must-release-concurrency-slot` machinery (Inngest steps cancel via `step.sleepUntil` watchdog; WS sessions emit `runtime_paused` event and close).
- Founder lift-pause = `approve_every_time` tier action (verify-external-state per §3.4: re-auth check before clearing `runtime_paused_at`).
- **PagerDuty deferred to beta.** Closed alpha = founder watching Sentry; `cq-silent-fallback-must-mirror-to-sentry` already gives the alert path. Tracking issue filed (see Deferred Capabilities). Anomaly detector deferred with PagerDuty.
- Per `2026-04-21-cloud-task-silence-watchdog-pattern`: pair with idle-window guard from §1.7.

### 3.6 — FR7 closed-preview launch gate (trivial flag)

`RUNTIME_PUBLIC_LAUNCH=false` env flag in Doppler `dev`/`prd`. Paid-tier signup/upgrade returns `503` when false. Legal artifacts (E&O, DPA, sub-processor page, etc.) tracked under CLO separately.

### 3.7 — TR9 failure-mode prevention summary

Already addressed across §1.7 (max-turns + idle/absolute timeouts), §3.1 (Inngest concurrency key), §3.5 (cost kill-switch). Document in the ADR (§3.1).

### Files to Create (Increment 3)

- `apps/web-platform/app/api/inngest/route.ts`
- `apps/web-platform/server/inngest/client.ts` — Inngest client + `EventEnvelope` types + schema-version band tolerance helpers (consolidated; no separate `event-envelope.ts` module per simplicity #8).
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts`
- `apps/web-platform/components/dashboard/today-card.tsx` — single component; list rendering inline in `dashboard/page.tsx` per simplicity #8 + DHH #5.
- `apps/web-platform/supabase/migrations/039_audit_log.sql` — generalized `audit_log` table (action-class events) WITHOUT hash-chain (deferred Post-MVP per A6); RLS-on, zero policies, service-role-only insert via SECURITY DEFINER `write_audit_log()` RPC. Index `(tenant_id, action_type, ts desc)` per Kieran P3.3.
- `apps/web-platform/supabase/migrations/040_runtime_cost_state.sql` — `users` ALTER (two columns: `runtime_paused_at`, `runtime_cost_cap_cents`) + `record_byok_use_and_check_cap()` RPC. NO new `tenant_cost_window` table (per DHH #4).
- (Migration `038_episodic_memory.sql` already listed in Increment 2 §2.3.)
- (No `trust_tier_policy` migration — `ACTION_CLASS_DEFAULTS` map in `server/trust-tier.ts` per simplicity #3.)
- `apps/web-platform/server/trust-tier.ts` — 3-tier action-class taxonomy + verify-state fallback contract.
- `apps/web-platform/server/cost-kill-switch.ts` — thin wrapper around `record_byok_use_and_check_cap()` RPC + lift-pause flow.
- `apps/web-platform/server/audit-log.ts` — writer (calls `write_audit_log` RPC).
- `apps/web-platform/test/server/inngest/cfo-on-payment-failed.test.ts`
- `apps/web-platform/test/server/cost-kill-switch.test.ts` — includes **concurrent-write race test (per Kieran P1.5):** two parallel +$3 increments against $5 cap → exactly one kill trip.
- `apps/web-platform/test/server/trust-tier.test.ts`
- `apps/web-platform/test/server/audit-log.test.ts`
- `apps/web-platform/test/e2e/dashboard-today.spec.ts` — Playwright e2e.
- `knowledge-base/engineering/adrs/<NNN>-inngest-as-durable-trigger-layer.md` (FR8, ADR).

### Files to Edit (Increment 3)

- `apps/web-platform/package.json` — add `inngest`. Regenerate `bun.lock` AND `package-lock.json`.
- `apps/web-platform/app/api/webhooks/stripe/route.ts` — handle `invoice.payment_failed` + `charge.failed`; emit Inngest event.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — render `TodayCardList` above existing inbox.
- `apps/web-platform/server/tool-tiers.ts` — refactor 3-tier → 5-tier; preserve existing tool entries via mapping.
- `apps/web-platform/lib/types.ts` — add `TrustTier`, `ActionClass`, `EventEnvelope`, payload union types.
- `apps/web-platform/server/permission-callback.ts:599-700` — extend review-gate for tier 3 (draft + 1-click) and tier 5 (per-command ack).
- `apps/web-platform/next.config.ts` — extend `serverExternalPackages` if any new server-only chain (Inngest server lib) leaks into client bundles.
- `apps/web-platform/server/agent-runner.ts` — wire trust-tier check before any external action; wire cost-kill-switch counter.

### Acceptance Criteria (Increment 3)

#### Pre-merge

- [ ] Inngest dep installed; `bun.lock` AND `package-lock.json` regenerated; `bun run build` green; `bun run test` green; `bun run typecheck` green.
- [ ] `app/api/inngest/route.ts` exports only HTTP handlers + Next.js config (per `cq-nextjs-route-files-http-only-exports`); `next build` green (the validator runs only at build time, not in vitest/tsc).
- [ ] Stripe `invoice.payment_failed` test: synthesized webhook with synthesized event_id (per `cq-test-fixtures-synthesized-only`); first delivery emits Inngest event; replay returns dedup hit (no second emit); CFO function runs once.
- [ ] CFO function test: under `runWithByokLease` + `tenantClient`, drafts a customer response saved with `tier: external_brand_critical, status: draft`; Today card surfaces with "Send" button; click Send → tier-4 review-gate UX fires.
- [ ] Today aggregator test: ≥3 source types each contribute ≥1 card under synthesized fixtures; cross-founder leak test (founder A's JWT cannot see founder B's Today cards).
- [ ] Trust-tier policy test: 5 action classes correctly route to 5 tier UX states; per-command-ack tier blocks until ack signal.
- [ ] **[RED-first]** Cost kill-switch atomic test (per Kieran P1.5): two concurrent `record_byok_use_and_check_cap` calls each adding $3 against a $5 cap result in EXACTLY one `kill_tripped == true` and one `kill_tripped == false` (NOT zero, NOT two). RETURNING from `INSERT … ON CONFLICT … DO UPDATE` is the source of truth; no separate SELECT-then-UPDATE.
- [ ] Cost kill-switch test: synthesized cumulative spend exceeds soft alert → `reportSilentFallback({feature:"cost-kill", op:"soft-alert"})` mirrored; exceeds hard cap → `users.runtime_paused_at` set; all founder's concurrency slots released; UI shows "Runtime paused."
- [ ] Trust-tier verify-state timeout test (per Kieran K3): synthesized Stripe API timeout (>2s) → action does NOT fire; founder sees "Verifying Stripe — try again shortly"; `reportSilentFallback({feature:"trust-tier-verify", op:"stripe"})` mirrored.
- [ ] Trust-tier verify-state mismatch test: webhook payload says `payment_failed` but live API returns `paid` (founder retried in another tab) → action does NOT fire; draft auto-archived; new draft re-queued.
- [ ] Inngest event envelope test: schema_version mismatch at consumer raises typed `SchemaVersionError`, NOT silent skip. Discriminated-union exhaustiveness verified by `_exhaustive: never` in switch.
- [ ] CSRF defense on `/api/dashboard/today` and Inngest receiver per `2026-03-20-csrf-three-layer-defense-nextjs-api-routes` (existing pattern).
- [ ] Browser smoke (Playwright): log in, navigate `/dashboard`, see Today section above inbox; click "Let CFO handle it" on a synthesized failed-payment card; draft response surfaces inline.
- [ ] No new client component imports `@/server/observability` (per `2026-04-23-render-time-scrub-sentinels-and-client-bundle-boundaries`); `serverExternalPackages` updated as needed.
- [ ] ADR file written; rejected alternatives section includes LangGraph, Bedrock AgentCore, Cloudflare DO + LISTEN/NOTIFY with rationale.
- [ ] Closes #3244 (whole feature), Closes #2955 (process-local state ADR) in PR body.

#### Post-merge (operator)

- [ ] `terraform apply` in `apps/web-platform/infra/` if infra changes (Inngest webhook URL exposure may need a Cloudflare Worker rule — verify; if not, no apply needed). Show command, wait for go-ahead per `hr-menu-option-ack-not-prod-write-auth`.
- [ ] Doppler: set `INNGEST_EVENT_KEY`, `INNGEST_SIGNING_KEY` in `prd` (and `dev` for staging). `doppler secrets get INNGEST_SIGNING_KEY -p soleur -c prd --plain` non-empty.
- [ ] Inngest dashboard: confirm `cfo-on-payment-failed` function registered. Browser-automate via Playwright MCP if possible (`hr-never-label-any-step-as-manual-without`).
- [ ] Smoke: trigger a Stripe `invoice.payment_failed` test event from Stripe dashboard; confirm Today card appears within 30s for the affected founder; CFO draft is non-empty and brand-correct.
- [ ] Per `wg-after-merging-a-pr-that-adds-or-modifies` workflow rule: no new GH Actions workflows in this increment (Inngest cron replaces). N/A.

### Test Scenarios (Increment 3)

- **Stripe replay idempotency.** Send the same webhook twice; CFO function runs once; one Today card produced.
- **Cross-founder Today card isolation.** Founder A has 3 Today cards; founder B logs in and sees zero of A's cards (RLS-enforced through `tenantClient` aggregator).
- **Trust-tier escalation.** Action class "external_brand_critical" → review-gate fires; founder approves → action runs. Action class "per_command_ack" → confirmation prompt with exact command; bypass attempt rejected.
- **Cost kill trip.** Synthesized cumulative spend exceeds hard cap; all founder's Inngest steps + WS sessions cancel; subsequent Inngest event for that founder is rejected at the gate; UI shows "Runtime paused."
- **Inngest concurrency key.** Two `{founderId}.finance.payment_failed` events for same founder — only one runs at a time (per concurrency key).
- **Cron-not-in-GH-Actions.** Verify no new `.github/workflows/*-cron-*.yml` workflow file added; cron lives in `server/inngest/functions/*` with Inngest scheduler config.
- **Action-completion executor.** CFO drafts response → Today card "Send" button → click drives the actual Stripe email send (or Slack post or whatever the action class allows). Per `2026-03-23-action-completion-workflow-gap`.

### Risks (Increment 3)

- **R3.1 — Inngest free-tier rate limit.** 50K steps/mo. Beta scaling (~30 founders) bursts past free tier. **Mitigation:** alpha is closed preview; track step count via Inngest dashboard; flip to paid tier at 70% of free-tier ceiling.
- **R3.2 — Stripe webhook retries flooding kill-switch.** Stripe retries up to 3 days with exponential backoff. If kill-switch trips during retries, replays come back later. **Mitigation:** dedup table catches replays; kill-switch state checked at the dedup boundary too.
- **R3.3 — Today aggregator SLO.** Three signal sources fetched on every `/dashboard` load. **Mitigation:** server-component fetch with parallel `Promise.all`; per-source timeout 2s (per `2026-04-28-bound-network-calls-with-timeouts`); fallback to cached state on source failure with `reportSilentFallback`.
- **R3.4 — Trust-tier UI sprawl.** 5-tier UX is more state than today. **Mitigation:** ship tier 1 + 2 (auto, auto+digest) with no-UI; tier 3 + 4 reuse existing review-gate; tier 5 reuses per-command-ack pattern; net new UI is the "Draft + 1-click" tier-3 surface only.
- **R3.5 — ADR drift.** Plan mentions Inngest decision in many places; ADR may lag. **Mitigation:** ADR is FR8 acceptance criterion; PR rejected without it.
- **R3.6 — Founder authorization for cost kill-switch resume.** Per-command ack at the lift-pause action — an attacker who reaches the founder's session can lift the pause. **Mitigation:** lift-pause requires re-auth (existing TC-acceptance-style fresh-session pattern from PR #2887 era).

## Sharp Edges

Plan-level sharp edges flagged by AGENTS.md and prior learnings; each maps to a specific increment:

- **`hr-weigh-every-decision-against-target-user-impact`.** Threshold `single-user incident`; `requires_cpo_signoff: true` in frontmatter; `user-impact-reviewer` invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block; preflight Check 6 fires on `apps/web-platform/server/**`, `supabase/migrations/**`, BYOK custody surfaces.
- **`cq-pg-security-definer-search-path-pin-pg-temp`.** Every new SECURITY DEFINER function (`mint_founder_jwt`, `write_byok_audit`, `write_audit_log`, hash-chain trigger) MUST `set search_path = public, pg_temp` AND qualify every relation as `public.<table>`. Migration tests assert via `pg_proc.proconfig`.
- **`2026-04-18-supabase-migration-concurrently-forbidden`.** Migrations 037, 038, 039, 040 use plain `CREATE INDEX IF NOT EXISTS`. NO `CONCURRENTLY` (SQLSTATE 25001).
- **`2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy`.** BYOK fetch is the textbook instance. Widen `(args) => T` → `(args) => Promise<T> | T`; do NOT proxy.
- **`2026-05-05-defense-relaxation-must-name-new-ceiling`.** §1.7 raises max-turn budget; pair with discriminated `idle_window` AND `max_turn_duration` ceilings. Document in ADR.
- **`cq-plan-ac-external-state-must-be-api-verified`.** ACs that claim audit-row written, RLS enforced, pgvector enabled, Doppler configured — query the API/DB directly, NEVER grep INSERT/SELECT.
- **`2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper`.** Increment 2 §2.2 sibling-query audit grep is non-negotiable; the audit table goes in the PR description.
- **`cq-union-widening-grep-three-patterns`.** Inngest event-envelope variants and `WorkflowEnd { reason }` discriminator: switch + `: never` rails at every consumer; greps for `\.kind === "` and `\?\.kind === "` clean.
- **`2026-04-29-jwt-fixture-reminting-decode-verify`.** All test fixtures for `mint_founder_jwt` decode the JWT payload and grep the decoded form for synthesized markers — not the encoded form.
- **`cq-test-fixtures-synthesized-only`.** All migration tests, integration tests, e2e fixtures use `@example.com`/`@test.local` emails, synthesized UUIDs (NOT prod-shape), no live JWT/BYOK/Doppler tokens. Hook-enforced via `secret-scan.yml`.
- **`2026-05-04-snapshot-leak-floor-must-precede-snapshot-infra`.** Verify gitleaks floor (PR #3121) is in `main` BEFORE any new fixture-emitting code lands. If a runtime snapshot/trajectory dump path is added, it goes through the floor first.
- **`hr-never-git-add-a-in-user-repo-agents`.** If Increment 3 background agents auto-commit to user repos, mirror `session-sync.ts:24 ALLOWED_AUTOCOMMIT_PATHS` allowlist (`/^knowledge-base\//`). No `git add -A`.
- **`2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526`.** BYOK lease delivered via stdin/fd or function-arg. NEVER added to `agent-env.ts` allowlist or `process.env`.
- **`cq-silent-fallback-must-mirror-to-sentry`.** Every catch returning 4xx/5xx or fallback in new code uses `reportSilentFallback`. Audit: BYOK fetch failure, JWT mint failure, RLS deny, audit-row insert failure, kill-switch trip, trust-tier denial, Inngest event delivery failure, episodic memory retrieval timeout, Today aggregator source failure.
- **`hr-never-label-any-step-as-manual-without`.** Post-merge operator steps (Stripe test event, Inngest function registration, Doppler secrets) — Playwright MCP first; only OAuth/CAPTCHA are genuinely manual.
- **`hr-menu-option-ack-not-prod-write-auth`.** Any production migration apply (`supabase db push`), Terraform apply, Inngest deployment hook — show exact command, wait for explicit per-command go-ahead, then run.
- **`hr-dev-prd-distinct-supabase-projects`.** Preflight Check 4 fires on the new migrations; verifies `dev` and `prd` Doppler configs resolve to distinct project refs (`^[a-z0-9]{20}\.supabase\.co$`). Pre-existing constraint; double-check at preflight.
- **Schema-version-on-payload (per `2026-04-18`).** Inngest event envelope `schema_version: 1` MUST be asserted at consumer (`functions/cfo-on-payment-failed.ts`), not just written by producer. Self-referential checks are cosmetic.
- **Plan globs verification (per `hr-when-a-plan-specifies-relative-paths-e-g`).** Every glob in this plan (`apps/web-platform/server/**`, `apps/web-platform/supabase/migrations/**`, `app/(dashboard)/**`, `components/dashboard/**`) verified to match ≥1 file at plan-time via `git ls-files | grep -E`.
- **Plan-time CLI verification (per `cq-plan-preflight-cli-form-verification`).** `inngest` CLI invocations cited in this plan (none directly — Inngest is library-only) — N/A. `supabase db push` form verified against installed CLI version.
- **Aggregate-numeric-target rule (per `cq-plan-ac-aggregate-numeric-self-consistency`).** Plan does not prescribe an aggregate numeric target (no "≥N bytes saved" or "≥M queries optimized"). N/A.
- **External-action-claim verification (per `2026-05-04-verify-third-party-action-behavior-claims-against-codebase-precedent`).** Inngest claim "concurrency key per `(founderId, domain, eventKey)` enforces single in-flight" — verified against Inngest docs at deepen-plan time, not just stated.
- **WS error sanitization (per `2026-03-20-websocket-error-sanitization-cwe-209`).** Every new error path goes through `sanitizeErrorForClient` (allowlist with fallback) before WS forward. Typed error classes added in §1.6.
- **PII regex three invariants (per `2026-04-17-pii-regex-scrubber-three-invariants`).** If audit-log content includes user/agent strings, length-cap upstream + match all UUID variants + no module-level `/g` regex with `.test()`.
- **Log-injection unicode (per `2026-04-17-log-injection-unicode-line-separators`).** Audit-log entry sanitizer uses `[\x00-\x1f\x7f  ]`, not just C0.
- **Bail-early forbidden in leak detection (per `2026-04-29-bail-early-defeats-exhaustive-leak-detection`).** Redaction sweeps and audit traversals iterate fully; no `break` on first match.

## Domain Review

**Domains relevant:** Engineering, Product, Marketing, Operations, Legal (carry-forward from brainstorm `## Domain Assessments`). Sales, Finance, Support: not orthogonal to architectural scope; not spawned.

### Engineering (CTO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm).
**Assessment summary:** Substrate exists; pivot is alignment + Inngest layer + RLS hardening. Per-invocation user-scoped JWT is the load-bearing isolation invariant. Per-invocation BYOK lease + audit row. Per-founder pgvector for episodic; shared host for procedural. Counter-take: substrate isn't the bottleneck, leader quality + delegation willingness are. Recommend ADR via `/soleur:architecture create` (FR8, captured in §3.1).

### Product (CPO) — carry-forward + plan-time sign-off required

**Status:** reviewed (carry-forward from brainstorm).
**Assessment summary:** Recommends shipping but reframes as alignment-not-pivot. MVP surface = Daily Priorities + 1 background trigger; trust model = "drafts everywhere, sends nowhere" + 5-tier autonomy. Validation still FLAG; recommends 5 more founder interviews. Push back: don't ship runtime before fixing #1044.
**Plan-time sign-off:** Required per `requires_cpo_signoff: true` in frontmatter (threshold = `single-user incident`). CPO has reviewed brainstorm; brainstorm carry-forward satisfies plan-time review. If CPO has not reviewed plan content as a separate step, invoke before `/work`.

### Marketing (CMO) — carry-forward (with branding override)

**Status:** reviewed (carry-forward from brainstorm).
**Assessment summary:** Position as "the agentic operating system for one-person companies" — NOT vs Cosmos. Headline "Run a company. Not a codebase." Demo: inbound email → cross-domain cascade. $99 flat BYOK. Channels: X, IndieHackers, YC W26, Lovable/Bolt Discords. Defensible wedge: opinionated org simulation, not agent count.
**Branding override (2026-05-05):** Single brand "Soleur"; no "Command Center" sub-brand (user directive supersedes original CMO sub-brand recommendation). Increment 0 renames user-visible "Command Center" strings to "Dashboard" / Soleur. Marketing collateral refresh tracked separately.

### Legal (CLO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm).
**Assessment summary:** Soleur is GDPR Art. 28 data processor the moment it executes against founder credentials. 9 must-have artifacts before first paid user. E&O insurance ($1-3M, ~$3-8K/yr) before paid tier. Liability cap = 12 months fees, founder retains command authority, scope-grants required, consequential-damages waiver, indemnity carve-out for gross negligence only. Forensic audit log: WORM, hash-chained, 7-year retention.
**Plan response:** Plan ships gating switch (FR7) + audit-log scaffold (TR5, Increment 1+3) only. The 9 legal artifacts are tracked separately under CLO domain. Audit-log retention (7-year) is a Postgres logical-replication / R2 cold-storage concern — out of MVP scope; document in ADR.

### Operations (COO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm).
**Assessment summary:** Inngest agent kit recommended; reject Bedrock (AWS lock). Doppler inadequate at 1000 founders for BYOK custody — need per-tenant envelope encryption. Alpha ~$30/mo additional; beta ~$300-400/mo. Biggest risk: BYOK custody breach (one Anthropic key leak = founder bankrupt). Add: per-tenant cost attribution, kill-switch on cost spike, PagerDuty, DPA chain (Inngest/AWS/CF).
**Plan response:** Per-tenant cost attribution + kill-switch lands in §3.5. PagerDuty integration noted. DPA chain is CLO-tracked. Doppler stays for Soleur infra; per-tenant BYOK custody via existing HKDF-per-user (TR8 — primitive already correct per repo research).

### Product/UX Gate

**Tier:** advisory (FR4 modifies the existing `/dashboard` page rather than creating a new route).
**Decision:** auto-accepted (carry-forward from brainstorm Daily Priorities discussion + existing Pencil wireframes at `knowledge-base/product/design/inbox/command-center.pen` cover the Today inbox surface).
**Agents invoked:** none at plan-time. Brainstorm CPO assessment satisfies the advisory tier.
**Skipped specialists:** ux-design-lead (Pencil wireframes already exist for the Today inbox layout — `knowledge-base/product/design/inbox/command-center.pen` — coverage is sufficient for advisory tier; founder confirmed direction). copywriter (no new persuasive/emotional copy in this PR — existing Dashboard layout retained; CMO collateral refresh tracked separately per spec Non-Goals).
**Pencil available:** N/A (not invoked).
**Brainstorm-recommended specialists:** none named explicitly in brainstorm domain assessments (CMO recommended brand collateral refresh as separate workstream, not as plan-time specialist invocation).

### Findings

The brainstorm produced a comprehensive 5-domain assessment that this plan inherits. The branding override (single brand "Soleur") preserves CMO's underlying positioning ("the agentic operating system for one-person companies") and only changes the surface naming. No domain assessment needs re-running.

## Plan Open Questions

These resolve at deepen-plan or `/work` time; they do not block plan write.

1. **Per-founder Supabase project vs. shared-project + RLS.** Spec wording implies per-founder Supabase project (TR3). Default plan interpretation: shared prd Supabase + per-founder RLS isolation on `episodic_memory` table. Confirm at deepen-plan; per-founder project is a 10x cost/ops/Doppler/Terraform fan-out and conflicts with `hr-dev-prd-distinct-supabase-projects` posture.
2. **#1044 reframe — verify-and-harden vs ship-from-scratch.** Issue is closed; SDK-resume + replay paths exist. Increment 2 verifies under user-scoped JWT and adds episodic memory. Confirm this scope at `/work`.
3. **Trust-tier policy storage — Postgres only, or YAML-in-workspace + Postgres.** Brainstorm Open Question. Plan defaults to Postgres + UI (Postgres-only). YAML adds workspace-sync surface area without offsetting benefit at single-founder scale.
4. **Daily Priorities source set for MVP — 3 chosen are Stripe/GH/KB-drift.** CPO's brainstorm mock listed 5 (Stripe failed-payment, milestone-overdue, lead inbox, privacy-policy-stale, competitive-note). Plan picks 3 cheapest-to-wire. Confirm at `/work`.
5. **Validation interview cadence.** CPO recommended 5 more interviews mid-MVP (after Increment 1, before Increment 3). Out-of-band; not on critical path of this plan but flagged.
6. **Cosmos defensibility runway.** Brainstorm Open Question. Out of scope here; tracked separately by CMO/CPO.

## Files to Create (consolidated)

(See per-Increment Files-to-Create sections above; consolidated here as a sanity reference.)

- `apps/web-platform/lib/supabase/tenant.ts` (`mintFounderJwt`, `createTenantClient`, `getFreshTenantClient`)
- `apps/web-platform/server/byok-lease.ts`
- `apps/web-platform/.service-role-allowlist` (no ESLint rule)
- `apps/web-platform/supabase/migrations/037_audit_byok_use.sql`
- `apps/web-platform/supabase/migrations/038_episodic_memory.sql`
- `apps/web-platform/supabase/migrations/039_audit_log.sql` (no hash-chain — deferred D1)
- `apps/web-platform/supabase/migrations/040_runtime_cost_state.sql` (`users` ALTER + `record_byok_use_and_check_cap` RPC; no `tenant_cost_window` table)
- `apps/web-platform/server/episodic-memory.ts`
- `apps/web-platform/server/inngest/client.ts` (envelope types consolidated here)
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts`
- `apps/web-platform/app/api/inngest/route.ts`
- `apps/web-platform/components/dashboard/today-card.tsx` (single component)
- `apps/web-platform/server/{trust-tier,cost-kill-switch,audit-log}.ts`
- Test files mirroring above (`apps/web-platform/test/{server,supabase-migrations,e2e}/...`) including the **concurrent-write race test** for the kill-switch and the **auto-remint test** for `getFreshTenantClient`
- `knowledge-base/engineering/adrs/<NNN>-inngest-as-durable-trigger-layer.md`

Plan-time glob verification (per `hr-when-a-plan-specifies-relative-paths-e-g`):

```bash
git ls-files apps/web-platform/server | head -n 5            # MUST return matches
git ls-files apps/web-platform/supabase/migrations | wc -l   # MUST be ≥ 36 (existing)
git ls-files apps/web-platform/app/\(dashboard\) | head -n 5 # MUST return matches
git ls-files apps/web-platform/components | head -n 5        # MUST return matches
```

## Files to Edit (consolidated)

(See per-Increment Files-to-Edit sections above; consolidated here.)

- `apps/web-platform/server/agent-runner.ts` (Increment 1, 2, 3)
- `apps/web-platform/server/session-sync.ts` (Increment 1 disclosure, Increment 2 migration)
- `apps/web-platform/server/byok.ts` (Increment 1)
- `apps/web-platform/server/health.ts` (Increment 1 disclosure)
- `apps/web-platform/server/agent-env.ts` (Increment 1 review only — no allowlist additions)
- `apps/web-platform/server/permission-callback.ts` (Increment 3)
- `apps/web-platform/server/tool-tiers.ts` (Increment 3)
- `apps/web-platform/server/cc-dispatcher.ts:833` (Increment 0 string)
- `apps/web-platform/lib/supabase/service.ts` (Increment 0 + 1)
- `apps/web-platform/lib/auth/error-messages.ts` (Increment 1)
- `apps/web-platform/lib/types.ts` (Increment 3 — 3-tier `TrustTier` only)
- `.github/workflows/lint.yml` (Increment 1 — CI grep gate, no ESLint config edits)
- `apps/web-platform/next.config.ts` (Increment 3 — only if a server package leaks)
- `apps/web-platform/sentry.server.config.ts` (Increment 0)
- `apps/web-platform/server/logger.ts` (Increment 0)
- `apps/web-platform/app/manifest.ts` (Increment 0)
- `apps/web-platform/app/layout.tsx` (Increment 0)
- `apps/web-platform/app/(dashboard)/layout.tsx` (Increment 0)
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (Increment 0 strings, Increment 3 Today section)
- `apps/web-platform/app/api/webhooks/stripe/route.ts` (Increment 3)
- `apps/web-platform/components/chat/chat-surface.tsx` (Increment 0)
- `apps/web-platform/components/chat/conversations-rail.tsx` (Increment 0)
- `apps/web-platform/components/connect-repo/ready-state.tsx` (Increment 0)
- `apps/web-platform/package.json` + `bun.lock` + `package-lock.json` (Increment 3)
- `plugins/soleur/docs/_data/site.json` (Increment 0)
- `apps/web-platform/server/agent-runner.ts` line ranges per §1.7 timeout pair (Increment 1 §1.7 sub-task)
- Sibling-query call-sites discovered in §2.2 audit (Increment 2; enumerated at work-phase from grep)

## PR Strategy

Four sequenced PRs (per DHH PR-strategy delta — split PR-C into runtime layer + surface layer for reviewability):

1. **PR-A (Increment 0).** Pre-flight: redaction allowlist, brand rename, `lib/supabase/service.ts` memoize. Small (~12 file edits). PR body: `Ref #3244` (NOT `Closes`). Closes #2962 (partial).
2. **PR-B (Increment 1).** Tenant isolation hardening: `mintFounderJwt` + `getFreshTenantClient` + `runWithByokLease` + `audit_byok_use` + CI grep gate + 11 `agent-runner.ts` call-site migrations + §1.7 timeout pair. PR body: `Ref #3244, Closes #3219, Closes #2962` (full). Required reviewers: `security-sentinel`, `user-impact-reviewer`, `architecture-strategist`.
3. **PR-C (Increment 2 + Inngest substrate + CFO function + Stripe webhook).** The runtime layer: replay verification, episodic memory pgvector, ~30-site sibling-query migration, Inngest install, `cfo-on-payment-failed.ts`, Stripe webhook extension. PR body: `Ref #3244`. Required reviewers: `security-sentinel`, `user-impact-reviewer`, `architecture-strategist`.
4. **PR-D (surface layer).** Today section in `dashboard/page.tsx`, `today-card.tsx`, 3-tier trust-tier, atomic cost kill-switch (`record_byok_use_and_check_cap` RPC), `audit_log` table, FR7 launch flag, ADR. PR body: `Closes #3244, Closes #2955`. Required reviewers: `user-impact-reviewer` (cost kill-switch is brand-survival; `single-user incident` threshold).

Rationale: PR-A independent + reduces PR-B blast-radius. PR-B gate-zero (security must land alone). PR-C bundles the durability layer (replay + Inngest + Stripe) because they share testing infrastructure and review concerns. PR-D bundles the user-facing surface + policy (Today + trust-tier + cost kill + ADR) because they're tightly coupled and individually too small to justify their own review cycles.

Per `wg-use-closes-n-in-pr-body-not-title-to`: only PR-D body says `Closes #3244`; PR-A through PR-C use `Ref #3244` (GitHub auto-close ignores qualifiers, so partial-close phrasing would prematurely close the issue).

## Deferred Capabilities

Per `wg-when-deferring-a-capability-create-a` — each item below requires a tracking issue at `/work` time, milestoned to "Post-MVP / Later" or to the named beta milestone. Plan does NOT bundle issue creation; `/work` Phase 1 files them.

| # | Deferred capability | Original spec ref | Reason | Re-evaluate |
|---|---|---|---|---|
| D1 | `audit_log` hash-chain (cryptographic prev_hash/this_hash) | TR5 | Closed-preview alpha lacks DB-compromise threat model; WORM + RLS-zero-policies + service-role-only-insert is the load-bearing isolation. | Beta entry / first paid user / SOC2 program kickoff. |
| D2 | 5-tier trust-tier (`auto_with_digest`, `per_command_ack` tiers) | FR6 | No action sites in MVP scope; collapsed to 3 tiers (`auto`, `draft_one_click`, `approve_every_time`). | Second background trigger lands. |
| D3 | Trust-tier per-founder override (Postgres `trust_tier_policy` table + UI) | FR6 | YAGNI until a founder requests one; `ACTION_CLASS_DEFAULTS` map covers MVP. | First founder-driven override request. |
| D4 | Today aggregator GitHub-source | FR4 | Requires per-founder GH App installation token plumbing not built; not in single-source MVP scope. | Beta. |
| D5 | Today aggregator KB-drift-source | FR4 | Duplicates existing foundation-card data on `dashboard/page.tsx`; not in single-source MVP scope. | Beta. |
| D6 | PagerDuty + cost-spike anomaly detector | TR6, TR7 | Closed alpha: founder watches Sentry; `reportSilentFallback` mirroring covers alert path. | Beta (paying customers, on-call rotation needed). |
| D7 | pgvector ivfflat / hnsw index | TR3 | ivfflat needs ≥1000 rows per founder for good recall; sequential scan acceptable for alpha. | First founder hits ~1000 episodic-memory rows. |
| D8 | `audit_share_use` table for KB share-link impersonation | §1.5 lint allowlist for `kb-share-tools.ts` | Allowlist comment lands in Increment 1; audit row deferred to keep Increment 1 tight. | Increment 3 alongside `audit_log`. |
| D9 | 5 founder validation interviews (mid-MVP) | CPO brainstorm recommendation | Out-of-band research, not on critical path. | Between PR-B and PR-C merge. |
| D10 | 9 legal artifacts (E&O, DPA, sub-processor page, breach runbook, AUP, ToS command-authority clause, scope-grant UX, audit-log retention pipeline) | FR7 | Tracked under CLO domain separately; this plan ships only the gating switch. | Before paid-tier launch. |
| D11 | Sub-brand collateral / marketing relaunch | spec Non-Goals | User directive 2026-05-05: single brand "Soleur"; CMO refresh tracked separately. | After alpha cohort feedback. |
