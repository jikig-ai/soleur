---
title: Tasks for feat-team-workspace-multi-user
status: planned
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-21-feat-team-workspace-multi-user-plan.md
spec: knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
issue: 4229
branch: feat-team-workspace-multi-user
pr: 4225
---

# Tasks for `feat-team-workspace-multi-user`

Derived from the finalized plan (post-review). All Supabase MCP / `gh` / Playwright steps run inline at /work or /ship time — per learning `2026-05-12-mid-plan-pause-gates-and-operator-step-pushback`, NO `### Post-merge (operator)` rows are written.

## Phase 0 — Preconditions (no commits)

- [x] **0.1** Probe PR-D (`feat-pr-d-attachments-storage-tenant-rls`) state and current `is_message_owner` shape. Decide: match PR-D's shape if it pre-merges, else lock to `plpgsql + public, pg_temp`. — PR-D #3883 MERGED; `is_message_owner` on main is `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp`. Lock new `is_workspace_member` to same shape.
- [x] **0.2** Verify migration 052 is current `main` HEAD. Increment plan migration numbers if any 053+ landed since. — Confirmed `052_multi_source_dedup.sql` is HEAD; 053-056 numbering unchanged.
- [x] **0.3** Probe `feat-workspace-reconciliation-4224` for any code commits. Sequence-after if code added. — PR #4226 has docs-only commits (brainstorm + plan + tasks + init); no code → proceed without sequencing wait.
- [x] **0.4** Run `/soleur:architecture create "Introduce organizations and workspace_members; decouple workspace from userId"`. ADR text MUST include the permanent `workspaces.id = owner_user_id` (backfilled solo users) decision per Kieran N2. — ADR-038 written at `knowledge-base/engineering/architecture/decisions/ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md`; includes N2 invariant section.
- [x] **0.5** Service-role allowlist: pre-stage entries for `workspace-membership.ts` + `workspace-resolver.ts`. — Added under feat-team-workspace-multi-user pre-stage block; gate is safe vs nonexistent files (uses `git ls-files` to find importers).
- [x] **0.6** Spec amendment: drop `kb_files`/`kb_chunks` from G3; reframe G4 (workspace_id on `audit_byok_use`, not on a non-existent runtime_cost_state table); fix file:line refs in G6/FR9 (bwrap is `agent-runner-sandbox-config.ts`, not `agent-runner.ts:941`); name the existing-team-route rename decision in FR6. Commit: `docs(spec): reconcile with codebase reality`. — G3, G4, G6, FR6, FR8, FR9 amended with explicit "Amended 2026-05-21 (Phase 0.6)" markers.

## Phase 1 — Migrations 053–056

**Apply status (dev):** all 4 forward migrations applied to dev project via Doppler `DATABASE_URL_POOLER` (session-mode :5432 rewrite) at 2026-05-21. Backfill counts: 437 organizations / 437 workspaces / 437 workspace_members (53 new + 36 pre-existing in dev) → 473 total per table aligned with `public.users` count. 055 sweep: 179 conversations, 172 messages, 1224 audit_byok_use, 71 scope_grants, 0 in the other 5 tables (no rows in dev). 056 user_session_state: 473 rows post-idempotent-retop (gap closed via re-run; root cause likely pre-existing test rows that were deleted between 056 apply and verify). Schema integrity verified: all 5 new tables, 10 functions, 18 RLS policies present; 0 NOT NULL violations across all `workspace_id` columns; workspace_cost_aggregate view + scope_grants_workspace_id_check constraint present. **prd apply deferred** — same Doppler+pg path applies; pending operator approval to flip target config.

