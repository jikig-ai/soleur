# Tasks: Account Email Display

## Phase 1: Sidebar Email Display

### 1.1 Add user email state to dashboard layout

- [x] In `apps/web-platform/app/(dashboard)/layout.tsx`, add `useState<string | null>(null)` for `userEmail`
- [x] Add `useEffect` to fetch session via `createClient().auth.getSession()` on mount (not `getUser()` -- avoids network call, reads from cookie)
- [x] Extract `session?.user?.email` and set state

### 1.2 Display email in sidebar footer

- [x] Add email display element above the "Status" link in the sidebar footer section
- [x] Style with `text-xs text-neutral-500 truncate` and `title` attribute for full email on hover
- [x] Ensure responsive behavior in both desktop sidebar and mobile drawer

## Phase 2: Settings Page Email Display

### 2.1 Add account info section to settings content

- [x] In `apps/web-platform/components/settings/settings-content.tsx`, add an "Account" info section before the Project section
- [x] Display email in a read-only styled field within a card matching existing section styling
- [x] Reuse existing `userEmail` prop (already passed from server component)
- [x] Rename existing "Account" section heading (danger zone) to "Danger Zone" to avoid duplicate section names

## Phase 3: Testing

### 3.1 Verify sidebar display

- [x] Confirm email appears in desktop sidebar footer
- [x] Confirm email appears in mobile drawer footer
- [x] Test with long email address for truncation behavior

### 3.2 Verify settings display

- [x] Confirm email appears in settings Account section
- [x] Confirm email is read-only (not editable)

### 3.3 Cross-session verification

- [x] Sign out and sign in with different email
- [x] Verify sidebar and settings reflect the new email
