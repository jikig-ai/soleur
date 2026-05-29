---
title: "feat: cancel a pending workspace invite (owner-side revoke)"
date: 2026-05-29
type: feature
issue: 4634
pr: 4632
branch: feat-cancel-pending-invite
worktree: .worktrees/feat-cancel-pending-invite
spec: knowledge-base/project/specs/feat-cancel-pending-invite/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-29-cancel-pending-invite-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan: Cancel a Pending Workspace Invite (owner-side revoke)

✨ **Type:** feature · **Issue:** #4634 · **Draft PR:** #4632 · **Threshold:** single-user incident

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Risks & Mitigations (+ Precedent Diff), Research Insights, Files to Edit (negative-confirmed).
**Gates run:** 4.6 User-Brand Impact (pass), 4.7 Observability (pass — 5 fields, no SSH), 4.8 PAT-shape (pass), 4.4 Precedent-Diff (SECURITY DEFINER RPC + WORM trigger), 4.45 verify-the-negative.

### Key Improvements

1. **WORM-trigger idiom correction (load-bearing):** the codebase has two WORM idioms. `workspace_invitations` (075) uses **negative-rejection** (fall-through-permit); `byok_delegations` (064) uses **positive-allowlist**. Migration 083 must mirror 075 — add only *re-mutation* rejection arms for `revoked_at`/`revoked_by`; NULL→NOT-NULL is already permitted. Copying 064's column-by-column allowlist would over-constrain.
2. **Revoke RPC: RETURN not RAISE on already-revoked.** Mirror `decline_workspace_invitation`'s `{ok:false, reason:'already_revoked'}` (not byok's RAISE), so the service wrapper maps the reason to HTTP 409 instead of losing it as `rpc_failed`.
3. **Grant posture: `TO service_role` only** (075 convention), not byok's `TO authenticated` — this feature routes through the service client.
4. **Leaked-link path needs NO accept-page edit** (negative-confirmed): `invite/[token]/page.tsx` renders a generic message for any `!result.ok`; the FR4 `'revoked'` reason falls into the existing catch-all.

### New Considerations Discovered

- 409 Conflict is the correct status for `already_*` terminal states (distinct from 404) — added to the reason→HTTP map.
- FR2 requires checking BOTH `res.ok` AND parsed `{ok:true}`; optimistic restore must re-sort by `created_at desc` to preserve row position.

## Overview

A workspace **owner** can create invites and remove existing members, but cannot revoke a
**pending** invite. A typo'd email or a never-accepted invite stays live until it expires (7 days),
with no cleanup path. Discovered while dogfooding multi-user in production (Settings → Members →
Team; the Pending invites list is display-only).

This is a **CRUD-hole fill**, not a new pattern. Every adjacent primitive exists:
- **Invitee side:** `accept_workspace_invitation` / `decline_workspace_invitation` RPCs + routes.
- **Owner side:** `remove-member` route is the verbatim authorization template.
- **State model:** `workspace_invitations` already uses soft-state columns (`accepted_at`,
  `declined_at`); cancellation adds the symmetric `revoked_at` (+ `revoked_by`).
- **Soft-revoke precedent (4 in-repo):** `scope_grants` (mig 048), `template_authorizations`
  (053), `byok_delegations` (064) all use `revoked_at`/`revoked_by` + SECURITY DEFINER revoke RPC.

Scope is **cancel only**. Resend/re-issue is explicitly deferred (Non-Goals).

No new dependency, no new infrastructure surface. The migration auto-applies on merge via
`web-platform-release.yml#migrate` (path-filtered `apps/web-platform/**`).

## Research Reconciliation — Spec vs. Codebase

