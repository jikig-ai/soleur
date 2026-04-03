---
title: "fix: Add project setup to settings page for users who skipped onboarding"
type: fix
date: 2026-04-03
---

# fix: Add project setup to settings page for users who skipped onboarding

## Overview

Users who skip the project setup step during onboarding see the message "you can connect a project later from Settings" (`apps/web-platform/app/(auth)/connect-repo/page.tsx:334`). However, the settings page (`apps/web-platform/components/settings/settings-content.tsx`) only contains API Key and Account sections -- there is no project creation or connection functionality. This is a broken promise in the onboarding flow.

## Problem Statement

The `connect-repo` onboarding page offers a "Skip this step" link with text saying users can set up a project later from Settings. When a user who skipped onboarding navigates to Settings, they find no way to create or connect a project. The only way to trigger project setup is to revisit `/connect-repo` directly, which is not discoverable from the dashboard.

## Proposed Solution

Add a "Project" section to the settings page that:

1. **Shows current project status** when a project is already connected (repo name, last synced, status).
2. **Provides a "Set Up Project" CTA** when no project is connected, linking the user to the existing `/connect-repo` onboarding flow.

This approach reuses the existing onboarding flow entirely -- no need to duplicate the multi-step state machine (GitHub App install, repo selection/creation, workspace provisioning) inside settings. The settings page becomes an entry point to the existing flow.

### Why not embed the full flow in settings?

The `connect-repo` page has a 9-state state machine handling GitHub OAuth redirects, installation callbacks, polling, error recovery, and repo creation. Duplicating this in settings would create a maintenance burden with no user benefit. The onboarding flow already handles all edge cases. A simple redirect with a return URL is sufficient.

## Technical Approach

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` | Fetch repo status from DB, pass to `SettingsContent` |
| `apps/web-platform/components/settings/settings-content.tsx` | Add Project section above API Key section |
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Read `return_to` query param; use it in `handleOpenDashboard` and `handleSkip` instead of hardcoded `/dashboard` |

### Files to create

| File | Purpose |
|------|---------|
| `apps/web-platform/components/settings/project-setup-card.tsx` | Client component for the Project section |

### Implementation details

#### 1. Settings page server component (`page.tsx`)

Query the user's `repo_status`, `repo_url`, and `repo_last_synced_at` from the `users` table (columns already exist per migration `011_repo_connection.sql`). Pass these as props to `SettingsContent`.

```typescript
// Additional query in settings/page.tsx
const { data: repoData } = await service
  .from("users")
  .select("repo_url, repo_status, repo_last_synced_at")
  .eq("id", user.id)
  .single();
```

#### 2. SettingsContent component

Add a new `ProjectSetupCard` component rendered as the first section. Accept new props:

- `repoUrl: string | null`
- `repoStatus: string` (from `repo_status` column: `not_connected`, `cloning`, `ready`, `error`)
- `repoLastSyncedAt: string | null`

#### 3. ProjectSetupCard component

Two visual states:

**State A: No project connected** (`repoStatus === "not_connected"`)

- Heading: "Project"
- Description: "Connect a GitHub project so your AI team has full context on your codebase."
- CTA button: "Set Up Project" linking to `/connect-repo?return_to=/dashboard/settings`
- Uses same card styling as existing settings sections (`rounded-xl border border-neutral-800 bg-neutral-900/50 p-6`)

**State B: Project connected** (`repoStatus === "ready"`)

- Heading: "Project"
- Shows repo name extracted from URL (e.g., `owner/repo`)
- Shows last synced date
- Shows status badge ("Connected" in green)

**State C: Error state** (`repoStatus === "error"`)

- Shows error message with "Retry Setup" button linking to `/connect-repo?return_to=/dashboard/settings`

**State D: Cloning in progress** (`repoStatus === "cloning"`)

- Shows "Setting up..." with a spinner
- Note: This state is rare in settings since cloning happens during onboarding, but handle gracefully

## Acceptance Criteria

- [ ] Settings page shows a "Project" section before the API Key section
- [ ] When no project is connected, the section shows a "Set Up Project" button
- [ ] Clicking "Set Up Project" navigates to `/connect-repo`
- [ ] When a project is connected, the section shows the repo name and last synced date
- [ ] When repo status is "error", the section shows an error state with retry option
- [ ] After completing project setup from settings, user returns to settings (not dashboard)
- [ ] Existing settings page tests still pass
- [ ] New tests cover all four visual states of `ProjectSetupCard`

## Test Scenarios

- Given a user with `repo_status = "not_connected"`, when they visit Settings, then they see a "Set Up Project" button
- Given a user with `repo_status = "ready"` and `repo_url = "https://github.com/owner/repo"`, when they visit Settings, then they see "owner/repo" with a "Connected" status
- Given a user with `repo_status = "error"`, when they visit Settings, then they see an error message with a retry button
- Given a user with `repo_status = "cloning"`, when they visit Settings, then they see a "Setting up..." message
- Given a user clicks "Set Up Project", when they complete the connect-repo flow, then returning to Settings shows the connected project

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

This modifies an existing settings page by adding a new section. The section reuses existing design patterns (card layout, button styles) from the settings page and links to the existing onboarding flow. No new user flows or pages are created.

## References

- Onboarding flow: `apps/web-platform/app/(auth)/connect-repo/page.tsx`
- Settings page: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`
- Settings content: `apps/web-platform/components/settings/settings-content.tsx`
- Repo status API: `apps/web-platform/app/api/repo/status/route.ts`
- DB migration: `apps/web-platform/supabase/migrations/011_repo_connection.sql`
- Repo connection learning: `knowledge-base/project/learnings/2026-03-29-repo-connection-implementation.md`
