---
title: Static docs site built directly from brand guide
category: workflow-patterns
module: docs
tags: [documentation, brand-identity, static-site, github-pages, design-system]
date: 2026-02-13
symptoms: [need-docs-site, brand-consistency, component-inventory]
---

# Learning: Static Docs Site Built Directly from Brand Guide

## Problem

Needed a documentation site for the Soleur plugin that matches the Solar Forge brand identity. Previous docs site was deleted (stale branding, wrong component counts). Had a brand guide but no mockup-to-HTML pipeline.

## Solution

Skipped the mockup phase entirely. Built static HTML/CSS/JS directly from the brand guide specification:

1. **CSS variables from brand guide** -- Extracted exact hex values, font families, and spacing rules from `knowledge-base/overview/brand-guide.md` into CSS custom properties. One source of truth.

2. **Component inventory via frontmatter** -- Read command/skill/agent descriptions directly from YAML frontmatter in markdown files rather than hardcoding. Used `head -10` and `grep` to batch-extract names and descriptions.

3. **Local testing with Python HTTP server** -- `python3 -m http.server 8787` from the docs directory, then Playwright for visual verification. Cannot use `file://` URLs with Playwright.

4. **Responsive from the start** -- Three breakpoints (1024px, 768px) built into the single CSS file. Mobile nav toggle in 30 lines of JS.

## Key Insight

When a brand guide exists with exact specifications (colors, fonts, spacing, corners), you can skip the design-tool-to-code translation step and build HTML directly. The brand guide IS the spec. This saved an entire round-trip of mockup iteration.

The component inventory pattern (grep frontmatter from source files) keeps docs accurate because it reads from the same files the plugin loader reads. No manual sync needed.

## Prevention

- Always check if `plugins/soleur/docs/` exists before creating a new docs site -- GitHub Pages workflow deploys from there automatically
- When updating component counts, re-inventory from source files rather than updating numbers manually
- The `release-docs` skill automates this inventory for future updates

## Tags

category: workflow-patterns
module: docs
