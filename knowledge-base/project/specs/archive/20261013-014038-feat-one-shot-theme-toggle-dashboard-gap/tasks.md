# Tasks — feat-one-shot-theme-toggle-dashboard-gap

Plan: `knowledge-base/project/plans/2026-05-06-fix-theme-toggle-dashboard-gap-plan.md`

## Phase 1 — Implementation

- [ ] 1.1 Edit `apps/web-platform/app/(dashboard)/layout.tsx` line 282: add `pt-3` to the `<nav>` className so the first nav item clears the theme-toggle divider with 12px symmetric rhythm matching the footer's `p-3` pattern.

## Phase 2 — Verification

- [ ] 2.1 Run dev server, visually confirm gap in expanded sidebar (light + dark themes).
- [ ] 2.2 Toggle to collapsed sidebar, confirm gap holds.
- [ ] 2.3 Open mobile drawer, confirm gap holds.
- [ ] 2.4 Run affected tests:
  - `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx`
  - `apps/web-platform/test/dashboard-layout-drawer-rail.test.tsx`
  - `apps/web-platform/test/components/theme-toggle.test.tsx`
  - `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx`
- [ ] 2.5 `tsc --noEmit` clean.

## Phase 3 — Ship

- [ ] 3.1 Commit and push.
- [ ] 3.2 Open PR with `Ref #3315` (theme-toggle relocation follow-up).
- [ ] 3.3 Run `/soleur:ship`.
