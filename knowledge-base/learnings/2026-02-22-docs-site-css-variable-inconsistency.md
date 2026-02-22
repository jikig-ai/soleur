# Learning: Docs site uses undefined CSS variable --accent

## Problem
The docs site vision page (and potentially other pages) uses `var(--accent)` in inline styles, but the CSS only defines `--color-accent`. The shorthand `--accent` is not declared anywhere in `style.css`.

## Solution
The affected pages render without visible breakage because the card dots using `var(--accent)` fall back to transparent -- but the dot is small enough that it's hard to notice. The correct variable is `--color-accent: #C9A962`.

A future cleanup PR should grep all `.njk` templates for `var(--accent)` and replace with `var(--color-accent)`.

## Key Insight
When reviewing docs site changes, check that inline style CSS variable references match the `:root` token definitions in `style.css`. Pre-existing bugs in templates can be carried forward silently through content-only changes.

## Tags
category: ui-bugs
module: docs-site
