---
title: "feat: workspace ownership transfer"
type: feat
date: 2026-05-27
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 4520
depends_on:
  - 4518
brainstorm: knowledge-base/project/brainstorms/2026-05-27-workspace-role-management-brainstorm.md
spec: knowledge-base/project/specs/feat-workspace-role-management/spec.md
---

# feat: Workspace Ownership Transfer

## Overview

Add atomic workspace ownership transfer to the Members tab. Single-owner strict model: exactly one owner per workspace at all times. Transfer = atomic swap via a dedicated `transfer_workspace_ownership` SECURITY DEFINER RPC that dual-writes `workspace_members.role` AND `organizations.owner_user_id` in one transaction.

**Dependency:** #4518 (Members tab PR) must merge first. It carries migration 067 (`update_workspace_member_role` RPC), the `TeamMembershipList` component, and the `updateWorkspaceMemberRole` TS wrapper. This plan builds on top of that foundation.

**What already exists (on `feat-team-workspace-members-tab`, not main):**
- `update_workspace_member_role` RPC with last-owner guard, self-change guard, actor GUC attribution (mig 067)
- `updateWorkspaceMemberRole` TS wrapper in `server/workspace-membership.ts` with SIGTERM + WS close cascade
- `workspace_member_actions` audit trigger capturing `role_changed` events (mig 063_workspace_member_actions.sql)
- `TeamMembershipList` with role badge and kebab menu (remove-only)
- `check-workspace-members-write-sites.sh` CI gate

**What this PR adds:**
- `transfer_workspace_ownership` RPC + restriction of `update_workspace_member_role` (single migration)
- `transferWorkspaceOwnership` TS wrapper + middleware `"ownership-transferred"` handler
- `app/api/workspace/transfer-ownership/route.ts` API route
- "Transfer ownership" kebab menu option + type-to-confirm dialog
- Fix `anonymise_organization_membership` to promote replacement member's role (pre-existing desync)

**Legal document updates** tracked separately (see Deferred Items below).

## User-Brand Impact

Carry-forward from brainstorm (2026-05-27, `USER_BRAND_CRITICAL=true`).

**If this lands broken, the user experiences:** ownerless workspace (locked out of invite/remove/audit), or unauthorized role escalation to owner.

**If this leaks, the user's data is exposed via:** cross-workspace role mutation (forged workspaceId), or retroactive audit-log PII exposure to unauthorized new owner.

**Brand-survival threshold:** `single-user incident` — one mis-written RPC that leaves a workspace ownerless or grants ownership without authorization.

CPO sign-off: covered by brainstorm Phase 0.5 CPO assessment (2026-05-27). `user-impact-reviewer` will be invoked at review time.

## Research Insights

**Existing patterns (from brainstorm repo-research + CTO assessment):**

| Pattern | Source | Applies to |
|---------|--------|-----------|
| SECURITY DEFINER RPC with `SET search_path = public, pg_temp` | mig 053, 058, 062, 063, 067 | New transfer RPC |
| Actor GUC `workspace_audit.actor_user_id` via `set_config()` | mig 063 trigger, 067 RPC | Transfer RPC |
| REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT TO authenticated | All workspace RPCs | Transfer RPC |
| invite-member API route pattern (CSRF, auth, flag gate, workspace mismatch, owner check) | `app/api/workspace/invite-member/route.ts` | Transfer API route |
| `removeWorkspaceMember` TS wrapper (RPC call + SIGTERM + WS close) | `server/workspace-membership.ts` | Transfer TS wrapper |
| `workspace_member_removals` revocation ledger row | mig 062, 067 | Transfer RPC |
| F6 session clear (`user_session_state.current_organization_id = NULL`) | mig 067 | Transfer RPC |

