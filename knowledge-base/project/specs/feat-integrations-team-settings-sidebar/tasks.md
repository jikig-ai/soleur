# Tasks: fix Integrations Settings sidebar (#2227)

## Phase 1: Setup

- [ ] 1.1 Read `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx` to confirm current state.
- [ ] 1.2 Re-read `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` for reference pattern.

## Phase 2: Core Implementation

- [ ] 2.1 Add import: `import { SettingsShell } from "@/components/settings/settings-shell";` to `settings/services/page.tsx`.
- [ ] 2.2 Wrap the returned `<ConnectedServicesContent ... />` element in `<SettingsShell>...</SettingsShell>`.
- [ ] 2.3 Verify no other changes are needed in `ConnectedServicesContent` (does not internally wrap in `SettingsShell`).

## Phase 3: Verification

- [ ] 3.1 Run lint for `apps/web-platform/`.
- [ ] 3.2 Run the existing test suite for `apps/web-platform/` — no regressions.
- [ ] 3.3 Start dev server, navigate to `/dashboard/settings/services`, verify sidebar visible on desktop.
- [ ] 3.4 Click between Settings tabs (General, Team, Integrations, Billing) — all navigate correctly with active-state highlighting.
- [ ] 3.5 Resize to mobile width — bottom tab bar appears; sidebar hidden.
- [ ] 3.6 Capture before/after screenshots for PR body.

## Phase 4: Ship

- [ ] 4.1 `soleur:compound` to capture any learnings.
- [ ] 4.2 Commit with message `fix(settings): wrap Integrations page in SettingsShell (#2227)`.
- [ ] 4.3 Open PR with `Closes #2227` in body, attach screenshots.
- [ ] 4.4 Apply `patch` semver label.
- [ ] 4.5 Monitor CI → merge → verify deploy.
