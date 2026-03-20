---
title: Fix mobile dual-column cards layout
feature: feat-mobile-cards-fix
date: 2026-02-19
---

# Tasks

## Phase 1: HTML Restructuring

- [x] 1.1 Split `.feature-grid` in `index.njk` into two groups: departments (5 cards) and workflow (5 cards)
- [x] 1.2 Add group labels or visual separators between the two groups

## Phase 2: CSS Responsive Fixes

- [x] 2.1 Replace `auto-fill` with explicit column counts at breakpoints for each group
- [x] 2.2 Add mobile media query (<=768px): 2-column grid for both groups
- [x] 2.3 Add tablet media query (769-1024px): appropriate column counts
- [x] 2.4 Ensure desktop layout (>1024px) remains unchanged

## Phase 3: Verification

- [x] 3.1 Visual verification at 375px, 768px, 1024px, and 1200px viewports
- [x] 3.2 No horizontal scrolling on any viewport
