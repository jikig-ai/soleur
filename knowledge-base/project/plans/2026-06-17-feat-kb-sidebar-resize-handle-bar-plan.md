---
title: "feat: KB sidebar resize handle — replace dot triad with a straight vertical bar"
date: 2026-06-17
type: feat
branch: feat-one-shot-kb-sidebar-resize-handle-bar
lane: cross-domain
status: planned
---

# ✨ feat: KB sidebar resize handle — straight vertical bar (replace faint dot triad)

## Enhancement Summary

**Deepened on:** 2026-06-17
**Sections enhanced:** Research Reconciliation, FR2/FR4 (grip styling), Research Insights (new), Acceptance Criteria (typecheck form)
**Agents used:** verify-the-negative pass (sonnet), code-simplicity-reviewer; (Phase 2.5) cpo + ux-design-lead

### Key Improvements

1. **Corrected the dot line range** from `104-108` to `105-107` (the spans; 104/108 are the wrapper `<div>`) — caught by the verify-negative grep pass.
2. **Killed a silent no-op affordance:** the original FR4 used idle `bg-soleur-text-secondary` + `group-hover:text-secondary` (same token = no visible hover change). Now idle `bg-soleur-text-muted` → `group-hover:bg-soleur-text-secondary`, a real brighten matching the dots' contrast step.
3. **Resolved the bar height at plan time** (`h-8` short centered grip, not full-height border) instead of deferring a single Tailwind class to the wireframe.
4. **Pinned the canonical typecheck command** (`npm run typecheck` from `apps/web-platform`, no `npm run -w`).

### New Considerations Discovered

- The handle container's hover (`hover:bg-soleur-text-secondary/50`) is a translucent wash *behind* the grip — it does not itself brighten the bar; the bar's own `group-hover` token must change for the affordance to react. (Resolved in FR4.)
- All four deepen-plan hard gates pass: User-Brand Impact (threshold `none`, non-sensitive paths), Observability (documented skip), no PAT-shaped vars, committed `.pen` for the UI surface.

## Overview

The Knowledge Base sidebar (the expanded KB **nav rail**, an `<aside>`) is widened by a thin right-edge drag handle. Today that handle paints its grip affordance as three faint vertical dots (`•••`) centered on the edge. The dots are low-contrast (`bg-soleur-text-muted`, two 2px dots), small (`h-0.5 w-0.5` each), and read as decorative rather than as a "you can drag this" control.

This plan replaces the dot triad with a **clearer straight vertical bar** — a single dedicated grip element/block running along the right edge of the sidebar, so the resize affordance is more visible and more obviously draggable. The grip is moved into its own clearly-named element (its own `<span>`/`<div>` block) rather than the three loose dot spans.

**Scope is the sidebar only.** Per the feature description ("the Knowledge Base **sidebar** … the right edge of the **sidebar** … slide/resize the **sidebar**"), the target is the KB nav-rail widener: `apps/web-platform/components/dashboard/rail-resize-handle.tsx`. The two react-resizable-panels `Separator`-based handles that share the same dot idiom (`kb-desktop-layout.tsx` doc/chat splitter, `c4-workspace.tsx` C4-panel splitter) are *panel splitters between two content panes*, not the sidebar, and are addressed as an explicit consistency decision below (see Research Reconciliation + Alternatives), not as in-scope edits.

This is a pure presentational change: **no change** to the handle's behavior (pointer drag, keyboard Arrow nudge, clamping), its persistence (`onWidthChange` transient / `onCommit` persisted), its props, its `data-testid`, or its a11y contract (`role="separator"`, `aria-orientation`, `aria-valuenow/min/max`, `tabIndex`).