The spec is accurate. Five facts the spec does **not** state that materially shape implementation:

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| TR1: add `revoked_at`/`revoked_by` columns | `workspace_invitations` has a **WORM trigger** `workspace_invitations_no_mutate` (mig 075:93-159) that **rejects any UPDATE** touching a column it doesn't explicitly allow (accepted_at / declined_at only). A naïve `UPDATE … SET revoked_at` is rejected with `P0001`. | Migration 083 MUST extend the WORM trigger to permit the `revoked_at` NULL→NOT-NULL one-time set + `revoked_by` NULL→NOT-NULL set (mirroring the accepted_at/declined_at immutability arms at 075:117-124). Add a trigger-arm rejecting NOT-NULL→NULL and value-change. **Load-bearing**: without it the RPC fails at runtime. |
| TR2: "set `revoked_at = now()`" | Sibling revoke RPCs (`byok_delegations` 064:563) use `clock_timestamp()` not `now()` for revoke timestamps (transaction-clock vs statement-clock; `now()` is fine for a single-row revoke but precedent diverges). | Use `now()` — single-statement revoke, no batch/loop; matches `decline_workspace_invitation` (075:393) which uses `now()`. Documented so deepen-plan's precedent-diff (Phase 4.4) doesn't re-litigate. |
| TR5: route "mirroring remove-member" | `remove-member/route.ts` (verified) is the exact template: `validateOrigin`→`auth.getUser`→`resolveTeamMembershipPageData`→`Identity`+`isTeamWorkspaceInviteEnabled`→workspace-match (403 `workspace_mismatch`)→owner-check via `pageData.data.members.find(...).role==="owner"` (403 `not_owner`)→service call. | Mirror verbatim. Body is `{ workspaceId, invitationId }` (not `userId`). |
| FR2: server-confirmed **optimistic** removal | `remove-member`'s client (`team-membership-list.tsx`) uses `window.confirm` + `window.location.reload()` on success / `window.alert` on failure — **NOT** optimistic. The spec deliberately mandates the optimistic pattern instead. `PendingInvitesList` already holds `useState(initialInvites)`, so optimistic remove+restore fits there natively. | Implement optimistic removal in `PendingInvitesList`: remove row from local state only after `res.ok && {ok:true}`; on error restore + surface inline message. Do NOT copy remove-member's reload pattern. |
| TR7: "extend `e2e/team-membership.e2e.ts`" | The authenticated interactive flows in that file are `describe.skip` — the public Playwright project's mock-Supabase surface does not emulate `workspace_invitations`. Real coverage lives in **vitest** unit/integration tests (`test/server/*.test.ts`, opt-in `TENANT_INTEGRATION_TEST=1`) + migration-regex tests (`test/supabase-migrations/`). | TR7's behavioral coverage lands as vitest tests (route + service + migration-regex). The e2e file gets one documented `describe.skip` placeholder for the cancel flow (consistent with the existing skip block). **Test runner is `vitest`, NOT `bun test`** (`apps/web-platform/bunfig.toml` blocks bun discovery via `pathIgnorePatterns=["**"]`, #1469). All test commands use `./node_modules/.bin/vitest run <path>`. |

Also confirmed (no drift): `revoke_workspace_invitation` RPC absent, `revoked_at` column absent on
`workspace_invitations`, `PendingInvitesList` not passed `isOwner` — all gaps real. Next migration
number is **083**. RPC TS typing must use explicit `SupabaseClient` not `ReturnType<typeof
createClient>` (learning 2026-04-05-supabase-returntype-resolves-to-never).

## User-Brand Impact

- **If this lands broken, the user experiences:** a "Cancel" button that appears to remove a pending
  invite but the invite stays live and acceptable (silent no-op), OR an owner of workspace A cancels
  workspace B's invite (cross-tenant write), OR a non-owner cancels invites.
- **If this leaks, the user's workspace membership boundary is exposed via:** a cross-workspace
  revoke (owner of A mutating B's `workspace_invitations` row) or a non-owner gaining a destructive
  membership-control action on a multi-tenant production surface.
- **Brand-survival threshold:** single-user incident.

Three confirmed vectors (operator-validated in brainstorm), each with its brake:
1. *Wrong invite / non-owner cancels* → owner-check at route AND re-checked inside SECURITY DEFINER RPC; invitation-id-scoped UPDATE.
2. *Cross-workspace leak* (owner of A cancels B's invite) → route workspace-match gate (403 `workspace_mismatch`) + RPC re-verifies caller owns `v_inv.workspace_id`.
3. *Silent no-op* (button "works", invite stays live) → UI commits removal only on server `{ ok: true }`; on error restores row + surfaces message.

**CPO sign-off required at plan time before `/work` begins.** Invoke CPO domain leader if not
already covered by Phase 2.5 carry-forward, or confirm CPO has reviewed the brainstorm (brainstorm
Domain Assessments covered Engineering + Product inline). `user-impact-reviewer` runs at review-time
per `review/SKILL.md`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (FR1):** `PendingInvitesList` receives `isOwner: boolean`; the Cancel control renders
  **only** when `isOwner === true`. team page passes the already-computed
  `data.members.some((m) => m.userId === data.currentUserId && m.role === "owner")` (currently passed
  only to `TeamMembershipList` at team/page.tsx:71).
- [ ] **AC2 (FR2):** On cancel click, the row is removed from `PendingInvitesList` local state **only
  after** `fetch` resolves `res.ok` and body `{ ok: true }`. On any error the row is restored and an
  inline error message is shown. Verifiable via component test: mock a 500 → assert row still present
  + error text; mock `{ok:true}` → assert row gone.
- [ ] **AC3 (FR3):** owner Pending-invites query (team/page.tsx:36-43) and
  `getPendingInvitesForUser` (workspace-invitations.ts:78-93, both `byUserId` and `byEmail` legs)
  add `.is("revoked_at", null)`. A revoked invite is absent from both. Verifiable via integration
  test (`TENANT_INTEGRATION_TEST=1`) asserting count drops by 1 after revoke.
- [ ] **AC4 (FR4):** `lookup_invitation_by_token` returns `{ ok:false, reason:"revoked" }` (new
  reason) when `revoked_at IS NOT NULL`. Verifiable via migration-regex test asserting the predicate
  + integration test asserting a revoked token is not acceptable.
- [ ] **AC5 (FR5):** the duplicate-pending guard in `create_workspace_invitation` (075:229-239) adds
  `AND revoked_at IS NULL` so a revoked invite does not block re-inviting the same email. Verifiable:
  integration test revokes then re-creates same email → second create succeeds.
- [ ] **AC6 (TR1 + WORM):** migration 083 adds `revoked_at timestamptz NULL` + `revoked_by uuid NULL
  REFERENCES public.users(id) ON DELETE RESTRICT`, AND extends `workspace_invitations_no_mutate` to
  permit `revoked_at`/`revoked_by` NULL→NOT-NULL one-time set + reject re-mutation. Migration-regex
  test asserts both the `ADD COLUMN revoked_at` and the trigger arm exist.
- [ ] **AC7 (TR2):** `revoke_workspace_invitation(p_invitation_id uuid, p_caller_user_id uuid)`
  SECURITY DEFINER, `SET search_path = public, pg_temp`, `REVOKE … FROM PUBLIC, anon, authenticated`
  + `GRANT EXECUTE … TO service_role`. Re-checks caller is owner of `v_inv.workspace_id`; rejects
  `already_accepted` / `already_declined` / `already_revoked` / `invitation_not_found`; sets
  `revoked_at = now(), revoked_by = v_caller`. Verifiable via migration-regex test (search_path pin,
  grant posture, owner re-check) + integration test (happy path, double-revoke rejected).
- [ ] **AC8 (TR4):** `revokeWorkspaceInvitation(invitationId, callerUserId)` wrapper in
  `server/workspace-invitations.ts` mirroring `declineWorkspaceInvitation` (230-251): typed result
  `{ ok:true } | { ok:false; reason:string }`, error mapping, `reportSilentFallback` on RPC error.
  Verifiable via service unit test with mocked supabase client.
- [ ] **AC9 (TR5):** `POST /api/workspace/cancel-invite/route.ts` exports HTTP handlers **only**
  (`cq-nextjs-route-files-http-only-exports`). Auth chain identical to remove-member; returns 403
  `workspace_mismatch` on cross-workspace, 403 `not_owner` for non-owner, 404 when flag off, 401
  unauthenticated. Verifiable via route test exercising each branch.
- [ ] **AC10 (TR6):** RPC/route failure paths reach Sentry/Better Stack via `reportSilentFallback`
  with `feature: "workspace-invitations", op: "revoke"` and the original error string preserved as
  `message`. Verifiable: service test asserts `reportSilentFallback` called on RPC error.
- [ ] **AC11 (TR7):** vitest tests written **before** implementation (`cq-write-failing-tests-before`):
  owner-cancels-happy-path, non-owner-rejected (403), cross-workspace-rejected (403),
  revoked-token-not-acceptable, re-invite-after-cancel. `./node_modules/.bin/vitest run` green.
  `npx tsc --noEmit` clean.
- [ ] **AC12:** down-migration `083_*.down.sql` drops the RPC, reverts the WORM trigger to the 075
  body, and drops the two columns (mirroring 075.down ordering).
- [ ] **AC13:** Draft PR #4632 body uses `Closes #4634` (this is a code change applied at merge, not
  an ops-remediation — `Closes` is correct here).

### Post-merge (operator)

- [ ] **AC14:** Migration auto-applies via `web-platform-release.yml#migrate` on merge (path-filtered).
  No operator step. **Automation: built into the release workflow** — the merge IS the apply.
- [ ] **AC15:** Flag `FLAG_TEAM_WORKSPACE_INVITE` flip remains gated on the parallel legal PR
  (per roadmap MU4); this feature ships behind the same flag and needs no separate flip. The Cancel
  control is only reachable when the flag is already on.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

1. `grep -n "workspace_invitations_no_mutate" apps/web-platform/supabase/migrations/075_workspace_invitations.sql` — confirm WORM trigger body to mirror.
2. `ls apps/web-platform/supabase/migrations/ | grep -oE '^[0-9]+' | sort -n | tail -1` — confirm next number is 083.
3. Read `byok_delegations` revoke RPC (mig 064:520-580) + `template_authorizations` revoke (053:340-365) as soft-revoke precedents for deepen-plan Phase 4.4 diff.
4. Confirm `./node_modules/.bin/vitest --version` resolves (runner is vitest, not bun).

### Phase 1 — Failing tests (RED, `cq-write-failing-tests-before`)

- **Files to create:**
  - `apps/web-platform/test/supabase-migrations/083-revoke-workspace-invitation.test.ts` — regex
    assertions: `ADD COLUMN revoked_at`, `revoked_by … REFERENCES public.users`, WORM trigger arm
    for `revoked_at`, RPC `SET search_path = public, pg_temp`, `SECURITY DEFINER`, owner re-check,
    `GRANT EXECUTE … TO service_role`, lookup predicate `revoked_at IS NULL`, duplicate-guard
    `revoked_at IS NULL`. (Mirror `test/supabase-migrations/064-byok-delegations.test.ts` shape.)
  - `apps/web-platform/test/server/workspace-invitations-revoke.test.ts` — service wrapper unit
    tests (mocked supabase client): RPC error → `{ok:false}` + `reportSilentFallback` called; RPC
    `{ok:false, reason}` passthrough; happy path `{ok:true}`.
  - `apps/web-platform/test/server/cancel-invite-route.test.ts` (or extend existing route-test
    convention) — 401 / 404-flag-off / 403 workspace_mismatch / 403 not_owner / 200 happy.
  - `apps/web-platform/components/settings/pending-invites-list.test.tsx` — optimistic remove on
    `{ok:true}`; restore + error text on 500; Cancel control absent when `isOwner=false`.
  - Integration coverage (opt-in `TENANT_INTEGRATION_TEST=1`) for FR3/FR4/FR5 against a real
    Supabase: revoke → absent from owner query + invitee query; revoked token not acceptable;
    re-invite after revoke succeeds. (Extend or sibling `test/server/workspace-members.test.ts` style.)
  - `apps/web-platform/e2e/team-membership.e2e.ts` — add one `describe.skip` placeholder documenting
    the cancel flow (consistent with existing skip block; mock surface limitation).

### Phase 2 — Migration 083 (DDL + WORM trigger + RPC + predicate updates)

- **Files to create:**
  - `apps/web-platform/supabase/migrations/083_revoke_workspace_invitation.sql`:
    1. `ALTER TABLE public.workspace_invitations ADD COLUMN IF NOT EXISTS revoked_at timestamptz NULL, ADD COLUMN IF NOT EXISTS revoked_by uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT;`
    2. `CREATE OR REPLACE FUNCTION public.workspace_invitations_no_mutate()` — re-issue the 075 body
       **plus** arms: reject `revoked_at` NOT-NULL→NULL or value-change once set; reject `revoked_by`
       NOT-NULL→NULL or change once set; allow NULL→NOT-NULL (the revoke set). (Triggers reference
       the function by name; `CREATE OR REPLACE` updates in place — no `DROP TRIGGER` needed.)
    3. `CREATE OR REPLACE FUNCTION public.revoke_workspace_invitation(p_invitation_id uuid, p_caller_user_id uuid DEFAULT NULL)` — SECURITY DEFINER, `SET search_path = public, pg_temp`,
       `LANGUAGE plpgsql`. `v_caller := COALESCE(p_caller_user_id, auth.uid())`; `SELECT * INTO v_inv
       … WHERE id = p_invitation_id FOR UPDATE`; reject `invitation_not_found` / `already_accepted` /
       `already_declined` / `already_revoked`; re-check `EXISTS(workspace_members WHERE workspace_id =
       v_inv.workspace_id AND user_id = v_caller AND role='owner')` else `caller_not_owner`; `UPDATE …
       SET revoked_at = now(), revoked_by = v_caller WHERE id = p_invitation_id`; return
       `jsonb_build_object('ok', true)`. `REVOKE ALL … FROM PUBLIC, anon, authenticated` +
       `GRANT EXECUTE … TO service_role`.
    4. `CREATE OR REPLACE FUNCTION public.lookup_invitation_by_token` — add `IF v_inv.revoked_at IS
       NOT NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'revoked'); END IF;` after the
       declined check (075:460).
    5. `CREATE OR REPLACE FUNCTION public.create_workspace_invitation` — add `AND revoked_at IS NULL`
       to the duplicate-pending guard (075:233-235).
  - `apps/web-platform/supabase/migrations/083_revoke_workspace_invitation.down.sql`:
    drop `revoke_workspace_invitation`; `CREATE OR REPLACE` lookup + create RPCs back to 075 bodies;
    `CREATE OR REPLACE workspace_invitations_no_mutate` back to 075 body; `ALTER TABLE … DROP COLUMN
    revoked_by, DROP COLUMN revoked_at`.
  - *(Optional, recommended)* `apps/web-platform/supabase/verify/083_revoke_workspace_invitation.sql`
    — idempotent post-apply sentinel (column exists + RPC exists + grant posture) for the release
    workflow's `verify` job, which auto-closes the follow-through issue.

### Phase 3 — Service wrapper (TR4)

- **Files to edit:** `apps/web-platform/server/workspace-invitations.ts`
  - Add `revokeWorkspaceInvitation(invitationId: string, callerUserId: string)` after
    `declineWorkspaceInvitation` (251). Mirror exactly: `service.rpc("revoke_workspace_invitation",
    { p_invitation_id, p_caller_user_id })`; on error `log.error` + `reportSilentFallback(null, {
    feature: "workspace-invitations", op: "revoke", message: error.message })` + `{ok:false,
    reason:"rpc_failed"}`; passthrough `result.reason`. Typed `RevokeInvitationResult = {ok:true} |
    {ok:false; reason:string}`.
  - Add `.is("revoked_at", null)` to **both** legs of `getPendingInvitesForUser` (lines 83-85 and
    89-92) — `byUserId` and `byEmail`. (FR3)

### Phase 4 — API route (TR5)

- **Files to create:** `apps/web-platform/app/api/workspace/cancel-invite/route.ts`
  - Copy `remove-member/route.ts` verbatim; change: import `revokeWorkspaceInvitation`; body is
    `{ workspaceId, invitationId }`; validate both are non-empty strings; workspace-match against
    `pageData.data.workspaceId` (403 `workspace_mismatch`); owner-check via `pageData.data.members`
    (403 `not_owner`); call `revokeWorkspaceInvitation(invitationId, user.id)`; map reasons:
    `caller_not_owner`→403, `workspace_mismatch`→403, `invitation_not_found`→404, `already_*`→409,
    else 500. Return `{ ok: true }`. **HTTP exports only** (`cq-nextjs-route-files-http-only-exports`).

### Phase 5 — UI: optimistic Cancel control (FR1 + FR2)

- **Files to edit:**
  - `apps/web-platform/components/settings/pending-invites-list.tsx` — add `isOwner: boolean` prop;
    render a Cancel button per row only when `isOwner`; on click: snapshot the row, optimistically
    `setInvites(prev => prev.filter(i => i.id !== invite.id))` **after** `await fetch(...)` resolves
    `res.ok && (await res.json()).ok === true`; on failure restore the snapshot via `setInvites` and
    set an inline error state for that row. Add `pending`/disabled state on the button during the
    request. (FR2 — commit only on server confirm.)
  - `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` — pass `isOwner={…}` to
    `PendingInvitesList` (line 77), reusing the same boolean computed at line 71.

### Phase 6 — Green + typecheck

- `./node_modules/.bin/vitest run apps/web-platform/test/supabase-migrations/083-revoke-workspace-invitation.test.ts apps/web-platform/test/server/workspace-invitations-revoke.test.ts apps/web-platform/test/server/cancel-invite-route.test.ts apps/web-platform/components/settings/pending-invites-list.test.tsx`
- `npx tsc --noEmit` (use explicit `SupabaseClient` type for RPC results).
- Integration suite locally with `TENANT_INTEGRATION_TEST=1` if a dev Supabase is available
  (DEV project only — `hr-dev-prd-distinct-supabase-projects`; never against prod).

## Files to Edit

- `apps/web-platform/server/workspace-invitations.ts` (wrapper + both query legs)
- `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` (pass `isOwner`; owner query `revoked_at IS NULL`)
- `apps/web-platform/components/settings/pending-invites-list.tsx` (`isOwner` prop + optimistic Cancel)
- `apps/web-platform/e2e/team-membership.e2e.ts` (documented skip placeholder)

## Files to Create

- `apps/web-platform/supabase/migrations/083_revoke_workspace_invitation.sql`
- `apps/web-platform/supabase/migrations/083_revoke_workspace_invitation.down.sql`
- `apps/web-platform/supabase/verify/083_revoke_workspace_invitation.sql` (optional sentinel)
- `apps/web-platform/app/api/workspace/cancel-invite/route.ts`
- `apps/web-platform/test/supabase-migrations/083-revoke-workspace-invitation.test.ts`
- `apps/web-platform/test/server/workspace-invitations-revoke.test.ts`
- `apps/web-platform/test/server/cancel-invite-route.test.ts`
- `apps/web-platform/components/settings/pending-invites-list.test.tsx`

## Open Code-Review Overlap

None. (Run at Step 1.7.5: no open `code-review` issue bodies reference the files above. Re-verify at
work time via `gh issue list --label code-review --state open --json number,title,body`.)

## Observability

```yaml
liveness_signal:
  what: revoke_workspace_invitation RPC success/failure ratio + cancel-invite route 2xx/5xx
  cadence: per-request (on-demand, owner action)
  alert_target: Sentry (error events) + Better Stack (structured warn logs)
  configured_in: server/workspace-invitations.ts (reportSilentFallback), server/observability.ts
error_reporting:
  destination: Sentry via reportSilentFallback(null, { feature:"workspace-invitations", op:"revoke", message })
  fail_loud: true  # RPC error → log.error + reportSilentFallback + {ok:false}; never silent
failure_modes:
  - mode: RPC rejects (caller_not_owner / workspace_mismatch / already_*)
    detection: route returns 4xx with reason; client surfaces inline error + restores row
    alert_route: structured warn log (expected-rejection, not paged)
  - mode: RPC infra error (rpc_failed)
    detection: reportSilentFallback → Sentry
    alert_route: Sentry issue
  - mode: WORM trigger rejects the revoke UPDATE (regression if trigger arm missing)
    detection: RPC raises P0001 → rpc_failed → Sentry; migration-regex test catches at CI
    alert_route: Sentry + CI failure
  - mode: stale-list silent no-op (row removed in UI but server failed)
    detection: FR2 guard — UI only removes on {ok:true}; on failure restores row
    alert_route: inline UI error (user-visible), no server alert needed
logs:
  where: pino structured logs (createChildLogger "workspace-invitations") → Better Stack
  retention: per existing Better Stack retention (no change)
discoverability_test:
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 -X POST -H "content-type: application/json" -d "{}" https://app.soleur.ai/api/workspace/cancel-invite
  expected_output: "401 or 403 or 400 (route mounted; auth/CSRF/body gate fires before any 200 — never 404)"
```

## Test Scenarios

| Scenario | Layer | Expected |
|---|---|---|
| Owner cancels a pending invite | route + integration | 200 `{ok:true}`; row gone from owner + invitee queries; token not acceptable |
| Non-owner attempts cancel | route | 403 `not_owner`; RPC also re-rejects `caller_not_owner` |
| Owner of A cancels B's invite | route | 403 `workspace_mismatch`; RPC re-rejects on workspace owner re-check |
| Cancel an already-accepted invite | RPC | `{ok:false, reason:"already_accepted"}` → 409 |
| Double-cancel | RPC | second call `{ok:false, reason:"already_revoked"}` |
| Server fails mid-cancel | component | row restored, inline error shown (no silent no-op) |
| Re-invite same email after cancel | integration | second `create_workspace_invitation` succeeds (guard ignores revoked) |
| Revoked token used at accept | RPC | `lookup_invitation_by_token` → `{ok:false, reason:"revoked"}` |
| WORM trigger arm missing (negative) | migration-regex test | test fails; RPC would raise P0001 |

## Risks & Mitigations

- **WORM trigger blocks the revoke UPDATE** (highest risk). The 075 trigger rejects any unlisted
  column mutation. Mitigation: migration 083 re-issues the trigger with explicit `revoked_at` /
  `revoked_by` arms; migration-regex test asserts the arm exists. **See Precedent Diff below** —
  the 075 table uses a negative-rejection WORM idiom (NOT the 064 positive-allowlist); the new arms
  only forbid *re-mutation* (NULL→NOT-NULL is already permitted by fall-through).
- **RPC result typed `never`** (TS): use explicit `SupabaseClient` import, not `ReturnType<typeof
  createClient>` (learning 2026-04-05).
- **`now()` vs `clock_timestamp()`**: single-statement revoke; `now()` matches the sibling
  `decline_workspace_invitation`. No batch/loop, so statement-clock is correct. Documented to
  pre-empt deepen-plan re-litigation.
- **Cross-PR cap/column coupling**: none — additive columns, no shared cap.
- **`revoked_by` FK to `public.users` ON DELETE RESTRICT**: matches the existing `inviter_user_id`
  posture (075:41). Art. 17 anonymise must NULL `revoked_by` too — fold into
  `anonymise_workspace_invitations` (075:407) if GDPR gate flags it (see Domain Review).

### Precedent Diff (deepen-plan Phase 4.4 — SECURITY DEFINER RPC + WORM trigger)

Two in-repo soft-revoke precedents grepped and diffed. **Critical finding: there are two distinct
WORM-trigger idioms in the codebase, and `workspace_invitations` must use its own (075) idiom, NOT
the byok (064) idiom.**

**WORM-trigger idiom — DO mirror 075's negative-rejection, NOT 064's positive-allowlist:**

| | `workspace_invitations` (075:93-152) — the table being changed | `byok_delegations` (064:280-360) |
|---|---|---|
| Idiom | **Negative rejection**: check specific immutability rules, `RAISE EXCEPTION` on violation, fall through to `RETURN NEW` | **Positive allowlist**: enumerate each allowed transition shape (Shape 1 revoke flip / anonymise), `RETURN NEW` on match, fall through to a terminal `RAISE EXCEPTION` |
| `accepted_at`/`declined_at` | `IF OLD.x IS NOT NULL AND NEW.x IS DISTINCT FROM OLD.x THEN RAISE` (one-time-set: NULL→NOT-NULL allowed, re-mutation rejected) — 075:117-124 | n/a |
| Revoke column | (new) | `IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL AND … all other cols unchanged AND attribution-check THEN RETURN NEW` |

**Plan response (corrects the Risks bullet above):** migration 083 mirrors the **075 idiom** —
add two rejection arms parallel to the `accepted_at`/`declined_at` arms:

```sql
-- revoked_at: NULL → NOT NULL permitted (one-time set); re-mutation rejected.
IF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
  RAISE EXCEPTION 'workspace_invitations revoked_at is immutable once set' USING ERRCODE = 'P0001';
END IF;
IF OLD.revoked_by IS NOT NULL AND NEW.revoked_by IS DISTINCT FROM OLD.revoked_by THEN
  RAISE EXCEPTION 'workspace_invitations revoked_by is immutable once set' USING ERRCODE = 'P0001';
END IF;
```

Because 075 is fall-through-permit, NULL→NOT-NULL on `revoked_at`/`revoked_by` is **already
permitted** by the absence of a blocking arm — the new arms only forbid *re-mutation*. This is
simpler than the 064 allowlist (no need to re-enumerate every unchanged column). Do NOT copy 064's
`AND NOT (OLD.x IS DISTINCT FROM NEW.x)` column-by-column guard — that idiom belongs to the
positive-allowlist table and would over-constrain here.

**Revoke RPC shape — mirror `decline_workspace_invitation` (075:360-398), borrow lock+idempotency
from byok (064:531-565):**

- `SELECT * INTO v_inv … WHERE id = p_invitation_id FOR UPDATE` — row-lock before validate (both
  precedents do this; prevents the accept/revoke race).
- Idempotency: byok 064 **RAISES** on already-revoked (`P0001`, `DETAIL='…:already_revoked'`);
  decline 075 **RETURNS** `{ok:false, reason:'already_declined'}`. **Mirror the 075 RETURN shape**
  (this table's convention) — return `{ok:false, reason:'already_revoked'}`, not RAISE. The service
  wrapper maps `reason` to HTTP status; a RAISE would surface as `rpc_failed` and lose the reason.
- Attribution: byok checks actor ∈ {grantor,grantee,created_by}; here the equivalent is the
  **owner re-check** `EXISTS(workspace_members WHERE workspace_id = v_inv.workspace_id AND user_id =
  v_caller AND role='owner')` → `caller_not_owner`. This is the tenant-boundary brake (vector 2).
- `now()` (statement-clock) is correct: single-statement revoke, no loop. byok uses
  `clock_timestamp()` because it revokes inside multi-statement sweep functions; decline 075 uses
  `now()`. Mirror decline.
- Grant posture: `REVOKE ALL … FROM PUBLIC, anon, authenticated; GRANT EXECUTE … TO service_role`
  (075 convention — route calls via service client). Do NOT add `TO authenticated` (064 does,
  because byok has a direct-authenticated-call path; this feature routes through the service client
  only, matching create/accept/decline).

No novel pattern — every shape has a 075 sibling. The one trap (positive-allowlist vs
negative-rejection idiom) is now explicit.

### Research Insights (deepen-plan)

**Best practices / edge cases confirmed against the codebase:**

- **Optimistic-UI restore pattern (FR2):** snapshot the removed row object before the `setInvites`
  filter, restore via `setInvites(prev => [...prev, snapshot])` on failure but re-sort by
  `created_at desc` (the owner query orders `created_at` descending — team/page.tsx:43) so the
  restored row lands in its original position, not at the end. Keep a per-row `pending`/`error`
  state keyed by `invite.id` so concurrent cancels on different rows don't clobber each other.
- **`res.ok` is necessary but not sufficient:** the route returns `{ ok: true }` JSON; FR2 requires
  checking BOTH `res.ok` AND the parsed body `{ ok: true }` (a 200 with an unexpected body must not
  commit the removal). Mirror the brainstorm's "server `{ ok: true }`" wording exactly.
- **Reason→HTTP map (route):** `not_owner`/`caller_not_owner`/`workspace_mismatch`→403,
  `invitation_not_found`→404, `already_accepted`/`already_declined`/`already_revoked`→409,
  `rpc_failed`/unknown→500. (409 Conflict is the correct code for "already in a terminal state" —
  distinct from 404; lets the client show "this invite was already cancelled/accepted" precisely.)
- **`lookup_invitation_by_token` reason value:** use `'revoked'` (FR4 / AC4). **Verified**: the
  invite landing page `app/(public)/invite/[token]/page.tsx:21,29` does NOT switch on `reason` — it
  renders a single generic message ("This invitation may have expired, already been used, or is no
  longer valid.") for any `!result.ok`. A revoked invite falls into this existing catch-all, so the
  cancelled-link path renders correctly with **no page edit**. The `'revoked'` reason is purely for
  the RPC contract / test assertion; do NOT add a landing-page file to Files to Edit.
- **Migration-regex test (vitest):** mirror `test/supabase-migrations/064-byok-delegations.test.ts`
  — read the `.sql` file as text, assert with `expect(sql).toMatch(/…/)`. Assert: `ADD COLUMN …
  revoked_at`, `revoked_by uuid`, `SET search_path = public, pg_temp` on the new RPC, `SECURITY
  DEFINER`, the owner re-check `EXISTS`, `GRANT EXECUTE … TO service_role`, the lookup `'revoked'`
  arm, and the duplicate-guard `revoked_at IS NULL`.

**New consideration surfaced by deepen (resolved):** the leaked-link-after-cancel path was a
candidate gap, but the landing page's generic `!result.ok` branch already covers it (verified
above). No additional file or copy work is needed — the FR4 predicate change is self-sufficient.

## Domain Review

**Domains relevant:** Engineering, Product (both assessed inline in brainstorm; carried forward).

### Engineering

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Pure additive CRUD-with-authz mirroring `remove-member` + `decline-invite`. Surfaces:
migration (`revoked_at`/`revoked_by` + SECURITY DEFINER RPC, `search_path` pinned to `pg_temp`),
service wrapper, new `/api/workspace/cancel-invite` route, `lookup_invitation_by_token` predicate
update, `PendingInvitesList` client action. WORM-trigger extension is the one non-obvious surface
(see Research Reconciliation). No new external dependency.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

This modifies an **existing** user-facing surface (`PendingInvitesList` on Settings → Members →
Team) by adding a Cancel control to existing rows — no new page, no new multi-step flow, no new
component file. Mechanical-escalation scan: no new file under `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx` (the new file is an API route + a new component **test**, not a component).
Tier = ADVISORY. Pipeline context → auto-accepted. The optimistic-removal UX is the spec-mandated
pattern; brainstorm Product assessment confirmed cancel-only is the right MVP slice. No domain
leader recommended a copywriter (single button label + one error string).

## Infrastructure (IaC)

None. Pure code change against an already-provisioned surface (`apps/web-platform/`). The migration
auto-applies via the existing `web-platform-release.yml#migrate` job on merge — no new server,
secret, vendor, cron, or persistent process. No Terraform changes.

## GDPR / Compliance Gate

In scope — TR1 adds columns to `workspace_invitations`, a PII-bearing table (`invitee_email`,
`invitee_user_id`), and adds a SECURITY DEFINER RPC. `/soleur:gdpr-gate` should run at this phase
(or be carried by deepen-plan). Pre-identified item for the gate: **`revoked_by` is a new
user-identifying column** — confirm `anonymise_workspace_invitations` (075:407) must also NULL
`revoked_by` on the Art. 17 cascade (it currently NULLs `inviter_user_id`/`invitee_email`/
`invitee_user_id` only). If the gate confirms, fold the `revoked_by = NULL` clause into migration 083
and the down-migration. Output is advisory; any Critical finding → operator-acked write to
`compliance-posture.md` + `compliance/critical` issue.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Hard DELETE the row | Rejected | Violates the WORM/append-only model (075 trigger forbids DELETE); loses audit trail; brainstorm chose soft-revoke. |
| Reuse `decline_workspace_invitation` (set `declined_at`) | Rejected | Conflates invitee-decline with owner-revoke in the audit trail; no `revoked_by`; semantically wrong. |
| Add a generic `status` enum column | Rejected | Magic-string/sentinel anti-pattern; codebase convention is paired soft-state timestamps (`accepted_at`/`declined_at`) + partial-null. Soft-revoke `revoked_at`/`revoked_by` matches. |
| Resend / re-issue in same PR | Deferred (Non-Goal) | YAGNI for the dogfooding incident; cancel + re-invite already covers wrong-email. **Tracking:** see Deferrals below. |

## Deferrals

- **Resend / re-issue invite** (new token, reset expiry): deferred per spec Non-Goals. Re-eval
  criteria: a user requests resend, or analytics show repeated cancel→re-invite churn. **Action:** a
  GitHub deferral issue should be filed at work/ship time (milestone: Post-MVP / Multi-User) so the
  deferral is tracked, not invisible (`wg-when-deferring-a-capability-create-a`).
- **"Expired" invites section in UI**: brainstorm Open Question 1 — expired invites don't render
  (owner query filters `expires_at > now()`), already inert. Not in scope; flag only if a future
  cleanup-UX need arises.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- The WORM trigger (`workspace_invitations_no_mutate`) is the silent blocker: any `UPDATE` touching
  a column the trigger doesn't whitelist raises `P0001`. The revoke RPC's UPDATE will fail at
  runtime unless migration 083 extends the trigger. The migration-regex test is the cheapest gate.
- Test runner is **vitest**, not bun — `apps/web-platform/bunfig.toml` sets `pathIgnorePatterns =
  ["**"]` (#1469). `bun test <file>` reports "filter did not match" even when the file exists. Use
  `./node_modules/.bin/vitest run <path>`.
- The owner-side Pending query (team/page.tsx) and `getPendingInvitesForUser` are **separate**
  queries — FR3 requires `revoked_at IS NULL` on **both** (and both legs of the latter). A single
  edit is insufficient.
- At `single-user incident` threshold, run deepen-plan (next pipeline step) — plan-review
  (DHH/Kieran/Simplicity) is structurally blind to the SQL-atomicity / SECURITY-DEFINER /
  WORM-trigger substance that data-integrity-guardian + identity-rbac-reviewer catch.

## Review Gates (carry-forward from spec)

- `identity-rbac-reviewer` — owner-check, workspace boundary, SECURITY DEFINER `search_path` pin,
  grant posture, WORM-trigger arm.
- `user-impact-reviewer` — `single-user incident` threshold; the three confirmed vectors
  (wrong-cancel, cross-workspace leak, silent no-op).
