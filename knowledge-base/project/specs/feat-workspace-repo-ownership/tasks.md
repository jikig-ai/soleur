---
title: Workspace Repo Ownership — Tasks
issue: 4558
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-28-feat-workspace-repo-ownership-plan.md
---

# Tasks: Workspace Repo Ownership (#4558)

> Phase ordering is load-bearing: schema (079) before backfill (080) before reads (081). Run `/soleur:deepen-plan` before `/work` (single-user-incident threshold). NEVER apply migrations to shared dev-Supabase pre-merge.

## Phase 0: Preconditions (re-verify at /work)

- [x] 0.1 Re-grep call sites (counts drift): broader than plan's known list — also `repo/create:51`, `repo/setup:59`, `repo/detect-installation:48`, `repo/repos:25`, `dashboard/today/[id]/undo:163`, `agent-on-spawn-requested:219` (all select `github_installation_id`; resolve users-vs-workspaces at sweep)
- [x] 0.2 Migration ceiling confirmed **078** (no parallel branch claimed 079)
- [ ] 0.3 Read `webhooks/github/route.ts:193-316` + `workspace-reconcile-on-push.ts:97-128` to confirm the P0-1 push-path shape before editing (deferred to Phase 3 start — not needed for migrations)
- [x] 0.4 Runner confirmed **vitest** (`test: "vitest"`); `bunfig.toml [test] pathIgnorePatterns = ["**"]` blocks bun test
- [x] 0.5 #2244 (kb-route-helpers `syncWorkspace`) still **OPEN** — thread `workspaceId` through current call shape; reconcile if it merges before this PR
- [x] 0.6 ADR-044 created (`amends: [ADR-038]`); ADR-038 back-referenced via `amended_by: [ADR-044]`
- [x] 0.7 Confirmed `is_workspace_member` pins `search_path = public, pg_temp` (053:120)

## Phase 1: Schema + session plumbing — migration 079 (additive, reversible)

- [x] 1.1 (RED→GREEN) Shape tests in `test/supabase-migrations/079-workspace-repo-ownership-schema.test.ts`: 5 repo cols, non-unique indexes, NO UNIQUE on repo_url (AC1), column-level credential split (AC2). RED confirmed (ENOENT), now GREEN (28 passed)
- [x] 1.2 Wrote `079_workspace_repo_ownership_schema.sql` with `-- LAWFUL_BASIS:` header; repo cols mirror 011 + non-unique indexes. **Plan correction:** column-level credential protection requires `REVOKE SELECT ON workspaces FROM authenticated` + `GRANT SELECT (non-credential cols)` — the plan's literal `REVOKE SELECT (github_installation_id)` is a no-op while Supabase's table-level grant exists
- [x] 1.3 `resolve_workspace_installation_id(p_workspace_id) RETURNS bigint`: is_workspace_member check (deny→RETURN NULL), search_path pin, 4-role REVOKE + GRANT authenticated
- [x] 1.4 Added `current_workspace_id` to `user_session_state` (FK ON DELETE SET NULL) + idempotent solo-workspace backfill (col ADD precedes hook CREATE OR REPLACE — asserted by test)
- [x] 1.5 Extended `runtime_jwt_mint_hook` to inject `current_workspace_id`; org-injection + OTP precheck preserved; hook grant stays `supabase_auth_admin`. (Combined the two user_session_state reads into one SELECT — org injection IF-block + OTP block unchanged)
- [x] 1.6 `set_current_workspace_id` RPC: 28000/22004/42501 guards; is_workspace_member; org_id lookup + FK-race RAISE (23503); sets both claims; 4-role REVOKE + GRANT authenticated
- [x] 1.7 Wrote `079_*.down.sql` (drop both RPCs, revert hook to exact 060 body, drop column + indexes + repo cols, restore table GRANT)
- [~] 1.8 (GREEN-apply) Behavioral integration tests (AC8/AC10/AC2 + round-trip) live in the `describe.skip` block, activate with `TENANT_INTEGRATION_TEST=1` + live `DATABASE_URL_POOLER` at apply time on a DEDICATED dev project — NOT applied to shared dev pre-merge per `hr-dev-prd-distinct-supabase-projects`. `migration-rpc-grants.test.ts` lint passes for both new RPCs

## Phase 2: Idempotent solo-only backfill — migration 080

