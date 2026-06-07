---
title: "Tasks — Fix workspace logo persistence + switcher refresh + relocate to General"
spec: feat-one-shot-workspace-logo-persist
plan: knowledge-base/project/plans/2026-06-07-fix-workspace-logo-persistence-and-section-placement-plan.md
lane: cross-domain
created: 2026-06-07
---

# Tasks

## 1. Preconditions (no code)
- [ ] 1.1 Re-read cited files; confirm `resolveCurrentWorkspaceId` returns `workspaces.id` (not org id) and N2 invariant in dev env.
- [ ] 1.2 Confirm migration 098 applied in dev (Supabase MCP: `workspaces.logo_path` column + `workspace-logos` bucket + `is_workspace_owner` RPC).
- [ ] 1.3 Re-run code-review overlap query against the finalized file list.

## 2. Live reproduction (no code)
- [ ] 2.1 Playwright: upload a logo on the Team page; capture the success toast.
- [ ] 2.2 Supabase MCP: read `workspaces.logo_path` for the active workspace immediately after upload.
- [ ] 2.3 Navigate away and back; capture whether the monogram returns.
- [ ] 2.4 Hit `GET /api/workspace/<id>/logo`; record 302 vs 404/502.
- [ ] 2.5 Record localization (write-side / read-side / env) in PR body. (AC1)

## 3. Persistence fix (RED → GREEN)
- [ ] 3.1 (RED) Add `workspace-logo-route.test.ts` test: 0-rows-matched update must NOT return a bare 200 success. (AC5)
- [ ] 3.2 (GREEN, write-side) Add row-match guard to POST `update` (count/returning/read-back) → 500 + Sentry breadcrumb on 0 rows.
- [ ] 3.3 (GREEN, read-side, only if Phase 1 localizes there) Fix proxy/signed-URL/RLS path.
- [ ] 3.4 Verify AC2 (logo_path non-NULL) + AC3 (survives nav) via repro re-run.

## 4. Switcher live-update fix (H1)
- [ ] 4.1 (RED) `workspace-logo-settings.test.tsx`: success/removal broadcasts a refresh signal.
- [ ] 4.2 (GREEN) Emit a same-tab refresh signal on upload/removal success.
- [ ] 4.3 (GREEN) `useActiveWorkspace` and/or `OrgSwitcherContainer` refetch on the signal.
- [ ] 4.4 Verify AC4 (switcher updates without full reload; reverts on removal).

## 5. Relocate workspace-identity to General
- [ ] 5.1 General `page.tsx`: resolve `workspaceId`, `organizationId`, `organizationName`, `isOwner`, `initialHasLogo`.
- [ ] 5.2 Render `RenameWorkspaceAction` + `WorkspaceLogoSettings` in `settings-content.tsx`.
- [ ] 5.3 Remove both controls from `team/page.tsx` (keep members/roles/invites).
- [ ] 5.4 New test under `test/` (matches vitest `test/**/*.test.tsx`): both controls render on General + owner gate + flag-off reachability. (AC6/AC7/AC8)

## 6. Verification
- [ ] 6.1 `vitest run` for the affected files + `tsc --noEmit` clean. (AC10)
- [ ] 6.2 Confirm AC9 (no client-supplied workspace id; proxy still membership-gates) by reading the diff.
- [ ] 6.3 Playwright full round-trip (upload on General → DB read → nav away/back → logo persists → switcher reflects).
- [ ] 6.4 Post-merge AC11 (env-verify mig 098) only if Phase 1 localized to "mig unapplied".
