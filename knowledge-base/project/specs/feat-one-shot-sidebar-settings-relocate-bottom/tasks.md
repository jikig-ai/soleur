# Tasks — feat-one-shot-sidebar-settings-relocate-bottom

Derived from `knowledge-base/project/plans/2026-05-11-feat-sidebar-settings-relocate-bottom-plan.md`.

## Phase 1 — RED: failing tests

- [x] 1.1 Create `apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx`.
  - [x] 1.1.1 Lift mock scaffold from `apps/web-platform/test/dashboard-layout-signout.test.tsx` (Supabase client, `use-team-names`, `next/navigation`, `fetch /api/admin/check`).
  - [x] 1.1.2 Replace the hardcoded `usePathname` mock with a `let _pathname` + `setPathname(...)` helper so Test 3 can vary the route.
  - [x] 1.1.3 If the project vitest setup does not register `@testing-library/jest-dom` matchers globally, import `"@testing-library/jest-dom/vitest"` at the top of the new file.
- [x] 1.2 Write Test 1 — NAV_ITEMS no longer contains Settings.
- [x] 1.3 Write Test 2 — Footer renders Settings between Status and Sign out (via `compareDocumentPosition` + `& Node.DOCUMENT_POSITION_FOLLOWING`).
- [x] 1.4 Write Test 3 — Active-state class applied + `aria-current="page"` when `pathname.startsWith("/dashboard/settings")`.
- [x] 1.5 Run `bun test apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx` and confirm all 3 fail with the expected reasons.

## Phase 2 — GREEN: apply the relocation

- [x] 2.1 In `apps/web-platform/app/(dashboard)/layout.tsx`:
  - [x] 2.1.1 Add `export` to the `NAV_ITEMS` const.
  - [x] 2.1.2 Remove the `{ href: "/dashboard/settings", label: "Settings", icon: SettingsIcon }` entry from `NAV_ITEMS`.
  - [x] 2.1.3 Compute `const settingsActive = pathname.startsWith("/dashboard/settings");` above the `return` statement.
  - [x] 2.1.4 Insert the new Settings `<Link>` between the Status `<a>` (lines 328-337) and the Sign out `<button>` (lines 338-345), using `aria-current={settingsActive ? "page" : undefined}` and the verified class strings from the plan body.
- [x] 2.2 Run `bun test apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx`. All 3 pass.
- [x] 2.3 Run the wider dashboard-layout test family: `bun test apps/web-platform/test/dashboard-layout-banner.test.tsx apps/web-platform/test/dashboard-layout-signout.test.tsx apps/web-platform/test/dashboard-layout-sidebar-settings.test.tsx`. All-green.
- [x] 2.4 Run `tsc --noEmit` from `apps/web-platform/`. Clean.
- [x] 2.5 Manually verify the `git diff` for `layout.tsx` shows:
  - `export const NAV_ITEMS = [` (was: `const`).
  - Settings entry removed from `NAV_ITEMS`.
  - New `<Link>` inserted between Status and Sign out.
  - The Cmd/Ctrl+B effect block (lines 152-173 before the edit) is byte-identical after the edit.

## Phase 3 — REFACTOR (skip)

- 3.1 Do NOT extract a shared `<SidebarFooterItem>` component in this PR. The three footer items diverge on element type — naïve extraction will bloat with variant props.

## Phase 4 — Ship

- 4.1 Run `/soleur:preflight` (covers User-Brand Impact section presence — already passes, threshold `none`, sensitive-path regex does not match the diff).
- 4.2 Confirm Acceptance Criteria checkboxes (plan body) — all pre-merge items pass; no post-merge items.
- 4.3 Open PR with `Closes` only if a tracking issue exists; otherwise standard PR body.
