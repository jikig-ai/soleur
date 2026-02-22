# Learning: Landing Page Grid Orphan Regression at Tablet Breakpoint

## Problem

After adding a 5th domain (Sales) to the Soleur plugin, the landing page was updated (PR #257, v2.31.4) to use `repeat(3, 1fr)` grids at desktop. However, the tablet breakpoint (769-1024px) still had `grid-template-columns: 1fr 1fr` for `.problem-cards`, which with 3 cards created a 2+1 orphan layout -- the "Knowledge Compounds" card dangled alone in row 2.

The fix was incomplete because only the desktop breakpoint was checked. The tablet breakpoint was missed entirely.

Additionally, the CMO was consulted but did not delegate to the UX designer for visual review of a marketing-visible page -- a process failure that allowed the layout bug to ship.

### Symptoms

- Third problem card orphaned to its own row at 769-1024px viewport width
- Layout looked correct at desktop (>1024px) and mobile (<=768px) but broken at tablet
- Previous fix (PR #257) was incomplete -- only addressed one of three breakpoints

## Solution

**PR #260 (v2.31.6)** fixed the issue by:

1. **Removed** `grid-template-columns: 1fr 1fr` for `.problem-cards` at tablet breakpoint
2. **Added** `grid-template-columns: repeat(2, 1fr)` for `.feature-grid-departments` and `.feature-grid-workflow` at tablet (6 cards / 2 = clean)
3. **Verified** at all three breakpoints before shipping

### Final breakpoint coverage

```
Desktop >1024px:  problem-cards repeat(3,1fr) | feature-grids repeat(3,1fr)
Tablet 769-1024:  problem-cards repeat(3,1fr) | feature-grids repeat(2,1fr)
Mobile <=768:     problem-cards 1fr           | feature-grids repeat(2,1fr)
```

### CSS change (tablet breakpoint)

Before:
```css
@media (min-width: 769px) and (max-width: 1024px) {
  .problem-cards { grid-template-columns: 1fr 1fr; }
}
```

After:
```css
@media (min-width: 769px) and (max-width: 1024px) {
  .feature-grid-departments,
  .feature-grid-workflow { grid-template-columns: repeat(2, 1fr); }
}
```

### Additional CMO-recommended fixes in same PR

- Stats strip: "1 Automated Workflow" changed to "6 Departments" (confusing stat)
- Added mid-page CTA section between testimonial quote and features
- Improved spacing on stats strip and feature grid sublabels

## Key Insight

**The Grid Divisibility Rule:** When changing card counts in a CSS grid, you must verify that the card count divides evenly into the column count at EVERY responsive breakpoint. A remainder means orphaned cards.

```
card_count % column_count == 0  # Must be true at every breakpoint
```

For the landing page:
- 3 problem cards: valid columns are 3 or 1 (never 2)
- 6 feature cards: valid columns are 6, 3, 2, or 1

**Breakpoint audit checklist** (run when card count or grid CSS changes):

1. List all breakpoints that affect the grid
2. For each breakpoint, compute `cards % columns`
3. If remainder != 0, either change the column count or the card count
4. Take screenshots at all breakpoints (desktop, tablet, mobile minimum)
5. Verify no orphaned cards visually

**Process rule:** Marketing-visible changes (landing page, docs site) must route through CMO, who should delegate to UX designer or conversion-optimizer for layout review. CMO provides strategic direction; specialists verify visual execution.

## Session Errors

1. **11ty build from wrong directory** -- Running from `plugins/soleur/docs/` fails with ENOENT. Must build from repo root with `--input=plugins/soleur/docs --output=_site`.
2. **Incomplete previous fix** -- PR #257 fixed desktop only, missed tablet. Always check ALL breakpoints.
3. **CMO didn't delegate to UX** -- Process gap repeated from PR #253. Need explicit delegation protocol.
4. **Worktree cleanup blocked by screenshots** -- Untracked `.png` files prevented `cleanup-merged`. Clean up temp files before merge.

## Cross-References

- Related learning: `knowledge-base/learnings/ui-bugs/2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile.md` (CSS grid auto-fill breakpoint failures)
- Related learning: `knowledge-base/learnings/2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md` (UX review process gap)
- PR #257 (v2.31.4): Original incomplete fix
- PR #260 (v2.31.6): Complete fix with CMO consultation

## Tags
category: ui-bugs
module: plugins/soleur/docs
tags: css-grid, responsive-design, tablet-breakpoint, landing-page, grid-divisibility, process-failure, cmo-delegation
severity: medium
