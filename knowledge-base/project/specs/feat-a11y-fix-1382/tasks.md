# Tasks: a11y focus indicators, screen reader announcements, and contrast

## Implementation (all fixes are independent)

- [ ] 1.1 Add `@layer base` focus-visible ring rule to `apps/web-platform/app/globals.css`
- [ ] 1.2 Add `overflow-wrap: anywhere` to `MessageBubble` `<p>` element in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:326`
- [ ] 1.3 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/setup-key/page.tsx:84`
- [ ] 1.4 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/signup/page.tsx:84,130`
- [ ] 1.5 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/connect-repo/page.tsx:444`
- [ ] 1.6 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/accept-terms/page.tsx:76`
- [ ] 1.7 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(auth)/login/page.tsx:111,157`
- [ ] 1.8 Add `role="alert"` to error `<p>` in `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx:95`
- [ ] 1.9 Add `role="alert"` to error `<p>` in `apps/web-platform/components/auth/oauth-buttons.tsx:99`
- [ ] 1.10 Add `role="alert"` to error `<p>` in `apps/web-platform/components/settings/key-rotation-form.tsx:74`
- [ ] 1.11 Add `role="alert"` to error `<p>` in `apps/web-platform/components/settings/delete-account-dialog.tsx:85`
- [ ] 1.12 Add `role="alert"` to `ErrorCard` container div in `apps/web-platform/components/ui/error-card.tsx:13`
- [ ] 1.13 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (lines 174, 265)
- [ ] 1.14 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (lines 132, 165)
- [ ] 1.15 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/components/chat/at-mention-dropdown.tsx` (line 117)
- [ ] 1.16 Replace `text-neutral-600` with `text-neutral-500` in `apps/web-platform/app/(auth)/connect-repo/page.tsx` (lines 641, 800)
- [ ] 1.17 Replace `placeholder:text-neutral-600` with `placeholder:text-neutral-500` in `apps/web-platform/components/settings/key-rotation-form.tsx` and `delete-account-dialog.tsx`
- [ ] 1.18 Verify contrast ratios against actual Tailwind v4 color hex values

## Tests

- [ ] 2.1 Write unit test: error elements have `role="alert"` attribute
- [ ] 2.2 Write unit test: `ErrorCard` container has `role="alert"`
- [ ] 2.3 Write unit test: hint text elements use `text-neutral-500` (not `text-neutral-600`)
- [ ] 2.4 Browser QA: tab through login/signup pages to verify visible amber focus ring
- [ ] 2.5 Browser QA: verify delete dialog shows red focus ring (not global amber)
- [ ] 2.6 Browser QA: verify mouse clicks do not trigger focus rings
- [ ] 2.7 Browser QA: verify long unbroken URLs wrap in chat messages
