---
title: Fix workspace member removal (auth.uid()-NULL RPC) + add BYOK daily-cap update for joined members + align Members table columns
type: fix + feat
date: 2026-06-02
branch: feat-one-shot-member-removal-byok-delegation-update
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Fix member removal + add BYOK daily-cap update for joined members

## Overview

Two defects on **Settings → Members** (`/dashboard/settings/team`), both reported against `app.soleur.ai` after PR #4779 merged:

1. **Member removal fails** with `"Failed to remove member. Please try again."` when an owner uses the `⋯` menu → *Remove member* (e.g. removing `jean.deruelle@gmail.com`). **Root cause is NOT in PR #4779** — it is a latent, structural defect in the `remove_workspace_member` SQL RPC: its owner-gate reads `v_caller_user_id uuid := auth.uid()` and `RAISE EXCEPTION … USING ERRCODE = '28000'` when `auth.uid()` is NULL, but the sole caller (`removeWorkspaceMember` in `server/workspace-membership.ts:271`) invokes it through `createServiceClient()` where **`auth.uid()` is always NULL**. Every removal therefore raises `28000` → `rpc_failed` → HTTP 500 → the toast. This is the *identical* defect class that migration **092** already fixed for `transfer_workspace_ownership` (#4765/#4768) and that #4761 fixed for the BYOK grant path. PR #4779 only changed the *workspace-resolution* on the same page, which is why the user noticed the breakage in the same window — but the RPC has been broken since the RPC's service-role caller landed (#4225 → mig 062/067/068).

2. **No way to update a member's "Daily Cap BYOK delegation" after they have joined.** The `DelegationToggle` (`components/settings/delegation-toggle.tsx`) only renders the cap `<input>` when `!active && !delegation` — i.e. the cap can be set **only at grant time**. Once a delegation is active, the owner sees `$spent/$cap` read-only and the only action is revoke (turn off). To change a cap today an owner must revoke then re-grant. The database **already supports** an in-place cap update: the WORM trigger `byok_delegations_no_mutate` permits a **"cap-update flip"** (064:332-353, "Shape 3 … Enables 'raise Harry's budget' UX without breaking audit continuity") and the columns `cap_updated_at` / `cap_updated_by_user_id` exist (064:102-103) — **but no RPC executes that flip**, and `byok_delegations` has explicit `REVOKE UPDATE … FROM authenticated`. So the fix is a new SECURITY DEFINER RPC `update_byok_delegation_cap` (migration 094, modelled on `revoke_byok_delegation`), a `PATCH /api/workspace/delegations` handler, and an inline editable-cap control in `DelegationToggle`.

3. **ROLE column is visibly misaligned in the Members table.** In `team-membership-list.tsx`, the header row aligns the `Role` and `Funded` cells with `text-center` (lines 54-55) and `Added` with `text-right` (line 56), but the data-row cells do not match: the Role badge is a bordered `<span>` grid item (167-175) with no `justify-self`, so it left-aligns/stretches in its `auto` column instead of centering under the `Role` header; the `Added` value cell uses `text-right` text but the column is `auto`-sized, so header and value can drift. The fix is to make each data cell's horizontal justification match its header cell (center the Role badge and Funded control under their centered headers; keep Added right-aligned consistently), and verify with a before/after screenshot at QA.

