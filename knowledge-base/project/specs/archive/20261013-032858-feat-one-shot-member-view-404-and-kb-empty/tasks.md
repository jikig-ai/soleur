---
feature: feat-one-shot-member-view-404-and-kb-empty
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-01-fix-member-view-404-and-kb-empty-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks: post-invite member-view 404 + empty Knowledge Base

Derived from `2026-06-01-fix-member-view-404-and-kb-empty-plan.md`. Implement in order;
phases are dependency-ordered (contract/resolution before consumers).

## Phase 0 — Reproduce & resolve open questions (no code)

- [x] 0.1 Playwright repro: member of a shared workspace switches to it → capture the
  landing 404 element + KB `NoProjectState`; capture network (`/api/kb/tree` = 404,
  `/api/workspace/active-repo` = repo). Pin symptom-1 hypothesis (a) bare `/dashboard/chat`
  404 vs (b) solo-scoped landing.
- [x] 0.2 Resolve Q1: read owner via `organizations.owner_user_id`; decide readiness source
  (owner `users.workspace_status` vs fs existence).
- [x] 0.3 Resolve Q2: read `resolve_workspace_installation_id` (mig 079) signature; decide
  whether KB sync ships in this PR or a follow-up issue.
- [x] 0.4 Precedent diff: `git show` `active-repo/route.ts` as the canonical resolution.
- [x] 0.5 Run `/soleur:gdpr-gate` against the plan + intended route diffs.
- [x] 0.6 Re-run `gh issue list --label code-review --state open` to confirm overlap dispositions.

## Phase 1 — RED

- [x] 1.1 Create `apps/web-platform/test/server/kb-active-workspace-scoping.test.ts`
  (path matches vitest `test/**/*.test.ts`; NOT bun test). Cases: member+claim→owner dir;
  null claim→solo; sibling-claim-without-membership→solo (never sibling); owner unchanged.
  Run: `./node_modules/.bin/vitest run test/server/kb-active-workspace-scoping.test.ts`
  (expect RED).

## Phase 2 — GREEN: KB read path (active-workspace-aware)

- [x] 2.1 `app/api/kb/tree/route.ts` — resolve `activeWsId = resolveCurrentWorkspaceId(...)`;
  fs root `path.join(workspacePathForWorkspaceId(activeWsId), "knowledge-base")`; gate on
  `workspaces.repo_status` + readiness (Q1). Preserve 503/404/200 status contract.
- [x] 2.2 `app/api/kb/content/[...path]/route.ts` — same (both handlers).
- [x] 2.3 `app/api/kb/file/[...path]/route.ts` — same (both read sites).
- [x] 2.4 `app/api/kb/search/route.ts` — same.
- [x] 2.5 `server/kb-route-helpers.ts` — make `authenticateAndResolveKbPath` +
  `resolveUserKbRoot` active-workspace-aware (shared locus).
- [x] 2.6 AC2 grep gate: `git grep -n 'from("users")' apps/web-platform/app/api/kb/` →
  zero caller-id-scoped `workspace_path`/`repo_status` reads (or each annotated solo-scoped).

## Phase 3 — GREEN: dashboard landing

- [x] 3.1 `app/(dashboard)/dashboard/page.tsx` — repo-disconnected hint (lines 217-243) reads
  `/api/workspace/active-repo`, not `users.repo_url` for `auth.user.id`. Reconcile the
  KB-tree-404 fall-through (line 153-155) so a connected member isn't routed to first-run/solo.
- [x] 3.2 (conditional on Phase 0 hypothesis (a)) add `app/(dashboard)/dashboard/chat/page.tsx`
  redirect stub so bare `/dashboard/chat` does not 404. Re-confirm UX tier if added.

## Phase 4 — (conditional) KB sync

- [x] 4.1 Per Q2: **DEFERRED** — write/sync paths cross the `github_installation_id`
  credential boundary (CLO guardrail). Filed follow-up issue #4755; the reported VIEW
  symptoms are fully resolved by the read-path + accept-flow fix without it.

## Phase 5 — Verify

- [x] 5.1 vitest green: `kb-active-workspace-scoping.test.ts` + existing kb-route-helpers tests.
- [x] 5.2 Playwright: member lands on a valid page (no 404), sees the shared KB tree, opens a
  file. Screenshot for PR body (AC5).
- [x] 5.3 Owner regression (AC6) + solo regression (AC7) — unchanged behavior.
- [x] 5.4 AC8: `NoApiKeyBanner` joiner branch still renders; no edits to BYOK key-resolution.
- [x] 5.5 AC9: `git diff --stat apps/web-platform/supabase/migrations/` empty (no migration).
- [x] 5.6 Write learning at `knowledge-base/project/learnings/bug-fixes/<topic>.md`
  (date at write-time).
