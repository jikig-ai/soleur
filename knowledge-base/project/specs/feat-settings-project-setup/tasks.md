# Tasks: Settings Project Setup

Source plan: `knowledge-base/project/plans/2026-04-03-fix-settings-project-setup-plan.md`

## Phase 1: Setup

- [ ] 1.1 Read existing settings page files (`page.tsx`, `settings-content.tsx`)
- [ ] 1.2 Read `connect-repo/page.tsx` to understand current redirect behavior

## Phase 2: Core Implementation

- [ ] 2.1 Write failing tests for `ProjectSetupCard` (all four states: not_connected, ready, error, cloning)
- [ ] 2.2 Write failing test for `SettingsContent` rendering the Project section
- [ ] 2.3 Create `project-setup-card.tsx` client component with four visual states
- [ ] 2.4 Update `settings-content.tsx` to accept repo props and render `ProjectSetupCard`
- [ ] 2.5 Update `settings/page.tsx` to query `repo_url`, `repo_status`, `repo_last_synced_at` from users table
- [ ] 2.6 Update `connect-repo/page.tsx` to read `return_to` query param and use it in `handleOpenDashboard` and `handleSkip`
- [ ] 2.7 Verify all tests pass

## Phase 3: Testing

- [ ] 3.1 Run full settings page test suite
- [ ] 3.2 Run TypeScript build check (`npx tsc --noEmit`)
- [ ] 3.3 Visual QA via dev server or Playwright screenshots
