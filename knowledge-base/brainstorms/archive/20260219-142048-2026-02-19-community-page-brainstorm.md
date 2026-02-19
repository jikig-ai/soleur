# Community Page Brainstorm

**Date:** 2026-02-19
**Status:** Complete

## What We're Building

A community hub page for the Soleur docs site that consolidates the currently separate GitHub and Discord links into a single "Community" destination. The page will have four sections: Discord + GitHub cards with descriptions, a contributing guide, a support/getting-help section, and a code of conduct reference.

The header and footer navigation will be updated to replace the two external links (GitHub, Discord) with a single "Community" link pointing to this page.

## Why This Approach

- The current header has two separate external links that take users away from the site. A community page keeps them in the docs and provides context around each resource.
- The page is deliberately simple -- a static hub with links and brief descriptions. There aren't enough contributors yet to justify dynamic content like digests or health metrics.
- Uses the Nunjucks template pattern (like agents.njk, skills.njk) with existing CSS classes for consistency.

## Key Decisions

1. **Simple hub page** -- No dynamic content, build-time data, or community metrics. Just a well-organized page with links and descriptions.
2. **Replace both header links** -- GitHub and Discord links removed from header nav, replaced with single "Community" link. The community page has prominent cards for both.
3. **Four sections:**
   - Discord + GitHub cards (hero-adjacent, most prominent)
   - Contributing guide (how to contribute)
   - Support / Getting Help (where to ask questions, report bugs)
   - Code of Conduct (community guidelines)
4. **Nunjucks template** -- Follows the same `.page-hero` + `.catalog-grid` + `.component-card` pattern as agents/skills pages.
5. **Footer updated too** -- Replace separate GitHub/Discord footer links with Community link.

## Open Questions

- Should the community page link to CONTRIBUTING.md in the repo, or inline the content?
- Should we add a Code of Conduct file to the repo if one doesn't exist?
- Future: when community grows, consider adding build-time community digest rendering.