Both problems live in the same Members surface; (1) and (2) share the BYOK-delegation/auth.uid()-service-role defect family and (3) is a pure presentation fix on the same component PR #4779 touched, so all three ship in one PR.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the task / common assumption) | Codebase reality | Plan response |
| --- | --- | --- |
| "PR #4779 broke member removal." | #4779 touched only `delegations/route.ts`, `team-membership-list.tsx`, `byok-delegation-ui-resolver.ts`, `team-membership-resolver.ts` (per `gh pr view 4779 --json files`). It did **not** touch `remove-member/route.ts` or `workspace-membership.ts`. The removal RPC's `auth.uid()`-NULL flaw predates it (mig 062/067/068, all `v_caller_user_id := auth.uid()`). | Fix the RPC, not #4779's diff. Note in PR body that #4779 is a co-incidence of timing, not the cause. Keep #4779's workspace-resolution change intact. |
| "The cap can only be set at invite time." | More precise: it can only be set at **grant** time (the grant is separate from the workspace invite). The DB *does* support cap updates (WORM Shape 3 at 064:332-353) but no RPC/route/UI reaches it. | Add `update_byok_delegation_cap` RPC + PATCH route + inline edit UI. Reuse the existing WORM Shape-3 contract. |
| "Re-grant with a new cap to change it." | `grant_byok_delegation` is a pure `INSERT` (064:467 VALUES…RETURNING) guarded by the partial unique index `byok_delegations_active_triple_uidx` (064:146). A second active grant for the same (grantor,grantee,workspace) triple **violates the unique index**. | Cap change MUST be an UPDATE-flip RPC, never a re-grant. |
| "`update_workspace_member_role` is user-reachable and also broken." | The helper + RPC exist (mig 067) but `grep` finds **no route/component** invoking `updateWorkspaceMemberRole`. Not user-reachable today. | Fix its `auth.uid()`-NULL flaw as defense-in-depth in the same migration (it WILL be wired later and has the identical hole), but it is not the user-facing fix. |

## User-Brand Impact

**If this lands broken, the user experiences:** (1) an owner permanently unable to remove a departed/incorrect member from their workspace — the member keeps live access to shared conversations, the KB, and (if delegated) the owner's funded API spend; (2) an owner unable to raise/lower a member's daily spend cap, so the only "fix" is revoke-and-re-grant which momentarily de-funds the member and resets their spend accounting.

**If this leaks, the user's money/workflow is exposed via:** a forgeable caller/actor id. Two distinct mitigation patterns, by RPC:
- **`remove_workspace_member` / `update_workspace_member_role`** use the **forgeable-override pattern** (`COALESCE(p_caller_user_id, auth.uid())` with NO internal impersonation guard). These MUST be `service_role`-only (`REVOKE … FROM PUBLIC, anon, authenticated; GRANT … TO service_role`) — exactly migration 092's transfer-ownership security note (092:178-191: "if authenticated could reach it via PostgREST, any user could … steal a workspace they do not own"). If `GRANT`ed to authenticated, any logged-in user could pass `p_caller_user_id = <victim owner uuid>` and remove members from a workspace they do not own.
- **`update_byok_delegation_cap`** uses the **impersonation-guarded pattern** of `grant`/`revoke_byok_delegation` (064:439-443, 524-525): authenticated callers may not pass an actor ≠ `auth.uid()`; service-role callers must supply the actor explicitly. This makes a `GRANT … TO authenticated, service_role` safe — the guard, not the grant restriction, closes the forge vector.

In all cases the route forwards the **server-verified `getUser()` id**, never a client-supplied value.

