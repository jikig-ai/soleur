# SEO & AEO Skill + Agent

**Issue:** #131
**Branch:** feat-seo-aeo
**Date:** 2026-02-19

## Problem Statement

Soleur's docs site (soleur.ai) lacks structured data, AI-optimized content, and several SEO fundamentals. More broadly, any Eleventy docs site built with Soleur's docs-site skill has no tooling to audit or fix SEO/AEO issues. This means sites are invisible to AI models and underperform in search results.

## Goals

- G1: Build a reusable `seo-aeo` skill with audit/fix/validate sub-commands for Eleventy docs sites
- G2: Build a `seo-aeo-analyst` agent that performs deep SEO/AEO analysis and content generation
- G3: Add a CI validation step to `deploy-docs.yml` that prevents SEO regressions
- G4: Apply the skill to soleur.ai as the first customer, fixing all identified issues

## Non-Goals

- Framework-agnostic support (Eleventy-only for v1)
- Paid SEO tool integrations (Google Search Console API, Ahrefs, etc.)
- Performance optimization (Core Web Vitals) -- separate concern
- Multi-language/i18n support
- Link building or off-page SEO

## Functional Requirements

- FR1: `seo-aeo audit` scans Eleventy source and built output, reports issues with severity (critical/warning/info)
- FR2: `seo-aeo fix` generates and applies fixes for all found issues (meta tags, JSON-LD, sitemap, llms.txt, content sections)
- FR3: `seo-aeo validate` runs lightweight checks suitable for CI (exit 0 = pass, exit 1 = fail)
- FR4: The agent analyzes page content and generates optimized versions (FAQ sections, clear definitions, comparison framing)
- FR5: The agent generates JSON-LD structured data (WebSite, SoftwareApplication, Organization, BreadcrumbList schemas)
- FR6: The agent generates/updates llms.txt following the emerging standard
- FR7: The skill adds Twitter/X card meta tags to the base template
- FR8: The skill adds canonical URLs to all pages
- FR9: The skill enhances sitemap.xml with lastmod dates
- FR10: The CI step runs in `deploy-docs.yml` before the deploy step

## Technical Requirements

- TR1: Skill follows Soleur skill conventions (SKILL.md, flat under skills/)
- TR2: Agent follows Soleur agent conventions (markdown under agents/)
- TR3: Eleventy v3 ESM compatibility (export default syntax)
- TR4: Nunjucks template awareness (no variables in frontmatter)
- TR5: Works with the existing docs site structure (base.njk, _data/, pages/)

## Success Criteria

- All audit checks pass on soleur.ai after running `seo-aeo fix`
- CI validation step catches regressions (e.g., removing a meta tag fails the build)
- JSON-LD validates against schema.org
- llms.txt accurately describes the project for AI crawlers
- Changelog page content is available to crawlers (server-rendered, not client-only)
