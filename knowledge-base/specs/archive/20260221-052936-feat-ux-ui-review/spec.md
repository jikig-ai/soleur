# UX/UI Review: Content Readability & Header Logo

**Date:** 2026-02-21
**Status:** Draft
**Branch:** feat-ux-ui-review

## Problem Statement

The soleur.ai documentation site has readability issues on long-form content pages (changelog, legal, getting started, vision). Content stretches to the full 1200px container width, headings and paragraphs lack vertical spacing, and the header uses plain text instead of the brand logo mark.

## Goals

- G1: Add the gold S logo mark to the site header alongside the "Soleur" wordmark
- G2: Improve readability of long-form content pages with proper width and spacing
- G3: Fix changelog content styling (currently unstyled because CSS class mismatch)

## Non-Goals

- Redesigning the homepage landing sections (they work well)
- Reworking the agents/skills card grid layouts (no issues)
- Adding new pages or navigation
- Mobile layout overhaul (current responsive design is functional)

## Functional Requirements

- FR1: Header displays logo mark image (~24px) next to "Soleur" text on all pages
- FR2: Long-form content capped at ~75ch max-width for comfortable reading
- FR3: Proper vertical spacing between headings, paragraphs, and lists in prose content
- FR4: Changelog version entries visually separated with clear spacing
- FR5: Getting Started and Vision prose sections have same reading-width treatment

## Technical Requirements

- TR1: Add `.prose` CSS class to `style.css` components layer
- TR2: Target `#changelog-content` directly in CSS for changelog-specific styles
- TR3: Use existing `logo-mark-512.png` resized via CSS (no new assets needed)
- TR4: No JavaScript changes required -- CSS and template-only modifications
- TR5: Maintain mobile responsiveness (prose max-width should not break narrow viewports)

## Files to Modify

- `plugins/soleur/docs/css/style.css` -- add `.prose` class, header logo styles
- `plugins/soleur/docs/_includes/base.njk` -- add logo `<img>` to header
- `plugins/soleur/docs/pages/changelog.njk` -- add `.prose` class to content wrapper
- `plugins/soleur/docs/pages/legal/*.md` -- add `.prose` class to content sections
- `plugins/soleur/docs/pages/getting-started.md` -- add `.prose` class
- `plugins/soleur/docs/pages/vision.njk` -- add `.prose` class to prose sections