**Brand-survival threshold:** single-user incident.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Removal works under service-role.** `removeWorkspaceMember` succeeds end-to-end: an owner removing a member returns `{ ok: true }` and HTTP 200; the `workspace_members` row is gone; the `⋯` menu no longer shows the failure toast. Verified by a rolled-back live-DB repro (see AC11) capturing the *before* SQLSTATE `28000` and the *after* success.
- [x] **AC2 — Migration 094 patches `remove_workspace_member`.** `CREATE OR REPLACE FUNCTION public.remove_workspace_member(p_workspace_id uuid, p_user_id uuid, p_caller_user_id uuid DEFAULT NULL)` resolves the caller via `COALESCE(p_caller_user_id, auth.uid())`; all four-arm RAISE semantics (NULL caller, not-owner, self-remove, owner-target) preserved; `SET search_path = public, pg_temp` retained (`cq-pg-security-definer-search-path-pin-pg-temp`).
- [x] **AC3 — Removal RPC is service_role-only.** `REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;` and `GRANT EXECUTE … TO service_role;` (mirrors mig 092:design constraint). A `pg_proc` + `information_schema.role_routine_grants` read confirms `authenticated` cannot execute the 3-arg overload.
- [x] **AC4 — `update_workspace_member_role` patched identically** (defense-in-depth) in the same migration: `COALESCE(p_caller_user_id, auth.uid())`, 3-arg→4-arg overload, service_role-only grant.
- [x] **AC5 — TS helpers forward the verified caller.** `removeWorkspaceMember` passes `p_caller_user_id: args.callerUserId`; `updateWorkspaceMemberRole` passes `p_caller_user_id: args.callerUserId`. The route already verifies `args.callerUserId = user.id` from `getUser()` (remove-member/route.ts:54-57, 73).
- [x] **AC6 — New RPC `update_byok_delegation_cap`** in migration 094: `(p_delegation_id uuid, p_daily_usd_cap_cents int, p_hourly_usd_cap_cents int, p_actor_user_id uuid DEFAULT NULL)`, SECURITY DEFINER, `SET search_path = public, pg_temp`. Performs the WORM **Shape-3 cap-update flip** (sets `daily_usd_cap_cents`, `hourly_usd_cap_cents`, `cap_updated_at = now()`, `cap_updated_by_user_id = <actor>`, every other column unchanged). **Caller/actor resolution follows the `revoke_byok_delegation` family pattern (064:495-568), NOT the transfer-ownership service_role-only pattern** — because the BYOK RPCs branch on `auth.uid() IS NULL`: service-role caller MUST supply `p_actor_user_id`; authenticated caller MAY NOT pass a `p_actor_user_id` that differs from `auth.uid()` (impersonation RAISE). Enforces: actor ∈ {grantor, created_by} of the row (revoke uses {grantor, grantee, created_by}; cap-raise is grantor/creator-only — grantee may not raise their own cap); delegation exists and is not revoked/anonymised; cap range checks identical to `grant_byok_delegation` (064:451-462: daily ∈ [1, 1000000], hourly ∈ [1, daily]). **GRANT EXECUTE TO `authenticated, service_role`** (mirrors grant/revoke at 064:482,564 — the internal impersonation guard makes the `authenticated` grant safe, unlike the forgeable-override transfer RPC).
- [x] **AC7 — PATCH route.** `PATCH /api/workspace/delegations` (in `app/api/workspace/delegations/route.ts`): origin/CSRF gate, auth, org resolution, `isByokDelegationsEnabled` gate (all mirroring the existing POST handler 42-78); validates `{ delegationId, dailyCapCents, hourlyCapCents? }`; ownership probe (caller is grantor of the delegation, via the existing service-role `byok_delegations` select); calls `update_byok_delegation_cap` with `p_actor_user_id: user.id`; on `error` returns 400 with `error.message` (matching POST/DELETE). `cq-nextjs-route-files-http-only-exports` preserved (only HTTP-verb exports).
- [x] **AC8 — Inline cap edit in `DelegationToggle`.** When `active && delegation && isOwner`, the `$spent/$cap` label becomes editable (an "Edit cap" affordance revealing a number input pre-filled with the current daily cap and a Save/Cancel); Save issues the PATCH and, on success, updates the displayed cap; on non-OK or thrown fetch, surfaces `window.alert(...)` and leaves the prior cap (matching the existing revoke/grant error posture, delegation-toggle.tsx:102-131). The grant path and revoke path are unchanged.
- [x] **AC9 — Cap-update column-name guard holds.** The PATCH route + RPC use `daily_usd_cap_cents` / `hourly_usd_cap_cents` (not the bare `*_cap_cents` names); the existing `byok-delegation-cap-column-names.test.ts` source guard passes against the new code.
- [x] **AC10 — `tsc --noEmit` clean** for `apps/web-platform`; full `apps/web-platform` vitest shard green.
- [x] **AC-ALIGN — Members table columns align header↔data.** In `team-membership-list.tsx`, the data-row cells' horizontal justification matches their header cells: the Role badge centers under the `text-center` `Role` header (wrap/justify the badge cell so the pill is centered, not stretched/left), the `Funded` (`DelegationToggle`) cell centers under its `text-center` header, and `Added` stays right-aligned consistently. Header grid template and data-row grid template remain identical (both `grid-cols-[1fr_auto_auto_auto_auto]` / `[1fr_auto_auto_auto]`). Verified by a before/after screenshot at QA (Playwright MCP on `/dashboard/settings/team`). No change to the removal/cap logic.
- [x] **AC11 — Migration 094 has a `.down.sql`** that `CREATE OR REPLACE`s the three functions back to their mig-068/067 bodies (2-arg overloads) and `DROP FUNCTION`s the new 3-arg/4-arg overloads + `update_byok_delegation_cap`. Verify the up + down round-trips against a transactional `BEGIN; \i 094…up; \i 094…down; ROLLBACK;` (mirrors the migration-test convention in `test/supabase-migrations/`).

