# Tasks: a11y focus indicators, screen reader announcements, and contrast

## Phase 1: Global Focus Ring + Overflow Wrap

- [ ] 1.1 Add `@layer base` focus-visible ring rule to `apps/web-platform/app/globals.css`
- [ ] 1.2 Add `break-all` to `MessageBubble` `<p>` element in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:326`
- [ ] 1.3 Write test: focus-visible ring appears on keyboard Tab for interactive elements
- [ ] 1.4 Write test: chat messages with long unbroken strings wrap without overflow

## Phase 2: Error Message Screen Reader Announcements

- [ ] 2.1 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/setup-key/page.tsx:84`
- [ ] 2.2 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/signup/page.tsx:84,130`
- [ ] 2.3 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/connect-repo/page.tsx:444`
- [ ] 2.4 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/accept-terms/page.tsx:76`
- [ ] 2.5 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/login/page.tsx:111,157`
- [ ] 2.6 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx:95`
- [ ] 2.7 Add `role="alert"` to error `<p>` in `apps/web-platform/components/auth/oauth-buttons.tsx:99`
- [ ] 2.8 Add `role="alert"` to error `<p>` in `apps/web-platform/components/settings/key-rotation-form.tsx:74`
- [ ] 2.9 Add `role="alert"` to error `<p>` in `apps/web-platform/components/settings/delete-account-dialog.tsx:85`
- [ ] 2.10 Write test: error elements have `role="alert"` attribute

## Phase 3: Contrast Fix

- [ ] 3.1 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (lines 174, 265)
- [ ] 3.2 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (lines 132, 165)
- [ ] 3.3 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/components/chat/at-mention-dropdown.tsx` (line 117)
- [ ] 3.4 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/app/(auth)/connect-repo/page.tsx` (lines 641, 800)
- [ ] 3.5 Replace `placeholder:text-neutral-600` with `placeholder:text-neutral-500` in `apps/web-platform/components/settings/key-rotation-form.tsx` and `delete-account-dialog.tsx`
- [ ] 3.6 Write test: no `text-neutral-600` remaining in text content elements (excluding icons)

## Phase 4: Focus Class Cleanup (optional)

- [ ] 4.1 Convert `focus:outline-none` to `focus-visible:outline-none` in all 10 instances
- [ ] 4.2 Convert `focus:border-neutral-500` to `focus-visible:border-neutral-500` on input elements
- [ ] 4.3 Convert `focus:border-amber-600` and `focus:ring-amber-600` to `focus-visible:` variants in `key-rotation-form.tsx`
- [ ] 4.4 Convert `focus:border-red-700` and `focus:ring-red-700` to `focus-visible:` variants in `delete-account-dialog.tsx`
- [ ] 4.5 Run full test suite to verify no regressions
