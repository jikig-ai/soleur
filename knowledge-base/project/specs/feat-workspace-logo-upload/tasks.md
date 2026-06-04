---
feature: workspace-logo-upload
issue: 4916
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-04-feat-workspace-logo-upload-plan.md
---

# Tasks: Workspace Logo Upload

Derived from the finalized (post-review) plan. RED→GREEN→REFACTOR per task. Vitest (`test/**`, not co-located).

## Phase 0 — Preconditions
- [x] 0.1 Locate the Workspace settings pane (grep `rename-workspace-action.tsx` mount) — `app/(dashboard)/dashboard/settings/team/page.tsx`; mounts `RenameWorkspaceAction` with `isOwner`; resolver `resolveTeamMembershipPageData` returns role/workspaceId.
- [x] 0.2 `@supabase/supabase-js` 2.99.2 (createSignedUrl/createSignedUrls present); sharp 0.34.5 (failOn/limitInputPixels); migrations 095–097 have NO top-level BEGIN/COMMIT (runner wraps `--single-transaction`); 098 collision-free on origin/main; next Art-30 PA = 26.
- [x] 0.3 `account-delete.ts` sole-owned teardown = `deleteWorkspace(userId)` (L169-179; `userId === workspaces.id` per mig 053 N2); shared-member removal is in `remove_workspace_member` RPC, NOT account-delete. Wire `purgeWorkspaceLogoObjects` beside `deleteWorkspace`.

## Phase 1 — Migration 098 (data + storage + RLS) ✅ applied+verified DEV (32/32 live)
- [x] 1.1 `ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS logo_path text;` + `-- LAWFUL_BASIS:` annotation (GDPR-Art-6, PA-26).
- [x] 1.2 `INSERT INTO storage.buckets` `workspace-logos` (private, 1048576, `['image/webp']`).
- [x] 1.3 `CREATE FUNCTION is_workspace_owner` — DEFINER, `search_path=public,pg_temp`, NULL-args guard, parameterized EXISTS, REVOKE all 4 + GRANT authenticated.
- [x] 1.4 `storage.objects` RLS: SELECT(member, USING) + INSERT(owner, WITH CHECK) + UPDATE(owner, USING **and** WITH CHECK) + DELETE(owner, USING); regex `^[0-9a-f-]{36}$` guard before `::uuid`; no `FOR ALL`, no `COMMENT ON POLICY`.
- [x] 1.5 `.down.sql` reverse order: policies → function → column. **Storage bucket/objects teardown is Storage-API-only — Supabase `protect_delete` trigger blocks direct `DELETE FROM storage.{objects,buckets}` (verified live; 019/042 precedent ship no SQL bucket teardown).** Plan's "DELETE objects→bucket" falsified at verify-time; corrected.
- [x] 1.6 Migration shape test (offline lint, mirrors 068) GREEN (24); **live DEV behavioral verification (migration-checklist.md): owner-write, member-read, non-member-deny-read, non-owner-deny-overwrite, cross-tenant-move-deny (UPDATE WITH CHECK), malformed-path-clean-deny — all PASS.** (AC1/AC2/AC3)

## Phase 2 — Upload/remove route (`api/workspace/logo/route.ts`)
- [ ] 2.1 POST: CSRF/origin → rate-limit → content-length 413 → auth → server-resolve active workspace → `is_workspace_owner` 403 → formData.
- [ ] 2.2 `sharp(buf,{limitInputPixels:16_000_000,failOn:'error'})`; assert `meta.format∈{png,webp}` from decoded metadata; reject non-square 422; flatten APNG; re-encode → WebP. (AC4)
- [ ] 2.3 Assert path `workspace_id` == resolved; upload `<wid>/logo.webp` (upsert) → `UPDATE logo_path`; orphan-cleanup + `logo-orphan-cleanup-failed` breadcrumb on DB-fail. (AC5/AC7b)
- [ ] 2.4 DELETE: owner-gate → `logo_path=NULL` first → remove object (+ cleanup breadcrumb on fail).
- [ ] 2.5 Sentry on all arms; HTTP-only exports. (AC6b rate-limit test)

## Phase 3 — Read path (stable proxy route)
- [ ] 3.1 `GET api/workspace/[id]/logo`: auth → `is_workspace_member` 403 → read logo_path 404 → `createSignedUrl(…,300)` → 302 + `Cache-Control: private, max-age=300` + `nosniff`; `reportSilentFallback`→502 on mint fail. (AC6)
- [ ] 3.2 `org-memberships-resolver.ts`: add `logo_path` to select, expose `hasLogo` (no mint, no storage import). (AC6)

## Phase 4 — Render
- [ ] 4.1 `WorkspaceIdentityTile`: `workspaceId`+`hasLogo` props; `<img src=/api/workspace/<id>/logo>` + `onError`→monogram (Sentry on error). (AC7)
- [ ] 4.2 Thread through `org-switcher-container`→`org-switcher`; extend `useActiveWorkspaceName`→`useActiveWorkspace` ({name,workspaceId,hasLogo}); thread into context band. (AC7c stable-src)

## Phase 5 — Settings UI
- [ ] 5.1 `workspace-logo-settings.tsx` (file input PNG/WebP, MAX 1MB, square check, FormData POST, optimistic preview, Remove→DELETE). 4-state union. (cq-union-widening)
- [ ] 5.2 Non-owner gating: load viewer `role`; disabled-with-tooltip for non-owners. (AC8b)
- [ ] 5.3 Reject copy names "SVG and JPG aren't accepted." Wire wireframes 25–27.

## Phase 6 — Legal lockstep (CLO attests at PR)
- [ ] 6.1 Privacy Policy + DPD + GDPR-policy/Art-30 (retention=workspace lifetime, next free PA#) + 1-line AUP. (AC9)
- [ ] 6.2 `purgeWorkspaceLogoObjects(workspaceId)` helper in `server/workspace.ts`; call from sole-owned-workspace teardown in `account-delete.ts` (NOT shared-member-removal). DSAR export excluded (Art. 15(4), documented).

## Phase 7 — Verify
- [ ] 7.1 AC5b: assert no client INSERT/UPDATE/DELETE policy on `public.workspaces` (column-takeover DB-enforced).
- [ ] 7.2 AC8: `csp.test.ts` signed-URL host ∈ img-src; no CSP edit shipped.
- [ ] 7.3 `tsc --noEmit` clean; full vitest suite; CPO sign-off (requires_cpo_signoff) before merge.