### Post-merge (operator)

- [ ] **AC12 — Apply migration 094 to prod.** `Automation:` applied automatically by the existing `web-platform-release.yml#migrate` job on merge to `main` (the canonical migration-apply mechanism; do NOT hand-apply via SSH). Post-merge verification reads `pg_proc.proargnames` for the 3 patched functions via the Supabase MCP read-only and confirms the `p_caller_user_id` arg is present. Ref the issue with `Ref #<N>` (not `Closes`) until this verify passes, then `gh issue close`.

## Hypotheses (Problem 1 root cause — ranked, with falsification)

1. **(Confirmed by static evidence) `auth.uid()`-NULL under service-role.** `remove_workspace_member` (mig 068:299, 306-308) raises `28000` because `removeWorkspaceMember` calls it via `createServiceClient()`. The TS error handler (`workspace-membership.ts:275-287`) has no arm matching the `28000` message text → falls through to `rpc_failed` → route 500 → toast. **Falsification at /work:** rolled-back live-DB repro — `BEGIN; SELECT public.remove_workspace_member('<ws>','<member>'); ROLLBACK;` under the service-role connection should raise `28000`; after the patch, the same call with `p_caller_user_id := '<owner>'` should return `1`. Per Sharp Edge `2026-06-01-write-path-internally-consistent-claim-misses-trigger-vs-rpc-contradiction.md`, capture the actual SQLSTATE before prescribing remediation.
2. **(Secondary, NOT the cause but verify) #4779 workspace-resolution mismatch.** If `resolveCurrentWorkspaceId(owner.id)` returned the owner's *solo* workspace (because `current_workspace_id` is NULL/stale), `pageData.data.workspaceId` would list only the owner and the route's `workspace_mismatch` (line 51) or `removeWorkspaceMember`'s `not_a_member` could fire instead. **Falsification:** confirm `current_workspace_id` for the reproducing owner points at the team workspace AND the owner holds a `workspace_members` row there (J5 self-heal at resolver:133-162 keeps it). If true, this path is not implicated and the RPC `28000` is the sole cause. Do not "fix" #4779.

## Implementation Phases

> Phase order is load-bearing: the contract-changing migration (Phase 1) MUST precede the TS callers (Phase 2) and the new feature (Phases 3-4), per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

