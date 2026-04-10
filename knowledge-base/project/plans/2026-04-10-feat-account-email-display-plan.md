---
title: "feat: Display account email in dashboard sidebar and settings"
type: feat
date: 2026-04-10
---

# feat: Display account email in dashboard sidebar and settings

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 4 (Technical Considerations, Proposed Solution, Acceptance Criteria, Test Scenarios)
**Research sources:** Supabase SSR docs (Context7), existing codebase patterns (use-onboarding.ts, use-conversations.ts, ws-client.ts), project learnings

### Key Improvements

1. **Use `getSession()` instead of `getUser()` for sidebar** -- `getUser()` makes a network request to the Supabase Auth server on every call; `getSession()` reads from cookies (no network round trip). For displaying an email in the UI (not a security-sensitive operation), `getSession()` is sufficient and avoids an extra HTTP call on every page load.
2. **Skeleton placeholder for email** -- Use a small animated placeholder (matching existing loading patterns in the codebase) while the session loads, preventing layout shift.
3. **`onAuthStateChange` consideration** -- The codebase currently has zero `onAuthStateChange` listeners; each component fetches auth independently. Adding one in the layout would be overengineering for this feature. Keep the per-component pattern consistent.

### New Considerations Discovered

- The Supabase docs explicitly warn: "You should never trust the unencoded session data if you're writing server code." However, this is client-side display-only code, so `getSession()` is safe here. The middleware already calls `getUser()` for route protection.
- The `ws-client.ts` already uses `getSession()` for the same reason (needs the token, not server-verified user data) -- establishes precedent in the codebase.

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

#### Research Insights

**Implementation pattern** -- Add a `userEmail` state variable and a `useEffect` that calls `supabase.auth.getSession()` on mount:

```typescript
const [userEmail, setUserEmail] = useState<string | null>(null);

useEffect(() => {
  const supabase = createClient();
  supabase.auth.getSession().then(({ data: { session } }) => {
    setUserEmail(session?.user?.email ?? null);
  });
}, []);
```

**Why `getSession()` over `getUser()`:** The Supabase docs state that `getSession()` reads from the local cookie store (no network request), while `getUser()` makes a round trip to the Supabase Auth server. Since:

- The middleware already verifies auth via `getUser()` on every request
- This is display-only (no security decision depends on this value)
- The sidebar renders on every dashboard page

Using `getSession()` avoids an unnecessary network call per page navigation. This matches the pattern in `lib/ws-client.ts:91` which uses `getSession()` for the same reason.

**Sidebar footer markup** -- Insert the email display in the footer `div` (line 140 of layout.tsx), before the Status link:

```tsx
{userEmail && (
  <p
    className="truncate px-3 py-1 text-xs text-neutral-500"
    title={userEmail}
  >
    {userEmail}
  </p>
)}
```

**Edge cases:**

- If `getSession()` returns null (expired cookie, race condition on first load), `userEmail` stays null and the email line is not rendered -- no layout shift, no error
- The `truncate` utility class applies `overflow: hidden; text-overflow: ellipsis; white-space: nowrap` -- handles long emails without breaking the sidebar width

### Settings Page Implementation

The settings page (`app/(dashboard)/dashboard/settings/page.tsx`) already passes `userEmail` to `SettingsContent`. Add an "Account" info section at the top of the settings content (before the Project section) that displays the email in a read-only field.

#### Research Insights

**Implementation pattern** -- Add a new section at the top of `SettingsContent`, before the Project section. Use the same card styling as other sections:

```tsx
{/* Account Section */}
<section>
  <h2 className="mb-4 text-lg font-semibold text-white">Account</h2>
  <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
    <div className="space-y-1">
      <p className="text-sm text-neutral-400">Email</p>
      <p className="text-sm font-medium text-white">{userEmail}</p>
    </div>
  </div>
</section>
```

**Reorganization** -- Move the existing "Account" section (danger zone with delete button) into the new Account section card, or keep it separate as "Danger Zone". The cleaner approach: rename the existing danger-zone section header from "Account" to "Danger Zone" and put the new email-display section under "Account" at the top. This prevents two sections both called "Account".

