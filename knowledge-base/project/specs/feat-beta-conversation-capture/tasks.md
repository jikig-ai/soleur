---
title: Tasks — Beta-Tester Conversation Capture
date: 2026-07-07
lane: cross-domain
issue: 6165
pr: 6160
plan: knowledge-base/project/plans/2026-07-07-feat-beta-conversation-capture-plan.md
adr: knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
---

# Tasks: Beta-Tester Conversation Capture (#6165)

Derived from the finalized (post-6-agent-review) plan. Single PR. Brand-survival threshold: single-user incident. Run RED tests before GREEN (`cq-write-failing-tests-before`).

## Phase 0 — Preconditions
- [ ] 0.1 Confirm mig head 125 → new `126_beta_crm.sql`.
- [ ] 0.2 Owner-only key = `user_id = auth.uid()` (no workspace_id for MVP).
- [ ] 0.3 Confirm imports: `getFreshTenantClient` `@/lib/supabase/tenant`, `reportSilentFallback` `@/server/observability`, `tool` `@anthropic-ai/claude-agent-sdk` (per `inbox-tools.ts`).
- [ ] 0.4 Tool-wiring site = `server/agent-runner.ts:1749-1808` (`buildInboxTools` :1773; `buildRoutineTools` singular).
- [ ] 0.5 `dsar-allowlist-completeness.test.ts` will force the 3 tables into the allowlist.
- [ ] 0.6 Read `102:452-468` pg_cron idiom + confirm no `CREATE INDEX CONCURRENTLY`.

## Phase 1 — Migration `126_beta_crm.sql` (+ `.down.sql`)
- [ ] 1.1 `beta_contacts` mutable head: cols per plan; `amount_basis NOT NULL DEFAULT 'unknown'`; **NO** FX columns; `UNIQUE (id, user_id)`; `CHECK (amount IS NULL OR currency IS NOT NULL)`; per-column `-- LAWFUL_BASIS:` annotations; `stage CHECK` from `<STAGE_ENUM>`.
- [ ] 1.2 `interview_notes` append-only: composite FK `(contact_id,user_id)→beta_contacts(id,user_id) ON DELETE CASCADE`; `lens ... cardinality(lens) >= 1` (NOT array_length); `body`, `occurred_at`, `created_at`.
- [ ] 1.3 `beta_contact_stage_transitions` append-only: composite FK; `to_stage CHECK IN (<STAGE_ENUM>)`; `from_stage`, `entered_at`.
- [ ] 1.4 RLS: enable + `REVOKE ins/upd/del FROM PUBLIC,anon,authenticated,service_role`; one `SELECT USING (user_id=auth.uid())` PERMISSIVE policy/table; RESTRICTIVE `<table>_jti_not_denied` (068 shape) on all 3; no owner-write policy.
- [ ] 1.5 RPCs (SECURITY DEFINER, search_path pinned, `auth.uid() IS NULL→42501`, `SELECT…FOR UPDATE`+ownership re-check, same-error-no-oracle, GRANT authenticated): `crm_contact_upsert` (all writable cols; no blind ON CONFLICT; COALESCE partial; initial+change transition same-txn; child user_id from parent), `crm_note_append(...,p_occurred_at)`, `crm_contact_set_stage` (validate `p_to_stage` enum); + `crm_erase_contact` (service_role-only).
- [ ] 1.6 Indexes (plain, no CONCURRENTLY): per plan §1.6.
- [ ] 1.7 `updated_at` BEFORE-UPDATE trigger on `beta_contacts` (search_path pinned).
- [ ] 1.8 pg_cron retention: `COALESCE(last_contact, created_at::date) < now() - interval '24 months'`; `WHEN undefined_table` guard.
- [ ] 1.9 `.down.sql`: DROP tables CASCADE, functions, unschedule cron.
- [ ] 1.T `test/supabase-migrations/126-beta-crm.test.ts`: FK/CASCADE shape; RLS `polcmd` (`='r'`, none in `'a','w','d','*'`); jti policy present; CHECK cases incl. live `lens='{}'` reject + `amount⇒currency`; composite-FK mis-stamp reject; append-only body guard (no UPDATE/DELETE on history tables).

## Phase 2 — `crm` module + agent tools
- [ ] 2.1 `server/crm/stage-probability.ts`: `STAGE_PROBABILITY` + `SCHEMA_VERSION` (enum source-of-truth).
- [ ] 2.2 `server/crm/crm-tools.ts` (crm-data inlined): reads `crm_contact_list`/`crm_contact_get` (all cols)/`crm_note_list(p_contact_id,p_lens?)`; writes `crm_contact_upsert`/`crm_note_append`/`crm_contact_set_stage` via `tenant.rpc` (`email-triage-tools.ts:427` shape); `userId` closure-captured; untrusted envelope on `body`; PII-safe error (`{op,userId,code}` only, no raw PG error).
- [ ] 2.3 Register `buildCrmTools({userId})` in `agent-runner.ts:1749-1808`.
- [ ] 2.T `test/crm-tools.test.ts`: userId-in-closure; write→RPC; untrusted envelope; error payload contains no row values; stage-enum drift guard (`Object.keys(STAGE_PROBABILITY)`==CHECK set).

## Phase 3 — DSAR + legal (single cross-document commit)
- [ ] 3.1 `dsar-export-allowlist.ts`: add 3 tables (`beta_contacts`/`interview_notes`=15+20, `beta_contact_stage_transitions`=15).
- [ ] 3.2 `dsar-export.ts`: wire export chain (owner-scoped, per-table `.eq("user_id",…)`).
- [ ] 3.3 4 legal docs (same PR — gate fires on allowlist): privacy-policy §4.7, gdpr-policy §6.1.b, data-protection-disclosure §2.3/§5.3, compliance-posture.
- [ ] 3.4 `article-30-register.md`: PA-30 (LI+LIA; 24-mo; Anthropic Chapter-V recipient; Art. 14 third-party + `crm_erase_contact` erasure path; no-Art.9).
- [ ] 3.5 LIA `knowledge-base/legal/<beta-crm-lia>.md` (Art. 6(1)(f) balancing + Art. 14 notice + Anthropic transfer + no-Art.9).
- [ ] 3.T `test/beta-crm-dsar.integration.test.ts` (DEV-only, synthesized): owner export returns 3 tables; real account-delete CASCADE empties all 3; cross-tenant deny w/ positive owner-read control; write→read round-trip incl. `crm_note_list`.

## Phase 4 — C4
- [ ] 4.1 `model.c4`: `crmStore` in infra; `betaContact` #external; edges `engine->crmStore` + `betaContact->founder` (NO `founder->crmStore`).
- [ ] 4.2 `views.c4`: add `crmStore`+`betaContact` to `containers`; add `betaContact` to `context`.
- [ ] 4.3 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Insight rollup boundary
- [ ] 5.1 Document (ADR §9 sentence / short note) where pseudonymised aggregate rollups go (`knowledge-base/sales/` + `product/`); no raw PII. Generation skill deferred.

## Phase 6 — Exit
- [ ] 6.1 `/soleur:gdpr-gate` at work Phase 2 exit (no un-addressed Critical).
- [ ] 6.2 typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; `./node_modules/.bin/vitest run` new tests green.
- [ ] 6.3 Legal cross-document gate + `dsar-allowlist-completeness` green.

## Deferred (file follow-up issues)
capture skill; BYO-CRM MCP; tester-visible records; UI surface; workspace-shared; USD FX normalization; field-level mutable-head audit; jti_not_denied on migs 102/122; #6166 standalone spin-out.