### Phase 0 — Preconditions (verify before coding)
- Read mig 092 (`transfer_ownership_caller_override`) end-to-end — it is the verbatim template for the COALESCE caller-override + service_role-only grant + forgeability security note.
- Read the 2-3 most recent migrations (`091`–`093`) to confirm no `CREATE INDEX CONCURRENTLY`/non-transactional DDL is needed (none here — pure `CREATE OR REPLACE FUNCTION`), per `2026-04-18-supabase-migration-concurrently-forbidden.md`.
- Live-DB rolled-back repro of `remove_workspace_member` under service-role (Hypothesis 1 falsification). Capture `28000`.
- Confirm `update_byok_delegation_cap` does not already exist (`grep` returned none) and that the WORM Shape-3 trigger arm (064:332-353) is the exact contract to satisfy.

### Phase 1 — Migration 094 (`094_member_rpc_caller_override_and_byok_cap_update.sql` + `.down.sql`)
1. `CREATE OR REPLACE FUNCTION public.remove_workspace_member(p_workspace_id uuid, p_user_id uuid, p_caller_user_id uuid DEFAULT NULL)` — paste mig 068 body verbatim, change only `v_caller_user_id uuid := COALESCE(p_caller_user_id, auth.uid());`. Keep the WORM-cascade ordering (`_anonymise_authored_messages_internal` BEFORE the DELETE) and the `user_session_state` clear (068:344-385). REVOKE from PUBLIC/anon/authenticated; GRANT EXECUTE TO service_role. **Diff against EVERY prior body** (058/062/067/068) to ensure no arm is silently dropped (per `2026-06-01-…` corollary).
2. `CREATE OR REPLACE FUNCTION public.update_workspace_member_role(p_workspace_id uuid, p_user_id uuid, p_new_role text, p_caller_user_id uuid DEFAULT NULL)` — same COALESCE override; preserve last-owner-demote guard (067:263-267) and the audit GUC set. service_role-only grant.
3. `CREATE FUNCTION public.update_byok_delegation_cap(p_delegation_id uuid, p_daily_usd_cap_cents int, p_hourly_usd_cap_cents int, p_actor_user_id uuid DEFAULT NULL)` modelled on `revoke_byok_delegation` (064:495-564): `v_caller_jwt := auth.uid()`; if `auth.uid() IS NULL` (service-role) require `p_actor_user_id` non-NULL else RAISE; if authenticated and `p_actor_user_id <> auth.uid()` RAISE impersonation; set `v_actor`. Load the row; reject if `revoked_at IS NOT NULL` (P0001 "already revoked") or anonymised; reject if `v_actor NOT IN (grantor_user_id, created_by_user_id)`; cap range checks (daily ∈ [1,1e6], hourly ∈ [1,daily]); then the Shape-3 UPDATE (`SET daily_usd_cap_cents=…, hourly_usd_cap_cents=…, cap_updated_at=now(), cap_updated_by_user_id=v_actor`). `REVOKE … FROM PUBLIC, anon; GRANT EXECUTE TO authenticated, service_role` (mirrors 064:482,564). COMMENT documenting the WORM Shape-3 contract.
4. `.down.sql`: `CREATE OR REPLACE` the two member RPCs back to their 2-arg mig-068/067 bodies, `DROP FUNCTION` the new overloads + `update_byok_delegation_cap`.

### Phase 2 — TS caller forwards verified caller (`server/workspace-membership.ts`)
- `removeWorkspaceMember`: add `p_caller_user_id: args.callerUserId` to the `rpc("remove_workspace_member", …)` call.
- `updateWorkspaceMemberRole`: add `p_caller_user_id: args.callerUserId`.
- Add a `28000`-message arm to both error handlers mapping to `caller_not_owner` (defense-in-depth; should be unreachable now that the caller is forwarded, mirroring the transfer/rename comment at workspace-membership.ts:396-397).
- No route change needed for removal — `remove-member/route.ts` already passes `callerUserId: user.id` (line 73).

### Phase 3 — Cap-update RPC wrapper + PATCH route
- Add `updateByokDelegationCap({ callerUserId, delegationId, dailyCapCents, hourlyCapCents })` helper (in `server/byok-delegation-ui-resolver.ts` or a sibling; match where grant/revoke wrappers live — verify at /work) that calls `update_byok_delegation_cap` with `p_actor_user_id: callerUserId`.
- Add `PATCH` export to `app/api/workspace/delegations/route.ts` per AC7.