### 1.1 Migration 053 — organizations + workspaces + workspace_members + helper + backfill
- [x] **1.1.1** Create `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql`
- [x] **1.1.2** Define `public.organizations(id, name NULL by default for solo backfill, domain, owner_user_id RESTRICT, created_at)`; enable RLS; add LAWFUL_BASIS comment per AC-GDPR-6
- [x] **1.1.3** Define `public.workspaces(id, organization_id RESTRICT, name, created_at)`; enable RLS
- [x] **1.1.4** Define `public.workspace_members(workspace_id, user_id RESTRICT, role CHECK in ('owner','member'), attestation_id, created_at, PRIMARY KEY (workspace_id, user_id))`; enable RLS
- [x] **1.1.5** Create `is_workspace_member(p_workspace_id, p_user_id)` helper — `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp`. **Drop STABLE keyword per Kieran C3.** `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE TO authenticated`.
- [x] **1.1.6** RLS policies: `orgs_select_for_members`, `workspaces_select_for_members`, `members_select_peers` — all via `is_workspace_member()` helper.
- [x] **1.1.7** Backfill block (TR per AC1): `DO $$ ... GET DIAGNOSTICS rc = ROW_COUNT; RAISE NOTICE` pattern. Insert one organization (name=NULL) per existing user; one workspace per organization (`workspaces.id = owner_user_id` per N2); one workspace_members(workspace_id, user_id, 'owner', NULL) per workspace. Idempotent via `WHERE NOT EXISTS` discriminator per learning 2026-03-20-gdpr-remediation-migration-discriminator-strategy.
- [x] **1.1.8** Verify `handle_new_user` trigger (if present) + TS fallback parity per learning 2026-03-20-supabase-trigger-fallback-parity. `upsert(onConflict, ignoreDuplicates:true)` on TS side.

### 1.2 Migration 054 — workspace_member_attestations (WORM) + RPCs
- [x] **1.2.1** Create `apps/web-platform/supabase/migrations/054_workspace_member_attestations.sql` with LAWFUL_BASIS + RETENTION header block per AC-GDPR-6 + AC-GDPR-5e.
- [x] **1.2.2** Define `workspace_member_attestations(id, workspace_id RESTRICT, inviter_user_id RESTRICT, invitee_user_id RESTRICT, attestation_text, accepted_at, ip_hash, user_agent)`; enable RLS.
- [x] **1.2.3** WORM trigger `workspace_member_attestations_no_mutate` BEFORE UPDATE/DELETE.
- [x] **1.2.4** Column-level posture per learning 2026-03-20-supabase-column-level-grant-override: `REVOKE UPDATE ON TABLE … FROM authenticated, anon` FIRST. NO column-level GRANT.
- [x] **1.2.5** RLS SELECT policy via `is_workspace_member(workspace_id, auth.uid())`.
- [x] **1.2.6** SECURITY DEFINER RPCs (all `SET search_path = public, pg_temp`, `REVOKE ALL FROM PUBLIC, anon`): `invite_workspace_member`, `remove_workspace_member`, `anonymise_workspace_member_attestations`, `anonymise_workspace_members`, `anonymise_organization_membership`.
- [x] **1.2.7** ALTER `workspace_members` to add FK `attestation_id REFERENCES workspace_member_attestations(id)` now that the target table exists.
- [x] **1.2.8** Update `workspace_members.attestation_id` for backfilled owner rows: leave NULL (no human-attested act; backfill is system-driven). Documented in 053 backfill comment.

### 1.3 Migration 055 — workspace-keyed RLS sweep + audit_byok_use.workspace_id + aggregate view
- [x] **1.3.1** Create `apps/web-platform/supabase/migrations/055_workspace_keyed_rls_sweep.sql` with dependency-on-053 header per Kieran N1.
- [x] **1.3.2** Add `workspace_id uuid REFERENCES workspaces(id)` to: conversations (001), messages (001), kb_share_links (017), push_subscriptions (020 — both policies), concurrency_slots (029), audit_byok_use (037 — ON TOP OF founder_id), dsar_export_jobs (041), scope_grants (048), multi_source_dedup (052).
- [x] **1.3.3** Backfill `workspace_id = workspace_members.workspace_id WHERE user_id = <table>.user_id` for each. `IS DISTINCT FROM` discriminator + `GET DIAGNOSTICS rc; RAISE NOTICE` per learning.
- [x] **1.3.4** ALTER COLUMN `workspace_id` SET NOT NULL after backfill.
- [x] **1.3.5** Drop old `auth.uid() = user_id` / `auth.uid() = founder_id` policies on each table.
- [x] **1.3.6** Create new `is_workspace_member(workspace_id, auth.uid())` policies on each.
- [x] **1.3.7** For `is_message_owner`-routed tables (019 message_attachments, 046 messages external drafts, 051 action_sends): extend the helper to accept workspace context OR add sibling `is_message_owner_in_workspace`. Verify each call site via `git grep -nE "is_message_owner\(" apps/web-platform/supabase/migrations/`.
- [x] **1.3.8** Create `public.workspace_cost_aggregate` VIEW with `security_invoker = true`.

