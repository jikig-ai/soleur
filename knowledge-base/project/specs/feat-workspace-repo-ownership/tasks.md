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

- [ ] 0.1 Re-grep call sites (counts drift): `git grep -nE '\.(eq|select)\([^)]*github_installation_id|\.from\("users"\)[^;]*repo_url' apps/web-platform/server apps/web-platform/app`
- [ ] 0.2 Confirm migration ceiling still 078 (no parallel branch claimed 079); `ls apps/web-platform/supabase/migrations/ | sort | tail`
- [ ] 0.3 Read `webhooks/github/route.ts:193-316` + `workspace-reconcile-on-push.ts:97-128` to confirm the P0-1 push-path shape before editing
- [ ] 0.4 Confirm vitest runner via `package.json`; check `apps/web-platform/bunfig.toml` for `pathIgnorePatterns`
- [ ] 0.5 Reconcile with open #2244 (kb-route-helpers `syncWorkspace`) if still open — adapt the upload call-shape sweep

## Phase 1: Schema + session plumbing — migration 079 (additive, reversible)

- [ ] 1.1 (RED) Test: `workspaces` has 5 repo cols; partial-UNIQUE on `repo_url WHERE NOT NULL`; non-unique index on `github_installation_id` (AC1)
- [ ] 1.2 Write `079_workspace_repo_ownership_schema.sql` with `-- LAWFUL_BASIS:` header (Art-6); add repo cols (mirror 011) + indexes
- [ ] 1.3 Add `current_workspace_id` to `user_session_state` (FK ON DELETE SET NULL) + idempotent backfill from solo workspace
- [ ] 1.4 Extend `runtime_jwt_mint_hook` to inject `app_metadata.current_workspace_id` (symmetric with org_id; omit when NULL)
- [ ] 1.5 Add `set_current_workspace_id(p_workspace_id uuid)` RPC: 28000 + 22004 + 42501 guards; `is_workspace_member` check; explicit `workspaces.organization_id` lookup; set both claims; SECURITY DEFINER + search_path pin + REVOKE/GRANT (precedent 060:175-218)
- [ ] 1.6 Write `079_*.down.sql` (drop RPC, revert hook to 060 body, drop column + indexes + repo cols)
- [ ] 1.7 (GREEN) Migration applies on a dedicated dev Supabase branch; RPC guard tests pass (AC6); OTP path carries new claim (AC8)

## Phase 2: Idempotent solo-only backfill — migration 080

- [ ] 2.1 (RED) Idempotence test (2nd apply → 0 rows) + invited-solo-workspace SKIP test (AC2)
- [ ] 2.2 Write `080_backfill_workspace_repo_from_users.sql`: copy users→workspaces repo cols joined on `w.id=u.id`, guarded by canary owner-row + `COUNT(members)=1`; `WHERE w.repo_url IS NULL`; `GET DIAGNOSTICS`/`RAISE NOTICE` audit
- [ ] 2.3 TS/SQL `normalizeRepoUrl` parity test (CTE fixtures incl. `.git.git`; synthesized fixtures only) (AC9)
- [ ] 2.4 Write `080_*.down.sql`
- [ ] 2.5 (GREEN) Backfill verified against a real dev DB (not mocks); keep `users` cols intact

## Phase 3: Read cutover — TS (workspaces-only reads)

- [ ] 3.1 (RED) Resolver test: 2-workspace member resolves ACTIVE workspace installation_id, never a sibling (AC3)
- [ ] 3.2 Rewrite `resolve-installation-id.ts`: `(userId, workspaceId)`; read `workspaces.github_installation_id`; **delete** the `.ilike("repo_url", ...)` fallback outright
- [ ] 3.3 Run-time repo revalidation in resolver/sync entry path (fail loud on 404/repo-change at agent-run time) — closes wrong-repo hazard (AC7)
- [ ] 3.4 Call-site sweep: thread `workspaceId` through `session-sync.ts`, `current-repo-url.ts` (signature break), `kb-route-helpers.ts`, `agent-runner.ts`, `app/api/repo/status`, `kb/upload`, `kb/sync`, `kb/file/[...path]`, dashboard pages, `use-conversations.ts`; verify via constrained grep = 0 (AC4) + tsc
- [ ] 3.5 (RED) Push-path test: 2 workspaces sharing one installation_id route correctly in BOTH route AND reconcile; `full_name` absent → fail closed (AC5)
- [ ] 3.6 Re-architect push path (P0-1): pass `repository.full_name` into Inngest payload; reconcile resolves `workspaces` by `(installation_id, repo_url)`; rewrite `workspace-reconcile-on-push.ts:124-128` match against workspace row
- [ ] 3.7 Route fail-closed branch when `repository.full_name` absent (P0-2)
- [ ] 3.8 Switcher write-path: call `set_current_workspace_id` → `refreshSession()`; read claim from session JWT not `getUser()`; INLINE confirm + status chain into `org-switcher-container.tsx` (no new confirm component)
- [ ] 3.9 `live-repo-badge.tsx`: poll-on-mount "Working on: owner/repo"; renders J6 default landing
- [ ] 3.10 Workspace-path resolution → active-workspace-relative (`workspace-resolver.ts`, `agent-runner.ts`)
- [ ] 3.11 J5: revocation interstitial + `current_workspace_id` fallback to personal workspace
- [ ] 3.12 Cascade: `anonymise_organization_membership` (or sibling) nulls `workspaces.github_installation_id`; `.down.sql` tested (AC10)

## Phase 4: Legal (parallel; TR8)

- [ ] 4.1 `legal-document-generator`: amend PA-17 across `privacy-policy.md`, `data-protection-disclosure.md` §2.3, `gdpr-policy.md`, `article-30-register.md` for co-member repo/KB access
- [ ] 4.2 Amend attestation (058) copy to cover repo/KB data-access consent
- [ ] 4.3 `legal-compliance-auditor`: cross-document consistency re-audit

## Phase 5: Verification

- [ ] 5.1 RLS test: a member cannot SELECT another workspace's repo columns
- [ ] 5.2 Full suite green; tsc clean (signature breaks caught)
- [ ] 5.3 `/soleur:review` + QA before merge

## Post-merge (operator)

- [ ] P.1 Apply 079 → 080 to prd via `web-platform-release.yml#migrate`; verify columns + backfill counts via Supabase MCP (read-only) (AC13)
- [ ] P.2 Verify GitHub App install `122213433` grants `jikig-ai/soleur` via App-JWT `gh api /installation/repositories`; if absent, install App on `soleur` (AC14, Open Q1)
