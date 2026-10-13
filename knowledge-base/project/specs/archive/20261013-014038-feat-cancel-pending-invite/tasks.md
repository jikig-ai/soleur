---
feature: cancel-pending-invite
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-29-feat-cancel-pending-workspace-invite-plan.md
issue: 4634
pr: 4632
---

# Tasks: Cancel a Pending Workspace Invite (owner-side revoke)

Derived from the finalized + deepened plan. Test runner is **vitest** (`./node_modules/.bin/vitest
run <path>`), NOT bun (`apps/web-platform/bunfig.toml` blocks bun discovery, #1469).

## Phase 0 — Preconditions (verify, no code)

- 0.1 Confirm WORM trigger body in `075_workspace_invitations.sql` (negative-rejection idiom; arms at 117-124 for accepted_at/declined_at).
- 0.2 Confirm next migration number is 083 (`ls .../migrations | grep -oE '^[0-9]+' | sort -n | tail -1`).
- 0.3 Read `byok_delegations` revoke RPC (064:531-565) + WORM (064:280-360) and `template_authorizations` revoke (053:340-365) as precedents — but mirror the **075 idiom** (see plan Precedent Diff).
- 0.4 Confirm `./node_modules/.bin/vitest --version` resolves.

## Phase 1 — Failing tests (RED, `cq-write-failing-tests-before`)

- 1.1 Create `test/supabase-migrations/083-revoke-workspace-invitation.test.ts` — regex assertions: `ADD COLUMN revoked_at`, `revoked_by … REFERENCES public.users`, WORM re-mutation arm for `revoked_at`, RPC `SET search_path = public, pg_temp` + `SECURITY DEFINER` + owner re-check `EXISTS`, `GRANT EXECUTE … TO service_role`, lookup `'revoked'` arm, duplicate-guard `revoked_at IS NULL`. (Mirror `064-byok-delegations.test.ts`.)
- 1.2 Create `test/server/workspace-invitations-revoke.test.ts` — service wrapper unit tests (mocked supabase): RPC error → `{ok:false}` + `reportSilentFallback` called; `{ok:false,reason}` passthrough; happy `{ok:true}`.
- 1.3 Create `test/server/cancel-invite-route.test.ts` — 401 / 404-flag-off / 403 workspace_mismatch / 403 not_owner / 409 already_* / 200 happy.
- 1.4 Create `components/settings/pending-invites-list.test.tsx` — optimistic remove on `{ok:true}`; restore + error on 500; Cancel control absent when `isOwner=false`.
- 1.5 Integration coverage (opt-in `TENANT_INTEGRATION_TEST=1`, DEV Supabase only) — FR3/FR4/FR5: revoke → absent from owner + invitee queries; revoked token not acceptable; re-invite after revoke succeeds.
- 1.6 Add a documented `describe.skip` placeholder for the cancel flow to `e2e/team-membership.e2e.ts` (mock-surface limitation, consistent with existing skip block).

## Phase 2 — Migration 083 (DDL + WORM + RPC + predicates)

- 2.1 Create `supabase/migrations/083_revoke_workspace_invitation.sql`:
  - 2.1.1 `ALTER TABLE … ADD COLUMN IF NOT EXISTS revoked_at timestamptz NULL, ADD COLUMN IF NOT EXISTS revoked_by uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT`.
  - 2.1.2 `CREATE OR REPLACE FUNCTION workspace_invitations_no_mutate()` — re-issue 075 body + two re-mutation rejection arms (revoked_at, revoked_by). NULL→NOT-NULL stays permitted by fall-through. (No DROP TRIGGER — `CREATE OR REPLACE` updates in place.)
  - 2.1.3 `CREATE OR REPLACE FUNCTION revoke_workspace_invitation(p_invitation_id uuid, p_caller_user_id uuid DEFAULT NULL)` — SECURITY DEFINER, `SET search_path = public, pg_temp`; `FOR UPDATE` lock; RETURN `{ok:false,reason:'invitation_not_found'|'already_accepted'|'already_declined'|'already_revoked'}`; owner re-check → `caller_not_owner`; `UPDATE … SET revoked_at = now(), revoked_by = v_caller`; RETURN `{ok:true}`. `REVOKE ALL … FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE … TO service_role`.
  - 2.1.4 `CREATE OR REPLACE FUNCTION lookup_invitation_by_token` — add `IF v_inv.revoked_at IS NOT NULL THEN RETURN {ok:false, reason:'revoked'}` after the declined check.
  - 2.1.5 `CREATE OR REPLACE FUNCTION create_workspace_invitation` — add `AND revoked_at IS NULL` to the duplicate-pending guard.
- 2.2 Create `083_revoke_workspace_invitation.down.sql` — drop revoke RPC; CREATE OR REPLACE lookup + create + WORM back to 075 bodies; DROP COLUMN revoked_by, revoked_at.
- 2.3 (Optional) Create `supabase/verify/083_revoke_workspace_invitation.sql` — idempotent post-apply sentinel (column + RPC + grant posture) for the release `verify` job.
- 2.4 GDPR follow-through: if the GDPR gate confirms, add `revoked_by = NULL` to `anonymise_workspace_invitations` (075:407) in 083 + the down-migration.

## Phase 3 — Service wrapper (TR4)

- 3.1 Add `revokeWorkspaceInvitation(invitationId, callerUserId)` to `server/workspace-invitations.ts` after `declineWorkspaceInvitation` — mirror it; `reportSilentFallback(null, { feature:"workspace-invitations", op:"revoke", message })` on error; typed `RevokeInvitationResult`.
- 3.2 Add `.is("revoked_at", null)` to BOTH legs of `getPendingInvitesForUser` (byUserId 83-85, byEmail 89-92). (FR3)
- 3.3 Use explicit `SupabaseClient` type for RPC result (avoid `never`, learning 2026-04-05).

## Phase 4 — API route (TR5)

- 4.1 Create `app/api/workspace/cancel-invite/route.ts` — copy `remove-member/route.ts`; body `{ workspaceId, invitationId }`; workspace-match (403 `workspace_mismatch`); owner-check (403 `not_owner`); call `revokeWorkspaceInvitation(invitationId, user.id)`; reason→HTTP map (403/404/409/500); return `{ok:true}`. HTTP exports only (`cq-nextjs-route-files-http-only-exports`).

## Phase 5 — UI: optimistic Cancel (FR1 + FR2)

- 5.1 `components/settings/pending-invites-list.tsx` — add `isOwner: boolean` prop; render Cancel per row only when `isOwner`; on click snapshot row, `await fetch`, commit removal only on `res.ok && body.ok===true`, else restore (re-sort `created_at desc`) + inline error; per-row pending/error state keyed by id; disable button while pending.
- 5.2 `app/(dashboard)/dashboard/settings/team/page.tsx` — pass `isOwner={…}` to `PendingInvitesList` (line 77), reusing the boolean at line 71; add `.is("revoked_at", null)` to the owner pending query (36-43). (FR3)

## Phase 6 — Green + typecheck

- 6.1 `./node_modules/.bin/vitest run` over the new test files → green.
- 6.2 `npx tsc --noEmit` → clean.
- 6.3 (If DEV Supabase available) integration suite `TENANT_INTEGRATION_TEST=1` — DEV only (`hr-dev-prd-distinct-supabase-projects`).

## Phase 7 — Ship prep

- 7.1 PR #4632 body uses `Closes #4634` (code change applied at merge).
- 7.2 File a deferral issue for resend/re-issue (Non-Goal) — milestone Post-MVP / Multi-User (`wg-when-deferring-a-capability-create-a`).
- 7.3 Migration auto-applies via `web-platform-release.yml#migrate` on merge — no operator step.

## Review Gates (carry-forward)

- `identity-rbac-reviewer` — owner-check, workspace boundary, SECURITY DEFINER search_path pin, grant posture, WORM arm.
- `user-impact-reviewer` — single-user-incident threshold; three vectors (wrong-cancel, cross-workspace leak, silent no-op).
- CPO sign-off required before `/work` (frontmatter `requires_cpo_signoff: true`).
