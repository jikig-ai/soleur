---
title: "feat: Replace leader badge with Soleur-branded logo badge"
type: feat
date: 2026-04-10
---

# feat: Replace leader badge with Soleur-branded logo badge

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** Proposed Solution, Acceptance Criteria
**Research conducted:** Logo image analysis (Pillow), CSP compatibility check, middleware matcher verification, PWA icon learning review

### Key Improvements

1. **Corrected background color approach:** The original plan proposed a `#C9A962` gold background, but the logo already has a dark `#0A0A0A` background with gold accents built in. Gold-on-gold would create poor contrast. The corrected plan uses the image as-is.
2. **Added image resize command:** Concrete Pillow command for 512px to 64px resize, confirmed Pillow is available on host.
3. **Added edge cases:** Image load failure (layout shift prevention) and dark-on-dark contrast mitigation.
4. **Verified CSP and middleware compatibility:** Inline styles are allowed (`unsafe-inline`); `.png` files bypass auth middleware.

---

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

### Research Insights

**Logo analysis (critical finding):** The source logo (`logo-mark-512.png`) is a gold "S" letter inside a gold circle outline on a dark `#0A0A0A` background. The image is fully opaque (alpha = 255 throughout). This means:

- The logo already carries its own dark background -- no additional background color needed.
- Adding a `#C9A962` gold background would only show as a thin edge around the `rounded-md` corners (gold behind gold = poor contrast).
- The correct approach is to use the logo as-is, letting the image's built-in dark background serve as the badge background.

**Image resizing:** Pillow (`python3 -c "from PIL import Image"`) is available on the host for the resize step. Use it to create a 64px version.

**CSP compatibility:** `style-src 'self' 'unsafe-inline'` is configured in `lib/csp.ts`, so inline styles are safe. However, since the gold background is no longer needed, inline styles may be unnecessary.

**Middleware:** The matcher regex in `middleware.ts` excludes `.*\.png$`, so `/icons/soleur-logo-mark.png` will be served without auth middleware interference.

### Steps

1. **Copy and resize the logo asset** to the Next.js public directory as `apps/web-platform/public/icons/soleur-logo-mark.png`. Resize from 512px to 64px (2x retina for the 32px max render size) using Pillow: `python3 -c "from PIL import Image; img = Image.open('plugins/soleur/docs/images/logo-mark-512.png'); img.resize((64, 64), Image.LANCZOS).save('apps/web-platform/public/icons/soleur-logo-mark.png')"`.

2. **Modify `LeaderBadge`** to render the Soleur logo image instead of the leader ID text:
   - Replace the inner `<span>` text with an `<img>` tag using `src="/icons/soleur-logo-mark.png"`
   - Use `object-fit: cover` and `rounded-md` so the image fills the badge with rounded corners
   - Keep the existing size classes (`h-7 w-7 md:h-8 md:w-8`)
   - No background color needed -- the logo's built-in dark background matches the app's dark theme
   - Remove the `LEADER_BG_COLORS` import from conversation-row.tsx (dead import after this change)

3. **Use `leaderId` for accessibility** -- set `aria-label={`Soleur ${leaderId.toUpperCase()}`}` on the badge element so screen readers convey which leader the badge represents. Do not preserve the prop "for future use" without a current consumer -- that violates YAGNI.

4. **Add `alt` text** to the image: `alt=""` (decorative, since `aria-label` on the container provides the semantic label).

### Edge Cases

- **Image load failure:** If the PNG fails to load, the badge will show an empty area. Add `width` and `height` attributes to prevent layout shift: `width={28} height={28}` (mobile) with responsive override via classes.
- **Dark-on-dark contrast:** The logo's dark background (`#0A0A0A`) is nearly identical to the app's dark theme backgrounds (`bg-neutral-900/50`, `bg-neutral-900`). The gold circle outline in the logo provides sufficient visual separation. If contrast is poor in practice, consider adding a 1px border via `ring-1 ring-neutral-700`.

## Acceptance Criteria

- [x] `LeaderBadge` displays the Soleur logo mark image (dark background with gold S, built into the image)
- [x] Badge renders at 28px (mobile) / 32px (desktop), matching current dimensions
- [x] Logo image is centered within the badge with appropriate padding
- [x] Badge has `aria-label` combining "Soleur" with the leader ID for screen readers
- [x] Image has `alt=""` (decorative -- aria-label on container provides semantics)
- [x] Logo asset exists at `apps/web-platform/public/icons/soleur-logo-mark.png` (resized to 64px)
- [x] `LEADER_BG_COLORS` import removed from conversation-row.tsx (dead import)
- [x] TypeScript compiles without errors (`npx tsc --noEmit` in `apps/web-platform/`)
- [x] No changes to the chat page message bubbles (out of scope)

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
