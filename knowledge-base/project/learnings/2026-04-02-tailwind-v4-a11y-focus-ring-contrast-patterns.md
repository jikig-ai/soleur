# Learning: Tailwind v4 accessibility patterns — focus rings, WCAG contrast, and @layer base

## Problem

Phase 1 screens had 27 P1 accessibility issues: missing focus indicators, no screen reader error announcements, and WCAG AA contrast failures. The issue (#1382) proposed `text-neutral-500` as the contrast fix, but this was wrong.

## Solution

Four independent fixes applied across 14 source files:

1. **Global focus ring via `@layer base`** — Added a `:where()` selector targeting interactive elements with `focus-visible` box-shadow ring (amber-500 with neutral-950 offset). The `:where()` wrapper gives zero specificity, so component-level `focus:ring-*` utilities naturally win without any override logic.

2. **`role="alert"` on error elements** — Mechanical addition to 11 error `<p>` elements and the `ErrorCard` container `<div>`. No abstraction needed — just the attribute.

3. **Contrast: `text-neutral-400` (not `text-neutral-500`)** — The original issue proposed neutral-500. Verified via WCAG relative luminance calculation:
   - neutral-600 (#525252) on neutral-950 (#0a0a0a): **2.53:1** — fails AA entirely
   - neutral-500 (#737373) on neutral-950 (#0a0a0a): **4.18:1** — fails AA normal text (needs 4.5:1)
   - neutral-400 (#a3a3a3) on neutral-950 (#0a0a0a): **7.85:1** — passes AA comfortably

4. **`overflow-wrap: anywhere`** — Applied via Tailwind arbitrary value `[overflow-wrap:anywhere]` (not inline style). Tailwind v4 has no native utility for this CSS property.

## Key Insight

Always verify WCAG contrast ratios with actual calculation rather than trusting issue descriptions. The proposed fix (neutral-500) would have still failed WCAG AA. The relative luminance formula catches this:

```python
def relative_luminance(hex_color):
    r, g, b = int(hex_color[1:3], 16)/255, int(hex_color[3:5], 16)/255, int(hex_color[5:7], 16)/255
    def linearize(c):
        return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
    return 0.2126*linearize(r) + 0.7152*linearize(g) + 0.0722*linearize(b)
```

In Tailwind v4, `@layer base` with `:where()` is the correct pattern for global defaults that should yield to utility classes. The `:where()` selector gives zero specificity, while `@layer base` ensures it loads before components and utilities layers.

## Session Errors

1. **Plan subagent output not persisted to worktree** — The Agent tool ran plan+deepen successfully but file writes from the subagent weren't visible in the worktree filesystem. Recovery: fell back to inline plan execution. Prevention: When using Agent tool for file-writing tasks, verify files exist in the worktree after the agent completes. Consider using `isolation: "worktree"` parameter for agents that need to write files.

2. **Duplicate plan file from subagent** — The subagent created a plan with a different filename than the inline fallback, resulting in two plan files. Recovery: removed the duplicate via `git rm`. Prevention: Check for existing plan files matching the feature before writing a new one.

3. **Dev server failed during QA — missing Supabase env vars** — `doppler run -c dev` did not provide `SUPABASE_URL` to the server process, causing immediate crash. Browser QA scenarios were skipped. Recovery: relied on static verification (build + typecheck + tests). Prevention: Before starting QA dev server, verify required env vars exist with `doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain`.

4. **Task description became no-op after plan update** — Task 1.17 said "Replace `placeholder:text-neutral-400` with `placeholder:text-neutral-400`" after the plan was updated from neutral-500 to neutral-400. The actual source files still had `placeholder:text-neutral-600`, so the fix was correct, but the task text was misleading. Recovery: fixed the actual files correctly. Prevention: When updating a plan's target values, re-derive task descriptions from the source files rather than string-replacing in task text.

## Tags

category: ui-bugs
module: web-platform
