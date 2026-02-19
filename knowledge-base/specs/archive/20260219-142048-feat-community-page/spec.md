# Community Page Spec

**Date:** 2026-02-19
**Branch:** feat-community-page

## Problem Statement

The Soleur docs site has GitHub and Discord as separate external links in both the header and footer navigation. This sends users directly to external platforms without context. There's no central place on the site that explains the community, how to contribute, or where to get help.

## Goals

- G1: Create a community hub page on the docs site
- G2: Replace separate GitHub/Discord nav links with a single "Community" link
- G3: Provide clear paths to Discord, GitHub, contributing, support, and conduct

## Non-Goals

- Dynamic content (community digests, health metrics, contributor stats)
- Build-time data fetching from Discord or GitHub APIs
- Custom CSS or layout -- reuse existing docs site patterns

## Functional Requirements

- FR1: New `community.njk` page at `pages/community.html`
- FR2: Hero section with page title and description
- FR3: Discord and GitHub cards with descriptions and external links
- FR4: Contributing section with guidance on how to contribute
- FR5: Support section explaining where to ask questions and report bugs
- FR6: Code of Conduct section with community guidelines
- FR7: Header nav updated -- remove hardcoded GitHub/Discord links, add "Community" to `site.nav`
- FR8: Footer nav updated -- replace GitHub/Discord entries in `site.footerLinks` with Community link

## Technical Requirements

- TR1: Use Nunjucks template with `layout: base.njk`
- TR2: Reuse existing CSS classes (`.page-hero`, `.catalog-grid`, `.component-card`, etc.)
- TR3: Page included in sitemap via standard Eleventy collections
- TR4: Responsive -- works at all three breakpoints (desktop, tablet at 1024px, mobile at 768px)