**No new dependencies.** The change is a Tailwind/JSX edit to one component plus an optional test assertion on the new grip element.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Reality (codebase) | Plan response |
| --- | --- | --- |
| "the resize/drag handle … renders as a faint '…' (vertical dots) on the right edge of the sidebar" | Confirmed. `rail-resize-handle.tsx:105-107` renders three `<span class="h-0.5 w-0.5 rounded-full bg-soleur-text-muted …">` dots (line 104 is the centering `<div>` wrapper, line 108 its `</div>`), `gap-0.5`, absolutely centered on the `inset-y-0 right-0 w-1` handle. | Replace the dot spans (105-107) inside the wrapper `<div>` (104-108) with a single vertical-bar grip element. |
| Implies a single "the KB sidebar handle" | There are **three** instances of the identical dot idiom: `rail-resize-handle.tsx` (the sidebar rail — the target), `kb-desktop-layout.tsx:23-27` (doc⇄chat `Separator`), `c4-workspace.tsx:25-29` (C4-panel `Separator`). | Scope to `rail-resize-handle.tsx` (the sidebar). The other two are content-pane splitters, out of scope; consistency follow-up tracked (see Alternatives + Deferral). |
| "Move it into its own element/block rather than the current dots affordance" | The dots already sit in a centered flex `<div>` wrapper (`pointer-events-none absolute inset-y-0 left-1/2 …`). | Keep a single wrapper block but render ONE bar element with a clear class/`data-testid`, not three dot spans. |
| (token to use is unspecified) | `globals.css` has `soleur-border-default`, `soleur-border-emphasized` (gold "strong"), `soleur-text-secondary`, `soleur-text-muted`, `bg-amber-500`. No `soleur-border-strong`. The handle container's own hover is `hover:bg-soleur-text-secondary/50` (a translucent wash *behind* the grip), active is `bg-amber-500/50`. | **Bar idle uses `bg-soleur-text-muted`, `group-hover:bg-soleur-text-secondary`** — preserving the dots' real idle→hover brighten step (`text-muted` → `text-secondary`). Do NOT set idle to `text-secondary` with `group-hover:text-secondary` — that is a no-op (same token both states). As a solid taller bar, even the `text-muted` idle is far more visible than the old 2px dots. |
| (corner shape unspecified) | `frontend-anti-slop` rule `BRAND-NONZERO-CORNER` (medium/advisory, exit 0) flags `rounded-full`/`rounded`. The current dots use `rounded-full` → already 3 advisory findings × 3 files. Brand mandates 0px sharp corners. | The straight bar uses **no `rounded-*` class** (sharp corners, brand-compliant), which *removes* the pre-existing advisory finding for the sidebar handle. No `anti-slop:disable` annotation needed. |
| (test coupling unknown) | `test/rail-resize-handle.test.tsx` asserts ONLY ARIA semantics + pointer/keyboard interaction + clamping. No assertion on the dot markup. No other test asserts on the dots. | Change does not break any existing test. Add ONE assertion that the new grip element renders (so the affordance can't silently disappear). |

## User-Brand Impact

**If this lands broken, the user experiences:** the KB sidebar resize affordance is visually missing or misrendered (e.g., an invisible/clipped bar, or a bar that overlaps content) on the dashboard KB rail — the handle still *functions* (pointer + keyboard paths are untouched) but the user can no longer *see* where to grab to resize, which is the exact problem this change set out to fix.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is a presentational CSS/markup change to a chrome control. It reads no user data, makes no network call, touches no auth/storage/billing surface, and persists only the existing rail-width integer the component already persisted.

**Brand-survival threshold:** none — reason: purely presentational chrome change to one resize-handle grip; worst case is a cosmetic regression on a single non-data control, fully covered by the component unit test + the wireframe sign-off, with no data, auth, or money surface touched.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — The dot triad is gone: `grep -c 'rounded-full' apps/web-platform/components/dashboard/rail-resize-handle.tsx` returns `0` (the three `rounded-full` dot spans are removed). The file contains no three-`<span>` grip group.
- [ ] AC2 — A single vertical-bar grip element exists in its own block: the component renders exactly one grip element carrying a stable hook (`data-testid="kb-rail-resize-grip"`), and `grep -c 'kb-rail-resize-grip' apps/web-platform/components/dashboard/rail-resize-handle.tsx` returns `1`.
- [ ] AC3 — The bar uses sharp corners (brand-compliant): the new grip element's className contains no `rounded` token; `grep -E 'kb-rail-resize-grip' -A1 apps/web-platform/components/dashboard/rail-resize-handle.tsx | grep -c 'rounded'` returns `0`.
- [ ] AC4 — The bar uses wired design tokens, not raw hex: `grep -E '\[#' apps/web-platform/components/dashboard/rail-resize-handle.tsx` returns no match (BRAND-RAW-HEX clean).
- [ ] AC5 — The handle's a11y + interaction contract is unchanged: `apps/web-platform/test/rail-resize-handle.test.tsx` still passes verbatim (no edit to its existing 6 assertions). Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/rail-resize-handle.test.tsx`.
- [ ] AC6 — A new test asserts the bar grip renders: `test/rail-resize-handle.test.tsx` gains one `it(...)` that does `screen.getByTestId("kb-rail-resize-grip")` and asserts it is in the document; the full file passes via the AC5 command.
- [ ] AC7 — Typecheck clean: `cd apps/web-platform && npm run typecheck` (declared script = `tsc --noEmit`; equivalently `./node_modules/.bin/tsc --noEmit`) exits 0.
- [ ] AC8 — `transition-colors` (not `transition-all`) is preserved on the handle container; `grep -c 'transition-all' apps/web-platform/components/dashboard/rail-resize-handle.tsx` returns `0`.
- [ ] AC9 — The wireframe `.pen` produced by the Product/UX gate exists on disk (non-empty) under `knowledge-base/product/design/kb/` and is referenced in this plan's FR list.

### Post-merge (operator)

- [ ] AC10 — Visual confirmation on the deployed dashboard KB rail: the resize handle shows a clear vertical bar on the sidebar's right edge; hover/active highlight still fires. Automation: Playwright MCP navigates to the dashboard KB route, drills into KB to expand the rail, screenshots the `[data-testid="kb-rail-resize-handle"]` region, and asserts the `kb-rail-resize-grip` element is visible (run in `/soleur:ship` post-merge verification or `/soleur:test-browser`). Not operator-eyeball — driven by Playwright.

## Functional Requirements

- FR1 — Remove the three dot `<span>`s (`rail-resize-handle.tsx:105-107`); the centering `<div>` wrapper (104/108) is reused to hold the single bar (or replaced by a bar that centers itself).
- FR2 — Render a single **vertical bar** grip element in its own block: a `<span>` positioned on the handle's right-edge centerline, taller than wide — **`w-0.5 h-8`** (2px wide, 32px tall), a short *centered* grip (reads as a grip, not a full-height border), centered with `top-1/2 -translate-y-1/2` (or `inset-y-0` + flex centering), with `pointer-events-none` so the parent handle keeps owning the drag. (Decision: `h-8` short grip, NOT full-height — resolved at plan time, not deferred.)
- FR3 — Give the bar a stable hook `data-testid="kb-rail-resize-grip"` and a self-descriptive class so the affordance is its own named block (not three anonymous dots).
- FR4 — Idle color `bg-soleur-text-muted`; hover brighten `group-hover:bg-soleur-text-secondary` (preserves the dots' real idle→hover contrast step). **Do NOT set idle to `text-secondary` with `group-hover:text-secondary` — same token both states is a silent no-op.** The handle container's existing `hover:bg-soleur-text-secondary/50` wash + `active:bg-amber-500/50` (gold) remain on the parent and continue to provide the hover/active backdrop. No new color literals, no raw hex.
- FR5 — Sharp corners: the bar carries **no** `rounded-*` class (brand 0px mandate).
- FR6 — Preserve verbatim: the handle container's `role="separator"`, `aria-orientation`, `aria-label`, `aria-valuenow/min/max`, `tabIndex`, `data-testid="kb-rail-resize-handle"`, pointer handlers, keyboard handler, clamp logic, `transition-colors duration-150`, `hidden md:block`, `cursor-col-resize`, `touch-none`, and the `RailResizeHandleProps` interface.
- FR7 — Update the component's leading comment block to describe the "vertical bar grip" idiom instead of "amber-active grip dots" so the file's self-doc matches the markup.
- FR8 — Wireframe reference: the Product/UX gate `.pen` at `knowledge-base/product/design/kb/<file>.pen` is the visual source of truth for bar dimensions, vertical extent, and idle/hover/active color steps.

## Files to Edit

- `apps/web-platform/components/dashboard/rail-resize-handle.tsx` — replace the dot triad (the three spans at 105-107, inside the centering wrapper `<div>` spanning 104-108) with the single vertical-bar grip block (FR1-FR5, FR7); leave everything else untouched (FR6).
- `apps/web-platform/test/rail-resize-handle.test.tsx` — add one `it(...)` asserting `getByTestId("kb-rail-resize-grip")` is present (FR3/AC6). Do not modify the existing 6 assertions.

## Files to Create

- `knowledge-base/product/design/kb/kb-sidebar-resize-handle-bar.pen` — wireframe of the sidebar right-edge with the vertical-bar grip in idle/hover/active states (produced by the Product/UX gate, Phase 2.5).

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references `rail-resize-handle.tsx`, `kb-desktop-layout.tsx`, or `c4-workspace.tsx` (checked at plan time; the plan's Files-to-Edit list is the query set).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
- Confirm `rail-resize-handle.tsx:104-108` still contains the three-`rounded-full`-span grip (the markup the plan targets): `grep -n 'rounded-full' apps/web-platform/components/dashboard/rail-resize-handle.tsx` → 3 hits at 105/106/107.
- Confirm the test glob collects the test: `grep -n 'include' apps/web-platform/vitest.config.ts` shows jsdom project `test/**/*.test.tsx` (the file matches).
- Confirm tokens exist: `grep -n 'soleur-text-secondary\|soleur-text-muted' apps/web-platform/app/globals.css`.

### Phase 1 — Replace the grip markup (FR1-FR5, FR7)
- Edit `rail-resize-handle.tsx`: swap the inner flex-column-of-dots `<div>` for a single vertical-bar grip element in its own block with `data-testid="kb-rail-resize-grip"`, idle `bg-soleur-text-secondary`, no `rounded-*`, `pointer-events-none`, vertically centered, dimensions per the wireframe.
- Update the file's leading comment (FR7) to say "vertical bar grip" not "grip dots".
- Keep the outer handle `<div>` and all its attributes/handlers byte-for-byte (FR6).

### Phase 2 — Test (FR3/AC6)
- Add one `it("renders the vertical-bar grip", …)` to `test/rail-resize-handle.test.tsx` asserting `screen.getByTestId("kb-rail-resize-grip")` is in the document. Leave the existing 6 tests untouched.

### Phase 3 — Verify (AC1-AC8)
- `cd apps/web-platform && npm run typecheck` (declared script = `tsc --noEmit`) (AC7).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/rail-resize-handle.test.tsx` (AC5/AC6).
- Run the AC1-AC4/AC8 greps.
- Optional: run the frontend-anti-slop scanner on the file to confirm the advisory `rounded-full` finding is gone and no new HIGH finding appeared.

## Research Insights

**Verify-the-negative pass (all claims grep-confirmed against `main`/worktree state):**

- Dots live at `rail-resize-handle.tsx:105-107` (wrapper `<div>` 104, `</div>` 108) — plan corrected from the off-by-one "104-108".
- `test/rail-resize-handle.test.tsx` (1-78) asserts ONLY ARIA + pointer/keyboard/clamping — zero references to `rounded-full`, `h-0.5`, child-span count, or `innerHTML`. Removing the dots breaks no assertion. **Confirmed.**
- `git grep 'rounded-full\|h-0.5 w-0.5' apps/web-platform/test/` → only unrelated button-shape hits (`auto-run-chip.test.tsx:39`, `theme-toggle.test.tsx:209,226`); zero on the grip markup. **No test depends on the dots.**
- Tokens confirmed in `globals.css`: `soleur-text-secondary` (`:51-52`, `:75-76`, `:130-131`) and `soleur-text-muted` (same blocks). **Both exist.**
- `vitest.config.ts:64` jsdom/component project `include: ["test/**/*.test.tsx"]` — the test path matches. **Confirmed.**
- `frontend-anti-slop` `BRAND-NONZERO-CORNER` is `medium`/advisory (exit 0, non-blocking) per `slop-rules.md:32,36`. A bar with no `rounded-*` class emits no finding. **Confirmed — net brand-compliance improvement** (the 3 `rounded-full` dots are an existing advisory finding this change removes for the sidebar handle).
- Exactly 3 files carry the dot-triad idiom (`rail-resize-handle.tsx`, `kb-desktop-layout.tsx`, `c4-workspace.tsx`); no 4th. **Confirmed** (scope split holds).
- Typecheck: `apps/web-platform/package.json` declares `"typecheck": "tsc --noEmit"`; repo root has no `workspaces` field. Canonical form is `npm run typecheck` from `apps/web-platform`. **Confirmed.**

**Implementation sketch (the entire grip diff):**

```tsx
// rail-resize-handle.tsx — replace the dot-triad <div> (104-108) with:
<div className="pointer-events-none absolute inset-y-0 left-1/2 flex -translate-x-1/2 items-center justify-center">
  <span
    data-testid="kb-rail-resize-grip"
    className="h-8 w-0.5 bg-soleur-text-muted group-hover:bg-soleur-text-secondary"
  />
</div>
```

- Idle `bg-soleur-text-muted` → `group-hover:bg-soleur-text-secondary` is a *real* brighten (avoids the same-token no-op). The parent handle's `hover:bg-soleur-text-secondary/50` wash + `active:bg-amber-500/50` gold stay on the container and back the bar on hover/active.
- `w-0.5 h-8` (2px × 32px) short centered grip; no `rounded-*` (sharp corners); `pointer-events-none` keeps the drag on the parent `<div>`.
- Simplicity review acknowledged: the AC/FR set is deliberately verification-shaped (the greps are the contract `/work` checks against). AC9/FR8 (`.pen`) are retained because `wg-ui-feature-requires-pen-wireframe` is non-skippable for a `components/**/*.tsx` surface; the wireframe is a gate deliverable, and the bar's dimensions/colors are fixed in FR2/FR4 (not deferred to the renders).

## Domain Review

**Domains relevant:** Product (UI surface).

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — Files-to-Edit includes `components/**/*.tsx`)
**Decision:** reviewed (pipeline — wireframes ready for async review; no interactive pause per Phase 2.5 step 4b headless arm)
**Agents invoked:** cpo, ux-design-lead
**Skipped specialists:** none (no domain leader recommended copywriter → Content Review Gate skipped)
**Pencil available:** yes (headless CLI Tier 0; Node v24.15.0 ≥ 22.9.0; `PENCIL_CLI_KEY` present in Doppler soleur/dev)

#### Findings

- **Wireframe produced (not deferred):** `knowledge-base/product/design/kb/kb-sidebar-resize-handle-bar.pen` (30,248 bytes, non-empty) with high-res renders under `knowledge-base/product/design/kb/screenshots/` (`01-resize-handle-idle.png`, `02-resize-handle-hover.png`, `03-resize-handle-active-dragging.png`). Shows three states: IDLE (2px × 36px bar, `#848484` / `soleur-text-secondary`, sharp 0px corners, 12px hit-zone), HOVER (subtle white wash + brighter bar), ACTIVE (gold `#C9A962` handle background + white bar). Confirms FR2-FR5 dimensions and the idle→hover→active color progression.
- **CPO advisory: Approve as written.** Brand-compliant (improves compliance — removes the existing `BRAND-NONZERO-CORNER` advisory from the `rounded-full` dots; sharp-corner bar aligns with `brand-guide.md:266`). Constitutionally minimal (minimalism ladder). a11y-safe (contract frozen, FR6). No flow gaps, no cross-domain flags, no data/auth/money surface.
- **CPO on scope split: sound — ship the sidebar alone.** The dot idiom appears in 3 places but only `rail-resize-handle.tsx` is an edge-of-`<aside>` widener; the other two are between-pane splitters where the bar idiom needs separate re-validation (border-vs-grip ambiguity differs). Doing all three now inflates a one-line change into a multi-component design exercise.
- **CPO refinement (applied):** the deferral follow-up issue must be framed as a *design question* ("does the vertical-bar idiom work centered between two panes, or do pane-splitters want a different treatment?"), not a mechanical "make the other two match." Captured in the Deferral Tracking section below.

## Observability

Skipped — pure presentational client-component change. No new `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/` code; no new error path, log call, network call, or failure mode. The only "failure mode" is a CSS/markup cosmetic regression, caught by the component unit test (AC5/AC6) and the post-merge Playwright visual check (AC10), neither of which requires SSH.

## Infrastructure (IaC)

Skipped — no new server, service, cron, secret, vendor, DNS record, or persistent runtime process. Edits live entirely under `apps/web-platform/components/` and `apps/web-platform/test/`.

## Test Scenarios

1. **Grip renders** — mount `RailResizeHandle`; `getByTestId("kb-rail-resize-grip")` is present (new, AC6).
2. **a11y unchanged** — existing: `role=separator`, `aria-orientation=vertical`, `aria-valuenow/min/max`, `tabindex=0` (AC5).
3. **Drag unchanged** — existing: pointerDown→move fires `onWidthChange(324)`, no commit until pointerUp→`onCommit(324)` (AC5).
4. **Clamp unchanged** — existing: drag past max → 480, below min → 224 (AC5).
5. **Keyboard unchanged** — existing: ArrowRight/Left nudge ±16 clamped, commit each step (AC5).
6. **No-drag move ignored** — existing (AC5).

## Alternatives Considered

| Alternative | Decision | Rationale |
| --- | --- | --- |
| Also restyle `kb-desktop-layout.tsx` + `c4-workspace.tsx` `Separator` grips in the same PR for consistency | **Deferred** (not in scope) | The feature explicitly names "the **sidebar**"; those two are content-pane splitters, not the sidebar. They share the idiom, so a consistency pass is reasonable but is a distinct decision (the bar idiom must be re-validated for a between-panels context, not an edge-of-aside context). Tracked as a deferral issue. |
| Keep `rounded-full` on the new bar (pill shape) | Rejected | Brand mandates 0px sharp corners (`BRAND-NONZERO-CORNER`); a sharp bar is on-brand and removes the existing advisory finding. |
| Use `soleur-border-emphasized` (gold) for the idle bar | Rejected for idle | Gold is the active/accent state (`bg-amber-500/50`); using it idle would erase the idle→active contrast step. Idle uses `soleur-text-secondary`; active stays gold. (Final call confirmed by wireframe.) |
| Make the bar the full handle height (`inset-y-0`, edge-to-edge) | Wireframe decision | A short centered bar reads as a grip; a full-height bar reads as a border. Defer the exact extent to the wireframe; FR2 allows either via `inset-y-0` centering. |

## Deferral Tracking

- **Deferred:** restyling the two `Separator`-based panel splitters (`kb-desktop-layout.tsx`, `c4-workspace.tsx`) to match the new bar idiom. **Why:** out of scope (they are not "the sidebar"); the bar idiom needs re-validation for a between-two-panels context. **Re-evaluation criteria:** after this PR ships, open a follow-up framed as a *design question* (per CPO refinement) — "does the vertical-bar grip idiom work centered between two content panes, or do pane-splitters want a different treatment (border-vs-grip ambiguity differs from an edge-of-`<aside>` widener)?" — NOT a mechanical "make the other two match." **Milestone:** post-MVP / UI polish. Action: file a `gh issue` at ship time (or note in PR body) so the overlap is not invisible.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a concrete artifact, vector (N/A), and `threshold: none` with a non-empty reason.
- The new grip element MUST keep `pointer-events-none`; if it captures pointer events, drags that start exactly on the bar would target the grip instead of the handle `<div>` and the drag-start `clientX` bookkeeping on the parent would not fire.
- Do NOT add a `rounded-*` class to the bar — it reintroduces the `BRAND-NONZERO-CORNER` advisory finding the change is removing (AC3).
- Typecheck for `apps/web-platform` MUST be run from inside `apps/web-platform` — `npm run typecheck` (declared script) or `./node_modules/.bin/tsc --noEmit` — NOT `npm run -w apps/web-platform typecheck` (the repo root `package.json` has no `workspaces` field, so the `-w` form aborts with "No workspaces found").
- The vitest invocation MUST be `./node_modules/.bin/vitest run <path>` from `apps/web-platform` (the package runner is vitest, and the test path `test/rail-resize-handle.test.tsx` matches the jsdom `test/**/*.test.tsx` include glob).
