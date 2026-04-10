---
title: "feat: Display account email in dashboard sidebar and settings"
type: feat
date: 2026-04-10
---

# feat: Display account email in dashboard sidebar and settings

## Overview

Users with multiple Soleur accounts (different email addresses) have no way to identify which account they are currently signed into. The email address is only used internally for the delete-account confirmation dialog but is never shown in the UI. This makes multi-account usage error-prone.

## Problem Statement / Motivation

Issue #1891 reports that there is no indication anywhere of the user's email address attached to the account. For users using different email addresses with different accounts, this is problematic -- they cannot tell which account is active without attempting to delete it (the only place the email appears).

The dashboard layout sidebar shows "Soleur" branding, navigation links, and a sign-out button, but no user identity. The settings page has an "Account" section but it only contains the danger zone (delete account). The Command Center header shows a generic user icon with no identifying information.

## Proposed Solution

Display the authenticated user's email address in two locations:

1. **Sidebar footer** (dashboard layout) -- Show the email above the sign-out button in the sidebar, giving persistent visibility across all dashboard pages
2. **Settings page** -- Add an "Account" info section at the top of the settings page showing the email, replacing the current pattern where "Account" only means "delete account"

### Sidebar Implementation

The sidebar footer currently contains "Status" link and "Sign out" button. Add the user's email above these items, truncated with ellipsis for long addresses.

The dashboard layout (`app/(dashboard)/layout.tsx`) is a client component that already creates a Supabase client for sign-out. It can fetch the user session to get the email.

### Settings Page Implementation

The settings page (`app/(dashboard)/dashboard/settings/page.tsx`) already passes `userEmail` to `SettingsContent`. Add an "Account" info section at the top of the settings content (before the Project section) that displays the email in a read-only field.

## Technical Considerations

### Data Source

The email is available from `supabase.auth.getUser()` which returns `user.email`. This is already called in:

- `app/(dashboard)/dashboard/settings/page.tsx` (server component) -- passes to `SettingsContent`
- `app/(dashboard)/dashboard/billing/page.tsx` (client component) -- fetches user but does not display email

For the sidebar (client component), add a `useEffect` to fetch the user session via `supabase.auth.getUser()` on mount.

### Performance

- The sidebar email fetch is a local cookie-based auth check, not a network round trip to Supabase -- minimal performance impact
- No new database queries needed; `auth.getUser()` reads from the session

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(dashboard)/layout.tsx` | Add `userEmail` state, fetch from Supabase auth, display in sidebar footer |
| `apps/web-platform/components/settings/settings-content.tsx` | Add account info section showing email at top of settings |

### No Database Changes

The `public.users` table already has an `email` column (from migration `001_initial_schema.sql`), and `auth.users` has email natively. No schema changes needed.

## Acceptance Criteria

- [ ] User's email address is visible in the dashboard sidebar footer, above the status link and sign-out button
- [ ] User's email address is displayed in the settings page in a clearly labeled "Account" section
- [ ] Long email addresses are truncated with ellipsis in the sidebar (CSS `text-overflow: ellipsis`)
- [ ] Email displays correctly on mobile (drawer sidebar) and desktop
- [ ] Email is not editable (read-only display)
- [ ] No layout shift or loading flash when email loads in the sidebar

## Domain Review

**Domains relevant:** Product, Support

### Support

**Status:** reviewed
**Assessment:** Displaying account email directly addresses the multi-account confusion reported in #1891. Users managing multiple accounts (common for freelancers and agencies) will be able to identify their active account at a glance. No support documentation changes needed -- the feature is self-explanatory.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

This modifies existing UI (sidebar footer and settings page) with minimal design risk. The pattern of showing user identity in a sidebar footer is well-established in SaaS applications. No new user flows or navigation patterns are introduced.

## Test Scenarios

- Given a signed-in user, when viewing any dashboard page, then the sidebar footer displays their email address
- Given a signed-in user with a long email address (40+ characters), when viewing the sidebar, then the email is truncated with ellipsis and a `title` attribute shows the full email on hover
- Given a signed-in user, when viewing the settings page, then the Account section at the top shows their email address
- Given a signed-in user on mobile, when opening the sidebar drawer, then the email is visible in the drawer footer
- Given a user who signs out and signs in with a different email, then the sidebar and settings show the new email

## Context

- The `DeleteAccountDialog` component already receives and uses `userEmail` for confirmation -- this pattern can be followed
- The dashboard layout is a client component using `createClient()` from `@/lib/supabase/client`
- The settings page is a server component that already calls `supabase.auth.getUser()`

## References

- Related issue: #1891
- Dashboard layout: `apps/web-platform/app/(dashboard)/layout.tsx`
- Settings page: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`
- Settings content: `apps/web-platform/components/settings/settings-content.tsx`
- Supabase client: `apps/web-platform/lib/supabase/client.ts`
- Initial schema: `apps/web-platform/supabase/migrations/001_initial_schema.sql`