- [x] 2.1 Shape test `test/supabase-migrations/080-backfill-workspace-repo-from-users.test.ts`: idempotence guard, invited-solo SKIP (COUNT>1 + NOTICE), copy shape. RED→GREEN (11 passed)
- [x] 2.2 Wrote `080_backfill_workspace_repo_from_users.sql`: copy users→workspaces on `w.id=u.id`, canary owner-row + `COUNT(members)=1` guard, `WHERE w.repo_url IS NULL AND u.repo_url IS NOT NULL`, `GET DIAGNOSTICS`/`RAISE NOTICE` audit + separate SKIP-audit loop for co-membered
- [x] 2.3 TS/SQL `normalizeRepoUrl` parity in `test/repo-url-sql-parity.test.ts` (JS port of 031 chain): URL→URL backfill parity (incl `.git.git`) AND slug→URL compose-before-normalize (AC7/task 3.9, since shared normalizer). 16 passed, synthesized fixtures
- [x] 2.4 Wrote `080_*.down.sql` — scoped-forward-only (nulls only rows still `IS NOT DISTINCT FROM` source; documented forward-only for divergent rows)
- [~] 2.5 (GREEN-apply) Real-DB backfill verification in `describe.skip` integration block (apply time, dedicated dev project). users cols kept intact (asserted by negative-space test). Plain copy — no re-normalization (031 already canonicalized)

## Phase 3: Read cutover — TS (workspaces-only reads)

