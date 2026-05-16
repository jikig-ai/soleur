---
date: 2026-05-05
category: ui-bugs
module: web-platform / markdown-renderer
tags: [tailwind, css, table-layout, overflow, markdown, regression-class]
related:
  - knowledge-base/project/learnings/ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md
pr: "#3222"
---

# `overflow-x-auto` wrapper is defeated when the child has `w-full`

## Problem

On the public `/shared/[token]` page, GFM tables in markdown rendered with crammed columns — prose cells wrapped to 1-3 chars per line, headers split mid-word. The `<div className="mb-3 overflow-x-auto"><table className="w-full">` wrapper looked correct on inspection (the wrapper exists, the scroll utility is applied), but horizontal scroll never engaged on overflow.

## Root Cause

`width: 100%` on the table forces the browser's auto-layout algorithm to compress every column to fit the parent's inner width. The wrapper's `overflow-x-auto` only engages when the child's `scrollWidth > clientWidth`. When the child is `width: 100%` of the parent, that inequality is mathematically impossible — the child always fits exactly. Wrapper scroll is dead code.

The same trap applies to **any** fluid-width child of an overflow-scroll wrapper:

```html
<!-- Same antipattern, different element -->
<div class="overflow-x-auto">
  <pre class="w-full">…</pre>          <!-- never scrolls -->
  <img class="w-full" src="...">       <!-- never overflows -->
  <iframe class="w-full">…</iframe>    <!-- ditto -->
</div>
```

## Solution

Switch the child's width to `w-auto` (browser default for tables — sizes from content via auto-layout). Keep the wrapper's `overflow-x-auto`. For tables specifically, also pin a per-cell width band so single-token cells don't collapse and prose cells don't blow out:

```tsx
table: ({ children }) => (
  <div className="mb-3 overflow-x-auto">
    <table className="w-auto border-collapse text-sm">{children}</table>
  </div>
),
th: ({ children }) => (
  <th className="whitespace-nowrap …">{children}</th>
),
td: ({ children }) => (
  <td className="min-w-[8ch] max-w-[40ch] align-top …">{children}</td>
),
```

`whitespace-nowrap` on `<th>` is intentional — column headers are identifiers; wrapping them mid-word is worse than scrolling the table. Header may exceed the `40ch` cell cap (header wins, body cells wrap inside the wider column).

## Key Insight

**An overflow-scroll wrapper around a `w-full` child is a no-op.** When a "scroll wrapper exists but doesn't engage" symptom appears, look at the child's width before rewriting layout. Don't conflate "wrapper is correct" with "scroll behavior is correct" — they're independent.

## Prevention

When prescribing an `overflow-x-auto` (or `overflow-x-scroll`) wrapper:
- Verify the child does NOT have `w-full`, `width: 100%`, `flex-1` (in a horizontal flex), or any utility that pins it to the parent width.
- For tables: prefer `w-auto` (browser auto-layout) unless the visual goal is a fixed table grid (use `table-fixed`, NOT `w-full`).
- For cells: pin a width band (`min-w-[Xch] max-w-[Ych]`) to prevent both collapse and blowout.

For test coverage that locks this in: assert both the positive class is present (`w-auto`) AND a regression-guard regex blocks the antipattern returning (`not.toMatch(/(^|\s)w-full(\s|$)/)`). The word-boundary regex avoids false-matches against `min-w-full` etc.

## Session Errors

- **`bash plugins/soleur/skills/review/scripts/ensure-semgrep.sh` exited 2** — no pip/pipx/brew available in agent shell. **Recovery:** noted gap, proceeded with 9 agents (skipped semgrep-sast). **Prevention:** environmental — diff was CSS-classes only with zero SAST scope, so no coverage loss; future runs in environments with pip will bootstrap normally. No skill change warranted.
- **`gh issue create --milestone 6` failed with `could not add to milestone '6': '6' not found`** — `gh issue create --milestone` expects the milestone *title string*, not the numeric API id returned from `gh api repos/.../milestones`. **Recovery:** re-ran with `--milestone "Post-MVP / Later"`. **Prevention:** discoverable from the error message; one-line note suffices.
