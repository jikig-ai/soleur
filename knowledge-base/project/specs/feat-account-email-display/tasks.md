# Tasks: Account Email Display

## Phase 1: Sidebar Email Display

### 1.1 Add user email state to dashboard layout

- [ ] In `apps/web-platform/app/(dashboard)/layout.tsx`, add `useState<string | null>(null)` for `userEmail`
- [ ] Add `useEffect` to fetch session via `createClient().auth.getSession()` on mount (not `getUser()` -- avoids network call, reads from cookie)
- [ ] Extract `session?.user?.email` and set state

### 1.2 Display email in sidebar footer

- [ ] Add email display element above the "Status" link in the sidebar footer section
- [ ] Style with `text-xs text-neutral-500 truncate` and `title` attribute for full email on hover
- [ ] Ensure responsive behavior in both desktop sidebar and mobile drawer

## Phase 2: Settings Page Email Display

### 2.1 Add account info section to settings content

- [ ] In `apps/web-platform/components/settings/settings-content.tsx`, add an "Account" info section before the Project section
- [ ] Display email in a read-only styled field within a card matching existing section styling
- [ ] Reuse existing `userEmail` prop (already passed from server component)
- [ ] Rename existing "Account" section heading (danger zone) to "Danger Zone" to avoid duplicate section names

## Phase 3: Testing

### 3.1 Verify sidebar display

- [ ] Confirm email appears in desktop sidebar footer
- [ ] Confirm email appears in mobile drawer footer
- [ ] Test with long email address for truncation behavior

### 3.2 Verify settings display

- [ ] Confirm email appears in settings Account section
- [ ] Confirm email is read-only (not editable)

### 3.3 Cross-session verification

- [ ] Sign out and sign in with different email
- [ ] Verify sidebar and settings reflect the new email
