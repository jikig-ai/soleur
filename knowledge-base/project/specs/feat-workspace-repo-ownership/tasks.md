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
> REMAINING, in order:
> 1. **Push-path fan-out re-architecture (HIGHEST RISK — the #4543 sync path). MUST land atomically:** (a) `session-sync.ts:301` bump `WORKSPACE_RECONCILE_SCHEMA_V` `"1"→"2"`; (b) webhook `route.ts:193-316` add `repository.full_name` to body type + Inngest payload, **fail-closed** skip+log when full_name absent (P0-2), emit v=2; (c) `workspace-reconcile-on-push.ts` add `fullName` to event.data, resolve workspace(s) by `(github_installation_id, normalizeRepoUrl("https://github.com/"+fullName))` via service client, **fan out**. **OPEN COUPLING: `workspace_path`/`workspace_status` live on `users` (migration 001), NOT workspaces — fan-out path = `join(WORKSPACES_ROOT, workspace_id)` (per `resolveWorkspacePathForUser`); workspace_status check needs an owner-join to users OR a filesystem-existence check. DECIDE before writing.** v=1 in-flight drains via existing non-throwing gate. DO NOT bump SCHEMA_V without (b)+(c) in the same commit (else all reconciles deadletter).
> 2. **AC5 sweep → 0.** Convert the 10 remaining direct `users.github_installation_id` reads to the workspace-scoped path (route through `resolveInstallationId` or the RPC): `dashboard/today/[id]/undo:163`, `kb/sync:79`, `repo/create:51` (connect WRITE — writes repo state; cut over to workspaces), `repo/detect-installation:48`, `repo/repos:25`, `repo/setup:59` (connect WRITE), `webhooks/github:240` (push-path, item 1), `agent-runner:931`, `agent-on-spawn-requested:219`, `workspace-reconcile-on-push:101` (item 1). Connect/setup WRITE-path cutover (repo/create, repo/setup) is its own sub-unit — these write repo_url/installation; post-cutover they must write to the active workspace, not users.
> 3. Run-time repo revalidation fail-loud on GitHub 404 (3.4) — getCurrentRepoUrl already re-reads workspaces fresh per call; add the 404/App-lost-access loud-fail in the sync entry path.
> 4. Switcher write-path (`org-switcher-container.tsx`): `set_current_workspace_id`→`refreshSession()`, read claim via `getCurrentWorkspaceId(session)` from JWT (added); inline confirm+status (no new component).
> 5. `live-repo-badge.tsx` (NEW, 3.11), J5 interstitial (3.13), anonymise cascade `workspaces.github_installation_id` (3.14, AC11).
> Helpers shipped: `getCurrentWorkspaceId(session)` + `resolveCurrentWorkspaceId(userId, supabase)` in `workspace-resolver.ts`. AC7 parity gate shipped in `test/repo-url-sql-parity.test.ts`.

- [x] 3.1 (RED→GREEN) Resolver tests in `test/resolve-installation-id.test.ts`: (a) active-workspace resolve never sibling; (b) non-member → null; (c) undefined/null claim → solo workspace. 7 passed
- [x] 3.2 Rewrote `resolve-installation-id.ts`: `(userId, workspaceId?)`; credential read **only via `resolve_workspace_installation_id` RPC**; **deleted** the `.ilike("repo_url", ...)` fallback, the unscoped `workspace_members … LIMIT 1` sibling lookup, AND `extractGitHubOwner` (dead after fallback removal)
- [x] 3.3 Undefined/null-claim default → caller's solo workspace (`= userId`); never error, never sibling. (Callers still pass only userId → behave as solo until the claim-threading sweep in step 5 above)
- [~] 3.4 Run-time repo revalidation: `getCurrentRepoUrl` now re-reads `workspaces.repo_url` fresh per call (truthful-at-run-time for repo_url). REMAINING: loud-fail on GitHub 404 / App-lost-access in the sync entry path (AC9)
- [~] 3.5 Read-cutover via INTERNAL resolution (operator-confirmed, not claim-threading): `getCurrentRepoUrl` + `resolveInstallationId` resolve the active workspace from `user_session_state` and read `workspaces`. Full suite green. REMAINING: 10 direct `users.github_installation_id` reads (AC5→0 list in RESUME POINT above), incl. connect/setup WRITE-path cutover
- [ ] 3.6 (RED) Push-path tests: 2 workspaces sharing one installation_id **both** reconciled (fan-out); `full_name` absent → fail closed; v=1 in-flight event drains to `{ok:false}` (AC6)
- [ ] 3.7 Re-architect push path: add `repository.full_name` to route body type + Inngest payload; **bump `WORKSPACE_RECONCILE_SCHEMA_V` "1"→"2"** emit v=2; reconcile **fans out** to all workspaces matching `(installation_id, normalize("https://github.com/"+full_name))`; rewrite `workspace-reconcile-on-push.ts:124-128` against workspace rows
- [ ] 3.8 Route fail-closed branch when `repository.full_name` absent (P0-2)
- [ ] 3.9 Slug→URL parity: compose `https://github.com/${full_name}` BEFORE `normalizeRepoUrl`; parity test incl. bare-slug→URL + `.git.git`, synthesized fixtures (AC7, hard gate)
- [ ] 3.10 Switcher write-path: call `set_current_workspace_id` → `refreshSession()`; read claim from session JWT not `getUser()`; INLINE confirm + status chain into `org-switcher-container.tsx` (no new confirm component)
- [ ] 3.11 `live-repo-badge.tsx`: poll-on-mount "Working on: owner/repo"; renders J6 default landing
- [ ] 3.12 Workspace-path resolution → active-workspace-relative (`workspace-resolver.ts`, `agent-runner.ts`)
- [ ] 3.13 J5: revocation interstitial + `current_workspace_id` fallback to personal workspace
- [ ] 3.14 Cascade: `anonymise_organization_membership` (or sibling) nulls `workspaces.github_installation_id`; `.down.sql` tested (AC11)

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