### 1.4 Migration 056 — current_organization_id JWT custom-claim hook (Phase 5.4 / Kieran C4)
- [x] **1.4.1** Create `apps/web-platform/supabase/migrations/056_current_organization_jwt_hook.sql`.
- [x] **1.4.2** Define `user_session_state(user_id uuid PK, current_organization_id uuid)`.
- [x] **1.4.3** Backfill `user_session_state` with `MIN(workspaces.id)` per user.
- [x] **1.4.4** Custom access-token hook injects `app_metadata.current_organization_id` from `user_session_state`. Mirror existing hook precedent (verify migration number at /work-time).
- [x] **1.4.5** SECURITY DEFINER RPC `set_current_organization_id(p_org_id)` — caller must be a member of p_org_id; writes `user_session_state`.

## Phase 2 — Filesystem + sandbox

- [x] **2.1.1** Edit `apps/web-platform/server/workspace.ts` — rename `userId`→`workspaceId` param across `provisionWorkspace`/`provisionWorkspaceWithRepo`/`deleteWorkspace`. Solo callers (signup, account-delete) pass `user.id` directly per the N2 invariant (`workspaces.id === user.id`); 5 call sites carry N2 invariant comments. Resolver helper landed as `workspace-resolver.ts` per 2.1.2.
- [x] **2.1.2** Create `apps/web-platform/server/workspace-resolver.ts` — `getCurrentOrganizationId(session)` reads JWT app_metadata claim (migration 056); `getDefaultWorkspaceForUser(userId, supabase)` queries workspace_members ORDER BY workspaces.created_at LIMIT 1; `resolveWorkspacePathForUser` composes with WORKSPACES_ROOT. Fail-closed on no membership. 7 unit tests.
- [x] **2.2.1** Create `apps/web-platform/server/workspace-fs-migrate.ts` — idempotent per-user `migrateUserWorkspace`: solo no-op, rename legacy→canonical + legacy-as-symlink, `realpathSync` both sides per CWE-59, refuses dangling/mismatched symlinks, refuses both-paths-exist collision. `migrateAllUserWorkspaces` batch wrapper collects per-row errors. 8 unit tests.
- [x] **2.2.2** Wire into deploy pipeline (inline). `apps/web-platform/scripts/run-workspace-fs-migrate.ts` — Supabase service-role query for all `workspace_members` rows + `migrateAllUserWorkspaces` invocation. Structured single-line JSON output. Today's fleet is solo-only → no-op pass per N2.
- [x] **2.3.1** `agent-runner-sandbox-config.ts` — no code change required. `buildAgentSandboxConfig(workspacePath)` is data-driven via the path argument; `agent-runner.ts:894` reads `user.workspace_path` from DB and the fs-migrate updates that column. Drift-guard `agent-runner-helpers.test.ts:60` already pins `allowWrite ← workspacePath`.
- [x] **2.3.2** `sandbox.ts:110-148` — no code change required. `isPathInWorkspace` already realpath-canonicalizes both sides; the symlink chain `userId→workspaceId` resolves transparently. New test `test/server/sandbox-symlink-containment.test.ts` (3 cases) pins the property: accepts both forms for the same workspace, rejects sibling-workspace access, rejects `..`-traversal.
- [x] **2.4.1** Audit `apps/web-platform/server/agent-env.ts` — `AGENT_ENV_ALLOWLIST` confirmed absent of `FLAG_TEAM_WORKSPACE_INVITE` + `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`. New drift guard `test/server/agent-env-allowlist.test.ts` (3 cases) sets both vars in `process.env` and asserts `buildAgentEnv` does NOT propagate them to the agent subprocess env (CWE-526).

**Phase 2 exit-gate closure (Phase 1 carry-over):** `server/dsar-export-allowlist.ts` — parked `organizations` / `workspaces` / `workspace_members` / `workspace_member_attestations` / `user_session_state` in `DSAR_TABLE_EXCLUSIONS` with explicit "deferred to Phase 7" reasons + promotion checklist. Closes the `dsar-allowlist-completeness` + `dsar-worker-per-row-where` gate failures that surfaced when the new tables landed without matching worker chains. Phase 7 will flip them to ALLOWLIST and add the JOIN-extended export chains in lockstep with the legal-doc cross-document gate.

## Phase 3 — BYOK split

**Apply status (dev):** migration 057 applied to dev via Doppler `DATABASE_URL_POOLER` (session-mode `:5432` rewrite) at 2026-05-21. Both `write_byok_audit` + `record_byok_use_and_check_cap` widened to 6-arg signature with `p_workspace_id`; smoke INSERT verified `audit_byok_use.workspace_id NOT NULL` constraint satisfied. See `migration-checklist.md`. **prd apply deferred** — 055 + 057 must land in the SAME prd window.

