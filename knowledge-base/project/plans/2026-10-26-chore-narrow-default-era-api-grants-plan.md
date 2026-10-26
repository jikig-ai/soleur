---
title: "chore(supabase): narrow default-era api-role table grants (audit list from 174 snapshot)"
type: chore
date: 2026-10-26
slug: chore-narrow-default-era-api-grants
branch: feat-one-shot-11193-api-grant-narrowing
issue: 11193
closes: 11193
lane: cross-domain
domain: engineering
priority: normal
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(supabase): narrow default-era api-role table grants (audit list from 174 snapshot)

## Enhancement Summary

**Deepened on:** 2026-10-26 (same-session deepen pass)
**Gate results:** 4.6 User-Brand Impact — pass (threshold `single-user incident`, matching ADR-303's declared threshold for this surface); 4.7 Observability — pass (`rg`-verb local probe, literal expected_output); 4.10 Encryption Posture — pass (no new store/connection; declared for touched surfaces); 4.11 Guard Contract — pass (`lint-guard-contract.py` clean, 1 guard entry, 6-row matrix incl. own-dispatch + order + must-PASS rows); 4.12 Scope Check — pass (exactly one unfenced section, all asks mapped, inferred items justified); 4.13 Task Design — N/A (no new autonomous-task surface); 4.5 network / 4.55 downtime / 4.8 PAT / 4.9 wireframe — all no-trigger.
**Fan-out disclosure:** no agent-spawn capability on this harness — per-section research agents, review agents, and the 4.45 verify-the-negative/post-edit passes were executed inline in this process; the negative claims were re-verified by direct grep (see below) rather than by subagent.

### Precedent-diff (4.4)

Prescribed pattern: `DO $$ BEGIN IF to_regclass('public."<rel>"') IS NOT NULL THEN REVOKE … [re-GRANT …] END IF; END $$;` + `check_name`/`bad` verify + `OVERRIDES` registry entries. Precedent: `migrations/175_tom4_shape_iv_client_grant_revokes.sql` + `verify/175_*.sql` + `table-grants.ts` OVERRIDES block — grepped and read verbatim at plan time. **Divergences from precedent, deliberate:** (a) 175 revoked with zero re-grants (shape-iv tables need nothing for client roles); 178 re-grants `SELECT` to `authenticated` on four live-read relations and column-level `UPDATE` on `users` — the REVOKE-ALL-then-re-GRANT ordering inside each block is pinned by Guard Contract matrix row 5; (b) 178 adds an `INTERNAL`-kind OVERRIDES entry (`_schema_migrations`), a shape 175's OVERRIDES block did not use — mechanism verified against `buildRegistry()`'s collision rule (INTERNAL map throws; OVERRIDES replaces). All other conventions (to_regclass guards, down-file restoring prior verb sets, verify contract, provenance strings) are 1:1 with the precedent.

### Verify-the-negative (4.45)

- "`flag_flip_audit` has no client readers" — `git grep -n "\.from(.flag_flip_audit.\)" apps/web-platform/{app,server,lib,hooks}` → 0 hits (writes only via `audit_flag_flip` definer RPC, confirmed 071).
- "`_schema_migrations` has no api-role client" — same grep → 0 `.from()` hits; all readers are `psql $DATABASE_URL` scripts (run-migrations.sh, dev-ledger-parity*, preflight-schema-vs-ledger). **Flagged residual:** the Phase-1 task re-runs this census before choosing INTERNAL vs service_role-only — a negative claim gated on implementation-time re-proof, not assumed.
- "No INSERT/DELETE policies on `users` for client roles" — policy census: `001` carries only "Users can read own profile" (SELECT) + "Users can update own profile" (UPDATE); migration 054's own comment verifies no INSERT grant path to anon/authenticated. `handle_new_user` trigger (001, definer-context) owns row creation.
- "No anon consumer of `users`" — middleware's `users` select sits after the `!user → /login` redirect (middleware.ts:707+); identity.ts selects post-auth-check; `(auth)/callback` uses serviceClient.

## Overview

Migration `174_api_data_grants_snapshot.sql` (merged PR #11180, ADR-303) reproduced prd's *effective* api-role privileges verbatim so fresh replays match prd after the 2026-10-30 Supabase grant-defaults flip. Issue #11193 is the deferred narrowing pass ADR-303 §Consequences names explicitly: several relations still hold default-era grants they never needed. This plan revokes them per-relation against two evidence criteria — (a) does any supabase-js/PostgREST client path read or write the relation as `anon`/`authenticated`, and (b) does any SECURITY DEFINER RPC require the base-table grant — then encodes the intended posture in `test/rls-fuzz/table-grants.ts` OVERRIDES so the live-catalog fuzz gate keeps asserting it.

Unlike 174 (zero-prd-change by construction), this migration *changes* prd: it removes privilege bits. Every retained verb must trace to a live consumer; every revoked verb must be provably inert for that relation (no client call site, or RLS already denies the operation for the role).

## Problem Statement

Default-era Supabase auto-grants materialized full DML (`DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE`) to `anon`, `authenticated`, and `service_role` on internal and audit tables. RLS masks most of the exposure (owner/member-scoped SELECT policies only), but the grant layer itself is wider than intent:

- `users` carries **table-level UPDATE to all three api roles** despite migration 006's deliberate `REVOKE UPDATE` + column-level `GRANT UPDATE (email)` — a later grant restored the table-level verb (documented wart in 174's header). Live authenticated write paths (browser `use-onboarding`, `team-names` route, `session-sync` tenant client) currently work *because of* the wart.
- `_schema_migrations` (the psql migration runner's ledger) holds full DML to all three api roles; no api-role client ever touches it.
- `api_keys`, `audit_byok_use`, `audit_github_token_use`, `dsar_export_jobs`, `flag_flip_audit` hold full default-era DML to `anon`/`authenticated` while their real surface is far narrower (authenticated SELECT on four of them; nothing at all on `flag_flip_audit`).

A stolen user JWT today can `INSERT`/`DELETE` rows in `api_keys`, `audit_byok_use`, `audit_github_token_use`, `dsar_export_jobs`, `flag_flip_audit`, and `users` via raw PostgREST wherever a permissive policy exists — and hold the *privilege* even where RLS still blocks, which is attack surface waiting for the next permissive policy.

## Proposed Solution

One narrowing migration (`178_api_data_grants_narrowing.sql`, next free number after 176 — see Dependencies) that mirrors migration 175's pattern exactly:

- Per relation, a `DO $$ BEGIN IF to_regclass('public."<rel>"') IS NOT NULL THEN … END IF; END $$;` block containing `REVOKE ALL ON TABLE public."<rel>" FROM anon, authenticated` followed by the re-GRANT of only the verbs the consumer evidence supports (or no re-GRANT).
- A `.down.sql` restoring the exact pre-178 grant state (the default-era verb sets 174 materialized), same convention as `175_*.down.sql`.
- A `verify/178_*.sql` file on the `check_name` + `bad` contract (`run-verify.sh`), one row per relation asserting revoked verbs are not held and kept verbs are held — including `has_column_privilege` rows for `users`.
- `OVERRIDES` entries in `test/rls-fuzz/table-grants.ts` replacing the parsed-snapshot expectations for each narrowed relation — the same mechanism 175 used (provenance strings citing this migration + issue).
- A shape test `test/supabase-migrations/178-api-data-grants-narrowing.test.ts` following the `163-*` precedent (pins file conventions: to_regclass preconditions, no transaction control, verify contract).

## Technical Approach

### Architecture

Nothing new is built. The change feeds three existing mechanisms: the migration corpus (174/175 conventions), the authoritative live-catalog grant gate (`rls-grants.integration.test.ts` + `table-grants.ts` registry, ADR-303 tier 1), and the verify-file contract (`run-verify.sh`). ADR-303 already decided the architecture; this plan executes its deferred narrowing.

### Per-Relation Decision Matrix

Consumer evidence gathered 2026-10-26 by repo census (`.from('<rel>')` call sites classified by client binding; RPC definer/invoker status; policy inventory). `authenticated` = cookie-bound SSR client (`lib/supabase/server.ts`), browser client (`lib/supabase/client.ts`), or tenant-scoped JWT client (`lib/supabase/tenant.ts` `getFreshTenantClient` — anon key + user JWT). `service` = `createServiceClient`/`getServiceClient` (service_role).

| Relation | 174 posture (all three roles unless noted) | Client evidence as `anon`/`authenticated` | SECURITY DEFINER RPC needs | Target posture | Registry change |
|---|---|---|---|---|---|
| `_schema_migrations` | full DML | **None.** No `.from()` call site anywhere. `run-migrations.sh`, `dev-ledger-parity*.sh`, `preflight-schema-vs-ledger.sh` read/write it over `DATABASE_URL` psql as the `postgres` role — not an api role. | None | **zero api-role grants** | `OVERRIDES` entry of kind `INTERNAL` (see Note A) |
| `api_keys` | full DML | `authenticated` SELECT only: `dashboard/settings/services/page.tsx`, `dashboard/settings/page.tsx` (service client — see evidence column), `GET /api/services` (cookie client). All writes (`POST/DELETE /api/services`, `/api/keys`) use `createServiceClient`. | None — no RPC reads it | `anon`: none; `authenticated`: `SELECT`; `service_role`: full | `OVERRIDES` EXPOSED |
| `audit_byok_use` | full DML | `authenticated` SELECT only: `dashboard/audit/page.tsx`, `GET /api/dashboard/today/[id]/cost` (cookie client). Writes via `write_byok_audit`, `record_byok_use_and_check_cap`, `check_and_record_byok_delegation_use` — all SECURITY DEFINER, called over service client. | Definer RPCs insert; they do not need base-table grants | `anon`: none; `authenticated`: `SELECT`; `service_role`: full | `OVERRIDES` EXPOSED |
| `audit_github_token_use` | full DML | `authenticated` SELECT only: `dashboard/audit/github/page.tsx` (cookie client). Writes via `record_github_token_use` (definer, service). | Definer RPC only | `anon`: none; `authenticated`: `SELECT`; `service_role`: full | `OVERRIDES` EXPOSED |
| `dsar_export_jobs` | full DML | `authenticated` SELECT only: `dashboard/settings/privacy/page.tsx`, `app/api/account/export/[jobId]/{route,download}/route.ts` (cookie client). Writes via `server/dsar-export.ts` + `server/account-delete.ts` (service client). | None | `anon`: none; `authenticated`: `SELECT`; `service_role`: full | `OVERRIDES` EXPOSED |
| `flag_flip_audit` | full DML | **None.** No `.from()` call site in app/server/lib. Writes only via `audit_flag_flip(…)` (definer, `GRANT EXECUTE … TO service_role`). | Definer RPC only | `anon`/`authenticated`: none; `service_role`: full (175 convention: service-role-only is the documented shape) | `OVERRIDES` EXPOSED |
| `dsar_export_audit_pii` | full DML in 174 | — | — | **No change** — already narrowed to `service_role`-only by migration 175 (shape-iv revoke). Issue body predates 175's landing. | `OVERRIDES` entry already exists (175) |
| `users` | full DML; table-level UPDATE contradicts 006 | `authenticated` SELECT (73 call sites — middleware post-auth, identity, dashboard, API routes). `authenticated` UPDATE on a **column census**: `email` (006 grant), `onboarding_completed_at`, `pwa_banner_dismissed_at`, `runtime_explainer_dismissed_at` (browser `hooks/use-onboarding.ts` `updateUserField`), `nudges_dismissed` (`app/api/team-names/route.ts`), `kb_sync_history` (`server/session-sync.ts` `recordKbSyncHistory` — see Note B). No authenticated INSERT/DELETE (row creation via `handle_new_user` trigger + service clients; no INSERT/DELETE policies — 054 verified). | `append_kb_sync_row` (053, definer, authenticated EXECUTE) is the sanctioned tenant write path for `kb_sync_history` | `anon`: none; `authenticated`: `SELECT` + column-level `UPDATE` on the census set; `service_role`: full | `OVERRIDES` EXPOSED with `columnPrivileges` |
| `runtime_mint_intent` | `service_role` only (049) | — | — | **No change** — already correct; coordinate with #4027, do not touch | none |

**Note A — `_schema_migrations` registry mechanics.** The `INTERNAL` map cannot hold it: `buildRegistry()` throws when an `INTERNAL` key collides with a parsed-snapshot entry, and `_schema_migrations` *is* in the 174 snapshot. The mechanism is an `OVERRIDES` entry of kind `INTERNAL` (kind field carries `"INTERNAL"` with a `reason`) — `OVERRIDES` replaces the parsed entry unconditionally. Before writing this, implementation MUST re-grep every `_schema_migrations` reader under `apps/web-platform/` (scripts included) to confirm none uses an api-role client; if a service-role reader exists, fall back to `service_role`-only EXPOSED instead.

**Note B — `users.kb_sync_history`.** `recordKbSyncHistory` (`server/session-sync.ts:587`) does a direct tenant-client `.update({ kb_sync_history })` which the repo's own comment (session-sync.ts ~line 675) says is "blocked by migration 006's column grant … the RPC is the only tenant-callable write path" — it works on prd today only because the wart restored table-level UPDATE. Re-narrowing breaks it unless the write is rerouted through `append_kb_sync_row` (definer RPC, authenticated-callable, `p_cap` parameter — call with cap 14 to match the current `.slice(-14)` trim). **Ruled by CTO agent, 2026-10-26: reroute `recordKbSyncHistory` through `append_kb_sync_row` with `{date,count}` rows and `p_cap: 14`** — and the column-grant fallback is struck: migration 017's RESTRICTIVE policy `WITH CHECK (kb_sync_history IS NOT DISTINCT FROM …)` (`017_kb_sync_history.sql:11-18`) means `GRANT UPDATE(kb_sync_history)` alone restores nothing — the write still dies at RLS while passing a `has_column_privilege` verify row (registry-green/prd-broken trap). 017's own comment says the policy exists "in case column-level grants are later broadened". The reroute is the only path; a semantic mismatch would be new scope, not a fallback.

**Note C — census completeness is an implementation gate.** The `users` column census above is plan-time evidence; before writing the migration the implementer re-runs the full census: every `.from("users").update|.upsert` call site classified by client binding, every SECURITY INVOKER function touching `users`, every `.rpc(` that transitively updates `users` as authenticated, and browser-client (`lib/supabase/client.ts`) writes. Any additional authenticated-update column discovered joins the `GRANT UPDATE (…)` column list or gets a named RPC reroute — never silently dropped.

### Implementation Phases

#### Phase 1: Census verification + registry prep (RED)

- Re-run the per-relation consumer census (Note A re-grep for `_schema_migrations`; Note C for `users`) and record the result in the PR body.
- Write `test/supabase-migrations/178-api-data-grants-narrowing.test.ts` asserting the migration's conventions (to_regclass preconditions per relation; REVOKE precedes re-GRANT; verify file carries one `check_name` row per relation; column-grant list matches the census) — RED until the files exist.
- Success criteria: test file committed red; census table in PR body.

#### Phase 2: Migration + verify + registry (GREEN)

- `migrations/178_api_data_grants_narrowing.sql`: per-relation `REVOKE ALL … FROM anon, authenticated` (+ `FROM service_role` only for `_schema_migrations`, where zero api-role grants is the target) then the re-GRANTs from the decision matrix. `users` gets `REVOKE ALL … FROM anon` and `REVOKE ALL … FROM authenticated` followed by `GRANT SELECT ON public."users" TO authenticated` and `GRANT UPDATE (<census cols>) ON public."users" TO authenticated` (re-asserts the 006 `email` grant and the census columns in one place).
- `migrations/178_api_data_grants_narrowing.down.sql`: re-GRANT the exact 174 verb sets per relation (175 convention).
- `verify/178_api_data_grants_narrowing.sql`: `check_name`/`bad` rows — per relation, revoked-role verb counts → 0 (`has_table_privilege` over the TABLE_VERBS universe) and kept grants present (`service_role` full set; `authenticated` SELECT on the four read tables; `has_column_privilege` rows for each `users` census column; `NOT has_table_privilege('authenticated','users','UPDATE')`).
- `test/rls-fuzz/table-grants.ts`: `OVERRIDES` additions per the matrix with provenance citing migration 178 + #11193.
- `server/session-sync.ts`: reroute `recordKbSyncHistory` through `append_kb_sync_row` (per the CTO ruling — the column-grant fallback is refuted by 017's RESTRICTIVE policy; no fallback).
- Success criteria: `RLS_FUZZ_LOCAL=1` rls-grants gate green against a replayed stack; `run-verify.sh` all `bad=0`; `lint-migration-api-grants.sh` green on the PR diff.

#### Phase 3: Rehearsal + docs

- Apply `178` + `.down.sql` + `178` on a dev/local stack; confirm the down file restores the 174 posture (verify/174's rows still pass after down+re-up… note: after re-up the narrowed state returns, so run verify/174 **between** down and re-up).
- Update the migration header comment documenting each relation's evidence one-liner (mirroring 175's header).
- Success criteria: dev rehearsal evidence in PR body; green tenant-integration.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Regenerate `174_api_data_grants_snapshot.sql` from a narrowed prd | 174 is a generated point-in-time record of *effective prd posture*; rewriting it falsifies provenance and breaks the registry's parse contract (the parse IS the baseline OVERRIDES diverges from). |
| `REVOKE ALL … FROM anon, authenticated` with no re-GRANTs (blanket INTERNAL) | Breaks live authenticated SELECT paths on `api_keys`, `audit_byok_use`, `audit_github_token_use`, `dsar_export_jobs`, `users` — the evidence matrix exists precisely because the relations differ. |
| `_schema_migrations` via the `INTERNAL` map in table-grants.ts | Mechanically impossible — `buildRegistry()` throws on an INTERNAL key that collides with a parsed snapshot entry (Note A). |
| Column-level `SELECT` on `api_keys` (exclude `encrypted_key`/`iv`/`auth_tag`) | Refuted by live evidence (CTO ruling 2026-10-26) — four `authenticated`-role call sites select the ciphertext triple today via `getFreshTenantClient`: `server/byok-lease.ts:433`, `server/codex-credential-provider.ts:72`, `server/agent-runner.ts:265`, `server/agent-runner.ts:357`. Excluding those columns hard-breaks live BYOK runtime lease paths; RLS already confines reads to the owner's rows. |
| Fix `recordKbSyncHistory` by adding `UPDATE(kb_sync_history)` to the column grant | Refuted (CTO ruling 2026-10-26) — migration 017's RESTRICTIVE `WITH CHECK` policy blocks the write at RLS regardless of the column grant, so it is dead-on-arrival, not a fallback; the RPC reroute is the only path and adds row-lock atomicity. |

## User-Brand Impact

- **If this lands broken, the user experiences:** 42501 permission-denied surfaces on the audit page (`/dashboard/audit`, `/dashboard/audit/github`), privacy page (`/dashboard/settings/privacy` DSAR export list + download), connected-services settings, onboarding banner dismissals silently failing, and the nudge-dismiss action — every one a named, user-facing artifact.
- **If this leaks, the user's data is exposed via:** the reverse failure — a migration or OVERRIDES typo that *widens* a grant (e.g., granting `service_role` verbs to `anon` on `audit_byok_use`/`dsar_export_audit_pii`-adjacent audit tables) combined with any permissive policy exposes one user's per-user audit/PII rows through the Data API.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the touched relations hold per-user audit PII and credential metadata, and ADR-303 — the governing decision for this exact grant surface — declares `brand_survival_threshold: single-user incident`; a coordinated migration+registry error could widen rather than narrow exposure, which is one user's breach, not an aggregate pattern.

Per-artifact pairs for `soleur:engineering:review:user-impact-reviewer`:

- `/dashboard/settings/privacy` DSAR job list ↔ `authenticated` SELECT on `dsar_export_jobs` revoked by mistake.
- `/dashboard/audit*` BYOK/GitHub audit views ↔ `authenticated` SELECT on `audit_byok_use`/`audit_github_token_use`.
- `/dashboard/settings/services` + `GET /api/services` ↔ `authenticated` SELECT on `api_keys`.
- `use-onboarding` banners + `/api/team-names` nudge dismiss + `session-sync` KB history ↔ `authenticated` column-level UPDATE census on `users` incomplete.

`requires_cpo_signoff: true` is set per plan Phase 2.6. **CPO sign-off obtained 2026-10-26** (`soleur:product:cpo`, verdict `signed-off`) with three conditions: (a) the Note A and Note C implementation-time censuses are re-run and recorded in the PR body before the migration is finalized — any newly discovered authenticated read/write surface joins the re-grant census or gets a named RPC reroute; (b) `authenticated` SELECT on `dsar_export_jobs` is a must-keep — a 42501 on the privacy DSAR list/download degrades a GDPR data-portability surface; (c) post-deploy, the enumerated user-facing surfaces (audit pages, privacy DSAR, connected-services settings, onboarding/nudge dismissals) are confirmed Sentry-quiet for 42501/`reportSilentFallback` events, or the down file restores the prior posture — treated as a release gate. Recorded in `decision-challenges.md`. `soleur:engineering:review:user-impact-reviewer` will be invoked at review-time per the review skill's conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: "run-verify.sh verdict over verify/178_api_data_grants_narrowing.sql (every check_name row bad=0) + the RLS_FUZZ_LOCAL=1 rls-grants.integration.test.ts catalog⇔registry gate"
  cadence: "per deploy (verify on migration apply) / per CI run (fuzz gate)"
  alert_target: "CI check failure on the PR; verify failure aborts the deploy arm"
  configured_in: "apps/web-platform/supabase/verify/178_api_data_grants_narrowing.sql; apps/web-platform/test/rls-fuzz/rls-grants.integration.test.ts"
error_reporting:
  destination: "Sentry web-platform via existing reportSilentFallback calls on every affected read path (session-sync appendKbSyncRow already mirrors RPC errors to Sentry)"
  fail_loud: "PostgREST 42501 responses on the named routes surface as route-level errors + Sentry reportSilentFallback events; a red verify row prints check_name+bad>0 and aborts"
failure_modes:
  - mode: "over-narrowed grant breaks a live read (missed census column or call site)"
    detection: "verify/178 keeps-grant rows red at apply time; Sentry 42501 events on the four read surfaces post-deploy"
    alert_route: "Sentry issue → PR author; verify output in deploy log"
  - mode: "registry OVERRIDES missing/mismatched — fuzz gate reds"
    detection: "rls-grants.integration.test.ts held-vs-registered equality failure on the fuzz stack"
    alert_route: "CI check failure pre-merge"
  - mode: "recordKbSyncHistory silently stops writing after users re-narrowing"
    detection: "reportSilentFallback Sentry event feature=session-sync op=appendKbSyncRow (the reroute lands inside the existing instrumented path)"
    alert_route: "Sentry issue"
logs:
  where: "Next.js server logs + Sentry (web-platform); migration apply output in run-migrations.sh log"
  retention: "Sentry project retention; CI run logs 90d"
discoverability_test:
  command: "rg -l 'check_name' apps/web-platform/supabase/verify/178_api_data_grants_narrowing.sql"
  expected_output: "178_api_data_grants_narrowing.sql"
```

## Encryption Posture

```yaml
# Detection fires (supabase/migrations/*.sql in Files to Create) but this change introduces
# NO new persistent store and NO new connection — it re-scopes privilege bits on existing
# relations. Posture is declared for the surfaces the change touches.
at_rest:
  - store: "supabase.prd (public schema — the eight named relations)"
    mechanism: "provider-managed:Supabase platform disk encryption (AES-256 at rest per Supabase security posture)"
    evidence: "Supabase security attestation, https://supabase.com/security, retrieved_on 2026-10-26; unchanged by this diff"
    defends_against: "raw disk/snapshot exfiltration of the underlying volume"
    does_not_defend: "a leaked api-role JWT exercising held grants — that gap is what THIS change narrows; grant-layer exposure, not storage-layer"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:provider-managed posture has no self-serve probe; grant posture IS live-verified by verify/178 + the rls-grants gate"
in_transit:
  - connection: "apps/web-platform server + browser -> Supabase PostgREST (the channel whose privilege surface this narrows)"
    enforced_at: "apps/web-platform/lib/supabase/server.ts; apps/web-platform/lib/supabase/client.ts; apps/web-platform/lib/supabase/tenant.ts"
    tls: "HTTPS via Supabase-hosted PostgREST, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "privilege misuse over the authenticated channel — addressed by the grant narrowing itself, not by transport"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — narrowed-grant verify + registry pair

**Property.** Post-apply, every api-role privilege held on each of the eight named relations equals the decision-matrix target — a missing revocation, an accidental widening, or a dropped keep-grant reds the verify rows and/or the live-catalog fuzz gate.

**Assembly.** The 8 relations × {anon, authenticated, service_role} × TABLE_VERBS probe universe, asserted through two chokepoints: (1) `verify/178` `check_name`/`bad` rows executed by `run-verify.sh` against the applied state; (2) `TABLE_GRANT_REGISTRY` OVERRIDES entries asserted held==registered by `rls-grants.integration.test.ts` over `publicApiRelations` — a relation absent from either chokepoint is caught by the gate's catalog⇔registry parity (unclassified member reds).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `REVOKE … FROM anon` block for `api_keys` while keeping its OVERRIDES entry | RED — verify row `revoked_anon_api_keys` counts held verbs >0; fuzz gate held≠registered |
| 2 | Omit the `users` `GRANT UPDATE(<cols>)` re-GRANT after `REVOKE ALL` | RED — verify `has_column_privilege` census rows count missing grants >0 |
| 3 | Remove every `UNION ALL` branch of the verify query except the first (guard's own dispatch truncated) and leave `_schema_migrations` un-revoked | RED — `run-verify.sh` contract sees a single passing row over an otherwise-widened catalog; the registry parity assertion reds on the un-overridden relation |
| 4 | Widen one OVERRIDES entry — add `UPDATE` to `authenticated` on `flag_flip_audit` while the migration grants none | RED — gate asserts effective==registered; registered verb not held → fails |
| 5 | Swap order inside the `users` DO block — `GRANT SELECT`/`GRANT UPDATE(…)` emitted BEFORE `REVOKE ALL … FROM authenticated` | RED — the later REVOKE strips the re-grants; keep-grant verify rows fail (order/lifetime row, not a delete row) |
| 6 | Replay on a stack where `flag_flip_audit` does not exist (to_regclass precondition skips it) while all other relations narrow correctly | PASS — preconditions make per-relation blocks no-ops on absent relations, and the registry never expected a privilege the catalog cannot hold |

## Domain Review

**Domains relevant:** legal (advisory)

### Legal

**Status:** error
**Assessment:** No agent-spawn capability on this harness — assessed inline plus `soleur:gdpr-gate` (Phase 2.7) run against the plan's regulated surfaces (`apps/web-platform/supabase/migrations/*.sql`, `app/api/**`, `.sql`): the five v1 checks (Art. 6 lawful basis, Art. 5(1)(e) retention, Art. 17 FK/caller, Chapter V vendor, Art. 9 special-category columns) produce **no findings** — the diff creates no columns, tables, FKs, vendors, or processing activities; it narrows Art. 32(1)(b) confidentiality-relevant privileges on existing audit tables, including `dsar_export_audit_pii`-adjacent DSAR surfaces. Advisory only; `soleur:legal:clo` review not required for a grants-only change but flagged here because the touched tables carry Art. 6(1)(f) LIA-registered audit data (`071_flag_flip_audit.sql` header).

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

### Product/UX Gate

Product domain: not relevant — no UI-surface files in `## Files to Create`/`## Files to Edit` (the only app-code edit is `server/session-sync.ts`, orchestration-layer; no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`). Tier: NONE. `Pencil available:` N/A (no UI surface).

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open` (98 open) searched for `apps/web-platform/test/rls-fuzz/table-grants.ts`, `apps/web-platform/server/session-sync.ts`, `supabase/migrations/178`, `api_keys`, `users`.

- No matches on the planned file paths or `api_keys`.
- Substring `users` matched #8540, #4525, #3416, #3242 — reviewed: all unrelated scope-outs (grok shims, org-id resolution, kb-template SHA, WS event names). **Disposition: acknowledge** — generic `users` mentions in unrelated bodies; no overlap with grant narrowing.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "users carries table-level UPDATE to anon/authenticated/service_role despite migration 006's deliberate REVOKE + column-level GRANT UPDATE(email); _schema_migrations holds full DML grants to anon/authenticated; audit/internal tables with default-era grants to anon/authenticated include audit_byok_use, audit_github_token_use, flag_flip_audit, dsar_export_audit_pii, dsar_export_jobs, api_keys" [issue #11193] | Phase 2 migration 178 + Per-Relation Decision Matrix | mapped |
| 2 | "(a) does any supabase-js/PostgREST client path read/write it as anon/authenticated? (b) does any SECURITY DEFINER RPC require base-table grants?" [issue #11193] | Per-Relation Decision Matrix evidence columns + Phase 1 census step | mapped |
| 3 | "Narrow only with a migration + matching table-grants.ts registry update so the fuzz gate stays green." [issue #11193] | `migrations/178*` + `test/rls-fuzz/table-grants.ts` OVERRIDES | mapped |
| 4 | "Related: #4027 (runtime_mint_intent, already narrowed via 049 — coordinate, do not duplicate)" [issue #11193] | Non-Goals + decision-matrix `runtime_mint_intent` no-change row | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `migrations/178_api_data_grants_narrowing.sql` (+`.down.sql`) | "Narrow only with a migration" | asked |
| `verify/178_api_data_grants_narrowing.sql` | "so the fuzz gate stays green" — verify contract is the deploy-time arm of the same grant assertion | inferred — justification: every prior grant migration (174, 175) ships the check_name/bad verify pair; omitting it breaks corpus convention |
| `test/rls-fuzz/table-grants.ts` OVERRIDES | "matching table-grants.ts registry update" | asked |
| `test/supabase-migrations/178-api-data-grants-narrowing.test.ts` | — | inferred — justification: every recent migration ships a `test/supabase-migrations/` shape test (163, 176-by-sibling); corpus convention the reviewer will require |
| `server/session-sync.ts` `recordKbSyncHistory` reroute | "does any supabase-js/PostgREST client path read/write it as anon/authenticated?" — criterion (a) requires the live path to survive the narrow | inferred — justification: re-narrowing `users` without it silently breaks a live authenticated write path the census found |
| Decision-matrix/`dsar_export_audit_pii` no-op row | "audit/internal tables … include … dsar_export_audit_pii" | asked — resolved to already-narrowed by 175 (premise validation) |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 6 | Estimated changed lines: ~350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: headless pipeline — no operator-stated criteria beyond the issue body -->

### Functional Requirements

- [ ] FR-1: `migrations/178_api_data_grants_narrowing.sql` revokes default-era api-role grants per the Per-Relation Decision Matrix, each revoke behind a `to_regclass` precondition; `service_role` postures are untouched except `_schema_migrations` (zero api-role grants there — pending the Note A re-grep).
- [ ] FR-2: `authenticated` retains exactly `SELECT` on `api_keys`, `audit_byok_use`, `audit_github_token_use`, `dsar_export_jobs`; `SELECT` + `UPDATE(<census columns>)` on `users`; nothing on `flag_flip_audit`, `_schema_migrations`; `anon` retains nothing on all eight.
- [ ] FR-3: `users` column-level UPDATE census covers, at minimum, `email`, `onboarding_completed_at`, `pwa_banner_dismissed_at`, `runtime_explainer_dismissed_at`, `nudges_dismissed`; `kb_sync_history` is covered by the `recordKbSyncHistory` → `append_kb_sync_row` reroute (CTO-ruled; the column-grant fallback is refuted by 017's RESTRICTIVE policy).
- [ ] FR-4: `test/rls-fuzz/table-grants.ts` carries an OVERRIDES entry per narrowed relation (`INTERNAL`-kind for `_schema_migrations`) with provenance citing migration 178 and #11193; the rls-grants gate reports held==registered.
- [ ] FR-5: `migrations/178_api_data_grants_narrowing.down.sql` restores the exact pre-178 grant state (the 174 verb sets) for every touched relation.
- [ ] FR-6: `verify/178_api_data_grants_narrowing.sql` emits `check_name`/`bad` rows covering every revoked-role verb → 0 and every kept grant → held, including `has_column_privilege` rows for each `users` census column and a `has_table_privilege('authenticated','users','UPDATE')` negative row.
- [ ] FR-7: `runtime_mint_intent` and `dsar_export_audit_pii` are untouched (already narrow); no edit to `174_api_data_grants_snapshot.sql` (it is the generated baseline OVERRIDES diverges from).

### Non-Functional Requirements

- [ ] NFR-1: Zero observable prd behavior change on the enumerated live paths — the four authenticated SELECT surfaces, the `users` column-update surfaces, and all SECURITY DEFINER RPC write paths (security: the change removes privilege, adds none beyond re-grants matching current use).
- [ ] NFR-2: No new table, policy, or RPC created; no change to RLS policies (PR #11224's layer — merge-order independent).
- [ ] NFR-3: NFR register assessment — `knowledge-base/engineering/architecture/nfr-register.md`: the affected register entries are authz/data-isolation rows; this change strengthens them (assessed, no register edit needed).

### Quality Gates

- [ ] QG-1: `test/supabase-migrations/178-api-data-grants-narrowing.test.ts` shape test green (conventions pinned: to_regclass preconditions, REVOKE-before-GRANT ordering, verify row-per-relation).
- [ ] QG-2: `bash apps/web-platform/scripts/lint-migration-api-grants.sh --from-pr-diff` green.
- [ ] QG-3: `RLS_FUZZ_LOCAL=1` fuzz gate green on a replayed stack; `run-verify.sh` all `bad=0`.
- [ ] QG-4: Census evidence (Note A + Note C greps) recorded in the PR body — reviewer can replay the greps.
- [ ] QG-5: No file collision with open PR #11224 (`176_*`, `test/rls-fuzz/rpc-cases.ts`, `dev-ledger-parity.test.sh` untouched) or #11115 (`177_*` — our number is 178).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the corpus applied through 178, when `has_table_privilege('anon','public.api_keys',verb)` is probed over all 8 TABLE_VERBS, then every verb returns false — `integration` (fuzz gate + verify row).
- Given 178 applied, when `has_table_privilege('authenticated','public.dsar_export_jobs','SELECT')` and `('…','UPDATE')` are probed, then SELECT=true, UPDATE=false — `integration`.
- Given 178 applied, when `has_column_privilege('authenticated','public.users','onboarding_completed_at','UPDATE')` is probed per census column, then all true while `has_table_privilege('authenticated','users','UPDATE')` is false — `integration`.
- Given `recordKbSyncHistory` invoked on a narrowed stack, when the tenant client writes a `{date,count}` row, then it lands via `append_kb_sync_row` (Sentry-clean, row present capped at 14) — `integration`.
- Given `178.down.sql` applied, when verify/174's grant rows are re-probed, then the pre-178 posture is restored for all eight relations — `integration`.
- Given a fresh replay stack missing `flag_flip_audit`, when 178 applies, then the file completes without error (to_regclass skips) — `integration`.

### Regression Tests

- Given a user JWT (authenticated), when `GET /api/services` and the audit/privacy pages query their tables, then responses still succeed post-178 — `integration`.
- Given `use-onboarding`'s `updateUserField` on each of the three dismissal columns, when the browser client updates, then no 42501 — `integration`.
- Given `/api/team-names` nudge dismiss, when the cookie client updates `nudges_dismissed`, then no 42501 — `integration`.

### Edge Cases

- Given a SECURITY INVOKER helper discovered in the Note C census that writes `users` as authenticated, when it is found, then its columns join the census or it is rerouted — never silently broken — `unit` (census checklist).
- Given two rapid `recordKbSyncHistory` calls, when the RPC path is used, then the row-level lock preserves both appends (the direct-update lost-update race the RPC was built to kill) — `integration`.

### Integration Verification (for `soleur:qa`)

- **API verify (grant state):** `RLS_FUZZ_LOCAL=1 npx vitest run apps/web-platform/test/rls-fuzz/rls-grants.integration.test.ts` expects held==registered for all eight relations.
- **Verify file:** `cd apps/web-platform && doppler run -c dev -- bash scripts/run-verify.sh` (globs `supabase/verify/*.sql`, runs each against `DATABASE_URL`) expects every row in `verify 178_*` group `bad=0` — verified 2026-10-26: `run-verify.sh` takes no file argument.

## Success Metrics

- Zero `has_table_privilege`/`has_column_privilege` surprises on the eight relations (verify/178 + fuzz gate green).
- Zero 42501 events on the enumerated live read/update surfaces post-deploy (Sentry-quiet on `feature=session-sync`, services, audit, privacy routes).
- `table-grants.ts` OVERRIDES count grows by 7 (one per narrowed relation; `dsar_export_audit_pii` already covered) — the registry becomes the stated intent, not just the snapshot.

## Dependencies & Prerequisites

- **Migration number 178** — `176` is claimed by open PR #11224 (different layer: RLS policy subqueries on `users`; no file overlap — it touches `rpc-cases.ts`, we touch `table-grants.ts`). `177` is claimed by open WIP PR #11115 (`177_egress_audit_summary_rpc`). Next free = **178**. Re-verify at implementation time (`git ls-tree` + `gh pr list` sweep) — claim the next free if 178 is taken by then.
- **PR #11224 adjacency** — it rewrites `users` RESTRICTIVE policies. GRANTs and POLICYs are independent Postgres layers; the changes commute, but whichever lands second should re-run its verify file against the merged corpus.
- **`dsar_export_audit_pii` already narrowed by 175** — the issue's list is partially stale; no-op row retained for audit completeness.
- **`scripts/dump-api-grants.ts`** exists for regenerating a snapshot if a future flip needs one — not needed here.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| Census misses an authenticated write path on `users` → 42501 on a live flow | Note C makes the census a gated implementation step with named greps; verify/FR-3 pins minimum columns; `recordKbSyncHistory` rerouted through `append_kb_sync_row` (017's RESTRICTIVE policy makes a column grant dead-on-arrival). |
| `_schema_migrations` has an unseen service-role reader (e.g., a dashboard probe) | Note A requires re-grepping all readers before choosing INTERNAL vs `service_role`-only; verify file asserts whichever target is chosen. |
| A future table/migration re-widens grants silently | The registry's catalog⇔registry parity is self-tracking — an unregistered grant reds the fuzz gate; OVERRIDES provenance strings cite this issue. |
| Merge-order interaction with #11224 (users policies) | Independent layers; noted in Dependencies; whichever merges second re-runs verify. |
| `recordKbSyncHistory` reroute semantics diverge (append-only vs rewrite-trim) | The RPC's `p_cap: 14` reproduces `.slice(-14)`; both writers already append `{date,count}`-shaped and `KbSyncRow`-shaped entries to the same JSONB array (053/100 comments confirm coexistence). |

## Future Considerations

- Full-catalog pass: the issue names eight relations; a follow-up could census the remaining ~54 snapshot relations on the same criteria (each already in the registry, so the gate would catch drift — but an intent review per relation is open scope).
- Column-level `SELECT` on `api_keys` (exclude `encrypted_key`/`iv`/`auth_tag` from authenticated reads) — the deeper narrowing deferred from Alternatives.
- `flag_flip_audit` → `INTERNAL` (zero api-role grants including service_role) if the service-role PostgREST debugging path is judged worthless — kept service_role here per the 175 convention.

## Documentation Plan

- Migration header comment carries the per-relation evidence one-liners (175 convention).
- OVERRIDES provenance strings cite migration 178 + #11193 (the durable intent record — the registry, not this plan, is what a future engineer reads).
- No ADR needed: ADR-303 §Consequences already defers this exact work to #11193 — executing a documented deferral is not a new architectural decision (checked `decisions/` for grant/RLS corpus: ADR-112, ADR-303, ADR-153; none diverged).

## Research Insights

**Premise Validation (Phase 0.6).** Checked: issue #11193 OPEN; PR #11180 MERGED 2026-10-26; migration 174 + registry + fuzz gate + verify convention all present on `origin/main`; migrations 006/049 exist; #4027 OPEN (`runtime_mint_intent` already narrowed via 049 — coordinate only). **Stale finding:** the issue lists `dsar_export_audit_pii` among tables holding "full default-era grants to anon/authenticated" — migration **175** (`175_tom4_shape_iv_client_grant_revokes`, already on main) revoked those exact grants; it is already `service_role`-only with an OVERRIDES entry. Plan treats it as a no-op verification row. Second stale-adjacent nuance: the `users` wart is *load-bearing* on prd — `hooks/use-onboarding.ts` (browser client), `app/api/team-names` (cookie client), and `server/session-sync.ts` (tenant client) all write `users` columns beyond `email` through it; narrowing requires the column census + the session-sync reroute, not a bare revoke.

**Property List (0.6b).** P1: the eight named relations hold only evidence-justified api-role verbs. P2: no enumerated live client path breaks. P3: the intended posture is encoded in `table-grants.ts` so the fuzz gate self-tracks drift. P4: the change is rollbackable (down file restores the 174 posture). P5: per-relation evidence is recorded where the next engineer reads it (migration header + OVERRIDES provenance).

**Cut List (0.6b).** No proposed mechanism cut — the ask's own mechanism (migration + registry update) IS the existing-mechanism path (175 proved it end-to-end); no new guard, lint, or tooling is introduced. Rejected alternatives recorded above.

**Key file paths.** `apps/web-platform/supabase/migrations/{174,175}_*.sql` (baseline + narrowing pattern); `apps/web-platform/supabase/verify/175_*.sql` (check_name/bad contract); `apps/web-platform/test/rls-fuzz/{table-grants.ts,rls-grants.integration.test.ts}` (registry + authoritative gate); `apps/web-platform/scripts/{lint-migration-api-grants.sh,run-verify.sh,dump-api-grants.ts}`; `apps/web-platform/hooks/use-onboarding.ts:73-85` (browser `users` UPDATE); `apps/web-platform/server/session-sync.ts:587` + `:692` (direct update vs `append_kb_sync_row` RPC); `apps/web-platform/lib/supabase/{server,client,tenant,service}.ts` (client-role bindings); `apps/web-platform/supabase/migrations/{006,053,071,100,037,041,052}_*.sql` (intent + RPC provenance).

**Institutional learnings applied.** `learnings/2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md` (sibling queries are the silent backdoor → the Note C census enumerates every `.from("users")` write, not just helpers); `learnings/2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md` (RESTRICTIVE policy + column grant — the exact failure mode that birthed `append_kb_sync_row` and that this plan's census must respect); `learnings/2026-03-20-supabase-column-level-grant-override.md` (column-level grant semantics under table-level revoke — governs the `users` REVOKE-then-column-GRANT ordering); ADR-303's own warning that narrowing must not ride a remediation banner (#4647 silent-failure class → honest per-relation blocks, verify on apply); ADR-112's two-tier guard split (registry authoritative, lint subordinate — both stay green).

**External research.** Skipped — security-adjacent but fully repo-bounded: the grant semantics (`has_table_privilege`, REVOKE/GRANT interaction, SECURITY DEFINER) are exercised and documented by 174/175 in-repo; nothing here depends on external APIs or novel patterns.

**CLAUDE.md conventions.** Migration corpus conventions observed: `NNN_name.sql` + `NNN_name.down.sql` + `verify/NNN_name.sql` + `test/supabase-migrations/NNN-name.test.ts`; `DO $$ to_regclass` preconditions; no transaction control inside files (runner wraps).

## References & Research

### Internal References

- ADR-303 (`knowledge-base/engineering/architecture/decisions/ADR-303-*.md`) — defers this narrowing to #11193 verbatim.
- ADR-112 — two-tier definer/grant guard split this registry mirrors.
- `supabase/migrations/175_tom4_shape_iv_client_grant_revokes.sql` — the narrowing template this migration clones.
- `supabase/migrations/006_restrict_tc_accepted_at_update.sql` — the `users` intent this restores.

### Related Work

- Issue #11193 (this work), #4027 (sibling `runtime_mint_intent` narrowing — do not duplicate), PR #11180 (merged, 174 snapshot), PR #11224 (open, users policies — coordinate), PR #11115 (open WIP, holds migration 177).

### Non-Goals

- Census/narrowing of the ~54 snapshot relations not named in the issue (Future Considerations).
- RLS policy changes (PR #11224's layer).
- Sequence grants, function EXECUTE grants (different registry/lint surfaces).
- Any change to `174_api_data_grants_snapshot.sql`.
