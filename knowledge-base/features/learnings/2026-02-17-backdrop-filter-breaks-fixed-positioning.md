---
title: backdrop-filter creates containing block for fixed-position descendants
date: 2026-02-17
category: css
tags: [css, backdrop-filter, position-fixed, mobile-nav, stacking-context]
module: docs
symptoms: [fixed-element-height-zero, fixed-element-wrong-position, mobile-nav-not-full-height]
---

# backdrop-filter Creates Containing Block for Fixed-Position Descendants

## Problem

Mobile navigation panel and backdrop overlay had `position: fixed; top: 56px; bottom: 0` but computed height was 0px. The panel appeared to be contained within the 56px-tall header instead of spanning the viewport.

## Root Cause

The `.site-header` had `backdrop-filter: blur(12px)` for a frosted glass effect. Per CSS spec, `backdrop-filter` (like `filter`, `transform`, and `perspective`) establishes a new containing block for fixed-position descendants. This means `position: fixed` children are positioned relative to the header, not the viewport.

With the header being 56px tall, `top: 56px; bottom: 0` computed to 0px height (top offset equals container height, leaving no space).

## Diagnostic

```js
// In browser console:
const navLinks = document.querySelector('.nav-links');
console.log(window.getComputedStyle(navLinks).height); // "32px" (content-only, not full viewport)

const label = document.querySelector('.nav-toggle-label');
console.log(window.getComputedStyle(label, '::before').height); // "0px"
```

## Fix

Replace `bottom: 0` with explicit viewport-relative height using `calc(100vh - var(--header-h))`. Viewport units (`vh`) always resolve against the viewport regardless of containing block.

```css
/* BEFORE -- broken by backdrop-filter containing block */
.nav-links {
  position: fixed;
  top: var(--header-h);
  bottom: 0; /* resolves to 0 height inside header */
}

/* AFTER -- viewport units bypass the containing block issue */
.nav-links {
  position: fixed;
  top: var(--header-h);
  height: calc(100vh - var(--header-h));
}
```

## Key Takeaway

When using `backdrop-filter` on a parent, never rely on `inset` properties (`top`/`bottom` or `left`/`right` pairs) for fixed-position children. Use explicit `width`/`height` with viewport units instead.

Properties that create containing blocks for fixed descendants:
- `transform` (any non-none value)
- `filter` (any non-none value)
- `backdrop-filter` (any non-none value)
- `perspective` (any non-none value)
- `contain: paint` or `contain: layout`
- `will-change` referencing any of the above
