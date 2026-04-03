# Tasks: Settings Project Setup

Source plan: `knowledge-base/project/plans/2026-04-03-fix-settings-project-setup-plan.md`

## Phase 1: Setup

- [x] 1.1 Read existing settings page files (`page.tsx`, `settings-content.tsx`)
- [x] 1.2 Read `connect-repo/page.tsx` to understand current redirect behavior

## Phase 2: Core Implementation

- [x] 2.1 Write failing tests for `ProjectSetupCard` (all four states: not_connected, ready, error, cloning)
- [x] 2.2 Write failing test for `SettingsContent` rendering the Project section
- [x] 2.3 Create `project-setup-card.tsx` client component with four visual states
- [x] 2.4 Update `settings-content.tsx` to accept repo props and render `ProjectSetupCard`
- [x] 2.5 Update `settings/page.tsx` to query `repo_url`, `repo_status`, `repo_last_synced_at` from users table
- [x] 2.6 Add `safeReturnTo()` validation helper (allowlist `/dashboard` prefix, block `//` and `\`)
- [x] 2.7 Update `connect-repo/page.tsx`: read `return_to` from query params, persist in `sessionStorage` before GitHub redirect, read back in `handleOpenDashboard` and `handleSkip`
- [x] 2.8 Verify all tests pass

## Phase 3: Testing

- [x] 3.1 Run full settings page test suite
- [x] 3.2 Run TypeScript build check (`npx tsc --noEmit`)
- [ ] 3.3 Visual QA via dev server or Playwright screenshots
