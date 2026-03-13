# X/Twitter Banner Design for @soleur_ai

**Date:** 2026-03-10
**Issue:** #483
**Branch:** feat-x-banner

## What We're Building

A 1500x500px banner image for the @soleur_ai X/Twitter profile that communicates Soleur's identity and ambition. The banner works alongside the existing gold circle "S" avatar.

## Why This Approach

The banner follows a **sparse, center-weighted hybrid** layout because:

1. X crops banners aggressively on mobile -- center 60% is the safe zone
2. The brand guide mandates generous whitespace ("let content breathe")
3. A hybrid of text + visual elements beats pure text or pure visual alone
4. The thesis statement ("Build a Billion-Dollar Company. Alone.") is the strongest hook for the X audience (solo founders, technical builders)

## Key Decisions

1. **Content hierarchy:**
   - Primary: "S O L E U R" wordmark (Inter 500, letterSpacing 4)
   - Secondary: "Build a Billion-Dollar Company. Alone." (Cormorant Garamond, thesis statement)
   - Tertiary (if space): "60+ Agents · 8 Departments · 1 Founder" metrics
2. **Layout:** Center-weighted with decorative gold elements at edges (safe to crop on mobile)
3. **Visual style:** Dark #0A0A0A background, gold #C9A962 accents, Solar Forge metaphor, sharp corners (0px border-radius)
4. **Generation approach:** Design layout in Pencil (.pen file), render final image via Gemini image generation
5. **Upload method:** Playwright MCP to set banner on @soleur_ai profile
6. **Documentation:** Add banner specs to `knowledge-base/overview/brand-guide.md` under X/Twitter section

## Design Constraints

- **Dimensions:** 1500x500px (X recommended)
- **Safe zone:** Center ~900x500px is guaranteed visible on all devices
- **Avatar overlap:** Bottom-left corner is obscured by the circular avatar on X profile view
- **Color palette:** Must use brand colors exclusively (no new colors)
- **Typography:** Cormorant Garamond for headlines, Inter for wordmark/labels
- **No emojis, no rounded corners, no stock imagery**

## Open Questions

- Exact gold accent element design (subtle gradient line? forge-like abstract shape?)
- Whether metrics fit without cluttering -- may need to test in Pencil at actual size
- Final Gemini prompt engineering for faithful brand reproduction
