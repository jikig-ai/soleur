---
date: 2026-06-16
category: ui-bugs
module: apps/web-platform/components/ui/markdown-renderer.tsx
tags: [css, overflow-wrap, tailwind, markdown, tables, inheritance]
branch: feat-one-shot-fix-md-table-cell-word-break
pr: 5414
---

# Learning: `overflow-wrap: anywhere` is inherited — it breaks table-cell words mid-character

## Problem

Rendered markdown **table data cells** broke short words mid-character in the KB
document viewer ("active" → "activ e", "Cloudflare" → "Cloudflar e", "deferred" →
"deferre d", "observability" → "observabil ity"). Headers rendered fine. Reproduced
on the operations/expenses.md view (both the dashboard KB viewer and the public
shared-token viewer use the same `MarkdownRenderer`).

A prior table-width fix (merged 2026-05-05) had already switched the table from
`w-full` to `w-auto` and added a `min-w-[8ch] max-w-[45ch]` band — so the obvious
"columns are too narrow" hypothesis was already addressed. The bug persisted.

## Root Cause

`markdown-renderer.tsx`'s root wrapper sets `<div className="min-w-0
[overflow-wrap:anywhere]">` (issue #2229, intentional for long prose/URLs).
**`overflow-wrap` is an INHERITED CSS property**, so `anywhere` cascades into every
descendant — including each `<td>`, which had no override. `overflow-wrap: anywhere`
(unlike `break-word`) also lets the table's auto-layout compute each cell's
min-content width as if every character is a break opportunity, so columns collapse
and short words break mid-character even when the table visually has room.

`<th>` was immune only because it carried `whitespace-nowrap` (`white-space: nowrap`
suppresses line-breaking entirely) — which is exactly why headers looked correct and
data cells did not. The 2026-05-05 fix addressed `w-full` compression but never
overrode the inherited `overflow-wrap` on cells.

## Solution

Add `break-normal` (Tailwind → `overflow-wrap: normal; word-break: normal`) to the
`<td>` className. A value declared *directly on the element* always beats an
*inherited* value (inheritance only supplies a value when the element has none of its
own — no specificity contest), so the cell wraps at word boundaries again. The root
wrapper's `[overflow-wrap:anywhere]` is preserved for non-table prose; only `<td>`
opts back out. One-line change; one renderer fixes both viewers.

## Key Insight

`overflow-wrap` and `word-break` are **inherited** properties. When a markdown/prose
container sets `overflow-wrap: anywhere` for long-URL safety, it silently cascades into
any table cells inside it and breaks ordinary words mid-character. When you scope an
"aggressive wrap" policy on a container, override it (`break-normal`) on structured
descendants (table cells, code, badges) that must wrap at word boundaries. A fix that
only adjusts column *width* (`w-auto`, min/max-width) will not address an inherited
*wrapping-policy* bug.

## Prevention / Testing

happy-dom can't compute inherited CSS layout, so the regression guard asserts the
className contract: each `<td>` carries a word-boundary opt-out (`break-normal` or the
arbitrary `[overflow-wrap:normal]` form) AND does **not** carry
`[overflow-wrap:anywhere]`. The negative assertion survives an equivalent refactor that
scopes overflow-wrap differently. Fixture uses single long tokens
("Cloudflare", "observability") — the exact inputs the bug mangles.

## Session Errors

1. **Edit-before-Read on the worktree copy of `markdown-renderer.tsx`** — Recovery:
   Read the worktree path before editing. Prevention: a Read at the bare-root synced
   copy does NOT satisfy the read-before-edit gate for the worktree copy — they are
   distinct paths. (one-off)
2. **Planning subagent cited a learning under the wrong subdirectory** — Recovery:
   self-corrected before commit; the path-resolution gate confirmed all citations
   resolve. (one-off)
