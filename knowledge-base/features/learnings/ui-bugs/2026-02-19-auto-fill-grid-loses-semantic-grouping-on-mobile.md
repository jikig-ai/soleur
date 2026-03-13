---
title: auto-fill grid loses semantic grouping on mobile
date: 2026-02-19
category: ui-bugs
tags: [css-grid, responsive, auto-fill, mobile, semantic-grouping, landing-page]
module: docs
symptoms: [cards-read-weird-on-mobile, lost-visual-pairing, awkward-column-grouping]
---

# auto-fill Grid Loses Semantic Grouping on Mobile

## Problem

Landing page feature grid used `repeat(auto-fill, minmax(200px, 1fr))` for 10 cards (5 departments + 5 workflow steps). On desktop at 1200px, this naturally created two rows of 5 -- departments on top, workflow below. On mobile (single column) and tablet (3 columns), the semantic grouping was lost entirely, creating awkward pairings like "Marketing, Support, Think" in one row.

## Solution

Split the single `.feature-grid` into two separate grids (`.feature-grid-departments` and `.feature-grid-workflow`) with a sublabel `<h3>` between them. Added a mobile media query forcing 2-column layout so cards maintain meaningful pairs.

```css
.feature-grid-departments,
.feature-grid-workflow {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: var(--space-5);
}

@media (max-width: 768px) {
  .feature-grid-departments,
  .feature-grid-workflow {
    grid-template-columns: repeat(2, 1fr);
  }
}
```

## Key Insight

`auto-fill` grids are great for homogeneous card collections but break semantic grouping when cards have conceptual categories. When card order carries meaning (departments vs. workflow steps), split into separate grids with explicit labels rather than relying on auto-fill to create visual rows that happen to align with semantic boundaries. The alignment is fragile and breaks at every breakpoint except the one it was designed for.

## Prevention

- When a grid contains cards with distinct conceptual groups, split into separate grids upfront
- Use `<h3>` (not `<p>`) for group sublabels -- screen readers navigate by headings
- Test responsive layouts at 375px, 768px, and 1024px to catch grouping issues early

## Tags

category: ui-bugs
module: docs
