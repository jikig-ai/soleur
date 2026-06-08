---
title: "Tasks — Fix workspace logo persistence + switcher refresh + relocate to General"
spec: feat-one-shot-workspace-logo-persist
plan: knowledge-base/project/plans/2026-06-07-fix-workspace-logo-persistence-and-section-placement-plan.md
lane: cross-domain
created: 2026-06-07
---

# Tasks

## 1. Preconditions (no code)
- [x] 1.1 Re-read cited files; confirmed `resolveCurrentWorkspaceId` reads `user_session_state.current_workspace_id` (→ solo fallback = `user.id`), i.e. a workspace id, never an org id. Write target (upload) and read target (team page, General resolver) BOTH use it → same id.
- [ ] 1.2 Confirm migration 098 applied (deferred to AC11 post-merge env-verify; the row-match guard makes an unapplied-mig env fail loud regardless).
- [x] 1.3 Code-review overlap re-checked against finalized file list (no open `code-review` issues touch these files).

## 2. Localization (code-trace substitute for live repro)
- [x] 2.1–2.5 Localized by code-tracing (valid substitute per /work skill — the failing state is a shared/team workspace in prod, not synthesizable in a solo dev repro). **Conclusion: write-side 0-rows-matched.** Write target == read target == `current_workspace_id`; if that id has no `workspaces` row, `service.from("workspaces").update({logo_path}).eq("id", workspaceId)` matches 0 rows, returns NO error → false "Logo updated." 200 → `logo_path` never set → monogram on nav. The row-match guard (3.2) converts this silent no-op into a loud 500 + `persist-logo-path-zero-rows` breadcrumb, which both stops the false toast AND surfaces the exact prod cause in Sentry. (AC1)

## 3. Persistence fix (RED → GREEN)
- [x] 3.1 (RED) `workspace-logo-route.test.ts`: 0-rows-matched update fails loud (500 + breadcrumb + orphan cleanup), not a bare 200. (AC5)
- [x] 3.2 (GREEN) POST + DELETE persist now use `.update().eq().select("id")` + row-match guard → 500 + distinct Sentry breadcrumb (`persist-logo-path-zero-rows` / `persist-logo-clear-zero-rows`) on 0 rows.
- [x] 3.3 Read-side: N/A — localization is write-side. Proxy path unchanged.
- [x] 3.4 AC2/AC3 enabled: a successful (1-row-matched) persist is now the ONLY 200 path, so a 200 proves `logo_path` is set; the existing proxy + `initialHasLogo` read path then renders post-nav.

## 4. Switcher live-update fix (H1)
- [x] 4.1 (RED) `workspace-logo-settings.test.tsx`: success/removal dispatches `WORKSPACE_LOGO_CHANGED_EVENT`; failure does not.
- [x] 4.2 (GREEN) `WorkspaceLogoSettings` dispatches the event on upload + removal success.
- [x] 4.3 (GREEN) `useActiveWorkspace` (collapsed band) + `OrgSwitcherContainer` (expanded switcher) listen and refetch memberships on the event.
- [x] 4.4 AC4 verified by tests; switcher refetches `list-memberships` (whose `hasLogo` is server-derived) without a full reload.

## 5. Relocate workspace-identity to General
- [x] 5.1 New `server/workspace-identity-resolver.ts` resolves `workspaceId`/`organizationId`/`organizationName`/`isOwner`/`hasLogo` WITHOUT the team flag; General `page.tsx` calls it.
- [x] 5.2 `settings-content.tsx` renders `RenameWorkspaceAction` + `WorkspaceLogoSettings` in a new Workspace section when identity is provided.
- [x] 5.3 Removed both controls (+ logo read + imports) from `team/page.tsx`; members/roles/invites kept.
- [x] 5.4 `workspace-identity-settings-resolver.test.ts` (flag-off reachability AC7 + owner gate AC8) + `settings-content-workspace-identity.test.tsx` (controls render AC6/AC8).

## 6. Verification
- [x] 6.1 Affected vitest files green (34 + related 56) + `tsc --noEmit` clean. (AC10)
- [x] 6.2 AC9: write path still resolves the workspace server-side (`resolveCurrentWorkspaceId`); no client-supplied id added; proxy still `is_workspace_member`-gated. Confirmed by diff.
- [ ] 6.3 Playwright full round-trip → /soleur:qa phase.
- [ ] 6.4 Post-merge AC11 (env-verify mig 098).
