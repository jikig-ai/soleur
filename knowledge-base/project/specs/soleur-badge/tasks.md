# Tasks: Soleur-branded leader badge

Source plan: `knowledge-base/project/plans/2026-04-10-feat-soleur-branded-leader-badge-plan.md`

## Phase 1: Setup

- [ ] 1.1 Copy logo asset from `plugins/soleur/docs/images/logo-mark-512.png` to `apps/web-platform/public/icons/soleur-logo-mark.png`

## Phase 2: Core Implementation

- [ ] 2.1 Modify `LeaderBadge` component in `apps/web-platform/components/inbox/conversation-row.tsx` to render an `<img>` tag with the Soleur logo instead of uppercase leader ID text
- [ ] 2.2 Apply brand accent background color `#C9A962` via inline style (Tailwind v4 -- no config file to extend)
- [ ] 2.3 Add appropriate padding so the logo does not touch badge edges
- [ ] 2.4 Add `alt="Soleur"` to the image for accessibility

## Phase 3: Verification

- [ ] 3.1 Run TypeScript type check: `npx tsc --noEmit` in `apps/web-platform/`
- [ ] 3.2 Verify no changes leaked into chat page message bubble avatars (`[conversationId]/page.tsx`)
- [ ] 3.3 Visual QA: verify badge renders at correct dimensions (28px mobile, 32px desktop)