### Phase 4 — Inline cap edit UI (`components/settings/delegation-toggle.tsx`)
- In `OwnerDelegationControl`, when `active && delegation`, render an "Edit" affordance next to `$spent/$cap` that toggles an inline number input + Save/Cancel; Save fetches `PATCH /api/workspace/delegations` and updates local `capCents` on success; error posture mirrors lines 102-131.

### Phase 4.5 — Members table column alignment (`components/settings/team-membership-list.tsx`)
- Make each data-row cell's horizontal justification match its header cell. Minimal approach: give the Role badge cell a wrapper with `justify-self-center` (or center the badge within the cell) so the pill sits under the centered `Role` header; ensure the `DelegationToggle` (Funded) cell is centered to match its `text-center` header; keep the `Added` cell right-aligned. Do NOT change the shared `grid-cols-[…]` templates — header (52) and data row (145) must stay identical so columns line up. Re-check both the `byokDelegationsEnabled` true/false variants.
- Verify against `test/team-membership-list.test.tsx` (already touched by #4779) and add/extend an assertion if it pins column structure; final confirmation is the QA screenshot (AC-ALIGN).

### Phase 5 — Tests (write failing first, `cq-write-failing-tests-before`)
- `test/supabase-migrations/094-…test.ts`: 28000-before / success-after for `remove_workspace_member` 3-arg; service_role-only grant assertion; `update_byok_delegation_cap` happy path + each RAISE arm + WORM Shape-3 acceptance + non-grantor rejection + revoked rejection + cap-range rejection.
- `test/api-delegation-cap-update-route.test.ts` (node): pins the exact arg object `{ p_delegation_id, p_daily_usd_cap_cents, p_hourly_usd_cap_cents, p_actor_user_id }`; rejects missing fields; 403 non-owner; 400 on RPC error.
- `test/remove-member-route.test.ts` (extend if exists, else add): asserts `removeWorkspaceMember` is called with `callerUserId` and the RPC receives `p_caller_user_id`.
- `test/delegation-toggle.test.tsx`: edit→Save issues PATCH and updates the cap; Save failure keeps prior cap + alerts.

## Files to Edit
- `apps/web-platform/server/workspace-membership.ts` — forward `p_caller_user_id` in `removeWorkspaceMember` + `updateWorkspaceMemberRole`; add 28000 arm.
- `apps/web-platform/app/api/workspace/delegations/route.ts` — add `PATCH` handler + cap-update wrapper import.
- `apps/web-platform/server/byok-delegation-ui-resolver.ts` — add `updateByokDelegationCap` wrapper (or sibling; verify call-site convention).
- `apps/web-platform/components/settings/delegation-toggle.tsx` — inline editable cap for active delegations.
- `apps/web-platform/components/settings/team-membership-list.tsx` — align Role/Funded/Added data cells to their header cells (AC-ALIGN).
- `apps/web-platform/test/delegation-toggle.test.tsx` — edit-cap cases.
- `apps/web-platform/test/team-membership-list.test.tsx` — extend if it pins column structure (AC-ALIGN).

## Files to Create
- `apps/web-platform/supabase/migrations/094_member_rpc_caller_override_and_byok_cap_update.sql`
- `apps/web-platform/supabase/migrations/094_member_rpc_caller_override_and_byok_cap_update.down.sql`
- `apps/web-platform/test/supabase-migrations/094-member-rpc-caller-override-and-byok-cap-update.test.ts`
- `apps/web-platform/test/api-delegation-cap-update-route.test.ts`
- `apps/web-platform/test/remove-member-route.test.ts` (if no existing remove-member route test)

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` checked against the five files above — no open scope-out names them. Recorded so the next planner sees the check ran.)

## Research Insights (deepen-plan, 2026-06-02)

### Precedent-Diff Gate (Phase 4.4) — SECURITY DEFINER caller-resolution

Two established precedents in this repo; the plan adopts the correct one per RPC:

| Concern | Transfer/rename precedent (mig 092) | BYOK grant/revoke precedent (mig 064) | Plan adopts |
| --- | --- | --- | --- |
| Caller resolution | `COALESCE(p_caller_user_id, auth.uid())`, forgeable | `auth.uid()` branch + `p_actor_user_id` + impersonation RAISE | member RPCs → 092 form; cap-update → 064 form |
| Grant | `TO service_role` ONLY (092:188-191) | `TO authenticated, service_role` (064:482,564) | member RPCs → service_role-only; cap-update → both |
| Why safe | grant restriction is the guard | internal impersonation RAISE is the guard | matches each RPC's guard model |

All three functions: `SECURITY DEFINER` + `SET search_path = public, pg_temp` (verified against 092:8-9 and `cq-pg-security-definer-search-path-pin-pg-temp`). No `SECURITY INVOKER` (the #2954 trap) and no missing search_path pin.

### Live-verified attribution claims

- **mig 092 is the exact bug-class precedent.** `092_transfer_ownership_caller_override.sql` header (verified, lines 4-21): "Migration 075 gated the caller on a bare `auth.uid()`, but the sole caller invokes it under service-role where `auth.uid()` returns NULL. Every call therefore raised 28000." Identical mechanism to `remove_workspace_member`.
- **`remove_workspace_member` flaw verified in current main body** (mig 068:299 `v_caller_user_id uuid := auth.uid();`, 068:306-308 RAISE 28000). The TS caller uses `createServiceClient()` (workspace-membership.ts:270-274) with no `p_caller_user_id`.
- **WORM Shape-3 cap-update flip is real and unused.** 064:332-353 permits the UPDATE shape; 064:355 is the rejecting RAISE; `cap_updated_at`/`cap_updated_by_user_id` exist (064:102-103); `grep` finds NO RPC executing the flip. All cited line numbers re-read and confirmed in this pass.
- **`update_workspace_member_role` has no route/component caller** (`grep` returned zero in `app/`+`components/`) — confirms it is not the user-facing fix; patched as defense-in-depth only.
- **Live-DB SQLSTATE repro deferred to /work Phase 0** (Supabase MCP requires interactive OAuth; not blocking planning). The static evidence + mig-092 precedent + learning `2026-06-01-write-path-internally-consistent-claim-misses-trigger-vs-rpc-contradiction.md` (the invite-accept analogue) are conclusive on the mechanism; the repro is a confirmation step, captured as AC1/Hypothesis-1 falsification.

### Round-1 implementation-realism (verify-the-negative)

- Plan claim "no other BEFORE-UPDATE trigger mutates a `byok_delegations` column": **must be grep-confirmed at /work Phase 0** (only `byok_delegations_no_update`/`_no_delete` triggers found at 064:363-371, both pointing at the same `no_mutate` function; confirm no sibling trigger sets `updated_at` etc. that would trip the Shape-3 "all other columns unchanged" arm). Carried as a Risks entry below.

## Risks & Mitigations
- **Forgeable `p_caller_user_id` (Critical).** New/overloaded RPCs MUST be service_role-only (REVOKE from authenticated). Precedent: mig 092 security note (lines 18-21). Verified by AC3/AC4 grant-introspection.
- **Dropping an arm when re-issuing `CREATE OR REPLACE remove_workspace_member`.** mig 058→062→067→068 each re-issued the body; 068 added the attachment cascade. Diff against all four (per `2026-06-01-…`). Mitigated by AC2's "all four-arm RAISE semantics preserved" + the down-round-trip test.
- **WORM Shape-3 arm mismatch.** The cap-update UPDATE must touch ONLY the cap columns + `cap_updated_at` + `cap_updated_by_user_id`; any stray column write (e.g. a trigger-set `updated_at`) trips the `P0001` "only … flip shapes are permitted" RAISE (064:355). Confirm `byok_delegations` has no other BEFORE-UPDATE trigger that mutates a column (per the trigger-vs-RPC-contradiction Sharp Edge). Read all triggers on the table at /work Phase 0.
- **Active-triple unique index.** Cap update is an UPDATE-flip, never a re-grant — re-grant would violate `byok_delegations_active_triple_uidx` (064:146). Encoded in Research Reconciliation.
- **#4779 secondary path.** If Hypothesis 2 is implicated for some orgs, do NOT alter #4779's resolver; file a follow-up. The RPC fix is necessary regardless.

## Observability

```yaml
liveness_signal:
  what: member-removal + cap-update RPC error rate (Sentry events tagged feature=workspace-membership op=remove-* / feature=byok-delegations op=PATCH.*)
  cadence: per-request
  alert_target: Sentry (existing reportSilentFallback → Sentry pipeline)
  configured_in: apps/web-platform/server/observability.ts (reportSilentFallback)
error_reporting:
  destination: Sentry via reportSilentFallback (server) + console.error + window.alert (client)
  fail_loud: true  # 28000/rpc_failed already returns non-OK → client alert; mirror unexpected DB errors to Sentry (cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - mode: RPC raises 28000 (caller NULL) post-fix — should be impossible
    detection: Sentry event count for op=remove-member-rpc with 28000
    alert_route: Sentry
  - mode: WORM Shape-3 P0001 (cap-update flip rejected)
    detection: PATCH route 400 with message 'only … flip shapes are permitted' mirrored to Sentry
    alert_route: Sentry
  - mode: forgeable-caller GRANT regression (authenticated can EXECUTE)
    detection: migration-test grant-introspection assertion (AC3/AC4) fails in CI
    alert_route: CI red
logs:
  where: pino stdout (web-platform container) + Sentry
  retention: per existing web-platform retention
discoverability_test:
  command: ./node_modules/.bin/vitest run test/supabase-migrations/094-member-rpc-caller-override-and-byok-cap-update.test.ts (NO ssh)
  expected_output: all assertions pass — 28000-before, success-after, service_role-only grant, cap-update flip accepted
```

## Test Scenarios
- Owner removes a member → 200, row gone (was: 500 + toast).
- Non-owner / unauthenticated DELETE → 403/401 (unchanged).
- Owner raises a member's daily cap from $20 → $50 → toggle row shows $50; `byok_delegations` row has new `daily_usd_cap_cents` + non-NULL `cap_updated_at`/`cap_updated_by_user_id`, same `id` (audit continuity).
- Cap update on a revoked delegation → 400 (RPC rejects).
- Cap update by a non-grantor → 403 (route ownership probe) or RPC rejection.
- Cap out of range (0, >$10k daily, hourly>daily) → 400.
- Members table renders with Role badge centered under the `ROLE` header and Funded control centered under `FUNDED`, Added right-aligned — verified by Playwright screenshot of `/dashboard/settings/team` (AC-ALIGN), both delegations-on and delegations-off variants.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold = single-user incident.)
- The removal RPC's TS error handler has NO arm for the `28000` message — after the fix the call should never raise it, but add the arm so a future regression maps to `caller_not_owner`, not an opaque `rpc_failed` 500.
- `CREATE OR REPLACE FUNCTION` overload note: adding `p_caller_user_id uuid DEFAULT NULL` creates a **new 3-arg overload** (the 2-arg signature still exists in the catalog until dropped). The down-migration must `DROP FUNCTION …(uuid,uuid,uuid)` explicitly and the up-migration's GRANT/REVOKE must target the 3-arg overload signature, or PostgREST may still resolve the old 2-arg form. Verify both overloads' grants at /work.