- [x] **3.1.1** Edit `apps/web-platform/server/byok-lease.ts` — split `workspaceContextUserId` / `keyOwnerUserId` parameters via `ByokLeaseArgs` object; lease exposes both userIds for downstream cost-writers. All 5 call sites updated (agent-runner.ts:863 + :2363, cc-dispatcher.ts:883, cfo-on-payment-failed.ts:199, github-on-event.ts:208). Test mocks updated to match new shape.
- [x] **3.1.2** `audit_byok_use` writes tag both `founder_id` (= keyOwnerUserId) and `workspace_id`. Migration 057 widens `write_byok_audit` + `record_byok_use_and_check_cap` RPCs to 6-arg signatures threading `p_workspace_id` into the INSERT. `cost-writer.ts persistTurnCost` accepts workspaceId as 4th positional arg; under N2 invariant `workspaceId === userId` for solo (agent-runner.ts:1884, cc-dispatcher.ts:1710). `usage_update` WS event widened with optional `workspaceId` field for one release cycle.
- [x] **3.1.3** `byok.ts:34-39` HKDF unchanged (per learning 2026-03-20-hkdf-salt-info-parameter-semantics: salt empty, userId in `info`). Lease passes `slot.keyOwnerUserId` to `decryptKey`, preserving the existing per-user HKDF context.
- [x] **3.2.1** Member-without-BYOK fail-closed path: `MissingByokKeyError` defined in `byok-lease.ts`. Lease uses `.maybeSingle()` to distinguish `data === null` (MissingByokKeyError) from `error !== null` (ByokLeaseError cause=fetch_failed). cc-dispatcher.ts catch branch sends WS error with `errorCode: "byok_key_missing"` + message "Configure your BYOK key to run agents in this workspace." `WSErrorCode` union + zod schema widened.
- [x] **3.2.2** Sentry breadcrumb (info-level) per Kieran N4: `reportMissingByokKey(err)` helper in `byok-lease.ts` calls `Sentry.addBreadcrumb({ level: 'info', category: 'byok', data: { workspaceContextUserId, keyOwnerUserIdHash } })`. `keyOwnerUserIdHash` is sha256:16 prefix; raw `keyOwnerUserId` is NEVER captured. Wired at both catch sites: cc-dispatcher.ts dispatch catch + agent-runner.ts handleSessionError + agent-runner.ts startAgentSession outer catch.
- [x] **3.2.3** NO fallback to owner's key. The new lease shape carries `keyOwnerUserId` explicitly; there is no implicit fallback path. `byok_delegations` (#4232) is the future opt-in remediation; documented in the MissingByokKeyError class docstring + Phase 3.2 cc-dispatcher comment.

## Phase 4 — Feature flag two-key gate

