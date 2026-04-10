---
title: "feat: Replace leader badge with Soleur-branded logo badge"
type: feat
date: 2026-04-10
---

# feat: Replace leader badge with Soleur-branded logo badge

Replace the text-based `LeaderBadge` component in the conversation list UI with a Soleur-branded badge that displays the Soleur logo mark on a gold accent background (`#C9A962`), replacing the plain colored square with uppercase leader ID text.

## Context

The current `LeaderBadge` in `apps/web-platform/components/inbox/conversation-row.tsx` renders a small colored square (7x7 on mobile, 8x8 on desktop) with the leader ID in uppercase text (e.g., "CMO", "CTO"). Each leader has a distinct Tailwind background color mapped via `LEADER_BG_COLORS`.

The user wants a unified "Soleur" badge instead -- a single badge style using the brand accent color `#C9A962` and the Soleur logo mark (`plugins/soleur/docs/images/logo-mark-512.png`) as the icon.

### Key Files

- `apps/web-platform/components/inbox/conversation-row.tsx` -- `LeaderBadge` component (lines 31-39)
- `apps/web-platform/components/chat/leader-colors.ts` -- `LEADER_BG_COLORS` map (consumed by both conversation-row and chat page)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- chat page also uses `LEADER_BG_COLORS` for inline message avatars (line 373)
- `plugins/soleur/docs/images/logo-mark-512.png` -- source logo asset (10KB, 512px)
- `apps/web-platform/public/` -- Next.js public directory for static assets
- `apps/web-platform/app/globals.css` -- Tailwind v4 (uses `@import "tailwindcss"`, no config file)

### Constraints

- **Tailwind v4**: No `tailwind.config.js` -- custom colors must use inline styles or CSS custom properties, not Tailwind config extensions.
- **No `next/image` usage in codebase**: The app does not currently use `next/image` or standard `<img>` tags in components. The badge is pure CSS/text. Using a standard `<img>` tag is simpler and avoids adding a new import pattern.
- **Scope boundary**: Only the `LeaderBadge` in conversation-row.tsx is in scope. The chat page (`[conversationId]/page.tsx`) has its own inline leader avatar at line 371-376 -- that is a separate concern and NOT in scope.
- **Brand color**: `#C9A962` (Gold Accent from brand guide, `knowledge-base/marketing/brand-guide.md` line 181).

## Proposed Solution

1. **Copy the logo asset** to the Next.js public directory as `apps/web-platform/public/icons/soleur-logo-mark.png` (or a size-optimized version). The 512px source is suitable; the badge renders at 28-32px so the browser handles downscaling.

2. **Modify `LeaderBadge`** to render the Soleur logo image instead of the leader ID text:
   - Replace the `<span>` text content with an `<img>` tag pointing to `/icons/soleur-logo-mark.png`
   - Use inline `style={{ backgroundColor: '#C9A962' }}` for the brand accent background (Tailwind v4 has no config to extend)
   - Keep the existing size classes (`h-7 w-7 md:h-8 md:w-8`) and layout (`flex items-center justify-center rounded-md`)
   - Add padding to prevent the logo from touching the badge edges
   - Remove the `leaderId` prop dependency on `LEADER_BG_COLORS` since all badges now share one color

3. **Preserve the `leaderId` prop** in `LeaderBadge` for potential future use (tooltip, aria-label) but stop using it for color selection.

4. **Add `alt` text** to the image for accessibility: `alt="Soleur"`.

## Acceptance Criteria

- [ ] `LeaderBadge` displays the Soleur logo mark image on a `#C9A962` gold background
- [ ] Badge renders at 28px (mobile) / 32px (desktop), matching current dimensions
- [ ] Logo image is centered within the badge with appropriate padding
- [ ] Image has proper `alt="Soleur"` text for accessibility
- [ ] Logo asset exists at `apps/web-platform/public/icons/soleur-logo-mark.png`
- [ ] TypeScript compiles without errors (`npx tsc --noEmit` in `apps/web-platform/`)
- [ ] No changes to the chat page message bubbles (out of scope)

## Test Scenarios

- Given a conversation with a domain leader, when the conversation list renders, then the leader badge shows the Soleur logo on a gold background instead of text
- Given a conversation without a domain leader, when the conversation list renders, then no badge is shown (existing conditional behavior preserved)
- Given the badge on a mobile viewport (< md breakpoint), when rendered, then it displays at 28x28px (h-7 w-7)
- Given the badge on a desktop viewport (>= md breakpoint), when rendered, then it displays at 32x32px (h-8 w-8)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- cosmetic UI change aligning existing component with brand identity.

## References

- Brand guide color palette: `knowledge-base/marketing/brand-guide.md` line 181 (Gold Accent `#C9A962`)
- Current component: `apps/web-platform/components/inbox/conversation-row.tsx:31-39`
- Logo source: `plugins/soleur/docs/images/logo-mark-512.png`
- Tailwind v4 learning: `knowledge-base/project/learnings/2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md`
