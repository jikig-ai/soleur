# Tasks: Soleur-branded leader badge

Source plan: `knowledge-base/project/plans/2026-04-10-feat-soleur-branded-leader-badge-plan.md`

## Phase 1: Setup

- [ ] 1.1 Resize logo from 512px to 64px using Pillow and copy to `apps/web-platform/public/icons/soleur-logo-mark.png`
  - Command: `python3 -c "from PIL import Image; img = Image.open('plugins/soleur/docs/images/logo-mark-512.png'); img.resize((64, 64), Image.LANCZOS).save('apps/web-platform/public/icons/soleur-logo-mark.png')"`

## Phase 2: Core Implementation

- [ ] 2.1 Modify `LeaderBadge` in `apps/web-platform/components/inbox/conversation-row.tsx` to render `<img>` with `src="/icons/soleur-logo-mark.png"` and `object-fit: cover` with `rounded-md`
- [ ] 2.2 No background color needed -- logo has built-in dark `#0A0A0A` background with gold accents (remove any bg color class)
- [ ] 2.3 Add `aria-label` to badge element combining "Soleur" with leader ID; set `alt=""` on image (decorative)
- [ ] 2.4 Remove `LEADER_BG_COLORS` import from conversation-row.tsx (dead import after change)
- [ ] 2.5 Add `width` and `height` attributes to `<img>` to prevent layout shift on load failure

## Phase 3: Verification

- [ ] 3.1 Run TypeScript type check: `npx tsc --noEmit` in `apps/web-platform/`
- [ ] 3.2 Verify no changes leaked into chat page message bubble avatars (`[conversationId]/page.tsx`)
- [ ] 3.3 Visual QA: verify badge renders at correct dimensions (28px mobile, 32px desktop)
