---
title: Footer layout redesign -- flex children and visual verification
module: docs-site
date: 2026-04-02
problem_type: ui_bug
component: css_layout
symptoms:
  - "Footer with 5 flex children cramped on single row at tablet widths"
  - "Link text clipped at right edge on mobile without flex-wrap"
root_cause: missing_flex_wrap
severity: low
tags: [css, flex, footer, responsive, eleventy, visual-verification]
synced_to: []
---

# Footer Layout Redesign -- Flex Children and Visual Verification

## Problem

After splitting 9 footer links into two groups (nav + legal), adding both `<ul>` elements as direct children of `.footer-inner` (a flex container) created a cramped layout. The footer went from 4 to 5 flex children, causing elements to squeeze together at tablet widths and "About" to clip at the right edge on mobile.

## Investigation

1. Initial plan prescribed adding `.footer-legal` as a sibling of `.footer-links` inside `.footer-inner`
2. Desktop screenshot at 1280px revealed "AboutLegal" running together -- 5 flex children with `justify-content: space-between` left no breathing room
3. Plan review agents (Kieran) had predicted this exact issue but the plan was implemented verbatim before visual verification

## Solution

1. Wrapped both link lists in a `.footer-nav-group` container (`flex-direction: column; gap: var(--space-2)`) so they remain a single flex child of `.footer-inner` -- preserving the original 4-child layout
2. Added `flex-wrap: wrap` to `.footer-inner` with `gap: var(--space-3)` for graceful wrapping at intermediate widths
3. Added `flex-wrap: wrap` to both `.footer-links` and `.footer-legal` for mobile graceful wrapping

## Key Insight

When adding children to an existing flex container, the number of flex children matters as much as their content. Going from 4 to 5 children with `justify-content: space-between` changes the spacing calculation significantly. The fix was to group related elements so the flex child count stays the same.

Always verify flex layout changes at desktop, tablet, AND mobile breakpoints with screenshots before committing -- the plan may prescribe a layout that looks correct in theory but fails at intermediate widths.

## Session Errors

1. **Eleventy build run from wrong directory** -- Ran `npx @11ty/eleventy` from `plugins/soleur/docs/` instead of repo root where `eleventy.config.js` lives. Got "filter not found: dateToShort" because filters are registered in the root config. Recovery: ran build from repo root. **Prevention:** Always run Eleventy from the repo root. The `eleventy.config.js` at repo root defines `INPUT = "plugins/soleur/docs"` -- running from the docs subdirectory bypasses the config entirely.

2. **Plan implemented verbatim despite reviewer warning** -- Kieran's plan review flagged the 5-child flex overflow risk, but implementation proceeded with the original plan structure. The wrapper div had to be added after the first screenshot revealed the issue. Recovery: added `.footer-nav-group` wrapper. **Prevention:** When plan review agents flag layout concerns, address them during implementation rather than implementing the original plan verbatim and fixing after visual verification.

## Prevention

- When modifying flex containers, count the resulting children and consider the impact on `justify-content` spacing
- Always take Playwright screenshots at 3 breakpoints (desktop 1280px, tablet 900px, mobile 375px) for any footer/nav/layout changes
- Run Eleventy builds from the repository root, not from subdirectories

## Tags

category: docs-site
module: docs-site
