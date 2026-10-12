---
issue: 4709
ref: 4702
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
related_prs: [4704, 4679]
---

# fix: template auto-revoke (expired/quota_exhausted) always 42501s — authed caller hits founder-attribution gate

> Source issue: [#4709](https://github.com/jikig-ai/soleur/issues/4709) (OPEN, `type/bug`, `domain/engineering`). Refs #4702 (CLOSED). Surfaced by review of PR #4704 (MERGED 2026-05-31, commit `958b4c68`).
> Change-class: **application code + SQL migration** under `apps/web-platform/`. NOT a knowledge-base/plugin change.

## ⚠️ Planning-process note (read first)

Two earlier drafts were wrong and are discarded:

1. **Draft 1** mis-diagnosed the repo as knowledge-base-only and concluded the code "lives in another repository." False — the code is in this repo (truncated grep output caused the error).
2. **Draft 2** inherited the issue body's claim that auto-revoke runs as a *"service-role auto-revoke side effect."* **Also false.** Source reads confirm `autoRevoke` passes the **same authenticated request `client`** the route created. There is no service-role client in this chain.

All facts below come from **direct file reads** (the bash/grep layer was intermittently degraded at plan-write time; file-Read is authoritative). Re-confirm line numbers at /work Phase 0 per `hr-always-read-a-file-before-editing-it`.

## Overview

`revoke_template_authorization`'s **auto-revoke** side-effect can never persist a revocation — it always fails with PostgreSQL `42501` (insufficient privilege) at the founder-attribution gate, independent of the WORM-bypass GUC.

When the send-gate predicate detects an authorization is `expired` or `quota_exhausted`, `isTemplateAuthorized` calls `autoRevoke(client, hash, reason)` to persist `revoked_at` / `revocation_reason`, so the scope-grants UI does not render dead-but-active "lying rows." That persistence never happens: the call uses an **authenticated** Supabase client, so `auth.uid()` is non-NULL inside the RPC, and the founder-attribution gate (migration 053, preserved verbatim in 088) raises `42501` for any authenticated caller whose `p_reason <> 'founder_revoked'`.

## Verified caller chain (from file reads)

1. `app/api/dashboard/today/[id]/send/route.ts:82` — `const supabase = await createClient()` (authenticated SSR client: anon key + founder JWT, from `@/lib/supabase/server`). Route comment L101-103 explicitly: *"Service-role NOT used."*
2. `route.ts:189` → `runTemplateGate({ supabase, ... })`.
3. `server/templates/run-template-gate.ts:90` → `isTemplateAuthorized(supabase, founderId, templateHash, grantId)` (the authenticated client threaded straight through).
4. `server/templates/is-template-authorized.ts:155` and `:160` → `void autoRevoke(client, templateHash, "expired" | "quota_exhausted")`.
5. `is-template-authorized.ts:180` → `client.rpc("revoke_template_authorization", { p_template_hash, p_reason })` — same authenticated `client`.

## The gate (verified, migration 088 L147-150 ≡ migration 053 L347-350)

```sql
IF auth.uid() IS NOT NULL AND p_reason <> 'founder_revoked' THEN
  RAISE EXCEPTION 'revoke_template_authorization: authenticated callers must use reason=founder_revoked (got %)', p_reason
    USING ERRCODE = '42501';
END IF;
```

Because the client is authenticated, `auth.uid()` is non-NULL; `autoRevoke` passes `'expired'`/`'quota_exhausted'`, so this raises **before** `SET LOCAL app.worm_bypass = 'on'`. PR #4704 / migration 088 (the `session_replication_role -> app.worm_bypass` swap) does **not** fix this — the failure is upstream of the bypass. 088 header L103-106 confirms it preserves "the authenticated-session guard, the full 8-value p_reason enum gate, and the founder-attribution gate ... only the bypass GUC changes."

## Multi-clause predicate — restate every operand

- **Operand A — `auth.uid() IS NOT NULL`**: TRUE for the authenticated SSR client (the auto-revoke path); FALSE only under a service-role/`postgres` connection.
- **Operand B — `p_reason <> 'founder_revoked'`**: TRUE for `'expired'`/`'quota_exhausted'`; FALSE for `'founder_revoked'`.
- **Conjunction**: raises iff **A AND B**. Founder-driven revoke → A=true,B=false → works. Auto-revoke → A=true,B=true → **always raises** (the bug). Each candidate fix breaks exactly one operand.

**Full `p_reason` enum (8 values, verified 053 L325-329 / 088 L125-129):** `founder_revoked`, `quota_exhausted`, `expired`, `dsr_erasure`, `regulator_ordered`, `vendor_tos_revoked`, `policy_violation`, `quarantine_retroactive`. Comment 053 L334-346 states `'quota_exhausted'`/`'expired'` are *"reserved for service-role / postgres callers"* — i.e., auto-revoke was DESIGNED to run with a NULL `auth.uid()`. The code never did. This confirms Approach 1 matches original intent.

## Grant reality (changes the trade-off — verified 088 L171-174)

```sql
REVOKE ALL ON FUNCTION public.revoke_template_authorization(text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_template_authorization(text, text)
  TO authenticated;
```

`service_role` is explicitly **REVOKE'd**; only `authenticated` is granted. So **Approach 1 (call via service-role client) ALSO requires a migration** to `GRANT EXECUTE ... TO service_role`. Approach 1 is NOT migration-free — this narrows its "smaller diff" advantage.

## Impact

Low / latent today: `autoRevoke` is fire-and-forget (`void autoRevoke(...)`; errors only `warnSilentFallback` at `is-template-authorized.ts:189,197`), so no user-facing 500, and read-time denial is still correct. But the migration COMMENT's design intent ("so the scope-grants UI does not display lying rows", 053 L376-378 / 088 L178-180) is silently unmet, and every scope-grants read re-fires the failing RPC. Threshold `single-user incident`: the surface is the credential/authorization lifecycle, with a user-visible scope-grants UI showing stale "active" state for dead grants.

**Provenance:** Pre-existing — predates #4702 / #4679. The founder-attribution gate landed in migration 053 (PR-I #4078); the authenticated auto-revoke caller predates it. **Not introduced or regressed by PR #4704** (`958b4c68`) — 088 is a verbatim GUC-swap mirror of 087 that preserves the gate.

## Research Reconciliation — Issue Body vs. Codebase

| Issue-body / draft claim | Verified reality | Plan response |
| --- | --- | --- |
| Repo is KB-only (draft 1) | False — `apps/web-platform/**` present | discarded |
| "service-role auto-revoke side effect" (issue body + draft 2) | False — `autoRevoke` uses the authenticated request `client` (`is-template-authorized.ts:155-180`; route L101-103) | Approach 1 must *introduce* both a service-role client AND a `service_role` grant |
| Gate raises `42501` for authed non-`founder_revoked` | Confirmed (088 L147-150) | load-bearing; both fixes target it |
| 088 verbatim mirror of 087 GUC swap | Confirmed (088 header L103-106); PR #4704 MERGED `958b4c68` | non-regression of #4704 |
| `p_reason` enum size | 8 values (verified) | grant (A) / carve-out (B) must respect all 8 |
| service_role can call the RPC | False — REVOKE'd (088 L171-174) | Approach 1 needs a grant migration |
| already-revoked rows re-fire autoRevoke | False — `is-template-authorized.ts:146` returns `template_revoked` early before autoRevoke; RPC also guards `WHERE revoked_at IS NULL` | idempotency already holds; add a regression test, no new guard |
| no existing test harness | False — `test/server/templates/is-template-authorized.test.ts:181,212` already spies on `revoke_template_authorization` via `rpcSpy` | extend that test for the RED regression |

## Proposed Solution — needs a security design decision

The founder-attribution gate exists deliberately (PR-I `user-impact-reviewer` FINDING 1, 053 L334-346) to stop an authenticated founder from stamping arbitrary `p_reason` values on their OWN rows (RLS already blocks cross-tenant; this protects the founder's own audit-trail attribution). **The Approach 1 vs 2 choice is the open security decision this plan surfaces for CPO + CTO sign-off.**

### Approach 1 — call auto-revoke through a service-role client (matches original design intent)

`autoRevoke` uses a service-role client (`createServiceClient`/`getServiceClient` from `lib/supabase/service.ts`) for the `revoke_template_authorization` RPC only. Under `service_role`, `auth.uid()` is NULL → Operand A false → gate's authenticated branch does not fire.

- **Requires a migration** to `GRANT EXECUTE ... TO service_role` (currently REVOKE'd).
- **Requires a `.service-role-allowlist` entry** for the new importer — and that file is **CODEOWNERS-pinned (`@jeanderuelle` approval required)** per its header. So Approach 1 has a human-approval gate beyond CPO/CTO.
- **SHARP EDGE (load-bearing):** the RPC's UPDATE is `WHERE founder_id = v_founder_id ... ` with `v_founder_id := auth.uid()`. Under service role `auth.uid()` is NULL → the WHERE matches nothing → **silent zero-row no-op** (bug persists, just without the 42501). Approach 1 must therefore ALSO add a `p_founder_id` parameter / new overload and thread the founder id — making the migration larger than it first appears.
- Pros: matches the "reserved for service-role / postgres callers" intent. Cons: service-role in the `send` hot path; CODEOWNERS gate; the zero-row sharp edge erodes its simplicity.

### Approach 2 — narrow carve-out in the RPC for self-owned expired/exhausted rows

Keep the authenticated client. In the RPC, allow `'expired'`/`'quota_exhausted'` from the founder's own authenticated session ONLY when the RPC **re-derives expiry/quota server-side** for the caller's own row (never trust the passed reason). `auth.uid()`-scoped `WHERE founder_id = v_founder_id` keeps working unchanged.

- Pros: keeps the request-scoped (RLS-bounded) client; no service-role in the hot path; no CODEOWNERS-pinned allowlist change; the `founder_id = v_founder_id` UPDATE keeps working. Cons: new migration + RPC logic; must re-derive expiry (read `expires_at`) and quota (count `action_sends` vs `max_sends`) server-side to avoid re-opening the spoofing hole; precedent-diff the `SECURITY DEFINER` + `app.worm_bypass` bracket against 088.

**Recommendation lean (planner, non-binding):** Approach 2 — it avoids the zero-row sharp edge and the CODEOWNERS-pinned allowlist gate, at the cost of more SQL. **Decision is CPO + CTO's at sign-off**, not the planner's; record it before any code.

## Files to Edit

- `apps/web-platform/server/templates/is-template-authorized.ts` — `autoRevoke` (Approach 1: swap to service-role client + thread founder_id; Approach 2: unchanged call — fix is in SQL).
- `apps/web-platform/supabase/migrations/089_template_auto_revoke_fix.sql` + `089_template_auto_revoke_fix.down.sql` — **both approaches need a migration** (verified next number is 089; current max is 088). Approach 1: `GRANT ... TO service_role` + `p_founder_id` overload. Approach 2: carve-out + server-side re-derivation.
- (Approach 1 only) `apps/web-platform/.service-role-allowlist` — add the new call site (CODEOWNERS-pinned; needs `@jeanderuelle`).
- `apps/web-platform/test/server/templates/is-template-authorized.test.ts` — extend the existing `rpcSpy` test (L181/L212) into a true persistence regression.
- Possibly `apps/web-platform/test/server/template-authorizations-worm.test.ts` (L455-475 already exercises the RPC against tenants) — add the auto-revoke persistence + anti-spoof cases.

## Files to Create

- The 089 migration + down-migration.
- Any new regression test file if the existing ones don't fit (runner: vitest `test/**/*.test.ts` per `vitest.config.ts:44`; do NOT co-locate).

## Implementation Steps

1. [x] **/work Phase 0 — re-read & re-verify.** Read all six files; re-confirmed line numbers (autoRevoke L155/L160/L174-204; RPC + gate in 088); confirmed 089 is free (max = 088); no divergence from main; `.service-role-allowlist` EXISTS; `createServiceClient`/`getServiceClient` present in `lib/supabase/service.ts`; open-code-review query → no overlap with `is-template-authorized.ts` / migration 089 / `revoke_template_authorization`.
2. [x] **CPO + CTO sign-off — DECISION: Approach 2** (narrow RPC carve-out; re-derive expiry/quota server-side). Recorded 2026-05-31.
   - **CTO** (binding constraints): re-derive never trust; preserve the gate's 42501 for ALL other non-`founder_revoked` reasons; keep `WHERE founder_id = v_founder_id` (no COALESCE-to-self degradation); WORM bracket + `search_path` + SECURITY DEFINER parity with 088; **overload via CREATE OR REPLACE, same `(text,text)` signature — no DROP+CREATE, no grant churn**; `>=` quota boundary parity with `is-template-authorized.ts:152`; mandatory anti-spoof RED test (authed `expired` on non-expired row → 42501; under-quota `quota_exhausted` → 42501; `policy_violation` → 42501; genuinely-expired → persists affected=1).
   - **CPO**: scope = "make scope-grants UI truthful", no creep (NO revocation-UI redesign, NO founder notifications, NO historical backfill — backfill is a separate follow-up). Verify self-healing-on-next-read in QA. `user-impact-reviewer` must confirm the carve-out cannot forge a reason on a still-valid row.
   - Confirmed via migration 088 read: Approach 1's `WHERE founder_id = COALESCE(v_founder_id, founder_id)` under service-role degrades to `founder_id = founder_id` (cross-tenant over-reach across founders sharing a `template_hash`), not a zero-row no-op — reinforces Approach 2.
3. [x] **RED test** — extended `test/server/template-authorizations-worm.test.ts` (SQL-level; the carve-out is in SQL so the meaningful RED is DB-level, not the mocked unit test). RED confirmed pre-089: 3 fix tests (expired-persists, quota-persists, idempotency) failed with 42501; 6 preservation tests passed.
4. [x] **Implemented Approach 2** — `089_template_auto_revoke_carveout.sql` + `.down.sql`. No TS change (`is-template-authorized.ts` keeps the authenticated client; fix is entirely in SQL per CTO constraint). Applied to DEV; GREEN = 20/20.
5. [x] **Fire-and-forget + observability preserved** — `void autoRevoke(...)` and `warnSilentFallback` (→ Sentry) unchanged in `is-template-authorized.ts`.
6. [x] **Idempotency confirmed** — test "auto-revoke is idempotent (second call is a no-op, no throw)" passes; `WHERE revoked_at IS NULL` + `COALESCE` hold; no new guard.
7. [x] **Founder-driven revoke unchanged** — `revoke(founder_revoked)` test passes; authed non-`founder_revoked`/non-carve-out reasons (e.g. `policy_violation`) still 42501.
8. [x] **Scope-grants UI stops lying** — an expired/exhausted row now persists `revoked_at` on the next gate evaluation (self-healing-on-next-read; CPO asked to verify in QA).

## Testing Strategy

- **RED regression (required):** post-gate, `revoked_at` non-NULL + `revocation_reason='expired'` (and `'quota_exhausted'`), parametrized; affected>0.
- **Security intact:** authed session still cannot stamp an arbitrary `p_reason` (e.g., `'policy_violation'`) → still `42501`; founder `'founder_revoked'` path still succeeds.
- **(Approach 2) anti-spoof:** a passed `'expired'` on a NON-expired / under-quota row owned by the caller is rejected (RPC re-derives state).
- **(Approach 1) no zero-row no-op & no widening:** assert the service-role client is used ONLY for this RPC, founder_id is threaded so the UPDATE matches the founder's row (affected>0), and no other call uses service role.
- **Idempotency:** auto-revoke twice → second = 0-row no-op success.
- **DEV only; synthesized fixtures** (`hr-dev-prd-distinct-supabase-projects`, `cq-test-fixtures-synthesized-only`). Runner = configured vitest (`./node_modules/.bin/vitest run`), not hardcoded `bun test`.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **Re-inheriting the "service-role side effect" premise.** | Verified caller chain + sharp edge documented; Phase 0 re-reads files. |
| **Approach 1 silent zero-row no-op** (`auth.uid()` NULL vs `founder_id = v_founder_id`). | Add `p_founder_id` overload; test asserts affected>0. |
| Approach 1 service-role leak / skips CODEOWNERS-pinned allowlist. | Scope to one RPC; add `.service-role-allowlist` line (needs `@jeanderuelle`); test asserts no other service-role use. |
| Approach 2 re-introduces spoofing hole. | Re-derive expiry/quota server-side; never trust `p_reason`; precedent-diff vs 088. |
| `search_path` not pinned on new/edited RPC. | `cq-pg-security-definer-search-path-pin-pg-temp`: pin `public, pg_temp` (matches 053/088); qualify relations `public.<table>`. |
| WORM bypass GUC mis-armed. | Mirror 088's `SET LOCAL app.worm_bypass='on' ... 'off'` bracket exactly. |
| Non-transactional DDL / outer BEGIN-COMMIT. | Supabase wraps each file in a txn (053 header L28-37); no `CONCURRENTLY`, no outer BEGIN/COMMIT. |
| Silent-fallback regresses to a true silent drop. | Keep `warnSilentFallback` + Sentry mirror. |
| Wrong line numbers (tool layer degraded at plan time). | Citations flagged "re-verify at Phase 0". |

## User-Brand Impact

**If this lands broken, the user experiences:** the scope-grants UI keeps showing expired / quota-exhausted template authorizations as "active" (lying rows), so a founder cannot trust the authorization list — and a wrong fix could be a silent zero-row no-op (Approach 1 without founder_id threading) or, worse, let an authenticated founder stamp arbitrary revocation reasons on rows, breaking the WORM audit-trail attribution the gate protects.

**If this leaks, the user's authorization/credential lifecycle integrity is exposed via:** a mis-scoped service-role client (Approach 1) reaching beyond the single auto-revoke RPC, or a too-broad RPC carve-out (Approach 2) accepting spoofed reasons — either weakens the founder-attribution / WORM guarantee on the `template_authorizations` audit surface (GDPR Art. 5(2) accountability).

**Brand-survival threshold:** single-user incident

**Sign-off:** `requires_cpo_signoff: true`. CPO sign-off required at plan time before `/work` (the Approach 1 vs 2 choice is the security decision). CTO co-signs (auth/RLS/SECURITY-DEFINER). `user-impact-reviewer` runs at review time per the review skill's conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: successful auto-revoke persists revoked_at + revocation_reason (RPC returns affected>0 for an expired/exhausted row)
  cadence: on each send-gate evaluation that hits an expired/quota_exhausted authorization
  alert_target: Sentry (existing warnSilentFallback -> Sentry mirror)
  configured_in: apps/web-platform/server/templates/is-template-authorized.ts autoRevoke error path (L189,197)
error_reporting:
  destination: Sentry via warnSilentFallback (from @/server/observability)
  fail_loud: user-level false (fire-and-forget, no 500); Sentry-level true (a revoke failure must surface, never silently drop)
failure_modes:
  - mode: RPC returns 42501 (current bug)
    detection: Sentry event from warnSilentFallback in autoRevoke catch
    alert_route: Sentry engineering project
  - mode: Approach 1 silent zero-row no-op (auth.uid() NULL vs founder_id WHERE)
    detection: regression test asserting affected>0; runtime would show repeated re-fires with rows_revoked=0
    alert_route: PR review + test
  - mode: service-role client mis-scoped (Approach 1)
    detection: .service-role-allowlist CI gate + test + user-impact-reviewer
    alert_route: CI allowlist gate + PR review
logs:
  where: Sentry (warnSilentFallback mirror); pino structured logs on the send route + gate
  retention: existing Sentry/log retention (no change)
discoverability_test:
  command: ./node_modules/.bin/vitest run apps/web-platform/test/server/templates/is-template-authorized.test.ts
  expected_output: the auto-revoke persistence regression test passes (revoked_at set + affected>0 for expired and quota_exhausted)
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] After the predicate evaluates an `expired` authorization, the row's `revoked_at` is non-NULL and `revocation_reason = 'expired'` (regression test `(#4709 carve-out: expired persists)`, was failing with 42501 under 088 — RED confirmed).
- [x] Same for `quota_exhausted` (`(#4709 carve-out: quota persists)`).
- [x] The RPC affects the caller's own row (`affected = 1`; Approach 2 keeps `WHERE founder_id = v_founder_id`, no zero-row no-op).
- [x] Auto-revoke is idempotent (`(#4709 carve-out: idempotent)`: second fire `affected = 0`, no throw, reason unchanged).
- [x] Founder-attribution security intact: an authenticated session still cannot stamp an arbitrary `p_reason` (`policy_violation` → `42501`); a spoofed `'expired'` on a non-expired row and `'quota_exhausted'` under quota are rejected (`42501`).
- [x] N/A — Approach 2 chosen (no service-role client, no `.service-role-allowlist` change). Cross-tenant attempt via the carve-out → `42501` (`(#4709 cross-tenant)`).
- [x] Auto-revoke remains fire-and-forget (no user-facing 500) AND failures still mirror to Sentry (`is-template-authorized.ts` `autoRevoke` unchanged — `void autoRevoke(...)` + `warnSilentFallback`).
- [x] Founder-driven revoke endpoint (`/api/template-authorizations/revoke`) unchanged and working (`(revoke happy)` test passes; `founder_revoked` path untouched).
- [x] Migration 089 (`SECURITY DEFINER`) pins `search_path = public, pg_temp`; mirrors the `SET LOCAL app.worm_bypass` on/off bracket; has a `.down.sql` (verbatim-088 restore); transaction-safe DDL; preserves all 8 `p_reason` enum values + the `RETURNS integer` signature; `088`/`revocation-reason-exhaustive` parity tests re-run green; new `089-template-auto-revoke-carveout.test.ts` shape test added.
- [x] Tests on DEV Supabase only (ref `mlwiodleouzwniehynfz`, `doppler -c dev`); fixtures synthesized; runner = configured vitest (`./node_modules/.bin/vitest`).
- [x] CPO + CTO sign-off on the chosen approach (Approach 2) recorded in the plan (Implementation Step 2).
- [x] `Closes #4709` — code+migration change; 089 applied to DEV in-session, applied to prd by the canonical `web-platform-release.yml#migrate` pipeline at merge (`wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- [ ] Migration 089 applied via the canonical web-platform migration path (`web-platform-release.yml#migrate` — confirm exact mechanism at ship time; do NOT prescribe SSH, `hr-no-ssh-fallback-in-runbooks`). Verify read-only that the RPC/grant exists (`pg_proc` / `information_schema.role_routine_grants`), not by creating synthetic rows on prod (`hr-dev-prd-distinct-supabase-projects`).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — sign-off)

### Engineering (CTO)

**Status:** carry-forward (auth/RLS/SECURITY-DEFINER decision)
**Assessment:** A privilege/attribution decision on a `SECURITY DEFINER` RPC guarding a WORM audit surface. CTO co-signs Approach 1 vs 2. Constraints: no service-role widening; `.service-role-allowlist` CODEOWNERS gate (Approach 1); `search_path` pin + `app.worm_bypass` bracket parity with 088; server-side expiry/quota re-derivation if a carve-out (Approach 2). Note the SHARP EDGE: Approach 1's `founder_id = v_founder_id` clause needs `auth.uid()` (NULL under service role) → likely forces a `p_founder_id` overload, eroding Approach 1's simplicity. Planner lean: Approach 2.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no new user-facing surface; the scope-grants UI already exists — the fix makes it truthful)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

No new UI. The user-visible effect is that already-rendered scope-grants rows stop lying. `user-impact-reviewer` runs at review time per the single-user-incident threshold.

## Open Code-Review Overlap

Not verified at plan time (bash tool layer degraded). **/work Phase 0 MUST run** `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/r.json` then `jq` each Files-to-Edit path per plan Phase 1.7.5, and record fold-in/acknowledge/defer before coding.