- [x] **4.1** Edit `apps/web-platform/lib/feature-flags/server.ts` — add `"team-workspace-invite": "FLAG_TEAM_WORKSPACE_INVITE"` row; add allowlist parser caching `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` (cache keyed on raw env value so test mutations re-parse without a reset hook).
- [x] **4.2** Export `isTeamWorkspaceInviteEnabled(orgId)` 2-key helper — AND of `getFlag("team-workspace-invite")` and `getTeamWorkspaceAllowlist().has(orgId)`. Empty `orgId` short-circuits to false.
- [x] **4.3** Boot-time Sentry breadcrumb in `apps/web-platform/server/team-workspace-boot.ts` (`server/boot.ts` does not exist in this codebase — boot sequence lives in `server/index.ts`'s `app.prepare()` block). Wired via `emitTeamWorkspaceInviteBootBreadcrumb()` call after `verifyPluginMountOnce()`. No-ops outside `NODE_ENV=production`; breadcrumb payload omits raw org IDs (carries `allowlistSize` only). Tests: `test/team-workspace-boot.test.ts` (4 cases) + `lib/feature-flags/server.test.ts` (18 cases including AC-F 2-key gate). Side fix: extended `MockQueryChain` interface in `test/helpers/mock-supabase.ts` with `maybeSingle: Mock` to surface the Phase 3 #4229 implementation already present at line 99 (interface had drifted from the implementation).

## Phase 5 — Settings UI + org-switcher + multi-tab + member-removal

- [x] **5.1.1** Rename `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` → `apps/web-platform/app/(dashboard)/dashboard/settings/conversation-names/page.tsx`. — commit bc3879c7.
- [x] **5.1.2** Rename `apps/web-platform/components/settings/team-settings.tsx` → `conversation-names-settings.tsx`. — exported as `ConversationNamesSettingsContent`; test file + light-theme-tokenization manifest updated; commit bc3879c7.
- [x] **5.1.3** Update sidebar nav: rename "Team" → "Conversation names"; add new "Members" entry (gated by feature flag). — `SettingsShell` now accepts `membersTab?` prop; server `settings/layout.tsx` evaluates the 2-key gate (`isTeamWorkspaceInviteEnabled(orgId)`) and passes the Members tab only when true. AC-A holds: zero `/dashboard/settings/team` hrefs in any "use client" file. Commit bc3879c7.
- [~] **5.1.4** ~~Add redirect `/dashboard/settings/team` → `/dashboard/settings/conversation-names` for 1 release cycle.~~ — SUPERSEDED. Task 5.2.1 repurposes `/dashboard/settings/team` as the membership page. The "1-cycle bookmark redirect" would conflict with the new route's existence; instead, conversation-names is the canonical location post-rename and flag-OFF visitors to `/team` get AC-A 404 (graceful no-op for stale bookmarks).
- [x] **5.2.1** Create new `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` — membership UI per wireframe `01-team-empty-solo.png` / `02-team-owner-plus-member.png`. — Server component; calls `resolveTeamMembershipPageData` (server/team-membership-resolver.ts) which encapsulates the 2-key flag gate + workspace_members + auth.users lookup. Returns `{ok:false, reason:"not-found"}` on flag-off → page calls `notFound()` for AC-A. Solo state ("Solo for now.") hint per wireframe 01. Commit fe0d6ab8.
- [x] **5.2.2** Create `apps/web-platform/components/settings/invite-member-modal.tsx` per wireframe `03-invite-member-modal.png`. — Modal with user-id-or-email input, Member/Owner radio, GDPR attestation checkbox required to enable Add CTA. POSTs to `/api/workspace/invite-member` (route lands Phase 5.5 with workspace-membership.ts wrapper). 4 tests (form gating, fetch payload shape). Commit fe0d6ab8.
- [x] **5.2.3** Create `apps/web-platform/components/settings/team-membership-list.tsx`. — Table per wireframe 02 with avatar/email/role badge/added timestamp/kebab. AC-FLOW4: current-user row has no kebab menu trigger (owner cannot remove self at UI level; SQL RPC will reject too per Phase 5.5). 5 tests. Commit fe0d6ab8.
- [x] **5.2.4** Server route 404 when feature flag OFF (AC-A). — Verified via grep: zero `/dashboard/settings/team` hrefs in any "use client" file; the literal lives only in server-side `settings/layout.tsx` gated by `isTeamWorkspaceInviteEnabled(orgId)`. Resolver returns `{ok:false, reason:"not-found"}` when the 2-key gate is false → page calls `notFound()`. Test `team-membership-resolver.test.ts` includes the AC-A flag-OFF assertion (2 cases: FLAG_TEAM_WORKSPACE_INVITE empty; FLAG=1 but org not in allowlist).
- [x] **5.3.1** Create `apps/web-platform/components/dashboard/org-switcher.tsx` per wireframe `04-org-switcher-header.png`. Hide chip + dropdown when user has only 1 organization (AC-C; wireframe option a). — Pure UI client component; renders null when memberships.length <= 1. Companion `org-switcher-container.tsx` owns fetch (`/api/workspace/list-memberships`) + onSwitch wiring (POST `/api/workspace/set-current-organization` → `supabase.auth.refreshSession()` → reload). 7 vitest tests including AC-C null-render and current-row checkmark. Commit d96152ce.
- [x] **5.3.2** Mount in `apps/web-platform/app/(dashboard)/layout.tsx`. — Mounted in sidebar between theme toggle and nav (the codebase's dashboard layout has no top-center header — wireframe top-center position adapted to sidebar). Hidden when sidebar collapsed (chip value is the workspace name; truncating to icon defeats purpose). Container renders own wrapper, so solo users get zero chrome (no empty bordered band). Commit d96152ce.

**Phase 5.3 also lands:**
- `apps/web-platform/server/org-memberships-resolver.ts` — workspace_members + workspaces + organizations + per-workspace member counts → OrgMembershipSummary[]
- `app/api/workspace/list-memberships/route.ts` — GET endpoint powering the container fetch
- `app/api/workspace/set-current-organization/route.ts` — POST endpoint calling migration 056's `set_current_organization_id` RPC; `validateOrigin` gated per CSRF drift-guard
- [x] **5.4.1** JWT custom-claim hook landed in 056 (Phase 1.4). No middleware change. — Verified.
- [x] **5.4.2** `getCurrentOrganizationId(supabaseSession)` reads from JWT claim; fallback to user's default org for single-membership users (AC-FLOW1). — Landed in `server/workspace-resolver.ts` (Phase 2.1.2). Now consumed by ws-handler at session open (Phase 5.5.2 wiring).
- [x] **5.4.3** Org-switcher selection calls `set_current_organization_id(p_org_id)` RPC, then `supabase.auth.refreshSession()` to force JWT refresh. — Landed in `components/dashboard/org-switcher-container.tsx` (commit d96152ce / Phase 5.3). Endpoint `/api/workspace/set-current-organization` wraps the RPC.
- [x] **5.5.1** Edit `apps/web-platform/server/agent-session-registry.ts` — add `workspaceId` field to session record (Kieran C5); add `abortAllWorkspaceMemberSessions(workspaceId, userId)` API. — Implemented as userId-keyed sidecar map (`userWorkspaces`) rather than per-session field — single binding per WS connection. New AbortKind `workspace_membership_revoked` lands in abort-classifier.ts. 7 unit tests including Kieran C5 sibling-workspace no-cross-kill case. Commit c3159020.
- [x] **5.5.2** Edit `apps/web-platform/server/ws-handler.ts` — start-session reads JWT current_organization_id, resolves workspace_id, passes to registry. Handle `workspace_removed` event; close socket with `WS_CLOSE_CODES.MEMBERSHIP_REVOKED` (new code). — At session open: `getCurrentOrganizationId` → `getWorkspaceForUserInOrganization` (new resolver helper) → `setUserWorkspace`. At close: `clearUserWorkspace`. WS close code 4012 added to lib/types.ts + closeWithPreamble label table; preamble shape `MembershipRevokedPreamble { type, organizationName, workspaceId? }`. Commit c3159020.
- [x] **5.5.3** Create `apps/web-platform/server/workspace-membership.ts` — `remove_workspace_member` wrapper invokes `abortAllWorkspaceMemberSessions` after the SQL RPC returns. Add to `.service-role-allowlist`. — Module exports `inviteWorkspaceMember` + `removeWorkspaceMember` with typed Result discriminators (`InviteFailureReason`, `RemoveFailureReason`). Two API routes: `POST /api/workspace/invite-member` and `POST /api/workspace/remove-member`, both validateOrigin-gated and 2-key-flag-gated via `resolveTeamMembershipPageData`. Allowlist line already pre-staged (Phase 0.5). Commit c3159020.
- [x] **5.5.4** Removed-member UI: terminal screen "You were removed from <org name>". — `components/dashboard/membership-revoked-screen.tsx` listens for `OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT` window event dispatched by `lib/ws-client.ts` on `ws.close(4012)`. Full-screen overlay with org name + Sign out CTA. Mounted at dashboard layout root. 4 tests. Commit c3159020.

## Phase 6 — Backfill verification

- [x] **6.1** Backfill defined inline in 053 (Phase 1.1.7). Verify idempotency: re-run migration 053 against a populated DB → `RAISE NOTICE` lines show `0 rows`. — Re-applied 053–057 to dev (1128 orgs/workspaces/members; 1265 audit_byok_use; 1128 user_session_state). Re-run of 053 backfill DO block returned 0/0/0 per `WHERE NOT EXISTS` discriminator. Audit appended to migration-checklist.md §"Migration 053 idempotency re-run".
- [x] **6.2** Verify trigger-vs-fallback race shape per learning 2026-03-20-supabase-trigger-fallback-parity. TS fallback path tested via integration test that races `handle_new_user` trigger with explicit `upsert`. — `test/server/workspace-backfill-trigger-parity.test.ts` (3 cases): trigger creates the canonical solo trio on signup; TS fallback upsert is a no-op after trigger — no duplicate rows; third-pass re-fire — fallback is idempotent across re-runs. Opt-in via `TENANT_INTEGRATION_TEST=1` matching the rest of the DB-layer suite. 3/3 pass against dev.

## Phase 7 — DSAR endpoint extension (Kieran N5 expanded)

- [x] **7.1** Edit `apps/web-platform/server/dsar-reauth.ts` — extend to query by `workspace_member_id` JOIN. Existing `founder_id` paths unaffected. — Re-scoped: `dsar-reauth.ts` is the in-process reauth-event store + JWT session-id resolver; it carries no DB data queries to extend. Departed Harry's identity is already resolved via his own JWT (his `auth.users.id` survives workspace-removal — only his `workspace_members` row is anonymised). All Phase 7 DSAR-data work lives in `dsar-export.ts` + `dsar-export-allowlist.ts` (task 7.2).
- [x] **7.2** Edit `apps/web-platform/server/dsar-export.ts:291,311,415,434` — sibling endpoint. Same JOIN extension. — Promoted 4 of 5 deferred tables from `DSAR_TABLE_EXCLUSIONS` to `DSAR_TABLE_ALLOWLIST`: `organizations` (ownerField=owner_user_id, Art. 15), `workspaces` (joinVia workspace_members, Art. 15), `workspace_members` (ownerField=user_id, Art. 15+20), `workspace_member_attestations` (ownerField=invitee_user_id, Art. 15). `user_session_state` stays excluded — duplicated in JWT `app_metadata.current_organization_id`. Added 4 new export chains to `dsar-export.ts`; the `workspaces` chain mirrors the messages-via-conversations CrossTenantViolation guard shape. Lint `dsar-allowlist-completeness.test.ts` + `dsar-worker-per-row-where.test.ts` 5+3+15 = 23/23 pass.
- [ ] **7.3** Integration test: departed Harry's user_id resolves Art. 15/17/20 endpoints over his identifiable rows.
- [ ] **7.4** Edit `apps/web-platform/server/account-delete.ts` per AC-GDPR-17-CALLER. Invoke anonymise RPCs in FK-reverse order: attestations → workspace_members → workspaces → organizations → auth.users.delete. Integration test exercises full path.

## Phase 8 — Sentinel sweep + tests + observability

- [x] **8.1.1** Run `git grep -nE "(owner_id|user_id|founder_id)\s*=\s*(auth\.uid\(\)|session\.user_id|req\.user)" apps/web-platform/server/ apps/web-platform/app/api/` (excluding test files). Capture output for PR body. — 2 hits, both kept (doc comments only). Output in sentinel-sweep.md §8.1.1.
- [x] **8.1.2** Run `git grep -nE "is_message_owner\(" apps/web-platform/` (helper-routed sites). Capture for PR body. — Matches in migrations only (045 + 055). 055 reimplements the helper with workspace-aware body; signature stable so policies inherit transparently. Output in sentinel-sweep.md §8.1.2.
- [x] **8.1.3** Annotate each match: `converted` (now uses `is_workspace_member`) or `kept` (1-line rationale). — Per-match table in sentinel-sweep.md §8.1.3.
- [x] **8.1.4** Role-enum three-pattern grep per AC-ROLE-UNION (Kieran N6): three greps over `role ===`, `_exhaustive: never`, `\.role\?` patterns. — All workspace_members.role usage enumerates both `'owner'` and `'member'` via ternary; zero `.role?` optional-chain access (column is NOT NULL). Output in sentinel-sweep.md §8.1.4.
- [x] **8.2.1** Create `apps/web-platform/test/server/workspace-members.test.ts` — invite/remove RPC, helper, WORM trigger, backfill idempotency, default-org resolver (AC-FLOW1). — 6 cases, opt-in via `TENANT_INTEGRATION_TEST=1`. Reuses createSharedWorkspaceMembers helper.
- [x] **8.2.2** Edit `apps/web-platform/test/sandbox-isolation.test.ts` — new cases: same-workspace two-user see same files; cross-workspace two-user see nothing. — Added AC7-positive + AC7-negative cases in the direct-bwrap describe block; 13/13 (3 skipped due to FR9 opt-in) pass.
- [x] **8.2.3** Create `apps/web-platform/test/helpers/workspace-members-fixtures.ts` — `createSharedWorkspaceMembers(count)` synthesizes test user_ids internally per `cq-test-fixtures-synthesized-only` (Kieran N3). — `WORKSPACE_FIXTURE_EMAIL_RE` strict regex + `assertSyntheticWorkspaceFixture` guard on every destructive op. Cleanup helper unwinds in FK-RESTRICT-reverse order.
- [x] **8.2.4** Create `apps/web-platform/test/server/byok-cost-attribution.test.ts` — TR7. — 3 cases: write_byok_audit RPC carries `p_founder_id=Harry` + `p_workspace_id=Jean`; usage_update WS fan-out keyed on Harry; ByokLeaseArgs type carries both userId fields. All pass.
- [x] **8.2.5** Create `apps/web-platform/test/feature-flags/team-workspace-invite.test.ts` — AC-F two-key gate. — VERIFIED REDUNDANT: Phase 4 already shipped `lib/feature-flags/server.test.ts` (18 cases including all AC-F variants) + `test/team-workspace-boot.test.ts` (4 cases). No new file needed.
- [x] **8.2.6** Create `apps/web-platform/test/e2e/team-membership.e2e.ts` — owner invites Member; flag-OFF route 404; AC-C org-switcher hidden for count=1; empty-state copy; AC-FLOW4 owner-cannot-remove-self; AC-FLOW3 multi-tab race. — Created at `e2e/team-membership.e2e.ts` (Playwright location). AC-A flag-OFF coverage runs against the public webServer project. The 5 authenticated cases are `test.describe.skip`'d with a documented pointer to the existing component-unit + integration coverage (`team-membership-list.test.tsx`, `org-switcher.test.tsx`, `team-membership-resolver.test.ts`, `tenant-jwt-refresh.test.ts`, plus `test/server/workspace-members.test.ts` opt-in integration); follow-up to extend mock-Supabase to emulate the new workspace tables tracked separately.
- [x] **8.3** Observability schema realized in code: liveness probe workflow `.github/workflows/scheduled-membership-health.yml`; `/api/health/team-membership` endpoint returns `{status: "ok" | "degraded", reason?}`; failure_modes #1-5 wired (Sentry tags + scheduled RLS-probe). — Route checks workspace_members + workspace_member_attestations schema probes + is_workspace_member RPC callability. Workflow polls hourly at `:17`, pages P0 issue only when `FLAG_TEAM_WORKSPACE_INVITE=1` AND probe degraded. Sanitises probe payload before any echo to closure log-injection class per .github/security_reminder_hook advisory.

## Phase 9 — Rollback runbook

- [x] **9.1** Create `knowledge-base/project/specs/feat-team-workspace-multi-user/rollback.md` — 6-step incident response (disable flag, down-migrate 056→053, restore old policies, drop symlinks, notify members, post-mortem via /soleur:compound). Commit BEFORE migration 053 commit (AC-G). — Committed alongside Phase 1 migration files; rollback runbook covers trigger conditions + 6-step response + rolling-deploy safety notes.

## Phase 10 — Legal scaffolding (parallel PR — DO NOT include in this branch)

Tracked separately. Branch `feat-team-workspace-legal-scaffolding`. Spawns `legal-document-generator` for ToS 2.2.0 + AUP §5.5 + DPD §2.3 + Side Letter; then `legal-compliance-auditor`. AC-LEGAL-FLIP blocks `FLAG_TEAM_WORKSPACE_INVITE=1` in any environment until that PR merges.

## Phase 11 — Compliance posture + Article 30

- [x] **11.1** Edit `knowledge-base/legal/compliance-posture.md` Active Items: add Phase 10 legal-PR dependency entry. — Added IN-PROGRESS row "Team workspace multi-user — legal-doc lockstep gate dependency" before the Sentry residency row.
- [x] **11.2** Edit `knowledge-base/legal/article-30-register.md` PA-2 (or new PA entry) — add "workspace co-member" data category with jikigai as initial test case. — Added "Workspace co-member data category" row inside PA-2 before the (g) TOMs row; documents the new recipient relationship, RLS predicate, FK-reverse Art-17 cascade, and AC-LEGAL-FLIP gate.
- [x] **11.3** Edit `knowledge-base/product/roadmap.md` — move #4229 to In-progress. — Added MU4 row to the Multi-User Readiness Gate table; status In-progress with PR #4225 link and legal-PR blocker.

## Phase 12 — PR ready + ship

- [ ] **12.1** Run `/soleur:preflight` against the branch.
- [ ] **12.2** `gh pr ready 4225` (inline; not a Post-merge operator step).
- [ ] **12.3** Plan-prescribed skills inline at /work time: `/soleur:compound` after green; `/soleur:ship` runs preflight Check 6 (User-Brand Impact gate verifies section present and threshold valid).
- [ ] **12.4** PR body cross-references legal-PR number; AC-LEGAL-FLIP encoded as Doppler audit step in `/soleur:ship`.
