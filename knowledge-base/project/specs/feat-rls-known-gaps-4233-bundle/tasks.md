---
feature: rls-known-gaps-4233-bundle
plan: knowledge-base/project/plans/2026-05-22-feat-workspace-member-session-invalidation-plan.md
spec: knowledge-base/project/specs/feat-rls-known-gaps-4233-bundle/spec.md
issue: "#4307"
lane: cross-domain
brand_survival_threshold: single-user incident
status: ready-for-work
---

# Tasks — PR-1: workspace-member session invalidation (#4307)

Derived from the v2 plan after 5-agent plan-review (7 cuts + 8 fixes applied). Tasks numbered by plan phase.

## Phase 1 — Migration 064 + Art. 30 + migration-shape lint

- 1.1 Run schema-vs-ledger parity probe on dev Supabase against `workspace_member_removals`. Halt if drift.
- 1.2 Write `apps/web-platform/supabase/migrations/064_workspace_member_revocation_lookup.sql` ADD COLUMNs (revoked_after timestamptz, revocation_reason text) + backfill (`UPDATE ... SET revoked_after = removed_at, revocation_reason = 'removed' WHERE revoked_after IS NULL`) + index `workspace_member_removals_revocation_lookup_idx` on `(removed_user_id, revoked_after)`.
- 1.3 Add `public.check_my_revocation(p_jwt_iat timestamptz)` SECURITY DEFINER returning `(revoked, workspace_id, reason)`. User-global predicate (F5). Pin `search_path = public, pg_temp`. REVOKE all + GRANT EXECUTE to authenticated.
- 1.4 Update `public.remove_workspace_member` body to populate `revoked_after = now()` + `revocation_reason = 'removed'` on INSERT AND UPDATE `user_session_state.current_organization_id = NULL` when org matches affected workspace AND no remaining same-org membership (F6).
- 1.5 Create `public.update_workspace_member_role(p_workspace_id, p_user_id, p_new_role)` SECURITY DEFINER. Start body with `PERFORM set_config('workspace_audit.actor_user_id', auth.uid()::text, true)` (F2). Owner-check (42501). UPDATE role. INSERT revocation row (revocation_reason='role-changed'). UPDATE user_session_state if matching org. REVOKE all + GRANT EXECUTE to authenticated.
- 1.6 Write `064_workspace_member_revocation_lookup.down.sql` — minimal DROP FUNCTION + DROP COLUMN (~15 lines).
- 1.7 Amend `knowledge-base/legal/article-30-register.md` PA-19 §(g)(2) prose to "EXACTLY TWO SECURITY DEFINER bodies INSERT" (F1). Append PA-19 §(g) TOM (10) describing revocation lookup. Amend PA-20 §(b) Purposes to cover role-change events via `update_workspace_member_role`.
- 1.8 Write `apps/web-platform/test/supabase-migrations/064-workspace-member-revocation-lookup.test.ts` migration-shape lint. Assertions: column types; function signatures + search_path pins; GRANT/REVOKE; EXACTLY TWO `CREATE OR REPLACE FUNCTION` bodies contain `INSERT INTO public.workspace_member_removals` (F1); role-change body contains `PERFORM set_config('workspace_audit.actor_user_id'` (F2); both RPCs contain `UPDATE public.user_session_state` (F6).
- 1.9 Apply mig 064 to dev Supabase locally. Verify PostgREST schema-cache reload via manual RPC probe.

## Phase 2 — Middleware revocation lookup + signin banner

