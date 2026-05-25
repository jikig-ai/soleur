---
title: "feat: Admin revoke_jti RPC + my_revocation_status reader + PostgREST RLS jti-deny predicate (#3930 + #3932)"
type: feat
date: 2026-05-25
status: ready-for-deepen
issue: 3930
co_closes: 3932
predecessor_pr: 3922
umbrella_issue: 3244
branch: feat-one-shot-jti-revoke-rls-3930-3932
worktree: .worktrees/feat-one-shot-jti-revoke-rls-3930-3932/
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat — Admin revoke_jti RPC + my_revocation_status reader + PostgREST RLS jti-deny predicate (#3930 + #3932)

## Overview

Bundle two P2 deferred-scope-outs from PR-E (#3922, merged 2026-05-16). They share the same surface (the `denied_jti` table + `is_jti_denied` reader from migration 037 + the `RuntimeAuthError("denied_jti", …)` discriminator at `apps/web-platform/lib/supabase/tenant.ts`) and are co-located in one PR because:

1. **Same migration file.** Both ship `SECURITY DEFINER` RPCs + an RLS predicate over `denied_jti` / tenant tables; one migration is cheaper than two for sequencing + rollback.
2. **Same JWT-deny semantics.** Issue #3930's `revoke_jti` is the *writer* surface; issue #3932's RLS predicate is the *cross-process reader* surface. Both make sense only when paired — a `revoke_jti` RPC without RLS enforcement closes only the in-Node-process kill-switch (PR-E already did that at the `getFreshTenantClient` boundary); the RLS predicate without an authenticated writer reduces the deny-list to operator-only SQL forever.
3. **Same Sentry/Article 30 disclosure surface.** Both surfaces emit to the same `is_jti_denied.deny` / `is_jti_denied.error` mirror feature already declared by PR-E; neither expands the personal-data surface (jti = random UUID; founder_id already in PA1 scope).

This plan closes:

- **#3930** — `revoke_jti(p_jti, p_founder_id, p_reason)` admin RPC + `my_revocation_status()` founder-readable RPC.
- **#3932** — `is_jti_denied(current_setting('request.jwt.claims', true)::jsonb->>'jti')` predicate added as an additional `USING` clause to every tenant-table RLS policy (19 tables, post-mig 059).

The plan does NOT introduce a new admin role surface. Per Phase 0.3 (admin-auth model selection), the `revoke_jti` writer is **service-role-only** at v1 (operator wraps it from `apps/web-platform/scripts/revoke-jti.ts` invoked through a Doppler-token-bound service client). A future admin UI is filed as a separate follow-up at the close of this PR's body. Rationale: introducing an `admin` role would force changes to `users.role` (currently a 2-value enum `{prd, dev}` per mig 054), the JWT-mint hook, AND a new auth-tier surface — all of which deserve their own design cycle. Service-role-with-script is the minimum credible writer to retire the "operator-runs-INSERT-via-SQL-Editor" pattern without re-architecting auth.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from issue body) | Reality at HEAD | Plan response |
|---|---|---|
| "admin RPC restricted to a new `admin` role" (#3930) | `users.role` is `{'prd', 'dev'}` only per `054_users_role_column.sql:13`. No `admin` role exists in DB, JWT-mint hook, or app code. | v1 scopes `revoke_jti` to **service_role only** (REVOKE FROM authenticated + GRANT EXECUTE TO service_role); operator invocation via `apps/web-platform/scripts/revoke-jti.ts` reading `SUPABASE_SERVICE_ROLE_KEY` from Doppler. New admin role + admin UI deferred per scope-out criterion — sub-issue filed at PR close. |
| "Mirrors to Sentry / audit log so admin actions leave a trace" (#3930) | PR-E already emits `is_jti_denied.deny` and `is_jti_denied.error` via `mirrorWithDebounce` at `tenant.ts`. No revocation-issuance mirror exists. | New `revoke_jti.issued` Sentry breadcrumb emitted from `scripts/revoke-jti.ts` (Node-side, not DB-side); the RPC writes the `denied_jti` row inside a `SECURITY DEFINER` body and the script post-call emits to Sentry. WORM-trace is the `denied_jti` row itself (jti, founder_id, denied_at, reason). |
| "`my_revocation_status()` SECURITY DEFINER, returns `{ revoked: bool, denied_at, reason }` for the calling `auth.uid()`" (#3930) | Sibling precedent: `check_my_revocation(p_jwt_iat timestamptz)` in `067_workspace_member_revocation_lookup.sql:63-94` returns `TABLE(revoked boolean, workspace_id uuid, reason text)` with an explicit `auth.uid() IS NULL → RAISE 28000` guard. | Mirror the 067 shape exactly: `RETURNS TABLE(revoked boolean, denied_at timestamptz, reason text)`, 28000 raise on NULL caller, REVOKE+GRANT to authenticated. DOES NOT return `jti` (jti enumeration side-channel mitigation per #3930). |
| "`is_jti_denied(jti)` as USING predicate on every RLS policy on every tenant table" (#3932) | 19 tables have ≥1 RLS policy at HEAD. The post-mig-059 sweep uses `public.is_workspace_member(workspace_id, auth.uid())` as the workspace-keyed predicate. None currently consult `request.jwt.claims->>'jti'`. | Add a single new **RESTRICTIVE** policy per table (does not replace existing PERMISSIVE policies) — `AS RESTRICTIVE USING (NOT public.is_jti_denied( (current_setting('request.jwt.claims', true)::jsonb->>'jti')::uuid ))`. RESTRICTIVE policies are AND-combined with existing PERMISSIVE policies in Postgres RLS — see "Risks & Mitigations §RLS combination semantics" below. |
| "PR-E's deny-list consumer enforces only at the Node-process-local JWT-mint boundary inside `getFreshTenantClient`" (#3932 problem statement) | Verified at `lib/supabase/tenant.ts` `denyProbe` (cache-hit at `~line 595` and cache-miss at `~line 405`). Confirmed `is_jti_denied` reader is currently invoked ONLY from Node, never from any RLS predicate. | Plan adds RLS-side consumer in mig 068. Node-side consumer stays — defense-in-depth, plus the deny-probe at JWT-mint also bounds cost (Node-side caching means fewer round-trips than per-PostgREST-query). |
| "PR-E shipped 7 deferred-scope-out follow-ups including #3928-#3934" (compliance-posture.md) | All 7 issues exist + open + labelled `deferred-scope-out`. | This plan closes 2 of 7 (#3930 + #3932). #3928 (TTL sweep), #3929 (per-sub-call audit), #3931 (deny-RPC cache), #3933 (in-flight client invalidation), #3934 (synthetic-fixture sweeper) stay open per their re-evaluation triggers. |

## Hypotheses

This plan does NOT address an SSH/network-connectivity surface; the network-outage checklist (Phase 1.4) does not apply.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident`. Carry-forward from PR-B → PR-C → PR-D → PR-E. The JWT-deny-list + tenant-RLS surface is the same auth-deny posture all four predecessors carried.

**If this lands broken, the user experiences:**

- A founder hit by `RuntimeAuthError("denied_jti", …)` on a fresh (un-revoked) JWT — false-positive on the RLS predicate (e.g., `current_setting('request.jwt.claims', true)::jsonb->>'jti'` returns NULL inside a SECURITY DEFINER body where the JWT claim context is not propagated). Founder loses access to every tenant table at once until an operator deletes the deny row or rotates the JWT secret. **OR**
- A founder calls `my_revocation_status()` expecting `{revoked: false, …}` but the RPC returns NULL/raises because of search_path misconfiguration or NULL `auth.uid()` under a stolen service-role context; the in-product status panel shows a broken state and shakes founder trust mid-incident. **OR**
- An operator invokes `scripts/revoke-jti.ts` against a Doppler config bound to dev Supabase instead of prd; the deny-list row lands in the wrong project and the actual stolen JWT remains active in prd. Same vector as `hr-dev-prd-distinct-supabase-projects`.

**If this leaks, the user's data / workflow / money is exposed via:**

- A stolen JWT used **directly against PostgREST from outside this Node process** (the canonical "stolen / leaked / replayed bearer token" threat model named in PR-E §User-Brand Impact residual table — vector explicitly tracked at #3932) continues to authorize reads/writes against tenant tables (`conversations`, `messages`, `api_keys`, `audit_byok_use`, `messages`, …) for the JWT's full 10-min TTL even *after* an operator inserts a deny-list row. PR-E's Node-side consumer mitigated the in-Node attack surface; this plan closes the cross-process surface. **OR**
- The new `revoke_jti` writer has a `founder_id`-mismatch bug (e.g., race between revoke-issuance and `denied_jti` FK to `users(id)`) and an operator's targeted revocation hits the wrong founder; the wrong founder loses access (denial of service) while the actual compromised JWT stays live.

**Founder-visible signal:** When this plan closes the cross-process JWT-deny surface, the founder's protection profile changes invisibly — there is no UI surface for #3932 itself; the deny-list reader fires inside Postgres. The `my_revocation_status()` reader from #3930 is the founder-readable companion that surfaces "your most recent session was revoked, reason = X" when a denial fires (replacing the current generic "Authentication unavailable; retry shortly" toast).

## Open Code-Review Overlap

To be re-verified at deepen-plan time after Phase 2 `## Files to Edit` is finalised. Pre-check:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
# Files touched (preliminary): apps/web-platform/supabase/migrations/068_*.sql, apps/web-platform/lib/supabase/tenant.ts,
# apps/web-platform/scripts/revoke-jti.ts (new), apps/web-platform/test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts (new)
```

Re-run with `jq -r --arg path "<file-path>" '.[] | select(.body // "" | contains($path))' /tmp/open-review-issues.json` per planned file at deepen-plan.

Result placeholder: **None pre-checked yet; deepen-plan Phase 4 must run the grep.**

## Functional Overlap Check

Sibling PRs touching the same surfaces this work touches (verified via grep + branch listing):

- **PR #4307 (`feat-rls-known-gaps-4233-bundle` PR-1, closed merged 2026-05-23 via mig 067):** Added `check_my_revocation(p_jwt_iat)` RPC + middleware. Closely sibling shape to `my_revocation_status()` — both are user-global revocation readers gated by `auth.uid()`. The two RPCs serve different revocation classes (member-removal vs JWT-deny) but share the SECURITY DEFINER + REVOKE+GRANT skeleton; this plan mirrors 067's REVOKE matrix exactly to avoid the "missing service_role REVOKE" trap from learning `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md` §Session Errors #6.
- **Migration 059 (`workspace_keyed_rls_sweep`, 2026-05-21):** Replaced 9 user-keyed policies with `is_workspace_member`-routed policies. The 10 remaining tenant tables (push_subscriptions, kb_share_links, audit_byok_use, etc.) all had their `auth.uid() = user_id` policies dropped + replaced with workspace-keyed ones. **Critical:** the RESTRICTIVE jti-deny policy in this plan stacks on top of those workspace-keyed policies, not on the legacy `auth.uid() = user_id` ones.

## Files to Edit

**New files (4):**

1. `apps/web-platform/supabase/migrations/068_jti_deny_rls_predicate_and_revoke_rpc.sql` — new migration containing:
   - (A) `revoke_jti(p_jti uuid, p_founder_id uuid, p_reason text) RETURNS void` — service-role-only writer for `denied_jti` (issue #3930 admin RPC).
   - (B) `my_revocation_status() RETURNS TABLE(revoked boolean, denied_at timestamptz, reason text)` — founder-readable status (issue #3930 reader).
   - (C) Per-tenant-table RESTRICTIVE policy `ON public.<table> AS RESTRICTIVE FOR ALL TO authenticated USING (NOT public.is_jti_denied(...))` for each of 19 tables: `conversations`, `messages`, `users`, `api_keys`, `audit_byok_use`, `scope_grants`, `audit_github_token_use`, `kb_share_links`, `push_subscriptions`, `user_concurrency_slots`, `dsar_export_jobs`, `action_sends`, `template_authorizations`, `byok_delegations`, `workspaces`, `workspace_members`, `workspace_member_attestations`, `user_session_state`, `message_attachments`.
   - (D) `GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated` — required because the RESTRICTIVE policy is evaluated under the authenticated role; SECURITY DEFINER's outer-call EXECUTE check still applies even when the fn body runs with definer privileges (per learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`).
   - (E) Companion CTE-shaped helper `public.is_jti_denied_from_jwt()` (zero-arg, reads `current_setting('request.jwt.claims', true)::jsonb->>'jti'` internally) — clean macro for the RESTRICTIVE policy body. Reduces 19 verbose policy bodies to one helper call, and lets us isolate the JWT-claim-read failure modes in one place.
2. `apps/web-platform/supabase/migrations/068_jti_deny_rls_predicate_and_revoke_rpc.down.sql` — rollback (DROP POLICY × 19 + DROP FUNCTION × 3 + REVOKE).
3. `apps/web-platform/scripts/revoke-jti.ts` — operator CLI for the new `revoke_jti` RPC. Reads `SUPABASE_SERVICE_ROLE_KEY` via Doppler-bound `createServiceClient()`, calls `service.rpc("revoke_jti", {p_jti, p_founder_id, p_reason})`, emits Sentry breadcrumb on success.
4. `apps/web-platform/test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts` — new tenant-isolation suite. Validates: (a) deny-list row blocks PostgREST-direct reads + writes for the revoked jti's full TTL, (b) un-revoked sessions are unaffected, (c) `my_revocation_status()` returns shape `(false, NULL, NULL)` for un-denied callers + `(true, denied_at, reason)` for denied callers, (d) `revoke_jti` REVOKE+GRANT matrix matches the service-role-only invariant, (e) the dual-shape `{error: { code: '42501' }} | {data: []}` deny-acceptance pattern per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md` (the RESTRICTIVE policy denies with `{data: [], error: null}`-shape because RLS-deny is silent zero-rows; ANY downstream column-grant rejection on the same statement returns `42501`).

**Modified files (3):**

5. `apps/web-platform/lib/supabase/tenant.ts` — wire `my_revocation_status()` into a new exported helper `getMyRevocationStatus(userId)` for ws-handler / API-route consumption. NO change to the existing `denyProbe` Node-side consumer (it stays — defense-in-depth alongside the new RLS-side consumer per #3932 problem statement). Also extend the docblock at lines 12-14 with a pointer to this PR's residual closing.
6. `apps/web-platform/server/ws-handler.ts` — when `RuntimeAuthError("denied_jti", …)` fires on a session, route the user-visible error toast to read `my_revocation_status()` first and emit `{revoked: true, reason: <reason>}` payload to the client instead of the generic "Authentication unavailable; retry shortly". Replaces the generic toast with a discriminated one for the deny-list class. Site to be confirmed via `grep -nE 'RuntimeAuthError.*denied_jti|tenant.*RuntimeAuthError' apps/web-platform/server/` at /work time.
7. `knowledge-base/legal/compliance-posture.md` — add a Completed Compliance Work row for "Cross-process JWT-deny RLS enforcement + admin revoke surface (PR-E follow-up #3930 + #3932)" linking this PR + date. Also append an HTML comment timestamp marker at the top of the Active Items block per the file's existing convention.

**No Article 30 register amendment expected.** PA1 (Account & Authentication) already covers `denied_jti` (added in PR-B #3395 / mig 037); jti is random UUID (not personal data); founder_id is already in PA1 scope. The new `revoke_jti` writer + `my_revocation_status` reader are mechanisms within the existing PA1 activity, not new processing. To be re-confirmed at gdpr-gate Phase 2.7.

## Acceptance Criteria

### Pre-merge (PR)

1. **Migration 068 applies cleanly against dev Supabase** — `cd apps/web-platform && supabase db push --linked --dry-run` shows the migration plan without errors; `supabase db push --linked` succeeds; `supabase db diff` returns empty after apply.
2. **Migration 068's `down.sql` cleanly reverses** — apply, then run `psql -f 068_jti_deny_rls_predicate_and_revoke_rpc.down.sql` against dev; `supabase db diff` shows the schema returned to pre-068 state.
3. **All 19 tenant tables have the new RESTRICTIVE policy** — `psql -c "SELECT tablename FROM pg_policies WHERE schemaname='public' AND policyname LIKE '%jti_not_denied%' AND permissive='RESTRICTIVE'" | wc -l` returns `19`. The verbose form (per learning `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`) explicitly enumerates each tenant table and asserts each has exactly one such policy.
4. **`is_jti_denied_from_jwt()` is callable from authenticated role** — `psql --role=authenticated -c "SELECT public.is_jti_denied_from_jwt()"` returns `false` (no JWT context outside PostgREST means jti claim is NULL → safely returns false). Test fixture sets `request.jwt.claims` GUC inline to verify both branches.
5. **`my_revocation_status()` returns correct shape for both states** — under a tenant client whose jti is NOT in `denied_jti`, returns `(false, NULL, NULL)`; after inserting a deny row, returns `(true, <ts>, <reason>)`.
6. **`revoke_jti` is service-role-only** — `psql --role=authenticated -c "SELECT public.revoke_jti('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'test')"` returns `42501 permission denied`; same call as service_role succeeds.
7. **`scripts/revoke-jti.ts` invocation against a real founder jti causes that founder's open PostgREST queries to fail with `0 rows` (RLS-deny shape) within 1 round-trip** — integration test in `tenant-jwt-rls-deny.tenant-isolation.test.ts` exercises this path end-to-end with `TENANT_INTEGRATION_TEST=1`.
8. **No new operator-facing manual step** — `scripts/revoke-jti.ts` is invokable via `npx tsx scripts/revoke-jti.ts <jti> <founder_id> <reason>` and is fully scripted with `--help` for arg validation. NO "operator runs psql" anywhere in the resulting docs.
9. **All existing `*.tenant-isolation.test.ts` suites stay green** — `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts` shows 0 failures, 0 unexpected skips. Per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`, any `skipped > 0` is investigated for `beforeAll` crash.
10. **`npx tsc --noEmit`** in `apps/web-platform` is clean. **`bash scripts/test-all.sh webplat`** has no new pre-existing-regression.
11. **`bash apps/web-platform/scripts/service-role-allowlist-gate.sh`** passes — no new service-role-importer entries needed (the new script reads `SUPABASE_SERVICE_ROLE_KEY` directly via Doppler env, not via the allowlisted singleton).
12. **`gdpr-gate` Phase 2.7 returns ≤ 0 Critical findings** for the regulated-data surface (mig 068 touches auth-domain schema; the `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex fires).
13. **No new `cq-pg-security-definer-search-path-pin-pg-temp` violations** — every new SECURITY DEFINER function in mig 068 has `SET search_path = public, pg_temp` pinned.

### Post-merge (operator — fully automated via existing CI)

14. **Migration 068 applies to prd** via `.github/workflows/web-platform-release.yml#migrate` job (existing automation; no operator action). Verified by the workflow's `verify-migrations` job which runs `select * from public._schema_migrations where version='068'` after apply.
15. **`gh issue close 3930 --comment "Closed by PR #<N>: <date> — admin revoke_jti RPC + my_revocation_status reader landed via mig 068"`** runs automatically in `web-platform-release.yml#post-deploy` (existing automation already mirrors PR-E's #3887 close pattern). Same for #3932.
16. **Sentry mirror sanity** — `sentry_id` query against `is_jti_denied.error` issue tag returns 0 hits in the first 24h post-merge (no NULL `request.jwt.claims` failures from the RESTRICTIVE policy). Filed as a `web-platform-release.yml#follow-through` gate; deferred re-check at 7d.

## Infrastructure (IaC)

### Terraform changes

None. This plan touches Postgres schema + TypeScript only. No Terraform root is modified.

### Apply path

N/A — schema change via Supabase migration (existing `web-platform-release.yml#migrate` pipeline). No vendor account, no DNS record, no firewall rule, no cron job introduced.

### Distinctness / drift safeguards

Migration apply is gated by `web-platform-release.yml#migrate` running against the prd Supabase project (Doppler `prd` config). The `hr-dev-prd-distinct-supabase-projects` rule applies — the operator-CLI `scripts/revoke-jti.ts` MUST read `SUPABASE_*` env from Doppler `prd` config when invoked against a prd-leaked jti; the script's `--help` text + opening preamble MUST display the resolved Supabase URL before any write so the operator can confirm dev/prd.

### Vendor-tier reality check

N/A — no new vendor surface.

## Observability

```yaml
liveness_signal:
  what: "Sentry breadcrumb 'revoke_jti.issued' on every operator invocation of scripts/revoke-jti.ts; Sentry issue 'is_jti_denied.deny' (existing PR-E mirror) fires on every cross-process RLS deny"
  cadence: "On every revocation event (low cardinality — single-user-incident class); on every authenticated RLS deny (cardinality scales with attacker traffic on a stolen JWT)"
  alert_target: "Sentry alert 'is_jti_denied.deny' P1 routing (existing, defined by PR-E)"
  configured_in: "apps/web-platform/lib/supabase/tenant.ts (existing mirrorWithDebounce) + apps/web-platform/scripts/revoke-jti.ts (new revoke_jti.issued breadcrumb)"
error_reporting:
  destination: "Sentry — existing 'tenant-jwt' feature scope with op='is_jti_denied.error' (NULL JWT claim, RPC error from RLS-side deny-probe)"
  fail_loud: "Yes — mirrorWithDebounce already preserves stack + msg via cq-silent-fallback-must-mirror-to-sentry"
failure_modes:
  - mode: "is_jti_denied_from_jwt() returns NULL (JWT claim missing or malformed)"
    detection: "Sentry issue with op='is_jti_denied_from_jwt.null_claim' (new emission added in tenant.ts when the helper returns NULL on a path that requires it to return boolean)"
    alert_route: "P2 — Sentry default issue routing; not paging"
  - mode: "revoke_jti RPC writes to wrong founder_id (FK mismatch)"
    detection: "scripts/revoke-jti.ts re-reads the inserted row via SELECT before exit; mismatch raises non-zero exit code that the operator sees inline"
    alert_route: "Operator-visible — no Sentry route needed (operator script is interactive)"
  - mode: "RESTRICTIVE policy denies a fresh un-revoked JWT (false positive)"
    detection: "Sentry issue 'tenant-jwt op=is_jti_denied.deny' for a jti that does NOT match any denied_jti row — detected by the existing mirror at tenant.ts denyProbe (Node-side check still runs)"
    alert_route: "P1 — Sentry alert (existing PR-E alert)"
logs:
  where: "Supabase Logs (RPC invocations); pino logs from scripts/revoke-jti.ts written to stdout for operator review"
  retention: "Supabase Logs 7 days (current free-tier); pino logs operator-machine-local (not persisted)"
discoverability_test:
  command: "cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts"
  expected_output: "Test Files 1 passed (1) ; Tests N passed (N) ; with at least one assertion of shape 'expect(error?.code === \"42501\" || data?.length === 0).toBe(true)'"
```

## Implementation Phases

### Phase 0 — Preconditions and verification (~10 min)

**0.1** Verify worktree CWD: `pwd` returns `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-jti-revoke-rls-3930-3932` (per `hr-when-in-a-worktree-never-read-from-bare`).

**0.2** Verify migration 037 shape unchanged: `git log -1 --format=%H -- apps/web-platform/supabase/migrations/037_audit_byok_use.sql` matches the SHA captured at PR-E merge (PR #3922). If drifted, abort + investigate.

**0.3** Verify `users.role` enum is still `{prd, dev}` (no `admin` role added by another worktree): `grep "check (role in" apps/web-platform/supabase/migrations/054_users_role_column.sql` returns the `{'prd', 'dev'}` form. If drifted, re-scope #3930 admin-auth section.

**0.4** Verify migration number 068 is free (no concurrent worktree has claimed it): `ls apps/web-platform/supabase/migrations/ | sort -V | tail -5` shows `067_*` as latest, no `068_*` claimed.

**0.5** Run sibling-precedent grep — confirm `check_my_revocation` (mig 067) signature shape we're mirroring: `grep -A 5 "CREATE FUNCTION public.check_my_revocation" apps/web-platform/supabase/migrations/067_workspace_member_revocation_lookup.sql`.

**0.6** Confirm GRANT EXECUTE plan via the precedent grep from learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`: `grep -nE "REVOKE EXECUTE.*FROM authenticated|GRANT EXECUTE.*TO authenticated" apps/web-platform/supabase/migrations/ | grep "is_jti_denied"`. The plan adds `GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated` — required because the new RESTRICTIVE policy runs in the authenticated role's RLS context. Without it, every PostgREST query under authenticated returns `42501 permission denied for function is_jti_denied` instead of evaluating the policy.

### Phase 1 — Migration 068 schema (~45 min, TDD)

**1.1 RED:** Write the new tenant-isolation test file `apps/web-platform/test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts`. Tests assert:

- (a) `service.rpc("revoke_jti", {p_jti: A.jti, p_founder_id: A.id, p_reason: "test"})` succeeds under service_role; same call under authenticated returns `42501`.
- (b) After (a) lands, `aClient.from("conversations").select()` (where `aClient` has jti = A.jti) returns either `{error: { code: "42501" }, data: null}` OR `{error: null, data: []}` (dual-shape per learning `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`).
- (c) A's un-revoked sibling jti continues to read normally.
- (d) `aClient.rpc("my_revocation_status")` returns `{data: [{revoked: true, denied_at: <ts>, reason: "test"}], error: null}`.
- (e) `bClient.rpc("my_revocation_status")` (B's jti not denied) returns `{data: [{revoked: false, denied_at: null, reason: null}], error: null}`.

These tests FAIL because mig 068 doesn't exist yet.

**1.2 GREEN:** Author `068_jti_deny_rls_predicate_and_revoke_rpc.sql`:

- `revoke_jti(p_jti uuid, p_founder_id uuid, p_reason text) RETURNS void` — `LANGUAGE sql` (simpler than plpgsql, since the body is one INSERT), SECURITY DEFINER, `SET search_path = public, pg_temp`. Body: `INSERT INTO public.denied_jti (jti, founder_id, denied_at, reason) VALUES (p_jti, p_founder_id, now(), p_reason)`. REVOKE FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role.
- `my_revocation_status() RETURNS TABLE(revoked boolean, denied_at timestamptz, reason text)` — LANGUAGE plpgsql, SECURITY DEFINER, `SET search_path = public, pg_temp`. Body mirrors `check_my_revocation` from mig 067 (28000 raise on NULL `auth.uid()`, single `SELECT … LIMIT 1` of latest denied row for `auth.uid()`'s founder_id, fallthrough to `(false, NULL, NULL)`). REVOKE FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE TO authenticated.
- `is_jti_denied_from_jwt() RETURNS boolean` — LANGUAGE sql, SECURITY DEFINER, `STABLE`, `SET search_path = public, pg_temp`. Body: `SELECT EXISTS (SELECT 1 FROM public.denied_jti WHERE jti = (current_setting('request.jwt.claims', true)::jsonb->>'jti')::uuid)`. REVOKE FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO authenticated.
- For each of 19 tenant tables: `CREATE POLICY <table>_jti_not_denied ON public.<table> AS RESTRICTIVE FOR ALL TO authenticated USING (NOT public.is_jti_denied_from_jwt())`. Note: RESTRICTIVE policies have `WITH CHECK` semantics on INSERT/UPDATE too; the `FOR ALL` form covers SELECT/INSERT/UPDATE/DELETE in one policy.
- Also `GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated` (the existing reader from mig 037 currently has REVOKE FROM authenticated; the new RLS policy invokes the wrapped form `is_jti_denied_from_jwt` which SECURITY DEFINERs into `is_jti_denied`, BUT the policy text body's EXECUTE check is on `is_jti_denied_from_jwt`; therefore `is_jti_denied`'s own GRANT remains service_role-only and Node-side consumer is unaffected).

**1.3** Run the RED tests — confirm GREEN.

**1.4** Write the `down.sql` rollback. Apply both forward+rollback against a fresh dev branch project (Supabase branch DBs are free per Phase 0.5 of plan reading — to confirm at /work time).

**1.5 REFACTOR:** Read the 19 RESTRICTIVE policies for DRY — if more than 5 lines of repeating `CREATE POLICY ... USING (NOT public.is_jti_denied_from_jwt())` is exact-duplicate prose, wrap in a `DO $$ ... LOOP ... END $$` block over a hardcoded table-name array.

### Phase 2 — `revoke-jti.ts` operator CLI (~30 min)

**2.1 RED:** Add a unit test under `apps/web-platform/test/scripts/revoke-jti.test.ts` (NOT `.tenant-isolation.test.ts` suffix — this script does not need the tenant-integration guard) that mocks `createServiceClient()` and asserts: argv validation, RPC invocation with correct args, re-read verification.

**2.2 GREEN:** Author `apps/web-platform/scripts/revoke-jti.ts`:

```ts
#!/usr/bin/env npx tsx
import { createServiceClient } from "@/lib/supabase/service";
import { Sentry } from "@/lib/sentry";

const [jti, founderId, ...reasonWords] = process.argv.slice(2);
if (!jti || !founderId || reasonWords.length === 0) {
  console.error("Usage: npx tsx scripts/revoke-jti.ts <jti-uuid> <founder-id-uuid> <reason-string>");
  process.exit(2);
}
const reason = reasonWords.join(" ");

const supa = createServiceClient();
const supabaseUrl = process.env.SUPABASE_URL ?? "<not set>";
console.log(`[revoke-jti] target Supabase: ${supabaseUrl}`);  // dev/prd visibility per hr-dev-prd-distinct-supabase-projects
const { error } = await supa.rpc("revoke_jti", { p_jti: jti, p_founder_id: founderId, p_reason: reason });
if (error) {
  console.error(`[revoke-jti] FAILED: ${error.code} ${error.message}`);
  process.exit(1);
}

// Re-read for sanity (founder_id-mismatch protection per Observability §failure_modes)
const { data: row } = await supa.from("denied_jti").select("*").eq("jti", jti).single();
if (!row || row.founder_id !== founderId) {
  console.error(`[revoke-jti] re-read mismatch: row=${JSON.stringify(row)}`);
  process.exit(1);
}

Sentry.addBreadcrumb({ category: "revoke_jti.issued", level: "warning", data: { jti, founderId, reason } });
console.log(`[revoke-jti] OK: jti=${jti} founder=${founderId} reason="${reason}"`);
process.exit(0);
```

**2.3** Verify mocks GREEN. Run script against dev Supabase as smoke test (NOT prd).

### Phase 3 — Node-side wiring + ws-handler discrimination (~30 min)

**3.1 RED:** Add a unit test for the new `getMyRevocationStatus(userId)` helper in `lib/supabase/tenant.ts`.

**3.2 GREEN:** Add `getMyRevocationStatus`: calls `tenant.rpc("my_revocation_status")` via the per-user tenant client, returns `{revoked, deniedAt, reason} | null` (null on error).

**3.3** Find the existing `RuntimeAuthError("denied_jti", …)` throw + catch sites: `grep -nE "denied_jti|RuntimeAuthError" apps/web-platform/server/ws-handler.ts apps/web-platform/server/cc-dispatcher.ts apps/web-platform/lib/supabase/tenant.ts`.

**3.4** At the WS-handler catch site, replace the generic toast with a call to `getMyRevocationStatus(userId)`; if `{revoked: true}`, emit a structured `revocation_notice` WebSocket message with `{reason}` payload to the client. Add a TypeScript unit test for the new message variant.

**3.5** Add the new message variant to the `WSMessage` discriminated union (and the test-d exhaustiveness file) per `cq-union-widening-grep-three-patterns`.

### Phase 4 — Compliance-posture amendment + PR body (~15 min)

**4.1** Read `knowledge-base/legal/compliance-posture.md`; append a row to the "Completed Compliance Work" table describing the PR with #3930+#3932 cited; prepend an HTML comment timestamp marker matching the file's existing pattern.

**4.2** Compose the PR body using the PR-E template shape (Summary, User-Brand Impact pointer, Changelog, Test plan with checkboxes, Reviewer Pipeline). Use `Closes #3930` and `Closes #3932` in the PR body (NOT title — per `wg-use-closes-n-in-pr-body-not-title-to`).

### Phase 5 — Test execution + verification (~20 min)

**5.1** Run `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts` — confirm all suites green (15-suite shape per PR-E baseline; this plan adds 1 → 16 expected).
**5.2** Run `bash scripts/test-all.sh webplat` — confirm no regression.
**5.3** Run `npx tsc --noEmit` in `apps/web-platform` — confirm clean.
**5.4** Run `bash apps/web-platform/scripts/service-role-allowlist-gate.sh` — confirm no new entries needed.
**5.5** Run `/soleur:gdpr-gate` against the diff — confirm 0 Critical findings.

### Phase 6 — /soleur:review with mandatory agents (~30 min)

Per `brand_survival_threshold: single-user incident`, the review pipeline MUST include:
- `user-impact-reviewer` (mandatory per threshold)
- `data-integrity-guardian` (WORM + RLS + audit-writer surface)
- `security-sentinel` (JWT mint path + RLS predicate change)
- `gdpr-gate` (auth-domain code change)
- Standard 6 code-review agents
- `test-design-reviewer` (test files present)
- `code-simplicity-reviewer` (CONCUR gate)

All findings P0/P1 fixed inline per `rf-review-finding-default-fix-inline`. Scope-outs filed with re-evaluation triggers per `wg-when-deferring-a-capability-create-a`.

### Phase 7 — Ship via `/soleur:ship` (~10 min)

Per `wg-after-marking-a-pr-ready-run-gh-pr-merge`: after Phase 6 closes, run `/soleur:ship`. The migration applies post-merge via existing `web-platform-release.yml#migrate` automation. POST-1 (`gh issue close 3930/3932`) is automated per `web-platform-release.yml#post-deploy`.

## Risks & Mitigations

### R1 — RESTRICTIVE-policy combination semantics with existing PERMISSIVE policies

Postgres RLS evaluates each row against the AND-combination of all RESTRICTIVE policies AND the OR-combination of all PERMISSIVE policies — i.e., `(any PERMISSIVE matches) AND (all RESTRICTIVE match)`. The new `<table>_jti_not_denied` RESTRICTIVE policy stacks on top of every existing PERMISSIVE policy (workspace-keyed per mig 059 + legacy auth.uid()=user_id where still present). **Risk:** A bug in the RESTRICTIVE policy body (NULL `current_setting`, malformed JWT claim, search_path missing) returns NULL, which Postgres treats as `false` → RESTRICTIVE policy denies → founder loses access to every table at once.

**Mitigations:**
- The `is_jti_denied_from_jwt()` helper handles NULL claims explicitly via `current_setting('request.jwt.claims', true)::jsonb->>'jti'` — the `true` arg to `current_setting` returns NULL instead of raising when the GUC is unset; `->>'jti'` on NULL returns NULL; `(NULL)::uuid` returns NULL; `EXISTS` against `WHERE jti = NULL` is `false`; the outer `NOT public.is_jti_denied_from_jwt()` then returns `NOT false = true` — i.e., access is GRANTED when claim is missing. Service-role contexts (where request.jwt.claims is unset) inherit no deny, matching the existing PR-E semantics.
- Unit-test the helper directly via `SET LOCAL request.jwt.claims = '{...}'::jsonb::text` inside a TRANSACTION at test time, with both branches (jti present + on deny list; jti present + not on deny list; jti absent).
- Deepen-plan precedent-diff (Phase 4.4) MUST diff the new policies against the existing precedent (`scope_grants_no_update`, the workspace-keyed sweep from mig 059) — see learning `best-practices/2026-04-23-plan-quality-class-deepen-pass-catches.md`.

### R2 — Migration ordering against in-flight worktrees

Multiple concurrent worktrees have claimed migration numbers 063–067 (see `ls` output during Phase 0). Migration 068 is available at HEAD, but the worktree merging the dev-supabase-drift-deltas (#4325) may claim it first.

**Mitigations:**
- Phase 0.4 verifies the number is unclaimed; rename to 069+ at /work time if a sibling lands first.
- Use `git ls-files apps/web-platform/supabase/migrations/` against `origin/main` at Phase 0 to detect lands-after-our-fetch claims.

### R3 — `revoke_jti` `denied_jti` FK to `users(id)` — operator typo

`denied_jti.founder_id REFERENCES public.users(id) ON DELETE RESTRICT`. An operator who types a wrong founder_id UUID would get a `23503` FK violation — not silent. Acceptable.

### R4 — Cross-process JWT enforcement performance cost (#3932 problem-statement perf dimension)

Adding a SECURITY DEFINER reader call to every RLS-evaluated query adds overhead. `denied_jti.jti` is the PK (UUID, indexed), so EXISTS lookup is O(1). The `STABLE` marker on `is_jti_denied_from_jwt` permits Postgres to memoize within a single statement — verified by `EXPLAIN ANALYZE` at /work time.

**Mitigations:**
- Phase 5 includes an `EXPLAIN ANALYZE` smoke against `conversations` SELECT under tenant client; expected delta < 0.2 ms per query.
- Index `denied_jti.jti` IS the PK (mig 037:123) — index-only scan.

### R5 — Founder-readable `my_revocation_status` jti enumeration side-channel

Issue #3930 explicitly calls out: "Does NOT expose the jti (jti enumeration side-channel mitigation)." The RPC body returns `(revoked, denied_at, reason)` only — no jti column. A founder cannot enumerate deny-list entries beyond their own.

**Mitigations:**
- RPC signature literally omits jti.
- The `denied_jti` table itself remains zero-RLS-policy (mig 037:129) — service-role-only access via SECURITY DEFINER funcs.

### R6 — Operator-CLI dev/prd footgun

`scripts/revoke-jti.ts` reads `SUPABASE_*` env at runtime. An operator running it against dev Doppler config leaves the prd-leaked jti live.

**Mitigations:**
- The script prints `[revoke-jti] target Supabase: <url>` BEFORE any write (Phase 2.2 code listing).
- Operator runbook (added inline in `knowledge-base/engineering/ops/runbooks/revoke-jti.md` if needed at /work time) instructs `doppler run -p soleur -c prd_terraform -- npx tsx scripts/revoke-jti.ts …` (note: not `prd` config — the operator's prd-bound service-token config name varies per project precedent; resolve at /work time).
- AC6 + AC11 verify the service-role-only invariant at unit and integration level.

### R7 — Tests mock the auth boundary, hiding RLS-deny shape

Per learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`: vitest mocks of `@supabase/supabase-js` resolve `.rpc()` to a `vi.fn()` that bypasses real Postgres. RLS-deny / GRANT-deny shapes will not surface in mocked tests.

**Mitigations:**
- The new `tenant-jwt-rls-deny.tenant-isolation.test.ts` runs under `TENANT_INTEGRATION_TEST=1` against real dev Supabase (Phase 5.1).
- Per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`: the dual-shape `{error: { code: '42501' }} | {data: []}` acceptance block is used.

### R8 — Future widening of `users.role` to include `admin`

If a future PR introduces an `admin` role, this plan's v1 service-role-only writer would be redundant. But the v1 design is forward-compatible: a future migration can `GRANT EXECUTE ON FUNCTION public.revoke_jti(uuid, uuid, text) TO admin` and add an `auth.uid() IN (SELECT id FROM users WHERE role = 'admin')` guard inside the body — without breaking the service-role caller. No design rework.

## Test Strategy

**Unit tests (mocked):**
- `apps/web-platform/test/scripts/revoke-jti.test.ts` — argv validation, RPC call signature, re-read verification, Sentry breadcrumb emission.
- `apps/web-platform/test/lib/tenant-revocation-status.test.ts` — `getMyRevocationStatus(userId)` helper.
- `apps/web-platform/test/server/ws-handler-revocation-notice.test.ts` — new WS message variant emission on revoked sessions.

**Integration tests (real Supabase, `TENANT_INTEGRATION_TEST=1`):**
- `apps/web-platform/test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts` — 5+ scenarios:
  1. `revoke_jti` service-role-only invariant (REVOKE matrix).
  2. After deny-row insert: cross-process PostgREST queries dual-shape-deny on `conversations`, `messages`, `audit_byok_use`.
  3. Un-revoked sibling JWT continues to read normally.
  4. `my_revocation_status()` returns `(true, denied_at, reason)` for denied founder.
  5. `my_revocation_status()` returns `(false, NULL, NULL)` for un-denied founder.
  6. After deny-row delete: queries succeed again (revocation is reversible at SQL level).

**Migration shape lint:**
- `apps/web-platform/test/supabase-migrations/068-jti-deny-rls-predicate.test.ts` — asserts the 19 RESTRICTIVE policies were created (matching count), the 3 new SECURITY DEFINER functions have `search_path` pinned, and the REVOKE matrix matches the canonical 3-role pattern per learning `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md` §Session Errors #6.

## Out of Scope

- **New `admin` role + admin UI.** Filed as new sub-issue at PR close (re-evaluation trigger: 2nd hosted founder onboards). The v1 service-role+script writer is sufficient for single-founder closed-preview.
- **JWT TTL shortening as alternative.** Issue #3932 names this as alternative consideration; deferred — the JWT TTL (10 min) is already the existing PR-E exposure ceiling; shortening trades exposure window for refresh rate-limit pressure. Re-evaluate at the next mint-rate review (not this PR's concern).
- **Signing-key rotation as alternative.** Heavy hammer per #3932 alternative consideration; explicitly tracked as a known operational footgun per `tenant.ts:12-14` docblock. This PR does not change rotation cadence.
- **Deny-list circuit-breaker promotion.** Tracked in #3931 (deny-RPC cache). PR-E shipped fail-open semantics for `is_jti_denied` Node-side; this PR's RLS predicate also fails-OPEN (NOT NULL → true → access granted) when claims are missing. Promotion of the circuit-breaker pattern stays at #3931.
- **In-flight cached-client header pinning.** Tracked in #3933.
- **`is_jti_denied` per-sub-call audit / TTL sweep / synthetic-fixture sweeper.** Tracked in #3928/#3929/#3934.

## Tracked Deferrals

1. **New admin role + admin UI** — filed at PR close with `architectural-pivot` scope-out criterion. Re-evaluation trigger: 2nd hosted founder onboards OR operator dogfood reports `scripts/revoke-jti.ts` is friction.
2. **`web-platform-release.yml#post-deploy` automation of `gh issue close 3930/3932`** — already covered by existing PR-E close pattern; verify at Phase 7 ship that the workflow path matches. If not, add a one-line operator runbook entry (not a new workflow).

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO).

### Engineering (CTO)

**Status:** to-be-reviewed at deepen-plan Phase 2.5 spawn.
**Assessment:** Two CTO-domain invariants: (a) RLS policy stacking semantics under PERMISSIVE+RESTRICTIVE evaluation, (b) JWT-claim availability under PostgREST routing vs direct service-role calls. The `current_setting('request.jwt.claims', true)::jsonb` shape is what Supabase's PostgREST sets per-request; the `true` arg short-circuits unset GUCs to NULL. Verified pattern by sibling probes in mig 060 + 047 (custom_access_token_hook).

### Legal (CLO)

**Status:** to-be-reviewed at deepen-plan Phase 2.5 spawn + gdpr-gate Phase 2.7.
**Assessment:** No new Article 30 PA expected (PA1 already covers `denied_jti` + revocation writer). Art. 5(2) accountability strengthened by adding a cross-process kill-switch (was previously Node-process-only). Art. 32(1)(b) "ongoing confidentiality" now extends across process boundaries (PostgREST as well as Node). compliance-posture.md row added.

### Product / UX Gate

**Tier:** advisory.
**Decision:** auto-accepted (pipeline) — this plan modifies an EXISTING toast message ("Authentication unavailable; retry shortly" → discriminated revocation message). No new UI surface, no new component file, no new page. Per mechanical-escalation rule, no `components/**/*.tsx` or `app/**/page.tsx` file is created. Wireframes not needed.

#### Findings

(advisory) The toast-message discrimination improves the founder's understanding of WHY the runtime is unavailable. CPO carry-forward from brainstorm domain assessments: this is brand-survival-critical because trust-erosion-per-incident is the load-bearing UX cost; a discriminated message ("Your most recent session was revoked. Reason: X. Contact support.") is markedly better than the generic toast.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with the brainstorm carry-forward + threshold `single-user incident`.
- The RESTRICTIVE policy fires for EVERY tenant-table query — verify perf impact via `EXPLAIN ANALYZE` at Phase 5 before merging. Use the existing `denied_jti.jti` PK index (mig 037:123).
- `current_setting('request.jwt.claims', true)` with `true` returns NULL when the GUC is unset (e.g., service-role context). NULL → NOT NULL → safe fail-open is intentional; service-role bypasses RLS regardless.
- `is_jti_denied_from_jwt()` must be marked `STABLE` (not `VOLATILE`) so Postgres can memoize within a statement. Test by running a 1000-row SELECT and timing it under EXPLAIN ANALYZE — if `STABLE` is missing, the deny-probe fires 1000 times per query.
- Per learning `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md`: the new policy's "permission-denied"-shape ON UPDATE/INSERT depends on whether the column GRANTs are checked first or RLS is checked first. **In Postgres, column-level GRANTs are checked BEFORE RLS.** So a tenant trying to UPDATE a non-granted column would get `42501` regardless of the deny-list state; the new RESTRICTIVE policy is the SECOND wall on the same surface. Phase 1.1 dual-shape acceptance handles this.
- Per learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`: this plan ADDS `GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated` — required because the RLS policy is evaluated under the authenticated role; SECURITY DEFINER's outer-call EXECUTE check still applies. Without this GRANT, every tenant query under authenticated returns `42501 permission denied for function is_jti_denied` instead of evaluating the policy.
- `scripts/revoke-jti.ts` MUST print the target Supabase URL BEFORE writing (`hr-dev-prd-distinct-supabase-projects` defense). The script's `--help` text and runtime preamble both display the URL.
- Plan-time PR-vs-issue disambiguation: PR-E reference is PR #3922 (the merged PR), umbrella issue is #3244, this plan's predecessors are issue #3930 + #3932 (both deferred-scope-outs from PR-E). Verified via `gh pr view 3922 --json title,state` (state: MERGED) and `gh issue view 3930/3932 --json state` (both OPEN).
- No `actionlint` errors expected — this PR does not add a workflow file.
- Per `cq-pg-security-definer-search-path-pin-pg-temp`: all 3 new SECURITY DEFINER functions in mig 068 pin `SET search_path = public, pg_temp` (in that order, public first).
- Per `wg-block-pr-ready-on-undeferred-operator-steps`: zero operator-only steps in the post-merge flow. `web-platform-release.yml#migrate` applies mig 068 automatically; `web-platform-release.yml#post-deploy` runs `gh issue close 3930/3932` automatically. The `scripts/revoke-jti.ts` is a tool the operator may use later if an actual JWT compromise occurs — that's incident-response, not a ship checklist item.

## References

- PR #3922 (PR-E merged) — predecessor.
- Issue #3930 — admin revoke_jti RPC + my_revocation_status reader.
- Issue #3932 — PostgREST-side RLS predicate for is_jti_denied.
- Issue #3887 — PR-E parent (closed).
- Issue #3244 — umbrella (open).
- Migration 037 — `audit_byok_use` + `denied_jti` + `is_jti_denied` (PR-B #3395).
- Migration 067 — `check_my_revocation` sibling precedent (PR #4307).
- Migration 059 — workspace-keyed RLS sweep (sets the existing PERMISSIVE-policy baseline this PR stacks RESTRICTIVE on top of).
- Plan: `knowledge-base/project/plans/2026-05-16-feat-pr-e-audit-byok-jti-deny-plan.md` — PR-E plan, this plan's predecessor.
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-16-pr-e-audit-byok-jti-deny-brainstorm.md` — PR-E brainstorm (carries User-Brand Impact framing).
- Learning: `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md`.
- Learning: `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`.
- Learning: `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`.
- Learning: `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`.
- Learning: `2026-05-22-tenant-integration-runtime-failures-post-mig-059.md`.
- Learning: `2026-05-10-content-vendoring-pin-policy-brainstorm.md` (stdout-vs-stderr for operator-protection signals — applies to `scripts/revoke-jti.ts`).
- Article 30 register: `knowledge-base/legal/article-30-register.md` — PA1 amendment NOT expected.
- compliance-posture.md — Completed Compliance Work row to be added.
