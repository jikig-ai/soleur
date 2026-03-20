---
title: Fix mobile dual-column cards layout
type: fix
date: 2026-02-19
deepened: 2026-02-19
---

# Fix Mobile Dual-Column Cards Layout

Closes #160.

## Enhancement Summary

**Deepened on:** 2026-02-19
**Sections enhanced:** 3
**Research sources:** institutional learnings (CSS class mismatch, backdrop-filter gotcha, docs site patterns)

### Key Improvements
1. Added concrete CSS implementation with exact breakpoints and column counts
2. Added edge case handling for 5th card in odd-count groups
3. Referenced institutional learnings to avoid known CSS pitfalls in this docs site

## Problem Statement

The landing page feature grid uses `auto-fill` with `minmax(200px, 1fr)`, which creates natural groupings on wide screens (5 departments + 5 workflow steps in two rows at 1200px). On mobile, all 10 cards stack into a single column, losing the visual pairing. At tablet widths (3 columns), cards pair awkwardly (e.g., "Marketing, Support, Think" in one row).

## Proposed Solution

1. **Split the feature grid HTML** into two semantic groups with a visual separator:
   - Departments: Strategy, Product, Engineering, Marketing, Support
   - Workflow: Think, Plan, Build, Ship, Learn & Grow

2. **Add responsive CSS** with fixed column counts at breakpoints:
   - Desktop (>1024px): 5 columns per group (one row each)
   - Tablet (769-1024px): departments auto-fill 3+2, workflow auto-fill 3+2
   - Mobile (<=768px): 2 columns for both groups to maintain pairing

3. **Add a subtle visual separator** (spacing + optional section sublabel) between departments and workflow groups.

### Research Insights

**CSS Grid Best Practices for Card Layouts:**
- Use `repeat(auto-fill, minmax(Xpx, 1fr))` for fluid grids but switch to fixed columns when semantic grouping matters more than fluidity
- For 5-item groups on 2-column mobile, the 5th card spans full width or centers -- use `grid-column: 1 / -1` or let it naturally wrap
- The existing site uses CSS `@layer` ordering (reset, tokens, base, layout, components, utilities) -- add new rules in the `components` layer

**Institutional Learnings Applied:**
- From `2026-02-13-parallel-subagent-css-class-mismatch.md`: reuse existing class names from `style.css` -- add new classes only for the group containers
- From `2026-02-13-static-docs-site-from-brand-guide.md`: the site uses 768px and 1024px breakpoints consistently -- follow the same pattern
- From `2026-02-17-backdrop-filter-breaks-fixed-positioning.md`: unrelated to this fix but confirms CSS awareness of this specific docs site

**Implementation Detail:**

```css
/* Split into two grids with a workflow sublabel */
.feature-grid-departments,
.feature-grid-workflow {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: var(--space-5);
  max-width: 1200px;
  margin-inline: auto;
}

.feature-grid-workflow {
  margin-top: var(--space-6);
}

/* Workflow sublabel between groups */
.feature-grid-sublabel {
  font-size: var(--text-xs);
  font-weight: 600;
  letter-spacing: 3px;
  color: var(--color-accent);
  text-transform: uppercase;
  text-align: center;
  margin-top: var(--space-8);
  margin-bottom: var(--space-4);
}

@media (max-width: 768px) {
  .feature-grid-departments,
  .feature-grid-workflow {
    grid-template-columns: repeat(2, 1fr);
  }
}
```

**Edge Cases:**
- 5th card in a 2-column grid wraps to a row alone -- acceptable, the odd card (Support / Learn & Grow) naturally serves as a "capstone" for each group
- Very narrow screens (<320px): 2-column grid may compress cards too much -- the existing `minmax(200px, 1fr)` would naturally fall back to 1 column at ~424px, which is fine since phones are typically 360px+

## Acceptance Criteria

- [ ] Feature cards maintain logical groupings at all viewport widths
- [ ] Desktop layout is unchanged (10 cards, two visual rows)
- [ ] Tablet layout pairs cards logically (no "Support, Think" row)
- [ ] Mobile layout uses 2 columns so cards pair meaningfully
- [ ] No horizontal scrolling on any viewport

## Test Scenarios

- Given a 375px viewport, when viewing the feature grid, then cards display in 2 columns with department and workflow groups visually separated
- Given a 768px viewport, when viewing the feature grid, then cards display in logical pairs
- Given a 1200px viewport, when viewing the feature grid, then each group displays as a single row of 5

## Files to Modify

- `plugins/soleur/docs/index.njk` -- split `.feature-grid` into `.feature-grid-departments` and `.feature-grid-workflow` with a sublabel between them
- `plugins/soleur/docs/css/style.css` -- replace `.feature-grid` styles with the two new grid classes and add mobile media query

## References

- Issue: #160
- CSS file: `plugins/soleur/docs/css/style.css:549-575` (feature grid styles)
- CSS file: `plugins/soleur/docs/css/style.css:851-858` (existing mobile overrides)
- HTML file: `plugins/soleur/docs/index.njk:77-134` (feature grid section)
- Learning: `knowledge-base/learnings/2026-02-13-parallel-subagent-css-class-mismatch.md`
- Learning: `knowledge-base/learnings/2026-02-13-static-docs-site-from-brand-guide.md`