- 2.1 Add `export` keyword to `decodeJwtPayloadUnsafe` at `apps/web-platform/lib/supabase/tenant.ts:172`. Document the throw contract above the function. Run `git grep -nE "decodeJwtPayloadUnsafe"` to confirm no other consumers need updating.
- 2.2 In `apps/web-platform/middleware.ts`, after `await supabase.auth.getUser()` at ~line 123, inject the revocation-gate block from plan §2.2 with explicit try/catch on `decodeJwtPayloadUnsafe` (C2 + K-P0-1); `supabase.rpc("check_my_revocation", { p_jwt_iat: iat.toISOString() })` call; row-shape handling; on `revoked === true` call `clearSessionAndRedirect(request, "/auth/signin?revoked=" + (row.reason ?? "removed"))`.
- 2.3 Add `clearSessionAndRedirect` helper in middleware.ts with `Cache-Control: no-store, no-cache, must-revalidate` + dual-shape cookie clear (Domain-less AND `Domain=NEXT_PUBLIC_COOKIE_DOMAIN`, F8).
- 2.4 Edit `apps/web-platform/app/auth/signin/page.tsx` to read `searchParams.revoked`. Render banner above existing form for `"removed"` / `"role-changed"` values; passthrough on missing param.
- 2.5 Write `apps/web-platform/test/server/middleware-revocation-redirect.test.ts` — mocked supabase-js cases for 302+cache-control+dual-cookie, 503 (DB error), 401 (malformed JWT), 200 (signin passthrough).
- 2.6 Write `apps/web-platform/test/components/signin-revoked-banner.test.tsx` — `?revoked=removed` copy, `?revoked=role-changed` copy, no `?revoked` bare form.

## Phase 3 — Role-change wrapper + WS fan-out + tenant-isolation tests

- 3.1 Add `updateWorkspaceMemberRole(workspace_id, user_id, new_role)` in `apps/web-platform/server/workspace-membership.ts`. Calls the RPC; on success, iterate `getActiveSessions({ userId, workspaceId })` and `closeWithPreamble(session.ws, WS_CLOSE_CODES.MEMBERSHIP_REVOKED, {})` per active session. Mirrors lines 187-192. No `reason` field on the preamble (cut C6 — defer to AC20-2).
- 3.2 Write `apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` with `TENANT_INTEGRATION_TEST=1` gate, synthetic email pattern, mintFounderJwt fixture, and:
  - 3.2.1 Positive control + service-role re-read poison; `randomUUID()` for uuid payloads.
  - 3.2.2 Multi-workspace user-global predicate (F5).
  - 3.2.3 Clock-skew tolerance (±1s service-role poison).
  - 3.2.4 Role-change: verify `workspace_members.role` change + `workspace_member_removals` row + `workspace_member_actions.actor_user_id` non-NULL (F2 verification).
  - 3.2.5 RLS dual-shape deny (`42501` OR `[]`) per learning 2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.
- 3.3 Run `./node_modules/.bin/vitest run apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` with `TENANT_INTEGRATION_TEST=1` against dev Supabase. Verify all pass.
- 3.4 AC15: trigger a supabase-js refresh after a removal in the integration suite; re-decode the post-refresh JWT; assert `current_organization_id` claim is absent for the affected org.

## Phase 4 — Ship

- 4.1 Run `tsc --noEmit` and `./node_modules/.bin/vitest run` (full suite). Fix any failures.
- 4.2 Run `bash scripts/test-all.sh`.
- 4.3 Run `/soleur:gdpr-gate` against the diff per Phase 2.7. Fold any fold-ins inline.
- 4.4 Run `/soleur:preflight` (migrations, security headers, lockfiles per Check 6).
- 4.5 Measure baseline auth-middleware RPS from Vercel + Sentry; record in PR body for AC14.
- 4.6 Push commits; mark PR #4345 ready (`gh pr ready 4345`). PR body MUST contain `Closes #4307` on its own body line (F3 / AC12).
- 4.7 Pass review (5-agent /soleur:review at single-user-incident threshold including `user-impact-reviewer`).
- 4.8 Squash-merge. Apply mig 064 via `web-platform-release.yml#migrate` (dev → prd ack-gated).
- 4.9 `gh issue close 4307 -r completed -c "Closed by PR #N..."`.
- 4.10 File follow-up issues per AC20: (1) mig 060 hook-side membership validation; (2) WS preamble `reason` field.
- 4.11 Run `/soleur:compound` to capture session learnings (e.g., 5-agent panel mechanics, RPC-collapse pattern).

## Out of scope for PR-1

- PR-2 chat-attachments storage-bucket workspace-keyed predicate (#4318 residual).
- Paper-closes #4304/#4305/#4306 (handled in PR-3 housekeeping per bundle spec NG6).
- Hook-side membership validation (filed as follow-up at AC20-1).
- WS preamble `reason` field (filed as follow-up at AC20-2).
- Disclosure modal at first invite-send (CPO §3, deferred per spec NG4).