**14 learnings applied** (from brainstorm learnings-researcher):
- WORM trigger bypass: GUC-only pattern, not `current_user = 'service_role'` (2026-05-18)
- Column-level REVOKE: table-level first, then re-grant safe columns (2026-03-20)
- Supabase default privileges: must REVOKE from named roles, not just PUBLIC (2026-05-06)
- RLS `FOR ALL USING` applies to writes — no `WITH CHECK (true)` (2026-04-18)
- Session invalidation gap (#4307): F6 mitigates but doesn't eliminate JWT window

**Dual ownership source of truth** (learning 2026-05-27): `organizations.owner_user_id` and `workspace_members.role = 'owner'` must always be updated atomically. Call sites reading `organizations.owner_user_id`:
- `server/account-delete.ts:670`
- `server/dsar-export-allowlist.ts:190`
- `server/dsar-export.ts:874`
- `supabase/migrations/063_workspace_member_actions.sql:256` (`list_workspace_member_actions`)

**5-agent plan review applied** (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer):
- Attestation must link to `workspace_members.attestation_id` on promote UPDATE (Kieran P0-1)
- `anonymise_organization_membership` (mig 065) must promote replacement member's role (Arch-Strat P0-2)
- Middleware must handle `"ownership-transferred"` revocation reason (Arch-Strat P0-3)
- SIGTERM/WS-close only for demoted owner, not new owner (DHH P2-3 + Spec-Flow P0-5)
- `TeamMembershipPageData` must include `organizationName` for confirmation dialog (Spec-Flow P0-2)
- Self-transfer must RAISE explicitly, not silently no-op (Kieran P1-5)
- `CREATE OR REPLACE` on `update_workspace_member_role` must carry full ~90-line body (Arch-Strat P1-1)
- Attestation column mapping: `inviter_user_id = old owner`, `invitee_user_id = new owner` (Kieran P1-1)

## Open Code-Review Overlap

None — no open code-review issues touch `workspace-membership.ts`, `team-membership-list.tsx`, or workspace API routes.

## Implementation Phases

### Phase 0: Preconditions

- [ ] Verify #4518 has merged to main (`gh pr view 4518 --json state,mergedAt`)
- [ ] Verify migration 067 exists on main (`ls apps/web-platform/supabase/migrations/067_*`)
- [ ] Verify `updateWorkspaceMemberRole` exists in `server/workspace-membership.ts`
- [ ] Determine next migration number: `ls apps/web-platform/supabase/migrations/*.sql | tail -1`
- [ ] Read `apps/web-platform/app/api/workspace/invite-member/route.ts` for API route pattern

### Phase 1: Migration

Create migration `NNN_transfer_workspace_ownership.sql` (and `.down.sql`). This single migration contains three functions: the new transfer RPC, the restricted `update_workspace_member_role`, and the fixed `anonymise_organization_membership`.

**1A: `transfer_workspace_ownership` RPC**

```sql
CREATE OR REPLACE FUNCTION public.transfer_workspace_ownership(
  p_workspace_id       uuid,
  p_new_owner_user_id  uuid,
  p_attestation_text   text
) RETURNS uuid  -- returns attestation_id
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
```

RPC body:
1. Authenticate caller via `auth.uid()` — RAISE `28000` if NULL
2. Verify caller is owner of `p_workspace_id` — RAISE `42501` if not
3. **Self-transfer guard:** `IF v_caller_user_id = p_new_owner_user_id THEN RAISE EXCEPTION 'cannot transfer ownership to self' USING ERRCODE = '22023'` (AC5)
4. Verify target is a member of the workspace — RAISE `P0001` if not
5. Verify target is not already the owner — if so, RAISE `22023` (distinct from self-transfer)
6. Set `workspace_audit.actor_user_id` GUC for audit trigger
7. Write fresh attestation row to `workspace_member_attestations`: `inviter_user_id = v_caller_user_id` (old owner/transferor), `invitee_user_id = p_new_owner_user_id` (new owner/transferee), `attestation_text = p_attestation_text`. Capture `v_attestation_id`.
8. UPDATE target: `SET role = 'owner', attestation_id = v_attestation_id` (promote first — links attestation to audit row via trigger)
9. UPDATE caller: `SET role = 'member'` (demote second — transient two-owner state within transaction is safe; no UNIQUE constraint on `(workspace_id, role='owner')`)
10. UPDATE `organizations SET owner_user_id = p_new_owner_user_id` (dual-write)
11. INSERT `workspace_member_removals` row for caller: `revocation_reason = 'ownership-transferred'`
12. Clear `user_session_state.current_organization_id` for **demoted owner only** (F6). The new owner's session does not need clearing — they gain privileges, not lose them.

The audit trigger (mig 063_workspace_member_actions.sql) fires automatically on both UPDATEs, producing two `role_changed` rows with correct `attestation_id` on the promote row.

Precedent: `remove_workspace_member` in mig 062 (same REVOKE/GRANT, same actor GUC, same `workspace_member_removals` INSERT pattern).

REVOKE/GRANT: `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated; GRANT EXECUTE ON FUNCTION ... TO authenticated;`

**1B: Restrict `update_workspace_member_role` (MANDATORY — same migration)**

`CREATE OR REPLACE FUNCTION public.update_workspace_member_role(...)` — must carry forward the FULL ~90-line function body from mig 067 (auth check, owner authorization, role validation, self-change guard, last-owner guard, actor GUC, UPDATE, revocation INSERT, F6 session clear). Add ONE guard after the role validation:

```sql
IF p_new_role = 'owner' THEN
  RAISE EXCEPTION 'direct promotion to owner is not allowed; use transfer_workspace_ownership'
    USING ERRCODE = '22023';
END IF;
```

**1C: Fix `anonymise_organization_membership` (pre-existing desync)**

`CREATE OR REPLACE FUNCTION public.anonymise_organization_membership(...)` — after reassigning `owner_user_id` to the oldest remaining member, also UPDATE `workspace_members SET role = 'owner'` for that member. Without this, account-delete leaves a workspace with `owner_user_id` pointing to a member whose `workspace_members.role` is `'member'`, locking all owner-gated RPCs. This is a pre-existing defect in mig 065 that becomes more dangerous after 1B restricts promotions.

### Phase 2: Server + API Route + Frontend

**2A: `transferWorkspaceOwnership` TS wrapper** in `server/workspace-membership.ts`

Pattern: identical to `removeWorkspaceMember` — RPC call via service client, error mapping from `error.message.includes()`. Post-mutation cascade for **demoted owner only**: SIGTERM in-flight agent sessions, WS close with preamble. The new owner is NOT SIGTERMed — they gain privileges, killing their sessions would be destructive and confusing.

Error-to-reason mapping: `"cannot transfer ownership to self"` → `"self_transfer"`, `"not owner"` → `"caller_not_owner"`, `"not a member"` → `"target_not_member"`, `"already owner"` → `"target_already_owner"`.

**Middleware extension:** Add `"ownership-transferred"` handler to `check_my_revocation` reason mapping in `middleware.ts`. Display accurate copy: "You transferred ownership of this workspace. Please sign in again to continue as a member." (not "you were removed").

**2B: API route** `apps/web-platform/app/api/workspace/transfer-ownership/route.ts`

Pattern lift from `invite-member/route.ts`:
1. CSRF via `validateOrigin`/`rejectCsrf`
2. Auth via `supabase.auth.getUser()`, 401 if unauthenticated
3. Flag gate via `resolveTeamMembershipPageData` + `isTeamWorkspaceInviteEnabled`, 404 if disabled
4. Parse body: `{ workspaceId, newOwnerUserId, attestationText }`
5. Workspace mismatch defense: `workspaceId !== pageData.data.workspaceId` → 403
6. Caller ownership check: `callerRow.role !== "owner"` → 403
7. Delegate to `transferWorkspaceOwnership()`
8. Map result: `self_transfer` → 400, `caller_not_owner` → 403, `target_not_member` → 404, `target_already_owner` → 409, `rpc_failed` → 500

**2C: `TeamMembershipPageData` extension**

Add `organizationName: string | null` to `TeamMembershipPageData` interface. Resolve from `organizations` table in `resolveTeamMembershipPageData`. Thread to the confirmation dialog.

**2D: Confirmation dialog** `components/settings/transfer-ownership-dialog.tsx`

- Modal with backdrop click to dismiss, Escape to close, Cancel button
- Consequences listed: "You will lose: audit log access, ability to invite and remove members, and GDPR controller designation for this workspace."
- Input field: user types organization name to confirm. **NULL name fallback:** when `organizationName` is NULL, the confirmation target is the target member's email address (e.g., "Type harry@jikigai.com to confirm"). This avoids security-theater ("type 'this workspace'") and unusable UX (type a UUID).
- Case-insensitive trimmed comparison
- "Transfer ownership to [name]" button disabled until match
- Loading state: input + buttons disabled during API call
- Error: inline alert in dialog, dialog stays open, user can retry
- Success: `window.location.reload()`

**2E: Kebab menu extension** in `components/settings/team-membership-list.tsx`

- Add "Transfer ownership" option to kebab menu
- Only visible when: `isOwner && !isCurrentUser`
- On click: open transfer-ownership-dialog with target member's info

### Phase 3: Tests

- Integration test for `transfer_workspace_ownership` RPC (happy path + all guards)
- Unit test for `transferWorkspaceOwnership` TS wrapper (error mapping)
- Negative tests: non-owner caller, self-transfer, non-member target, workspace mismatch, already-owner
- Verify `update_workspace_member_role` rejects `p_new_role = 'owner'`
- Verify `anonymise_organization_membership` promotes replacement member's role
- Verify audit trigger produces two `role_changed` rows with correct `attestation_id`
- Verify `list_workspace_member_actions` returns for new owner, not old owner

**Review checklist (not a phase — performed during code review):**

- Write-boundary sentinel sweep: `git grep -n "owner_user_id" -- '*.ts' '*.sql' | grep -v test | grep -v '.down.sql' | grep -v node_modules` — verify all call sites behave correctly post-transfer
- `check-workspace-members-write-sites.sh` CI gate passes

## Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/supabase/migrations/NNN_transfer_workspace_ownership.sql` | Transfer RPC + restrict update-role + fix anonymise |
| `apps/web-platform/supabase/migrations/NNN_transfer_workspace_ownership.down.sql` | Down migration |
| `apps/web-platform/app/api/workspace/transfer-ownership/route.ts` | API route |
| `apps/web-platform/components/settings/transfer-ownership-dialog.tsx` | Confirmation dialog |

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/server/workspace-membership.ts` | Add `transferWorkspaceOwnership` function + types |
| `apps/web-platform/server/team-membership-resolver.ts` | Add `organizationName` to `TeamMembershipPageData` |
| `apps/web-platform/components/settings/team-membership-list.tsx` | Add "Transfer ownership" to kebab menu, pass org name |
| `apps/web-platform/middleware.ts` | Add `"ownership-transferred"` reason handler |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `transfer_workspace_ownership` RPC exists with SECURITY DEFINER, `SET search_path = public, pg_temp`
- [ ] AC2: RPC atomically updates `workspace_members.role` (promote target with `attestation_id`, demote caller) AND `organizations.owner_user_id` in one transaction
- [ ] AC3: RPC writes fresh attestation row before role swap; promote UPDATE includes `attestation_id = v_new_attestation_id`
- [ ] AC4: RPC sets `workspace_audit.actor_user_id` GUC — audit trigger produces two `role_changed` rows with correct `actor_user_id` and `attestation_id`
- [ ] AC5: RPC raises `22023` when caller attempts self-transfer (explicit guard, not incidental)
- [ ] AC6: RPC raises `42501` when non-owner calls
- [ ] AC7: RPC raises `P0001` when target is not a workspace member
- [ ] AC8: `update_workspace_member_role` rejects `p_new_role = 'owner'` with `22023` (full body carried forward from mig 067)
- [ ] AC9: `anonymise_organization_membership` promotes replacement member's `workspace_members.role` to `'owner'` alongside `organizations.owner_user_id` reassignment
- [ ] AC10: API route returns 400 self-transfer, 403 workspace mismatch, 403 non-owner, 401 unauthenticated, 404 flag disabled, 404 non-member, 409 already-owner
- [ ] AC11: Middleware handles `"ownership-transferred"` revocation reason with accurate copy (not "you were removed")
- [ ] AC12: Confirmation dialog requires typing org name (or target email when org name is NULL)
- [ ] AC13: Post-transfer SIGTERM + WS close fires for demoted owner only (not new owner)
- [ ] AC14: `check-workspace-members-write-sites.sh` passes
- [ ] AC15: `tsc --noEmit` passes
- [ ] AC16: Post-transfer, `list_workspace_member_actions` returns for new owner, not old owner

## Deferred Items

| Item | Tracking |
|------|----------|
| Legal document updates (ToS, AUP, Privacy, GDPR, DPD) | File as separate issue at implementation time |
| BYOK delegation orphaning on transfer (NG2) | Existing issue scope in brainstorm |
| Kebab menu visibility for non-owners (pre-existing) | File as separate issue |
| DSAR export timing edge case (old owner requests DSAR, then transfers before export runs) | Document as known edge case |

## Domain Review

**Domains relevant:** Product, Engineering, Legal

Carry-forward from brainstorm `2026-05-27-workspace-role-management-brainstorm.md` §Domain Assessments. CPO + CLO + CTO spawned as mandatory triad (`USER_BRAND_CRITICAL=true`).

### Product (CPO)

**Status:** reviewed (carry-forward)
**Assessment:** Deferral well-reasoned. Dependency chain clear (#4518 → #4520). Critical risk: dual ownership source of truth. Recommends single-owner strict with atomic swap.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Fresh attestation required on promotion. Controller designation transfer needs ToS §"Workspace Members". 5 legal docs need coordinated updates (deferred to separate PR). Recommends `/soleur:gdpr-gate` at plan Phase 2.7.

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Most backend work exists on feature branch. Net-new: transfer RPC (medium), API route + UI (small). Dual ownership source of truth is the critical risk. BYOK delegation orphaning deferred.

### Product/UX Gate

**Tier:** blocking (new confirmation dialog component)
**Decision:** reviewed (brainstorm-validated idea; dialog is a lift of existing `window.confirm` pattern from remove-member, upgraded to type-to-confirm)
**Agents invoked:** CPO (carry-forward from brainstorm), ux-design-lead (post-plan, wireframes)
**Pencil available:** TBD

## GDPR / Compliance Gate

Per spec TR6 and CLO assessment, `/soleur:gdpr-gate` must run at work Phase 2 exit against the migration + API route diffs. The feature touches:
- `workspace_member_attestations` (PII: inviter, invitee, attestation_text, ip_hash, user_agent)
- `workspace_member_actions` trigger (PII: actor_user_id, target_user_id)
- `workspace_members.role` column (determines controller designation)
- New API route processing authenticated user identity

## Observability

```yaml
liveness_signal:
  what: workspace_member_actions audit trigger fires two role_changed rows per transfer
  cadence: on-demand (transfer events)
  alert_target: Sentry (orphan-actor-audit-row warning per mig 063 TR13)
  configured_in: supabase/migrations/063_workspace_member_actions.sql

error_reporting:
  destination: Sentry via reportSilentFallback (post-transfer SIGTERM + WS close for demoted owner)
  fail_loud: RPC errors surface as HTTP 4xx/5xx to the client

failure_modes:
  - mode: audit trigger fails to capture role_changed
    detection: Sentry RAISE LOG warning (TR13 orphan-actor)
    alert_route: Sentry alert on "orphan audit row" structured log
  - mode: post-transfer WS close fails for demoted owner
    detection: reportSilentFallback → Sentry
    alert_route: Sentry via existing workspace-membership feature tag
  - mode: anonymise_organization_membership fails to promote replacement
    detection: owner-gated RPCs return 42501 for all surviving members
    alert_route: Sentry via account-delete error cascade

logs:
  where: Sentry (errors), pino (structured logs via existing server middleware)
  retention: Sentry 90d, pino via Better Stack

discoverability_test:
  command: |
    curl -s https://app.soleur.ai/api/health/team-membership | jq .status
  expected_output: '"ok"'
```

## Test Scenarios

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Owner transfers to member | Both roles swap, `organizations.owner_user_id` updated, two `role_changed` audit rows with correct `attestation_id` |
| 2 | Non-owner calls transfer | 403 / `42501` |
| 3 | Owner transfers to self | 400 / `22023` (explicit self-transfer guard) |
| 4 | Owner transfers to non-member | 404 / `P0001` |
| 5 | Transfer with wrong workspaceId | 403 workspace mismatch |
| 6 | Transfer when flag disabled | 404 |
| 7 | Confirmation dialog — wrong name typed | Transfer button disabled |
| 8 | Confirmation dialog — correct name typed | Transfer button enabled, executes |
| 9 | `update_workspace_member_role` with `p_new_role = 'owner'` | Rejected with `22023` |
| 10 | Post-transfer: new owner can invite members | 200 OK |
| 11 | Post-transfer: old owner cannot invite members | 403 |
| 12 | Post-transfer: `list_workspace_member_actions` returns for new owner | Audit log visible |
| 13 | Account-delete of owner: replacement member promoted to owner | `workspace_members.role = 'owner'` for replacement |
| 14 | Post-transfer: demoted owner sees "You transferred ownership" middleware copy | Correct copy, not "you were removed" |
| 15 | Confirmation with NULL org name | Dialog shows target email as confirmation target |

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Ownerless workspace | HIGH | Single SECURITY DEFINER RPC; promote-before-demote ordering; all in one transaction. Transient two-owner state is safe (no UNIQUE constraint on `(workspace_id, role='owner')`) — document in migration comment. |
| `organizations.owner_user_id` desync | HIGH | Atomic dual-write in transfer RPC; `anonymise_organization_membership` fix (1C); write-boundary sentinel sweep at review |
| Cross-workspace role mutation | HIGH | `workspace_mismatch` check in API route (invite-member pattern) |
| Privilege retention post-demotion | MEDIUM | F6 clears `user_session_state` for demoted owner + `workspace_member_removals` triggers `check_my_revocation` middleware. JWT window bounded by natural expiry (~1h). |
| BYOK delegation orphaning | LOW | Deferred (NG2) — delegation grantor is always the current owner post-transfer |
| DSAR export timing | LOW | Export filters by `owner_user_id` at execution time. If ownership transfers between DSAR request and execution, old owner's org data is empty. Legally defensible (Art. 15 at time of response). |

## Sharp Edges

- Migration number is TBD — depends on what merges between now and #4518 landing. At implementation time, run `ls apps/web-platform/supabase/migrations/*.sql | tail -1` to determine next number.
- `CREATE OR REPLACE` on `update_workspace_member_role` must reproduce the FULL ~90-line function body from mig 067, not just the new guard. If only the delta is applied, all existing guards (auth, owner check, self-change, last-owner, actor GUC, revocation INSERT, F6 clear) are silently dropped.
- The transient two-owner state within the transaction (promote step 8 before demote step 9) is intentional. If a future migration adds a partial unique index on `(workspace_id) WHERE role = 'owner'`, this RPC breaks. Document in migration comment.
- CPO sign-off required at plan time before `/work` begins. CPO has reviewed via brainstorm Phase 0.5 (2026-05-27).
- At `brand_survival_threshold: single-user incident`, recommend ultrathink/deepen-plan before `/work` for substance-level findings (SQL atomicity, plpgsql edge cases, security primitives).