## Technical Considerations

### Data Source

The email is available from two Supabase auth methods:

- **`supabase.auth.getSession()`** -- Reads session from cookies (Next.js SSR) or localStorage (SPA). No network request. Returns `session.user.email`. Suitable for display-only client components.
- **`supabase.auth.getUser()`** -- Makes a network request to the Supabase Auth server to verify the JWT. Returns verified `user.email`. Required for server-side security decisions.

Existing usage in the codebase:

- `app/(dashboard)/dashboard/settings/page.tsx` (server component) -- uses `getUser()`, passes email to `SettingsContent`
- `app/(dashboard)/dashboard/billing/page.tsx` (client component) -- uses `getUser()` but does not display email
- `lib/ws-client.ts` (client) -- uses `getSession()` to get the access token without a network call
- `hooks/use-onboarding.ts` (client) -- uses `getUser()` but also needs the user ID for database writes

For the sidebar (client component, display-only), use `getSession()` to avoid an additional network request on every page load.

### Performance

- **Sidebar:** `getSession()` reads from the cookie store -- zero network overhead. This is the same approach used by `ws-client.ts`.
- **Settings page:** Already uses server-side `getUser()` in the page component -- no additional fetch needed. The `userEmail` prop is already passed to `SettingsContent`.
- No new database queries needed.
- No additional Supabase auth server round trips introduced.

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(dashboard)/layout.tsx` | Add `userEmail` state, fetch from Supabase auth, display in sidebar footer |
| `apps/web-platform/components/settings/settings-content.tsx` | Add account info section showing email at top of settings |

### No Database Changes

The `public.users` table already has an `email` column (from migration `001_initial_schema.sql`), and `auth.users` has email natively. No schema changes needed.

## Acceptance Criteria

- [ ] User's email address is visible in the dashboard sidebar footer, above the status link and sign-out button
- [ ] User's email address is displayed in the settings page in a clearly labeled "Account" section at the top (before Project section)
- [ ] The existing "Account" heading in settings (danger zone) is renamed to "Danger Zone" to avoid duplicate section names
- [ ] Long email addresses are truncated with ellipsis in the sidebar (CSS `truncate` utility) with full email in `title` attribute for hover
- [ ] Email displays correctly on mobile (drawer sidebar) and desktop
- [ ] Email is not editable (read-only display)
- [ ] No layout shift when email loads -- conditional rendering (`{userEmail && ...}`) rather than a placeholder, since `getSession()` resolves from cookies nearly instantly
- [ ] Sidebar uses `getSession()` (not `getUser()`) to avoid an unnecessary network request per page load

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

### Sidebar Email Display

- Given a signed-in user, when viewing any dashboard page, then the sidebar footer displays their email address above the Status link
- Given a signed-in user with a long email address (e.g., `very.long.email.address.for.testing@extremely-long-domain-name.example.com`), when viewing the sidebar, then the email is truncated with ellipsis and a `title` attribute shows the full email on hover
- Given a signed-in user on mobile, when opening the sidebar drawer, then the email is visible in the drawer footer
- Given a signed-in user, when the page loads, then no layout shift occurs in the sidebar footer (email renders without visible flicker)

### Settings Email Display

- Given a signed-in user, when viewing the settings page, then the "Account" section at the top shows their email address
- Given a signed-in user, when viewing the settings page, then the delete-account section is labeled "Danger Zone" (not "Account")

### Session Handling

- Given a user who signs out and signs in with a different email, then the sidebar and settings show the new email
- Given an expired session (edge case), when the sidebar attempts to read the session, then no error is thrown and the email line is simply not rendered

### Browser: Visual Verification

- **Browser:** Navigate to `/dashboard`, verify email appears in the left sidebar footer area
- **Browser:** Navigate to `/dashboard/settings`, verify email appears in the Account section at the top of the page
- **Browser:** On mobile viewport (375px wide), open the sidebar drawer, verify email is visible and does not overflow

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
