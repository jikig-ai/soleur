# Spec: Brand Website (Solar Forge)

**Date:** 2026-02-14
**Branch:** feat-brand-website
**Brainstorm:** `knowledge-base/brainstorms/2026-02-14-brand-website-brainstorm.md`

## Problem Statement

PR #86 enabled GitHub Pages with a basic documentation site. The site needs a proper brand landing page based on the Solar Forge visual identity, and the existing docs pages need to be restyled to match the brand.

## Goals

1. Publish a marketing landing page for Soleur using the Solar Forge design
2. Restyle existing docs pages to match the Solar Forge brand
3. Maintain the zero-dependency static HTML/CSS approach

## Non-Goals

- Adding JavaScript interactions or animations
- CMS or dynamic content
- Blog functionality
- Full mobile-responsive design (follow-up)

## Functional Requirements

- **FR1:** Landing page (`index.html`) generated from the Solar Forge .pen design (frame `0Ja8a`)
- **FR2:** Shared brand CSS file with Solar Forge design tokens (colors, fonts, spacing)
- **FR3:** Existing docs pages (agents, commands, skills, mcp-servers, changelog, getting-started) restyled using brand CSS
- **FR4:** Consistent nav and footer across all pages matching Solar Forge design
- **FR5:** Favicon and OG meta tags using logo variations from the .pen file

## Technical Requirements

- **TR1:** All output is static HTML/CSS -- no build step, no dependencies
- **TR2:** Deployed from `plugins/soleur/docs/` via existing GitHub Actions workflow
- **TR3:** Code generated from .pen file using Pencil code generation guidelines
- **TR4:** Brand tokens extracted into a reusable CSS custom properties file

## Design Source

- `.pen` file: `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`
- Primary frame: `0Ja8a` (Solar Forge -- full landing page)
- Logo frame: `g31nK` (Logo Variations)
- Brand colors: `#0A0A0A` (bg), `#C9A962` (gold accent), `#FFFFFF` / `#848484` (text)
- Fonts: Cormorant Garamond (headlines), Inter (body)
