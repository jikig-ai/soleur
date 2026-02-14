# Brand Website Brainstorm

**Date:** 2026-02-14
**Status:** Complete
**Topic:** Publish Soleur marketing website based on Solar Forge brand identity

## What We're Building

A marketing/landing page website for Soleur, published via GitHub Pages, based on the "Solar Forge" visual identity direction from `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`.

The site will serve as both the brand landing page (homepage) and the documentation hub, with the existing docs pages restyled to match the Solar Forge brand.

## Why This Approach

- **Solar Forge** is the only fully designed direction in the .pen file -- it has a complete landing page with nav, hero, stats strip, problem section, quote, features grid, CTA, and footer. The other 3 directions (First Light, Stellar, Solar Radiance) only have hero sections and color palettes.
- **Landing page + docs** keeps everything under one roof. The landing page sells the product; the docs serve existing users. One deployment, one domain.
- **Static HTML/CSS** matches the existing docs setup (no build step, no dependencies). GitHub Pages serves it directly. Pencil can generate code from the .pen design.
- **Approach A** (generate from .pen, then adapt docs) ships fastest. The landing page design is ready; the docs pages just need consistent branding, not pixel-perfect mockups.

## Key Decisions

1. **Design direction:** Solar Forge (dark theme, gold #C9A962 accents, Cormorant Garamond + Inter fonts)
2. **Site structure:** Solar Forge landing page as homepage (`index.html`), existing docs pages restyled to match brand
3. **Tech stack:** Static HTML/CSS, no build step, no framework
4. **Deployment:** Same GitHub Actions workflow deploying from `plugins/soleur/docs/`
5. **Execution approach:** Generate landing page code from .pen file, extract brand tokens into shared CSS, apply to docs pages

## Design Assets Available

- **Full landing page:** Frame `0Ja8a` ("1 -- Solar Forge") with 9 sections
- **Logo variations:** Frame `g31nK` with favicon, avatar, mark, horizontal dark/light, OG image
- **Logo explorations:** Frame `w1G4s` with 5 logo variants
- **Color palette:** Dark backgrounds (#0A0A0A, #0E0E0E, #141414), gold accent (#C9A962), text (#FFFFFF, #848484, #4A4A4A)
- **Typography:** Cormorant Garamond (headlines), Inter (body/UI)

## Scope

### In Scope
- Generate landing page HTML/CSS from Solar Forge .pen design
- Create shared brand CSS (colors, fonts, spacing)
- Restyle existing docs pages to match Solar Forge brand
- Update deploy workflow if needed
- Favicon and OG meta tags from logo variations

### Out of Scope
- Custom JavaScript interactions or animations
- CMS or dynamic content
- Blog or content management
- Mobile-responsive design beyond basic viewport handling (can be added later)
- Analytics or tracking

## Open Questions

- Should the nav links (Platform, Docs, Community) point somewhere specific, or be placeholder for now?
- Do the CTA buttons ("Start Building", "Read the Docs") need real destinations?
- Should we add responsive/mobile design in this first pass or as a follow-up?
