---
title: Beta-Tester Conversation Capture (Soleur module)
date: 2026-07-07
type: feat
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 6165
pr: 6160
brainstorm: knowledge-base/project/brainstorms/2026-07-07-beta-conversation-capture-brainstorm.md
spec: knowledge-base/project/specs/feat-beta-conversation-capture/spec.md
validation: knowledge-base/product/validation/2026-07-07-agent-operated-crm-validation.md
adr: knowledge-base/engineering/architecture/decisions/ADR-098-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
---

# Plan: Beta-Tester Conversation Capture (Soleur module) — #6165

✨ A private, per-tenant, agent-native capture store for beta-tester / prospect conversations, serving one dual-lens (sales + product) record from Supabase, with the compliance floor (Article 30 + retention + DSAR) shipped as part of the feature — and organized behind a `crm` module seam so it can later be extracted as its own agent-operated CRM product (#6166).

## Overview

The operator is onboarding Soleur's first beta testers this week. Conversations carry both **sales** signal (interest, objections, deal potential) and **product** signal (pain, feature requests) and today have no private structured home. This feature builds:

1. Three per-tenant Supabase tables — `beta_contacts` (mutable head), `interview_notes` (append-only dual-lens conversation notes), `beta_contact_stage_transitions` (append-only velocity source) — owner-private (owner-only RLS), inheriting the existing DSAR + retention machinery. **No third-party PII in git.**
2. An **agent read/write path**: an in-process MCP tool module (`server/crm/crm-tools.ts`) exposing `crm_contact_list/get/upsert`, `crm_note_append`, `crm_contact_set_stage`, with reads on the RLS-scoped tenant client and writes through `auth.uid()`-pinned SECURITY DEFINER RPCs. This is the make-or-break agent-native capability — no such DB-write tool exists today.
3. A **Finance contract**: a canonical versioned stage→probability map + stage-transition timestamps feeding `pipeline-analyst` → `revenue-analyst`/`cfo`.
4. The **compliance floor**: Article 30 PA-30 (Art. 6(1)(f) legitimate interest + LIA), 24-month retention (in-migration `pg_cron`), DSAR allowlist registration + export chain + 4 legal-doc updates, Art. 17 erasure via `ON DELETE CASCADE`.
5. **De-identified insight rollups** to `knowledge-base/sales/` + `product/` (both already sanctioned KB dirs).

The storage-boundary + data-model decision is recorded in **ADR-098** (delivered with this plan). Design is deliberately kept behind a clean `crm` module seam (§Extraction, ADR-098 §8) for the possible #6166 spin-out, without over-building a plugin abstraction now.

**Complexity:** medium (days), single PR. **Detail level:** A LOT (single-user-incident PII surface).

### Resolved Open Questions (operator delegated "resolve during planning")
1. **Consent mechanism** → Art. 6(1)(f) legitimate interest + a dedicated **LIA** + an **Art. 14** notice line to the beta tester (they are an involuntary third-party subject; gdpr-gate authoritative). Matches PA-27/PA-28.
2. **Record grain** → **per-contact**, `company` as a denormalized text field. Nested companies deferred (CRO's smallest schema).
3. **Beta-stage amount** → `amount` **nullable** + `amount_basis` discriminator `{hypothetical_acv, committed, unknown}` (default `'unknown'`) so `pipeline-analyst` separates directional beta ACV from real committed pipeline.
4. **Currency basis** → store **raw `amount` + `currency` (ISO 4217) now**; **USD normalization (`amount_normalized_usd`/`fx_rate`/`fx_rate_date`) DEFERRED** — there is no FX source in the write path and no reporting consumer at 0 deals (CFO: "capture the fields now, forecasting is theater at 0 deals"; capturing raw amount+currency IS the field). Normalization is a one-line follow-up migration when a reporting consumer exists.
5. **Owner-private vs workspace-shared** → **owner-private** (owner-only RLS, `user_id = auth.uid()`). Workspace-shared (the 111 shape) deferred.
6. **Retention horizon** → **24 months from `COALESCE(last_contact, created_at)`** (aligns with the PA-PII 24-month envelope; the COALESCE closes the null-last_contact leak).

## Research Reconciliation — Spec vs. Codebase

All cited artifacts verified present on the branch (Phase 0.6 premise validation held — no stale premise; #6165/#6160/#6166/#6163 all OPEN). Three reconciliations refine spec claims:

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "reuse migration 075 template" (TR1) | `075_conversation_visibility.sql` is the owner-only RLS *policy* template; the fuller table+RPC+retention template is `102_email_triage_items.sql` (mig 122 is latest → new = **123**). | Copy RLS shape from 075; copy table DDL + SECURITY DEFINER RPC + `pg_cron` retention shape from 102. |
| "Inherit existing DSAR/WORM/erasure machinery" (TR2) | `email_triage_items` uses `ON DELETE RESTRICT` + `anonymise_*` RPC **because it retains statutory rows**. The beta-CRM has **no statutory-retention class**. | Use plain `ON DELETE CASCADE` (simpler; ADR-098 §4). **No** `anonymise_beta_*` RPC, **no** `account-delete.ts` step. Still register in `DSAR_TABLE_ALLOWLIST` (owner's Art. 15/20 export). |
| "agent read/write path (MCP tool or app/api route)" (FR5) | **Make-or-break RESOLVED with a working precedent:** `server/email-triage-tools.ts` is an agent MCP tool that calls `tenant.rpc("suppress_recipient", …)` on `getFreshTenantClient(userId)` (line 427) — i.e. an agent write through a SECURITY DEFINER RPC on the **user-JWT tenant client**, so `auth.uid()` inside the RPC resolves to the operator (not NULL/service_role). Read precedent = `inbox-tools.ts`. | Choose **MCP tool → auth.uid()-pinned SECURITY DEFINER RPC** on the tenant client (per-user, in-session), NOT the service-role/env-owner Inngest shape. `userId` closure-captured; owner-only RLS; **no owner-INSERT policy** (learning 2026-05-21: it's an RPC bypass). Copy the `email-triage-tools.ts` write shape verbatim. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a create/append call that silently drops a captured conversation (write path filled a row a read path doesn't return) — the operator loses a beta conversation they believe was saved.
- **If this leaks, the user's [data] is exposed via:** an RLS gap or mis-scoped query returning another workspace's `beta_contacts`/`interview_notes` — every prospect in a workspace (name, employer, role, email, verbatim conversation content) exposed; third-party PII shared under implied confidence → trust rupture + GDPR breach (Art. 33, 72h clock). Git storage would make the exposure permanent and secret-scan-invisible (why the DB boundary is load-bearing).
- **Brand-survival threshold:** `single-user incident`.

`requires_cpo_signoff: true` — CPO reviewed the approach in the brainstorm §Domain Assessments (Product). `user-impact-reviewer` runs at review time against this section.

## Implementation Phases

Phase order is dependency-directed (contract-declaring edits precede consumers; a single atomic-merge PR still reads sequentially at `/work`).

### Phase 0 — Preconditions (grep-verify before coding)
- `0.1` Confirm mig ledger head is 122 → new migration is `123_beta_crm.sql`. `ls apps/web-platform/supabase/migrations/ | tail`.
- `0.2` Confirm the `is_workspace_member` helper signature (not needed for owner-only MVP, but confirm no workspace_id column is required by any consumer): owner-only keys on `user_id = auth.uid()`.
- `0.3` Confirm `getFreshTenantClient` import path (`@/lib/supabase/tenant`) + `reportSilentFallback` (`@/server/observability`) + `tool` from `@anthropic-ai/claude-agent-sdk` (all per `inbox-tools.ts`).
- `0.4` Tool-registration site confirmed: `apps/web-platform/server/agent-runner.ts` `:1749–1808` (`buildInboxTools` at `:1773`; note `buildRoutineTools` is **singular**). `buildCrmTools({ userId })` slots in there.
- `0.5` Confirm `DSAR_TABLE_ALLOWLIST` completeness lint (`test/dsar-allowlist-completeness.test.ts`) enumerates public tables with a `user_id`/user-FK column — the new tables MUST be added or CI fails.
- `0.6` Read the last 2 migrations for the `pg_cron` retention idiom (`102:452-468` shape) and the transaction constraint (no `CREATE INDEX CONCURRENTLY` — learning 2026-04-18).

### Phase 1 — Migration `123_beta_crm.sql` (+ `.down.sql`)  [RED→GREEN with offline migration test]
- `1.1` `beta_contacts` (mutable head): `id uuid PK`, `user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`, `name text`, `company text`, `role text`, `source text`, `stage text NOT NULL DEFAULT 'new' CHECK (stage IN (<STAGE_ENUM>))`, `next_action text`, `next_action_date date`, `last_contact date`, `amount numeric`, `currency text CHECK (currency ~ '^[A-Z]{3}$')`, `amount_basis text NOT NULL DEFAULT 'unknown' CHECK (amount_basis IN ('hypothetical_acv','committed','unknown'))`, `expected_close_date date`, `created_at timestamptz NOT NULL DEFAULT now()`, `updated_at timestamptz NOT NULL DEFAULT now()`, **`UNIQUE (id, user_id)`** (target for the children's composite FK).
  - **FX trio cut** (simplicity + spec-flow convergence): `amount_normalized_usd`/`fx_rate`/`fx_rate_date` **deferred** (no FX source in write path, no reporting consumer at 0 deals). Raw `amount`+`currency` only.
  - **Kieran-C / data-integrity P2-1:** add table CHECK `CHECK (amount IS NULL OR currency IS NOT NULL)` (no amount without a unit).
  - `<STAGE_ENUM>` is generated FROM `stage-probability.ts` keys (drift-guarded — Phase 2.1 / AC).
  - **GDPR-Art-6:** annotate each PII column `-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA <file>)` — `name, company, role, source`, and `interview_notes.body` (1.2).
- `1.2` `interview_notes` (append-only): `id uuid PK`, `contact_id uuid NOT NULL`, `user_id uuid NOT NULL` (denormalized), **composite FK `(contact_id, user_id) REFERENCES public.beta_contacts(id, user_id) ON DELETE CASCADE`** (security P2-2 / data-integrity P1-2 — a child can only ever carry its parent's owner; mis-stamp is a DB error, closing the cross-tenant injection vector), `body text NOT NULL`, `lens text[] NOT NULL CHECK (lens <@ ARRAY['sales','product'] AND cardinality(lens) >= 1)` **(`cardinality`, NOT `array_length` — Kieran-A/data-integrity P1-3: `array_length('{}',1)` is NULL → passes; `cardinality('{}')=0` → rejects empty)**, `occurred_at date`, `created_at timestamptz NOT NULL DEFAULT now()`.
- `1.3` `beta_contact_stage_transitions` (append-only): `id uuid PK`, `contact_id uuid NOT NULL`, `user_id uuid NOT NULL`, **composite FK `(contact_id, user_id) REFERENCES public.beta_contacts(id, user_id) ON DELETE CASCADE`**, `from_stage text`, `to_stage text NOT NULL CHECK (to_stage IN (<STAGE_ENUM>))` (security P2-3), `entered_at timestamptz NOT NULL DEFAULT now()`.
- `1.4` RLS: `ENABLE ROW LEVEL SECURITY` on all three. `REVOKE INSERT/UPDATE/DELETE … FROM PUBLIC, anon, authenticated, **service_role**` (security P1-2 — no service-role write pipeline exists; RPCs run as function owner, so REVOKE-ing service_role closes the bypass). **Only** `FOR SELECT … USING (user_id = auth.uid())` PERMISSIVE policy per table; **no** owner INSERT/UPDATE/DELETE policy (learning 2026-05-21). Plus a **RESTRICTIVE `<table>_jti_not_denied` policy** on all three (068/076/077 shape — data-integrity P1-4: a revoked/stolen founder JWT used directly against PostgREST is rejected at the policy boundary; 102/122 lack this — inherit 068's shape, not their gap; file the 102/122 omission as a follow-up). Writes go through the RPCs below.
- `1.5` SECURITY DEFINER RPCs (all `SET search_path = public, pg_temp`; all open with **`IF auth.uid() IS NULL THEN RAISE … ERRCODE='42501'`** (data-integrity Q1 fail-closed) then **`SELECT … FOR UPDATE` the target row + reject with the single generic `42501` if `NOT FOUND OR user_id <> auth.uid()`** (security P0-1 / data-integrity P1-1 — SECURITY DEFINER bypasses RLS, so the UPDATE branch MUST re-check ownership; no existence oracle; `set_email_triage_status:257,268-277` shape). GRANT EXECUTE TO authenticated, REVOKE from PUBLIC/anon/service_role:
  - `crm_contact_upsert(<all writable cols as params>)` → INSERT (stamp `user_id = auth.uid()`) or ownership-checked UPDATE. **No blind `ON CONFLICT DO UPDATE`** (security P0-1). Partial update: unsupplied columns COALESCE-to-existing (never null a field or emit a spurious transition — spec-flow P1-3). On INSERT at a non-default stage, and on any stage change, append exactly one `beta_contact_stage_transitions` row (`from_stage` = prior or NULL on insert, `to_stage`, now()) **in the same txn**; sets `updated_at`. Child `user_id` set from the parent/`auth.uid()`, never a param.
  - `crm_note_append(p_contact_id, p_body, p_lens, p_occurred_at default now()::date)` → ownership-checked INSERT into `interview_notes`; `user_id` from parent; updates `beta_contacts.last_contact = COALESCE(p_occurred_at, now()::date)`. (`p_occurred_at` closes the spec-flow P1-2 dead-column; guard against a backdated note corrupting the retention clock.)
  - `crm_contact_set_stage(p_contact_id, p_to_stage)` → validates `p_to_stage IN (<STAGE_ENUM>)` (security P2-3), ownership + `FOR UPDATE`, appends a transition, UPDATEs `beta_contacts.stage`. (Kept as a clear agent affordance; shares the transition logic with upsert.)
  - `crm_erase_contact(p_contact_id)` — **`service_role`-only** SECURITY DEFINER RPC (`GRANT EXECUTE TO service_role`, REVOKE from PUBLIC/anon/authenticated) that DELETEs a contact (CASCADEs to children) — the auditable, implementable third-party (beta-tester) Art. 17 erasure path (security P1-2 / spec-flow P1-5), replacing "manual raw service-role SQL." Mirrors `purge_email_triage_items` grant shape.
- `1.6` Indexes (plain `CREATE INDEX IF NOT EXISTS`, never CONCURRENTLY): `beta_contacts (user_id, last_contact DESC)`; `beta_contacts (user_id, stage)`; `interview_notes (contact_id, occurred_at DESC)`; `beta_contact_stage_transitions (contact_id, entered_at)`. Note `UNIQUE (id, user_id)` on `beta_contacts` (1.1) also creates the index the composite FKs require.
- `1.7` `updated_at` trigger on `beta_contacts` (BEFORE UPDATE → `NEW.updated_at = now()`), search_path pinned.
- `1.8` `pg_cron` 24-month retention sweep of `beta_contacts` where **`COALESCE(last_contact, created_at::date) < now() - interval '24 months'`** (security P2-1 / data-integrity P2-2 — never-contacted rows must still expire; CASCADE removes children), guarded `WHEN undefined_table` for local/CI (`102:452-468` shape). Down-file unschedules.
- `1.9` `.down.sql`: DROP tables (CASCADE), functions, unschedule cron.

### Phase 2 — `crm` module + agent tools  [/work Phase 2 exit re-runs `/soleur:gdpr-gate`]
- `2.1` `server/crm/stage-probability.ts` — the canonical **single source of the stage enum + probability** (`export const STAGE_PROBABILITY: Record<Stage, number>`, `SCHEMA_VERSION`), tenant-generic. This IS the locked "canonical stage→probability map." Its real merge-time consumer is the **drift-guard test** (AC): the migration `<STAGE_ENUM>` CHECK set MUST equal `Object.keys(STAGE_PROBABILITY)` (arch P2-3 / spec-flow P1-4 / data-integrity). `pipeline-analyst` (a markdown agent) **references** it (not a TS import — arch P2-2 correction); the weighted-forecasting consumer is deferred (CFO: no forecasting at 0 deals).
- `2.2` `server/crm/crm-tools.ts` — `buildCrmTools({ userId })` (single file — `crm-data.ts` **inlined**, matching the `inbox-tools.ts`/`email-triage-tools.ts` single-file precedent; the extraction seam is the `server/crm/` **directory**, ADR §8). Tools:
  - **Reads** (RLS-scoped tenant client, `inbox-tools.ts` shape): `crm_contact_list`, `crm_contact_get` (return **every** `beta_contacts` column — spec-flow P1-1 projection), **`crm_note_list(p_contact_id, p_lens?)`** (spec-flow P0-1 dead-read-path fix — notes must be readable back, with an optional `lens` filter for the cro/cpo split; without it every captured note is write-only). Conversation `body` wrapped in the UNTRUSTED-content envelope.
  - **Writes** (`tenant.rpc(...)`, copy the **`email-triage-tools.ts:427` shape** verbatim): `crm_contact_upsert`, `crm_note_append`, `crm_contact_set_stage`. `userId` closure-captured (never a tool input / zod field).
  - **PII-safe errors** (security P1-1): the catch path maps to a stable `code` (`inbox-tools.ts` `code:"list_failed"` shape) and reports **only `{ op, userId, code }`** — it must **NOT** forward the raw PG error (the `Failing row contains (…)` DETAIL carries `name`/`company`/`body`). `reportSilentFallback` before the generic `isError` return (cq-silent-fallback-must-mirror-to-sentry).
- `2.3` Register `buildCrmTools({ userId })` in **`apps/web-platform/server/agent-runner.ts`** at the `buildInboxTools`/`buildRoutineTools` wiring block (`:1749–1808`, `buildInboxTools` at `:1773` — arch confirmed; note `buildRoutineTools` is singular).

### Phase 3 — DSAR + legal (single-commit cross-document set)
- `3.1` `server/dsar-export-allowlist.ts` — add `beta_contacts: { ownerField: "user_id", article: "15+20" }`, `interview_notes: { ownerField: "user_id", article: "15+20" }`, `beta_contact_stage_transitions: { ownerField: "user_id", article: "15" }` (controller-generated velocity audit).
- `3.2` `server/dsar-export.ts` — wire the three tables into the export chain (per-table `.eq("user_id", …)` reads).
- `3.3` **Four legal docs, same PR** (the cross-document gate fires on `dsar-export-allowlist.ts`): `docs/legal/privacy-policy.md` §4.7, `docs/legal/gdpr-policy.md` §6.1.b, `docs/legal/data-protection-disclosure.md` §2.3/§5.3, `knowledge-base/legal/compliance-posture.md` — add the beta-CRM processing description + PA-30 xref + 24-month retention.
- `3.4` `knowledge-base/legal/article-30-register.md` — add **Processing Activity 30** (beta-tester conversation capture; Art. 6(1)(f) LI + LIA; 24-month retention; Supabase EU processor; DSAR owner-export + Art. 17 CASCADE erasure; single-user-incident threshold). **Gate fold-ins in PA-30:** (a) **recipients** list **Anthropic (US)** — the `crm_*` agent-read path surfaces third-party conversation PII to Claude for `cro`/`cpo` reasoning (Chapter V transfer under the existing Anthropic DPA — confirm the DPA purpose covers it); (b) the **involuntary third-party (beta tester) posture** — Art. 14 (not Art. 13) transparency; access/erasure requests fulfilled via the **`crm_erase_contact` service_role-only RPC** keyed on contact identity (Phase 1.5 — an auditable, implementable path, NOT raw manual SQL; distinct from the owner CASCADE); (c) **no special-category data solicited** (Art. 9) — free-text `body` is an incidental ingress the operator avoids populating.
- `3.5` **LIA deliverable** — `knowledge-base/legal/<beta-crm-lia>.md`: the Art. 6(1)(f) three-part balancing test for capturing third-party contact + conversation PII, the **Art. 14 notice mechanism** to the beta tester (contrast PA-28's in-line first-contact disclosure), the Anthropic-transfer note, and the no-Art.9 posture. Referenced by the per-column `LAWFUL_BASIS` annotations (1.1) and PA-30.

### Phase 4 — C4 model + views (in-scope, not deferred — `wg-architecture-decision-is-a-plan-deliverable`)
- `4.1` `model.c4`: add `crmStore` database in `infra`; add `betaContact` external actor (`#external`); edges: **`engine -> crmStore`** (crm_* MCP tools, agent-native parity — the true mirror of `engine -> operationalInbox`) + **`betaContact -> founder`** (PII origin). **Do NOT add `founder -> crmStore`** (arch P1-1: no `founder -> <database>` edge exists anywhere; the MVP has no UI/API surface so the only real access path is the agent; add `webapp -> crmStore` only when the deferred UI/API phase lands).
- `4.2` `views.c4`: add `platform.infra.crmStore` + `betaContact` to the **`containers`** view `include`; **also add `betaContact` to the `context` view** `include` (arch P2-1 — mirrors `emailSender`, which appears in both; `crmStore` stays containers-only, mirroring `operationalInbox`).
- `4.3` Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view include` on an undefined element fails here, not at `tsc`).

### Phase 5 — De-identified insight rollup scaffold
- `5.1` A short `knowledge-base/sales/README`-note (or a rollup stub) documenting where `cro`/`cpo` write pseudonymised aggregate signal (no identifiable person). No raw PII. (The rollup *generation* skill is deferred — see Deferred.)

### Phase 6 — Tests (write RED first per cq-write-failing-tests-before)
See §Test Scenarios.

## Files to Create
- `apps/web-platform/supabase/migrations/123_beta_crm.sql`
- `apps/web-platform/supabase/migrations/123_beta_crm.down.sql`
- `apps/web-platform/server/crm/stage-probability.ts`
- `apps/web-platform/server/crm/crm-tools.ts` (`crm-data.ts` inlined — single-file precedent)
- `apps/web-platform/test/supabase-migrations/123-beta-crm.test.ts` (offline RLS/FK/CASCADE shape)
- `apps/web-platform/test/crm-tools.test.ts` (tool builder: userId-in-closure, RPC call shape, untrusted envelope, error→reportSilentFallback)
- `apps/web-platform/test/beta-crm-dsar.integration.test.ts` (owner export includes 3 tables; Art. 17 CASCADE deletes all rows; cross-tenant RLS deny with schema-valid payloads)
- `knowledge-base/legal/<beta-crm-lia>.md` (Legitimate Interest Assessment — GDPR-gate fold-in; work picks the dated filename)
- `knowledge-base/engineering/architecture/decisions/ADR-098-beta-crm-capture-store-per-tenant-owner-private-agent-native.md` *(delivered with this plan)*

## Files to Edit
- `apps/web-platform/server/dsar-export-allowlist.ts` (register 3 tables) — **triggers the legal cross-document gate**
- `apps/web-platform/server/dsar-export.ts` (export chain)
- `apps/web-platform/server/<session-tool-wiring-site>.ts` (register `buildCrmTools` — resolve exact file at Phase 0.4)
- `docs/legal/privacy-policy.md`
- `docs/legal/gdpr-policy.md`
- `docs/legal/data-protection-disclosure.md`
- `knowledge-base/legal/compliance-posture.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/views.c4`

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` scanned against the Files-to-Edit set — no open scope-out names any of these paths. Recorded so the next planner sees the check ran.)

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `123_beta_crm.sql` applies cleanly on a fresh DB; `.down.sql` reverses it (offline migration test green). No `CREATE INDEX CONCURRENTLY`.
- **AC2** RLS shape (per table, via `pg_policy.polcmd`): exactly **one** row with `polcmd='r'` (SELECT, `USING (user_id = auth.uid())`) AND **zero** rows with `polcmd IN ('a','w','d','*')` for `authenticated` (Kieran-D — `'*'` catches a `FOR ALL` policy the prose form would miss); plus the RESTRICTIVE `<table>_jti_not_denied` policy present. Table-level INSERT/UPDATE/DELETE REVOKEd from `PUBLIC, anon, authenticated, service_role`.
- **AC3** Cross-tenant RLS deny **with a positive owner-read control** (Kieran-B): user A reads own row → **1 row**; user B reads A's row → **0 rows**. Dropping the SELECT policy must **break the positive control** (A reads own → 0) so the test fails — proving the policy is load-bearing (learning 2026-05-16). Schema-valid UUIDs. (The write-isolation half lives in AC4, not here.)
- **AC4** Each write RPC is SECURITY DEFINER, pins `search_path=public, pg_temp`, opens with an explicit `auth.uid() IS NULL → 42501` guard, then `SELECT … FOR UPDATE` + rejects a missing OR foreign `contact_id` with the **same** `42501` (no existence oracle). Test: **user B `crm_contact_upsert`/`set_stage`/`note_append` against user A's `contact_id` raises `not authorized` AND leaves A's row unchanged** (security P0-1 cross-tenant write isolation).
- **AC5** Stage transition: `crm_contact_upsert` on INSERT-at-non-default-stage AND any stage change writes exactly one `beta_contact_stage_transitions` row in the same txn; a partial upsert that omits `stage` emits **no** transition and does not null the stage (spec-flow P1-3). **Concurrency:** a concurrent double stage-change (both via `FOR UPDATE`) yields two *consecutive* transitions, not two claiming the same `from_stage` (data-integrity P1-1).
- **AC6** `crm-tools.ts`: `userId` is closure-captured (not a zod tool-input field); read tools run on `getFreshTenantClient(userId)`; write tools call `tenant.rpc(...)`; the untrusted-content envelope precedes any conversation `body`; the error path reports **only `{op,userId,code}`** and does **NOT** forward the raw PG error — a test asserts a CHECK-violation write's reported payload contains **no** row field values (security P1-1).
- **AC7** Write→read round-trip (the make-or-break behavioral gate): a `crm_contact_upsert` via the real tenant client lands a `beta_contacts` row with `user_id = operator`, and `crm_contact_list`/`crm_contact_get` returns it with **every writable column** round-tripped (spec-flow P1-1); a `crm_note_append` note is returned by **`crm_note_list`** in the same and a fresh session, with the `lens` filter honored (spec-flow P0-1). DEV-only, synthesized fixtures.
- **AC8** Stage-enum single-source drift guard: `Object.keys(STAGE_PROBABILITY)` equals the migration `<STAGE_ENUM>` CHECK set (arch P2-3 / spec-flow P1-4); test fails on divergence.
- **AC9** DSAR: all 3 tables in `DSAR_TABLE_ALLOWLIST` (`beta_contacts`/`interview_notes` = `15+20`, `beta_contact_stage_transitions` = `15`); `dsar-allowlist-completeness.test.ts` passes; owner export integration test returns rows from all 3.
- **AC10** Art. 17 owner erasure: deleting via the **real account-delete path** (`auth.admin.deleteUser` → `public.users` CASCADE) empties all 3 tables (data-integrity confirmed no WORM/RESTRICT ancestor); **not** a bare `DELETE FROM beta_contacts` (spec-flow P2-5). Third-party erasure: `crm_erase_contact` (service_role-only) deletes a contact + CASCADEs children.
- **AC11** Append-only guard: a migration-body test asserts **no `UPDATE`/`DELETE`** statement targets `interview_notes` or `beta_contact_stage_transitions` (data-integrity P2-3 — history mutation trips CI). Composite-FK guard: a child row cannot carry a `user_id` differing from its parent (composite FK rejects; security P2-2).
- **AC12** Legal cross-document gate passes: the PR touches `dsar-export-allowlist.ts` AND all four legal docs.
- **AC13** `article-30-register.md` contains a `## Processing Activity 30 — …` heading (next free; PA-29 prior max — grep-verified).
- **AC14** C4: `model.c4` defines `crmStore` + `betaContact` with edges `engine -> crmStore` + `betaContact -> founder` (**no** `founder -> crmStore`); `views.c4` `containers` includes both, `context` includes `betaContact`; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC15** `apps/web-platform` typecheck (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`) + `./node_modules/.bin/vitest run` for the new tests are green.
- **AC16** `/soleur:gdpr-gate` produced no Critical finding; the six Important/Suggestion fold-ins are applied: per-column `LAWFUL_BASIS` (Phase 1.1), the LIA + Art. 14 notice deliverable (Phase 3.5), the third-party erasure via `crm_erase_contact` + Anthropic Chapter-V recipient + no-Art.9 posture (PA-30, Phase 3.4), and DEV-only synthesized test fixtures (AC18).
- **AC17** The LIA (`knowledge-base/legal/<beta-crm-lia>.md`) exists and covers: Art. 6(1)(f) 3-part balancing, the Art. 14 notice mechanism to the beta tester, the Anthropic transfer, and the no-Art.9 posture; PA-30 recipients include Anthropic (US) and state the involuntary-third-party erasure path.
- **AC18** DSAR/cross-tenant/round-trip integration tests run **DEV-only** (`hr-dev-prd-distinct-supabase-projects`) with **synthesized** fixtures (`cq-test-fixtures-synthesized-only`); no synthetic user is created against prod.

### Post-merge (operator)
- **AC19** *(none currently expected — pure code/migration/docs, no operator dashboard/vendor step).* The migration applies via the existing `web-platform-release.yml#migrate` job on merge (not a separate operator step). Verify apply via `mcp__plugin_supabase_supabase__list_migrations` shows `123`.

## Test Scenarios
- Migration shape (offline, `123-beta-crm.test.ts`): FK targets + `ON DELETE CASCADE` on all 3; RLS SELECT-only; REVOKEs present; RPC search_path pins; CHECK constraints (currency regex, amount_basis enum, lens subset).
- Cross-tenant isolation (integration): user B cannot read/write user A's contacts/notes/transitions; deny test fails-open when policy removed.
- Stage transition: upsert with a new stage appends exactly one transition row; velocity is computable from `entered_at`.
- Agent tool (`crm-tools.test.ts`): builder captures userId; write calls RPC not a raw table insert; untrusted envelope present; error→reportSilentFallback+isError.
- DSAR round-trip (integration): owner export includes 3 tables; account delete CASCADE-empties all 3.
- FX/amount: `amount` nullable; `amount_basis` discriminates hypothetical vs committed; `amount_normalized_usd` + `fx_rate_date` stored.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Sales, Operations, Finance (carried forward from brainstorm §Domain Assessments — no fresh spawn).

### Legal (CLO)
**Status:** reviewed (carry-forward). Third-party PII; Art. 6(1)(f) LI + LIA + notice; git-committed PII is the anti-pattern avoided; new PA-30 + retention + DSAR wiring is the compliance floor. `/soleur:gdpr-gate` run at Phase 2.7 (below).

### Engineering (CTO)
**Status:** reviewed (carry-forward). DB route correct; net-new = CRM tables + agent read/write path (the make-or-break); ADR recommended (delivered as ADR-098); medium complexity.

### Sales (CRO)
**Status:** reviewed (carry-forward). Bootstraps the first pipeline data layer; stage-transition timestamps for velocity; one dual-lens record; tenant-generic stages.

### Finance (CFO)
**Status:** reviewed (carry-forward). Capture the fields now (no forecasting at 0 deals); canonical stage→probability map; currency raw + normalized at dated FX; `amount_basis` discriminator.

### Operations (COO)
**Status:** reviewed (carry-forward). BUILD-light; zero new vendor/sub-processor/recurring cost; inside the already-DPA'd Supabase/Hetzner boundary.

### Product/UX Gate
**Tier:** none. Mechanical UI-surface override checked: **no** file in Files-to-Create/Edit matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` — the plan implements DB + server module + docs; the UI surface is deferred (N1). No wireframes required. `ux-design-lead` correctly NOT invoked (no UI feature). CPO reviewed the approach via brainstorm carry-forward (`requires_cpo_signoff` satisfied).

## Observability

```yaml
liveness_signal:
  what: crm_* MCP tool invocations succeed; RPC calls return without error
  cadence: on-demand (operator/agent-initiated, in-session)
  alert_target: Sentry (reportSilentFallback op="crm-tools")
  configured_in: apps/web-platform/server/crm/crm-tools.ts
error_reporting:
  destination: Sentry via reportSilentFallback (feature="crm-tools", op in {list,get,upsert,note_append,set_stage})
  fail_loud: true (agent sees isError:true; Sentry gets the real error before the generic return — cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - mode: RPC rejects (foreign/missing contact, not-authorized 42501)
    detection: reportSilentFallback op + error code; agent-visible isError
    alert_route: Sentry crm-tools op
  - mode: RLS returns 0 rows unexpectedly (cross-tenant regression)
    detection: beta-crm-dsar.integration.test cross-tenant deny (CI); no silent prod path
    alert_route: CI gate (pre-merge)
  - mode: DSAR export omits a beta table (allowlist drift)
    detection: dsar-allowlist-completeness.test.ts (CI, fail-closed)
    alert_route: CI gate
logs:
  where: Sentry (structured, op-tagged); no PII in the mirror (op + userId only, never contact content)
  retention: Sentry default
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/crm-tools.test.ts test/beta-crm-dsar.integration.test.ts
  expected_output: all green; cross-tenant deny + CASCADE erasure asserted (NO ssh)
```

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-098** (delivered with this plan): storage-boundary + data-model + erasure-via-CASCADE + agent-path + extraction-seam decision, with the Sourcing Options Canvas as the alternatives record. Ordinal provisional; `/ship` re-verifies against `origin/main`.

### C4 views
Read all three `.c4` files (done). Enumeration against the completeness mandate — for this feature the C4-relevant elements are the new **external data subject** and the new **data store** (not the feature's own noun):
- **External human actor:** `betaContact` (Beta Tester / Prospect) — the third-party data subject whose conversation PII is captured. NOT currently modeled (mirrors `emailSender`). → add to `model.c4` `#external` + `betaContact -> founder` (PII origin) + include in `containers` view.
- **External system / vendor:** none new (Supabase already modeled).
- **Container / data store:** `crmStore` (Supabase: beta_contacts + interview_notes + beta_contact_stage_transitions, mig 123) — NOT modeled (mirrors `operationalInbox`). → add to `model.c4` `infra` + `containers` view.
- **Access relationship:** `founder -> crmStore` (owner RLS-scoped read/write) and `engine -> crmStore` (crm_* MCP tools — agent-native parity, mirrors `engine -> operationalInbox`). → add edges.
No existing element description is falsified (owner-private CRM; the `founder` multi-Owner note is unaffected — MVP is owner-only). Validated by `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
The ADR is authored now describing the target state (`status: adopting`); Phase 4 lands the C4 edits in the same PR. Not deferred.

## Infrastructure (IaC)

**None.** The feature introduces no server, systemd unit, vendor account, DNS record, TLS cert, secret, or firewall rule. The only recurring runtime is an **in-migration `pg_cron` retention sweep** (defined in `123_beta_crm.sql`, the `processed_resend_events` precedent) — in-DB, no Terraform, no operator provisioning. IaC routing gate: skipped (pure code+migration+docs against already-provisioned Supabase).

## Risks & Mitigations
- **R1 — RLS gap exposes cross-tenant PII (brand-survival).** Mitigation: SELECT-owner-only RLS + no owner-write policy + RPC-only writes + `auth.uid()` pin + cross-tenant deny test with schema-valid payloads that fails-open when the policy is removed. Deepen-plan `data-integrity-guardian` + `security-sentinel` MUST stress-test (see below).
- **R2 — Art. 17 CASCADE collides with a WORM/RESTRICT ancestor** (learning 2026-05-25). Mitigation: no no-mutate trigger on the append-only tables (immutability by RLS shape, ADR-098 §3); CASCADE chain is users→beta_contacts→children only; integration test asserts full-delete. `data-integrity-guardian` verifies no RESTRICT ancestor.
- **R3 — Agent write path is the first agent WRITE over untrusted content** (security P1-3). The `auth.uid()` pin structurally blocks **cross-tenant** writes, but **within-tenant** corruption is NOT closed by the envelope: injected instructions in a captured conversation `body` could drive the agent to `crm_contact_upsert` and overwrite a real contact's `name`/`company`/`amount`/`stage`. Mitigations: (a) envelope wording instructs the agent to treat all `body` strictly as data, never as write-tool instructions; (b) the mutable head has no field-level audit today (only `stage` is logged via transitions) → a lightweight old→new field-diff audit is a **deferred hardening** (operator reviews agent actions in-session at single-user scale). Explicitly acknowledged, not implied-closed (ADR §5). `agent-native-reviewer` + `security-sentinel` at review.
- **R7 — Revoked/stolen founder JWT reads beta PII directly against PostgREST** for the JWT TTL (data-integrity P1-4). Mitigation: the RESTRICTIVE `<table>_jti_not_denied` policy (068/076/077 shape) on all 3 tables consults the deny-list at the policy boundary — the only server-side revocation enforcement for direct reads. (102/122 lack it; filed as a follow-up, not inherited.)
- **R4 — Legal cross-document gate blocks the PR** if the 4 legal docs aren't touched with the allowlist edit. Mitigation: Phase 3 folds all four into the same commit; AC9 gates it.
- **R5 — DSAR export omits a beta table.** Mitigation: `dsar-allowlist-completeness.test.ts` is fail-closed CI.
- **R6 — pseudonymised rollup over-claims** (learning 2026-05-12). Mitigation: the git rollup layer is scoped to *aggregate, no-identifiable-person* signal only; raw PII never leaves the DB; disclosure names the exact boundary.

## Sharp Edges
- The legal cross-document gate fires on **`dsar-export-allowlist.ts`** (not only `dsar-export.ts`) — registering the 3 tables REQUIRES touching all 4 legal docs in the same PR (workflow lines 61-62). AC9 is load-bearing.
- Do NOT copy `email_triage_items`'s `ON DELETE RESTRICT` + `anonymise_*` + no-mutate trigger — that shape exists to retain **statutory** rows the beta-CRM does not have; copying it reintroduces the Art. 17 CASCADE deadlock (ADR-098 §3-4).
- Do NOT add an owner-INSERT/UPDATE RLS policy "for convenience" beside the RPCs — it is an RPC bypass (learning 2026-05-21). Writes are RPC-only; RLS is SELECT-only.
- RLS-deny tests MUST use schema-valid payloads (valid UUIDs) or type-validation preempts RLS and the test passes for the wrong reason (learning 2026-05-16). Confirm each deny test FAILS when the policy is dropped.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces:` field → `npm run -w` aborts). Tests: `./node_modules/.bin/vitest run test/<file>` (test files under `test/**`, the vitest `include` globs).
- ADR-098 ordinal is provisional; a sibling PR can claim 098 pre-squash. `/ship` re-verifies against `origin/main`; on renumber, sweep `knowledge-base/project/{plans,specs}/feat-beta-conversation-capture/` + this ADR + the migration/code seed in the same edit.
- A plan whose `## User-Brand Impact` is empty/TBD fails `deepen-plan` Phase 4.6 — it is filled above.
- **`lens text[]` CHECK MUST use `cardinality(lens) >= 1`, NOT `array_length(lens,1) >= 1`** — `array_length('{}',1)` returns NULL (not 0), `NULL >= 1` is NULL, and a CHECK treats NULL as satisfied, so an empty-lens note would be accepted. `cardinality('{}')=0` rejects it. Only reproducible against real Postgres (offline SQL-text/pg-mem shims won't catch it) — the migration test needs a live `'{}'` INSERT.
- **SECURITY DEFINER bypasses RLS** — every write RPC's UPDATE branch MUST `SELECT … FOR UPDATE` and re-check `user_id = auth.uid()` before mutating; a blind `ON CONFLICT DO UPDATE` or unguarded `UPDATE … WHERE id=p_id` lets user B overwrite user A's row cross-tenant. The `FOR UPDATE` also serializes concurrent stage changes (else two transitions claim the same `from_stage`).
- **Never forward the raw PG error to Sentry** on these tables — the `Failing row contains (…)` DETAIL carries `name`/`company`/`body`. Map to a stable `code`; report `{op,userId,code}` only. `extra`-scrubbing is insufficient (the PII rides in `exception.value`).
- **AC2 must pin `pg_policy.polcmd`** (`='r'` and `NOT IN ('a','w','d','*')`) — a prose "no INSERT/UPDATE/DELETE policy" check misses a `FOR ALL` (`'*'`) policy.
- **Composite FK `(contact_id, user_id) → beta_contacts(id, user_id)`** requires a `UNIQUE (id, user_id)` on `beta_contacts` — order the migration so the UNIQUE exists before the children's FK.

## Plan Review — Consolidated Findings (6-agent panel + gdpr-gate)

At the `single-user incident` threshold the panel ran the escalated set: spec-flow-analyzer, data-integrity-guardian, security-sentinel, architecture-strategist, kieran-rails-reviewer, code-simplicity-reviewer (+ `/soleur:gdpr-gate` at Phase 2.7). **Agreement:** the storage boundary, the MCP-tool→`auth.uid()`-pinned-RPC agent write path, and CASCADE-not-RESTRICT erasure are all sound; both make-or-break questions resolved GREEN (`auth.uid()` resolves via the founder-JWT tenant client — `suppress_recipient`/mig 104 precedent; the CASCADE chain `auth.users`→`public.users`→`beta_contacts`→children fires with no WORM/RESTRICT ancestor, so `account-delete.ts` needs no new step).

**Mechanical (auto-applied to this plan + ADR):** `cardinality()` lens fix (Kieran-A/DI P1-3); `SELECT…FOR UPDATE` + ownership re-check on all write RPCs (Sec P0-1/DI P1-1); PII-safe error mapping, no raw PG error (Sec P1-1); `service_role` REVOKE + `crm_erase_contact` service-role RPC (Sec P1-2/SF P1-5); composite FK `(contact_id,user_id)` (Sec P2-2/DI P1-2); `amount⇒currency` CHECK + `amount_basis NOT NULL` (Kieran-C/DI P2-1); AC2 `polcmd` pin (Kieran-D); AC3 positive owner-read control (Kieran-B); write→read round-trip + `crm_note_list` read tool (SF P0-1/P1-1, Simplicity); `p_occurred_at` (SF P1-2); initial-stage transition + COALESCE partial-update (SF P1-3); stage-enum drift guard (SF P1-4/Arch P2-3); retention `COALESCE(last_contact,created_at)` (Sec P2-1/DI P2-2); `to_stage` enum CHECK (Sec P2-3); append-only migration-body guard test (DI P2-3); `jti_not_denied` RESTRICTIVE policy on all 3 tables (DI P1-4); drop `founder→crmStore` C4 edge + add `betaContact` to context view (Arch P1-1/P2-1); `stage-probability.ts` "references not imports" + `buildRoutineTools` singular + wiring site `agent-runner.ts:1749-1808` (Arch P2-2/P2-4).

**Taste / operator-delegated (resolved, see §Resolved Open Questions):** FX-trio **cut** (Simplicity/SF P2-4 — deferred to a reporting consumer); `crm-data.ts` **inlined** into `crm-tools.ts` (Simplicity — single-file precedent); **kept** the 3-table model incl. `beta_contact_stage_transitions` as a table (rejected Simplicity's JSONB-column cut — the composite-FK owner guard (Sec P2-2/DI P1-2) and queryable velocity require a table on this single-user-incident surface); **kept** `crm_contact_set_stage` as a distinct agent affordance (rejected Simplicity's fold-into-upsert — sharing the transition logic); **kept** `stage-probability.ts` as the enum source-of-truth (rejected Simplicity's defer — it single-sources the CHECK enum and is the operator's locked "canonical map", drift-guarded by a real test).

**Residual acknowledged (not MVP-blocking):** within-tenant prompt-injection overwrite of the mutable head (R3 — field-diff audit deferred; operator reviews in-session at single-user scale).

## Deferred Items (→ follow-up issues)
1. **`/soleur:capture-conversation` skill** — parse a raw pasted/dictated conversation into a faceted `beta_contacts` + `interview_notes` record (Productize Candidate). *(File follow-up.)*
2. **BYO-CRM connect** via native MCP (HubSpot first). Re-eval unified-API at ~8–10 tenants across 4+ CRMs. *(File follow-up.)*
3. **Tester-visible records** (external-person auth surface; agent-user parity). *(File follow-up.)*
4. **In-Soleur-UI surface** for contacts/pipeline over the store's API (wireframes required when scoped). *(File follow-up.)*
5. **Workspace-shared visibility** (the 111 workspace-owner RLS shape) if multi-member workspaces need shared CRM. *(File follow-up.)*
6. **USD normalization** (`amount_normalized_usd` + `fx_rate` + `fx_rate_date` + an FX source) when a reporting/forecasting consumer exists (one-line migration). *(File follow-up.)*
7. **Field-level audit** for `beta_contacts` mutable-head overwrites (old→new diff), hardening R3's within-tenant injection risk beyond in-session operator review. *(File follow-up.)*
8. **`jti_not_denied` omission on `email_triage_items` (mig 102) + `inbox_item` (mig 122)** — pre-existing revocation-surface gap surfaced by data-integrity P1-4; add the RESTRICTIVE policy to those tables too. *(File follow-up.)*
9. **`/soleur:capture-conversation` skill** — parse a raw conversation into a faceted record (already listed #1; Productize Candidate).
10. **Standalone agent-operated CRM spin-out** — tracked in #6166 (NOT-NOW; watch triggers).
