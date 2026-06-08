# Learning: aligning an absolute control to an in-flow sibling must account for the offset between their containing blocks — derive against the live VRT

## Problem

The floated desktop sidebar collapse toggle (`apps/web-platform/app/(dashboard)/layout.tsx`)
was visually misaligned with the workspace selector card. PR #4997 had floated it
with `absolute right-3 top-3` (a fixed top-right CORNER offset borrowed from
`error-card.tsx`), so its vertical center sat well above the workspace pill's center.

The first fix attempt computed the target offset statically: pill = `lg` tile
(h-11 = 44px) + `py-2.5` (20px) = 64px tall, leading the band at `pt-2` (8px) →
center at 8+32 = **40px**; toggle h-6 at `top-7` (28px) → center at 28+12 = **40px**.
The math looked exact, so `top-7` shipped to the work commit.

The structural-UI VRT gate (`nav-states-shell.e2e.ts`, `--project=authenticated`)
then **failed** with a measured center delta of **12px** — not 0. The static math
had a hidden error.

## Root cause

The toggle is `absolute`, so its offset (`top-N`) is measured from its **positioning
containing block** — the `<aside>` (`md:relative`). The workspace pill is **in flow**
inside the **band** (`WorkspaceContextBand`), which is mounted ~12px *below* the aside
top (the reclaimed-space offset that the VRT separately asserts as `bandBox.y -
asideBox.y ≤ 12`). The static calc implicitly assumed the band's coordinate origin ==
the aside's origin. It does not.

The algebra makes the trap exact:
`delta = |toggle_center − pill_center| = |(aside.y + top + 12) − (aside.y + band_offset + 8 + 32)| = |top − band_offset − 28|`.
At `top-7` (28): `|28 − band_offset − 28| = band_offset = 12`. So the residual delta
**equals the band offset** for any `top` value. Correct value: `top = band_offset(12)
+ pt-2(8) + pill_half(32) − toggle_half(12) = 40px = top-10`. The single-workspace
AC1 VRT then passed ≤2px.

## Solution

1. `top-3` → `top-10` (40px) on the floated toggle. Its center now lands at
   12 (band offset) + 8 (pt-2) + 32 (pill half) = 52px from the aside top, matching
   the pill center.
2. Collapsed branch: the monogram column's `pt-10` → `pt-14` (the toggle's bottom
   edge moved from 36px to 64px from the aside top; pt-14 keeps a 4px gap in the
   band-relative frame, which is also offset 12px below the aside).
3. Added a **positive rect-center VRT assertion** (`expectVerticallyCentered`,
   ≤2px) for both the multi-workspace switch button and the single-workspace chip.
   The pre-existing test only asserted **non-overlap** — which a
   misaligned-but-disjoint toggle passes, exactly how PR #4997's regression shipped.

## Key Insight

When an `absolute`/`fixed` control must align to an **in-flow** element, the two live
in **different containing blocks**. Static pixel math that derives the offset from the
target's padding alone silently omits the gap between the two containing blocks'
origins. **Do not eyeball or static-compute the offset — derive it against the live
VRT** (the plan's own Precedent-Diff prescribed this) and assert a *positive*
rect-center alignment (≤2px), never just non-overlap. A non-overlap assertion is the
exact gap that lets a centering regression ship green.

Corollary: the repo has two competing conventions — fixed-corner
(`absolute right-3 top-3`, `error-card.tsx`) vs centered
(`top-1/2 -translate-y-1/2`, `file-tree.tsx`/`search-overlay.tsx`). `top-1/2` is wrong
here because the toggle is positioned against the *whole tall aside*, not the header
band — it would center against the full rail height. An explicit `top-N` derived
against the VRT is the correct shape when the offset parent ≠ the alignment target's
parent.

## Session Errors

1. **Static-geometry miscalculation (`top-7`).** Assumed band origin == aside origin;
   missed the 12px reclaimed-space band offset. Recovery: VRT-derived `top-10`.
   **Prevention:** for an absolute control aligning to an in-flow sibling, measure the
   offset-parent → target gap (or derive against the live VRT) before committing a
   `top-N`; never assume the target's containing block starts at the offset parent.
2. **Local Playwright VRT unreliable** — `page.goto: Target page... has been closed`
   dev-server crashes on this throttled host (BD_PROCHOT), hitting untouched
   pre-existing tests identically. **Prevention:** known per-host hardware quirk, not a
   code defect; CI's `e2e:` Playwright container is the authoritative VRT gate. Run a
   single geometry-bearing test in isolation to reduce server load when a full-suite
   run keeps crashing.
3. **Stale `.next/types` tsc false-positive** (`PaymentWarningBanner` route export
   "not assignable to never") surfaced only after a local dev server regenerated
   `.next/types`; the export is byte-identical on `main` and CI is green there.
   **Prevention:** when `tsc --noEmit` fails on a `.next/types/**` *generated* file
   after running a dev server, confirm the flagged symbol is pre-existing on `main`
   and re-run tsc against a fresh `rm -rf .next/types` (the CI shard condition) before
   treating it as a regression.
4. **`pkill -f "playwright"` / `fuser -k` self-kill (exit 144)** — running it *inside*
   a command that is itself a detached playwright run killed its own process tree (no
   log produced). **Prevention:** free ports / kill servers in a **separate** prior
   Bash step; never `pkill -f playwright` from within a command running playwright.
5. **Plan subagent: Task tool unavailable in planning-pipeline context** (forwarded
   from session-state.md) — plan-review / deepen-plan agent fan-out fell back to
   mechanical gates. One-off known limitation; the full agent panels ran in
   /work + /review.

## Tags
category: ui-bugs
module: apps/web-platform/app/(dashboard)/layout.tsx
related: [[2026-06-08-floating-absolute-control-needs-clearance-in-both-render-branches]], [[2026-04-17-alignment-fixes-must-verify-both-toggle-states]], [[2026-06-03-playwright-x-alignment-measure-glyph-not-border-box]]