> **RESUME POINT (2026-05-28, rev 2).** DB layer (079/080), resolver guard, AND the core read-cutover are done, tested, committed, pushed. Full web-platform suite GREEN (7083 passed). Design decision (operator-confirmed): read paths use INTERNAL active-workspace resolution from `user_session_state` (via new `resolveCurrentWorkspaceId`), NOT claim-threading through 18 sites — server-derived, satisfies AC5 IDOR intent, far lower blast radius. `getCurrentRepoUrl` + `resolveInstallationId` now read `workspaces` for the active workspace.
>
> **rev 3 (2026-05-28): push-path fan-out (item 1) + anonymise cascade (3.14) DONE & green.** Migrations 079/080/081 + resolver + read-cutover + push-path fan-out all committed/pushed; full suite green (7085+). Backend/DB/sync re-architecture core COMPLETE. Remaining is UI + connect-write-path sweep + legal + ship:
> - **AC5 write-path sweep (3.5 cont.):** 10 direct `users.github_installation_id` reads remain. Triage: `repo/create:51` + `repo/setup:59` are CONNECT WRITE flows — post-cutover they must WRITE repo_url/installation to the active `workspaces` row (via a definer RPC or service write), not `users`. `repo/detect-installation:48`, `repo/repos:25`, `dashboard/today/.../undo:163`, `agent-runner:931`, `agent-on-spawn-requested:219`, `kb/sync:79` — route through `resolveInstallationId`/RPC. (users cols still authoritative until decommission, so these are not divergent — AC5→0 is the goal, not a correctness blocker.)
> - **3.4 run-time 404 fail-loud (AC9):** sync entry path must fail loud on GitHub 404 / App-lost-access (getCurrentRepoUrl already re-reads workspaces fresh per call).
> - **3.10 switcher write-path / 3.11 live-repo-badge.tsx / 3.13 J5 interstitial:** UI — needs browser testing (dev server). Use `getCurrentWorkspaceId(session)` (added) to read the claim; `set_current_workspace_id` RPC + refreshSession() (both shipped in 079). Wireframe badge/confirm delta first (.pen assets exist per Domain Review).
> - **Phase 4 legal (4.1-4.3) + Phase 5 verification/review/ship.**
>
> --- superseded earlier steps (DONE) ---
> REMAINING (historical, in order):
> 1. **Push-path fan-out re-architecture (HIGHEST RISK — the #4543 sync path). MUST land atomically in ONE commit.** Operator decision (2026-05-28): readiness guard = **filesystem-existence check** (drop the `users.workspace_status` dependency entirely). Concrete steps:
>    - (a) `isReconcilablePush` (`server/webhook-push-reconcilable.ts`): add `full_name?` to `ReconcilablePushBody.repository`; return `{ ok:false, reason:"missing-full-name" }` when absent (**fail-closed P0-2**); include `fullName` in the ok result. Update its test.
>    - (b) `session-sync.ts:301` bump `WORKSPACE_RECONCILE_SCHEMA_V` `"1"→"2"`.
>    - (c) webhook `route.ts`: add `full_name` to the body `repository` type (`:200`); add `fullName: reconcilable.fullName` to the dispatched Inngest `data` (`:292-300`); the `v: WORKSPACE_RECONCILE_SCHEMA_V` line auto-emits v=2.
>    - (d) `workspace-reconcile-on-push.ts` REWRITE: add `fullName: string` to `ReconcileEvent.data`; replace the `users`-row fetch with a **service-client** query `from("workspaces").select("id").eq("github_installation_id", installationId).eq("repo_url", normalizeRepoUrl("https://github.com/"+fullName))` → **fan out** over matches; per workspace: path = `join(WORKSPACES_ROOT, ws.id)` (export a `workspacePathForWorkspaceId(id)` helper from `workspace-resolver.ts` using `getWorkspacesRoot`), **fs-existence check** (`fs.promises.stat`/`existsSync` on path; absent → skip + kb_sync_history `workspace_not_ready` for the owner); resolve owner via `workspace_members role='owner'` for `appendKbSyncRow(ownerId,…)` attribution; `syncWorkspace(installationId, path, logger, {userId: ownerId, op:"push"})`. v=1 in-flight drains via the existing non-throwing schema-gate (already returns `{ok:false}` for v≠"2").
>    - (e) **REWRITE `test/server/inngest/workspace-reconcile-on-push.test.ts`** (423 lines, currently founder/users-keyed): mock service client `from("workspaces")` + `workspace_members` owner lookup + `fs`; assert fan-out (2 workspaces sharing installation both synced), fail-closed on absent full_name, v=1 drains to `{ok:false}`, slug→URL match yields non-zero rows, cross-tenant isolation preserved. Update `test/server/webhooks/webhook-push-dispatch.test.ts` for fullName+v=2.
>    - DO NOT commit (b) without (c)+(d) in the SAME commit (a lone SCHEMA_V bump deadletters every reconcile).
> 2. **AC5 sweep → 0.** Convert the 10 remaining direct `users.github_installation_id` reads to the workspace-scoped path (route through `resolveInstallationId` or the RPC): `dashboard/today/[id]/undo:163`, `kb/sync:79`, `repo/create:51` (connect WRITE — writes repo state; cut over to workspaces), `repo/detect-installation:48`, `repo/repos:25`, `repo/setup:59` (connect WRITE), `webhooks/github:240` (push-path, item 1), `agent-runner:931`, `agent-on-spawn-requested:219`, `workspace-reconcile-on-push:101` (item 1). Connect/setup WRITE-path cutover (repo/create, repo/setup) is its own sub-unit — these write repo_url/installation; post-cutover they must write to the active workspace, not users.
> 3. Run-time repo revalidation fail-loud on GitHub 404 (3.4) — getCurrentRepoUrl already re-reads workspaces fresh per call; add the 404/App-lost-access loud-fail in the sync entry path.
> 4. Switcher write-path (`org-switcher-container.tsx`): `set_current_workspace_id`→`refreshSession()`, read claim via `getCurrentWorkspaceId(session)` from JWT (added); inline confirm+status (no new component).
> 5. `live-repo-badge.tsx` (NEW, 3.11), J5 interstitial (3.13), anonymise cascade `workspaces.github_installation_id` (3.14, AC11).
> Helpers shipped: `getCurrentWorkspaceId(session)` + `resolveCurrentWorkspaceId(userId, supabase)` in `workspace-resolver.ts`. AC7 parity gate shipped in `test/repo-url-sql-parity.test.ts`.

- [x] 3.1 (RED→GREEN) Resolver tests in `test/resolve-installation-id.test.ts`: (a) active-workspace resolve never sibling; (b) non-member → null; (c) undefined/null claim → solo workspace. 7 passed
- [x] 3.2 Rewrote `resolve-installation-id.ts`: `(userId, workspaceId?)`; credential read **only via `resolve_workspace_installation_id` RPC**; **deleted** the `.ilike("repo_url", ...)` fallback, the unscoped `workspace_members … LIMIT 1` sibling lookup, AND `extractGitHubOwner` (dead after fallback removal)
- [x] 3.3 Undefined/null-claim default → caller's solo workspace (`= userId`); never error, never sibling. (Callers still pass only userId → behave as solo until the claim-threading sweep in step 5 above)
- [~] 3.4 Run-time repo revalidation: `getCurrentRepoUrl` re-reads `workspaces.repo_url` fresh per call (truthful-at-run-time for repo_url — repo-side revalidation DONE). DEFERRED to fresh session: cut over `agent-runner.ts:1255` installationId from `users.github_installation_id` → `resolveInstallationId(userId)` (active-workspace, fixes #4543 at runtime for joined members) + fail-loud when repoUrl present but installation null (AC9). **Reason for defer:** entangled with the 12-file agent-runner test mock harness — each `rpc: vi.fn()` must return the per-test installation (incl. null cases) for `resolve_workspace_installation_id`; a careful uniform mock-helper pass, not a rushed session-end edit. Source change is a clean ~10-line diff (drafted then reverted to keep suite green).
- [x] 3.5 (write-path) Read-cutover via INTERNAL resolution: `getCurrentRepoUrl`+`resolveInstallationId` read active workspace from `workspaces` (DONE). **Write-path dual-write DONE** — `mirrorRepoColsToSoloWorkspace` wired into `repo/setup` (×3), `repo/install`, `repo/detect-installation`, `repo/disconnect` so connects/disconnects keep the workspace read-path consistent (closes the soak read/write gap). REMAINING (fresh session, AC5-grep polish, NOT correctness — users cols dual-written/authoritative): route the sync-read sites (`agent-runner:1255` per 3.4, `agent-on-spawn:219`, `kb/sync:79`, `dashboard/today/.../undo:163`, `repo/repos:25`) through the workspace path. The connect-flow installation READS (detect/repos/create/setup) legitimately read the user's GitHub App identity (meaning #1) and stay user-scoped.
- [x] 3.6 Push-path tests (rewrote `workspace-reconcile-on-push.test.ts`, 8 tests): fan-out (2 workspaces sharing installation both synced), full_name absent → fail-closed (dispatch test Case 1b), v=1 drains to `{ok:false}`, no-match skip, dir-missing skip, sync-failure, cross-tenant isolation (AC6)
- [x] 3.7 Re-architected push path: `full_name` in route body type + Inngest payload; `WORKSPACE_RECONCILE_SCHEMA_V` `"1"→"2"`; reconcile fans out via service client to all workspaces matching `(github_installation_id, normalizeRepoUrl("https://github.com/"+fullName))`; path = `workspacePathForWorkspaceId(ws.id)`; **filesystem-existence** readiness (operator decision, drops users.workspace_status); owner-attributed kb_sync_history
- [x] 3.8 Fail-closed in `isReconcilablePush` (`reason: "missing-full-name"`) when `repository.full_name` absent (P0-2) — never installation-id-only match
- [x] 3.9 Slug→URL: reconcile composes `https://github.com/${fullName}` BEFORE `normalizeRepoUrl` (AC7 test asserts repo_url filter gets composed URL, never bare slug); parity gate `test/repo-url-sql-parity.test.ts` already green
- [ ] 3.10 Switcher write-path: call `set_current_workspace_id` → `refreshSession()`; read claim from session JWT not `getUser()`; INLINE confirm + status chain into `org-switcher-container.tsx` (no new confirm component)
- [ ] 3.11 `live-repo-badge.tsx`: poll-on-mount "Working on: owner/repo"; renders J6 default landing
- [ ] 3.12 Workspace-path resolution → active-workspace-relative (`workspace-resolver.ts`, `agent-runner.ts`)
- [ ] 3.13 J5: revocation interstitial + `current_workspace_id` fallback to personal workspace
- [x] 3.14 Cascade: migration **081** CREATE OR REPLACEs `anonymise_organization_membership` to null `workspaces.github_installation_id` (+ repo_status='not_connected', repo_last_synced_at=NULL) per owned org; preserves 078 owner-transfer; `.down.sql` reverts to 078 body; shape test + grants lint green (AC11, Art-17)

## Phase 4: Legal (parallel; TR8)

- [ ] 4.1 `legal-document-generator`: amend PA-17 across `privacy-policy.md`, `data-protection-disclosure.md` §2.3, `gdpr-policy.md`, `article-30-register.md` for co-member repo/KB access
- [ ] 4.2 Amend attestation (058) copy to cover repo/KB data-access consent
- [ ] 4.3 `legal-compliance-auditor`: cross-document consistency re-audit

## Phase 5: Verification

- [ ] 5.1 RLS tests: (a) member cannot SELECT another workspace's row; (b) member cannot SELECT `github_installation_id` of their OWN workspace (column-level) — only via `resolve_workspace_installation_id` (AC2)
- [ ] 5.2 Full suite green; tsc clean (signature breaks caught)
- [ ] 5.3 `/soleur:review` + QA before merge

## Post-merge (operator)

- [ ] P.1 Apply 079 → 080 to prd via `web-platform-release.yml#migrate`; verify columns + backfill counts via Supabase MCP (read-only) (AC14)
- [ ] P.2 Verify GitHub App install `122213433` grants `jikig-ai/soleur` via App-JWT `gh api /installation/repositories`; if absent, install App on `soleur` (AC16, Open Q1)
- [ ] P.3 **Before any decommission migration:** drift reconciliation query returns 0 (re-backfill mid-migration connects first) (AC15)
