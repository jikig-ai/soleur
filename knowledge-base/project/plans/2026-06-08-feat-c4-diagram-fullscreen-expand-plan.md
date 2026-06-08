---
title: "feat: C4 diagram fullscreen / expand control"
date: 2026-06-08
branch: feat-one-shot-c4-diagram-fullscreen-expand
type: feature
lane: single-domain
status: planned
---

# ✨ feat: C4 diagram fullscreen / expand control

## Enhancement Summary

**Deepened on:** 2026-06-08

### Key Improvements
1. **Native-API verdict pinned to installed source.** Confirmed against v1.50.0 type defs +
   Context7 that `LikeC4Diagram` has no native fullscreen prop and the native `browser` modal
   is bound to the wrong (`LikeC4View`, ShadowRoot) component → custom overlay is correct.
2. **Read-only invariant verified-the-negative.** Grepped that `C4Canvas` imports no
   Code/Concierge component; added the implementation guard "re-parent `C4Canvas` subtree only".
3. **Test mock shape captured.** The new test must override `useLikeC4ViewModel` to non-null,
   else the canvas (+ expand button) never renders under the established mock.
4. **Portal precedent identified** (4 existing `createPortal` sites) — no new dependency.
5. **UI-wireframe gate satisfied.** `.pen` produced via Pencil covering BOTH toggle states
   (inline + fullscreen overlay), committed + referenced.

### New Considerations Discovered
- Single-canvas-re-parent vs double-mount: a re-mount resets the viewport (`fitView` re-fits,
  losing the user's pan) → keep one mount with lifted `currentView` state; documented as a
  Sharp Edge with a fallback.
- `LikeC4View`'s `browser` modal conflicts with `enableFocusMode` — a second reason not to
  switch components to get the native modal.

## Overview

Add a "fullscreen / expand" control to the LikeC4 C4 diagram so a viewer can maximize the
inline diagram to fill the browser viewport and collapse back. The control must appear on
**both** consumers of the shared `C4Canvas`:

1. The **public read-only shared-document viewer** — `app/shared/[token]/page.tsx` → `C4Diagram` (readOnly).
2. The **authenticated KB viewer** — `c4-workspace.tsx` (LEFT diagram pane) and the inline
   `C4Diagram` embed in `markdown-renderer.tsx`.

Because every diagram render flows through one shared component — `C4Canvas` in
`apps/web-platform/components/kb/c4-shared.tsx` — the expand control is added **once** to
`C4Canvas` and is inherited for free by all three call sites. This is a **pure client-side
view enhancement**: no share-link, route, or data-endpoint changes.

Read-only/public context MUST stay read-only: fullscreen exposes **no** edit / Concierge /
Code affordances — it only maximizes the read-only diagram canvas. (The Code tab and
Concierge panel live OUTSIDE `C4Canvas`, in `c4-diagram.tsx` / `c4-workspace.tsx`, so they
are structurally excluded from the fullscreen overlay by construction.)

Builds on web-v0.114.1's public shared-document diagram render (PR #5007, merged 2026-06-08).

## Research Reconciliation — Spec vs. Codebase

The feature description instructed: "FIRST check the installed `@likec4/diagram` version's
API for a native fullscreen/maximize control or `LikeC4Browser` modal … prefer it over a
custom overlay." This was investigated against the installed source (v1.50.0). Findings:

| Premise (from feature description) | Reality (verified in installed v1.50.0) | Plan response |
|---|---|---|
| `@likec4/diagram` may expose a native fullscreen/maximize control on the diagram toolbar | `LikeC4DiagramProperties` (`dist/LikeC4Diagram.props.d.ts`) has **no** `fullscreen` / `maximize` / `browser` prop. The full prop set is `pannable, zoomable, controls, fitView, fitViewPadding, nodesSelectable, background, showNavigationButtons, enableNotations, enableRelationshipDetails, enableFocusMode, enableSearch, enableElementDetails, enableRelationshipBrowser, enableDynamicViewWalkthrough, enableCompareWithLatest, dynamicViewVariant, enableElementTags, enableNotes, reduceGraphics, renderIcon, renderNodes, where, reactFlowProps`. None maximizes the canvas. | Native prop unavailable on the used component → custom overlay. |
| There may be a `LikeC4Browser` / fullscreen modal to enable | A `browser` prop ("Click on the view opens a modal with browser", default true) and `LikeC4BrowserProps` exist **only on `LikeC4View`** (`dist/LikeC4View.d.ts`) — a *different, higher-level* component the codebase does NOT use. `LikeC4View` is `ShadowRoot`-wrapped (breaks the `.soleur-c4` theme scoping per learning `2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet.md`), is **click-to-open** (not an explicit button), and its docstring states `browser` **conflicts with `enableFocusMode`** which `ViewCanvas` currently sets. An internal `Overlay` with `fullscreen?: boolean` exists at `dist/overlays/overlay/Overlay.d.ts` but is **NOT re-exported** from the package `index.d.ts` (no public import path). `DiagramApi` (`dist/hooks/useDiagram.d.ts`) exposes no `openOverlay`/`fullscreen`/`maximize` method. | Native modal is bound to the wrong component and the only fullscreen primitive is internal/unexported → **a minimal custom overlay is the correct call** (not reinventing — the library does not expose this for the component in use). Context7 (`/likec4/likec4`) confirms `LikeC4Diagram` supports composition: "render custom React components inside the diagram, such as panels or portal elements." |
| The inline embed uses a fixed-height container (`h-[600px]`) | Confirmed: `c4-diagram.tsx:80` wraps `C4Canvas` in `<div className="relative h-[600px] w-full">`. `c4-workspace.tsx:104` uses `min-h-0 flex-1`. The overlay must escape BOTH container geometries. | Overlay uses `position: fixed; inset: 0` so it is independent of the parent's height clamp. |

**Premise Validation:** PR #5007 ("render LikeC4 diagram on public /shared document links")
is present on the branch base (commit `90000d0da`). The cited prior art exists; the
`readOnly` plumbing in `c4-diagram.tsx` + the shared page (`app/shared/[token]/page.tsx:173`)
exists as described. No stale premises.

## User-Brand Impact

**If this lands broken, the user experiences:** a diagram that won't expand, an expand
button that opens an empty/black overlay, or — worst case — an expand overlay on the public
share link that leaks an owner-only affordance (Code/Concierge) to an anonymous recipient.

**If this leaks, the user's workflow/data is exposed via:** an edit/Concierge/Code control
reachable from the public read-only overlay. This is structurally prevented: `C4Canvas`
renders ONLY the diagram; the Code tab and Concierge panel are siblings in the parent
components, never children of `C4Canvas`, so they cannot enter the overlay. The overlay also
inherits no `fetchUrl`/`dirPath` write context — it re-parents the already-mounted
read-only canvas.

**Brand-survival threshold:** none — this is a client-side view toggle over an already-public,
already-read-only render. No new data surface, no new write path, no regulated data. The
diff touches only `apps/web-platform/components/kb/*.tsx` + a component test (no sensitive
path per preflight Check 6).
threshold: none, reason: client-side view-maximize toggle over an existing read-only canvas; no data, auth, or write surface is added.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Expand control present.** `C4Canvas` renders an "Expand" / fullscreen
  toggle button inside the `.soleur-c4` wrapper, positioned so it does not overlap the
  LikeC4 top-left controls panel (top-RIGHT of the canvas). `grep -nE 'aria-label="(Expand|Enter fullscreen|Maximize)' apps/web-platform/components/kb/c4-shared.tsx` returns ≥1.
- [ ] **AC2 — Fullscreen fills viewport.** Activating expand renders the canvas in a
  `position: fixed; inset: 0` overlay at `z-index` above app chrome. Verified by a vitest
  happy-dom component test asserting the overlay container carries `fixed inset-0` (or the
  resolved class) and `role="dialog"` + `aria-modal="true"`.
- [ ] **AC3 — Collapse paths.** The overlay closes on (a) Escape keydown and (b) a
  close/collapse button. Test asserts `keydown{Escape}` calls the close handler and the
  overlay unmounts; the collapse button has `aria-label="Exit fullscreen"` (or "Collapse").
- [ ] **AC4 — Read-only stays read-only.** No edit / Concierge / Code affordance is rendered
  inside the overlay. Test mounts `C4Canvas` (the only thing the overlay re-parents) and
  asserts no `textContent` match for `/Code|Concierge|Save/` originates from the overlay
  subtree. (Structural: `C4Canvas` never imports `C4CodePanel`/`KbChatContent`.)
- [ ] **AC5 — Theme scoping preserved.** The fullscreen overlay subtree is wrapped in
  `.soleur-c4` so the scoped re-theme (`c4-theme.css`) applies in fullscreen exactly as
  inline. Test asserts a `.soleur-c4` ancestor exists in the overlay DOM.
- [ ] **AC6 — Scroll-lock.** While the overlay is open, `document.body` (or the documentElement)
  gets `overflow: hidden`; on close it is restored to its prior value. Test asserts
  body overflow is `"hidden"` while open and restored on unmount.
- [ ] **AC7 — Pan/zoom/drill-down preserved.** The `LikeC4Diagram` in fullscreen keeps
  `pannable zoomable fitView controls showNavigationButtons enableElementDetails
  enableRelationshipDetails enableFocusMode onNavigateTo` (same prop set as inline). Drill-down
  state (`currentView`) is shared — see Design note (single mounted canvas re-parented, NOT a
  second `LikeC4Diagram` instance). Test asserts the same view-change callback drives both states.
- [ ] **AC8 — Inline-container independence.** Expand works from inside the `h-[600px]`
  fixed-height embed container — the overlay is NOT clipped by the parent. Verified
  structurally: overlay is rendered via `createPortal(…, document.body)` so it escapes the
  `overflow-hidden rounded-lg` parent in `c4-diagram.tsx:44`.
- [ ] **AC9 — Typecheck + tests green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  passes, and `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-fullscreen.test.tsx`
  passes. (Repo root has no `workspaces` field — the `-w` form fails; per Sharp Edges.)
- [ ] **AC10 — A11y focus management.** On open, focus moves into the overlay (the close
  button or a focusable element); on close, focus returns to the expand button that opened it.
  Test asserts `document.activeElement` is inside the overlay after open.

### Post-merge (operator)

- [ ] **AC11 — Visual QA on both surfaces.** Playwright MCP screenshot of (a) authenticated
  KB diagram page expanded, (b) public `/shared/<token>` diagram expanded, confirming the
  overlay fills the viewport, the theme is intact, and no Code/Concierge control is visible
  on the public surface. Automation: feasible via `mcp__playwright__*` — see `/soleur:qa`.
  (Falls to post-merge because it needs a live share token + deployed build.)

## Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

- [ ] **0.1** Re-confirm `@likec4/diagram@1.50.0` has no `fullscreen`/`browser` prop on
  `LikeC4Diagram`: `grep -niE 'fullscreen|maximize|browser' apps/web-platform/node_modules/@likec4/diagram/dist/LikeC4Diagram.props.d.ts` returns empty. (If a future bump adds it, prefer the native prop — re-evaluate this plan.)
- [ ] **0.2** Confirm `createPortal` is the codebase portal convention:
  `grep -rn "createPortal" apps/web-platform/components --include="*.tsx" | head`. Reuse it;
  do not add a new portal lib.
- [ ] **0.3** Confirm the Esc/`role="dialog"`/`useId` modal pattern to mirror at
  `apps/web-platform/components/ui/typed-confirm-modal.tsx` (Esc handler via `window.addEventListener("keydown")`, `aria-modal`, focus-on-open via `requestAnimationFrame`).

### Phase 1 — RED: failing component test

- [ ] **1.1** Write `apps/web-platform/test/c4-fullscreen.test.tsx` (vitest, happy-dom —
  must live under `test/**/*.test.tsx` per `vitest.config.ts:60`; co-located component
  tests are silently skipped). Cover AC1–AC8 + AC10. Mock `@likec4/diagram`'s
  `LikeC4Diagram`/`LikeC4ModelProvider`/`useLikeC4ViewModel` the same way the existing
  `test/c4-shared.test.tsx` / `test/c4-diagram.test.tsx` do (read those first for the
  established mock shape — do NOT invent a new mock).
- [ ] **1.2** Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-fullscreen.test.tsx`
  and confirm it fails for the right reason (no expand control yet).

### Phase 2 — GREEN: expand control + overlay in `C4Canvas`

- [ ] **2.1** In `c4-shared.tsx`, refactor `C4Canvas` so the diagram render
  (`LikeC4ModelProvider` + `ViewCanvas`) is wrapped by a new `expanded` state. Add an
  "Expand" button overlaid on the canvas (top-right, absolutely positioned inside the
  `.soleur-c4`-relative container).
- [ ] **2.2** When `expanded`, render the SAME diagram via `createPortal(…, document.body)`
  inside a `fixed inset-0 z-[<above-chrome>]` overlay that ALSO carries the `.soleur-c4`
  wrapper class (so `c4-theme.css` applies). Use `role="dialog" aria-modal="true"` + an
  `aria-labelledby`/`aria-label`. Add a close button (`aria-label="Exit fullscreen"`).
  **Design — single shared canvas (avoid double-mount):** keep ONE `LikeC4Diagram` mount.
  Lift the drill-down `currentView` state in `C4Canvas` to drive whichever container is
  active (inline OR portal), so pan/zoom/drill-down state is identical across the toggle and
  there is no second WebGL/SVG canvas. The portal node hosts the SAME `LikeC4ModelProvider`
  subtree; do not instantiate a second `LikeC4Diagram` with divergent state. (If
  re-parenting a single instance proves impractical with React reconciliation, the fallback
  is two mounts that share the SAME lifted `currentView` setter — document whichever is used.)
- [ ] **2.3** Esc-to-close: `window.addEventListener("keydown")` gated on `expanded`
  (mirror `typed-confirm-modal.tsx:81-91`), cleaned up on unmount/close.
- [ ] **2.4** Scroll-lock: on open, save `document.body.style.overflow`, set `"hidden"`;
  restore on close/unmount.
- [ ] **2.5** Focus management: on open, focus the close button (`requestAnimationFrame`);
  store the opener element ref and restore focus to it on close.

### Phase 3 — Verify all three call sites inherit the control

- [ ] **3.1** No changes needed in `c4-diagram.tsx`, `c4-workspace.tsx`,
  `markdown-renderer.tsx`, or `app/shared/[token]/page.tsx` — they all render `C4Canvas`.
  Confirm by reading each: the expand button must appear in (a) inline embed, (b) readOnly
  shared embed, (c) workspace LEFT pane. If the `c4-diagram.tsx` parent's
  `overflow-hidden rounded-lg` clips the inline expand BUTTON (not the overlay — the portal
  escapes it), nudge the button inset so it stays visible; otherwise touch nothing.
- [ ] **3.2** Confirm the `h-[600px]` inline container does not clip the OVERLAY (it won't —
  portal renders to `document.body`). Confirm the button is visible within the 600px frame.

### Phase 4 — Typecheck + full lint

- [ ] **4.1** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] **4.2** `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-fullscreen.test.tsx test/c4-shared.test.tsx test/c4-diagram.test.tsx test/c4-workspace.test.tsx` (regression sweep on the C4 component tests touching `c4-shared.tsx`).

## Files to Edit

- `apps/web-platform/components/kb/c4-shared.tsx` — add expand state, button, portal overlay,
  Esc handler, scroll-lock, focus management to `C4Canvas` (and possibly `ViewCanvas`).

## Files to Create

- `apps/web-platform/test/c4-fullscreen.test.tsx` — vitest/happy-dom component test (AC1–AC8, AC10).
- `knowledge-base/product/design/kb-viewer/c4-diagram-fullscreen-expand.pen` — wireframe (DONE; committed) covering inline + fullscreen-overlay toggle states.

## Open Code-Review Overlap

None. Checked all 63 open `code-review` issues for body references to
`components/kb/c4-shared.tsx` and `test/c4-fullscreen.test.tsx` — zero matches (2026-06-08).

## Research Insights (deepen-plan)

**Native-API verdict (verified in installed v1.50.0).** `LikeC4Diagram` (the component the
codebase uses via `C4Canvas`→`ViewCanvas`) exposes no fullscreen/maximize/browser prop
(`dist/LikeC4Diagram.props.d.ts`). The native click-to-open `browser` modal lives only on the
distinct `LikeC4View` component (`dist/LikeC4View.d.ts:43`), which is ShadowRoot-wrapped
(would break `.soleur-c4` scoping) and conflicts with `enableFocusMode`. The `Overlay`
`fullscreen` primitive (`dist/overlays/overlay/Overlay.d.ts`) is NOT re-exported from
`index.d.ts`. Context7 (`/likec4/likec4`) confirms `LikeC4Diagram` supports composition
(custom panels/portal children) — a custom overlay is the sanctioned path, not reinvention.

**Verify-the-negative (read-only claim).** `C4Canvas`/`ViewCanvas` (c4-shared.tsx:94-172)
import and render NO `C4CodePanel`/`KbChatContent`/Concierge component. `C4CodePanel` IS
exported from the *same module* (`c4-shared.tsx:227`) but is a sibling export, not a child of
`C4Canvas`. **Implementation guard:** the overlay must re-parent the `C4Canvas`/`ViewCanvas`
subtree ONLY — never the module's `C4CodePanel` export. The read-only invariant holds by
construction; AC4 verifies it.

**Portal precedent (no new dep).** `createPortal` is already used in
`components/kb/selection-toolbar.tsx`, `components/ui/sheet.tsx`,
`components/dashboard/rail-slot.tsx`, `components/chat/conversations-rail-portal.tsx`. Reuse
`react-dom`'s `createPortal`; do not add a portal/focus-trap library.

**Test mock shape (load-bearing).** `test/c4-shared.test.tsx:7-16` mocks `@likec4/diagram`
with `LikeC4Diagram: () => <div data-testid="likec4-diagram" />`, `useLikeC4ViewModel: () => null`,
and `@likec4/core/model` `LikeC4Model.create: () => ({})`. With `useLikeC4ViewModel` returning
`null`, `ViewCanvas` short-circuits to the "View not found" branch and the canvas (and thus
the expand button) never renders. **The new `test/c4-fullscreen.test.tsx` MUST override
`useLikeC4ViewModel` to return a non-null `{ $view: {…} }`** so `ViewCanvas` renders the
diagram + expand button. Reuse the established mock for `@likec4/core/model`,
`@codemirror/theme-one-dark`, `@uiw/react-codemirror`. Imports use
`@testing-library/react` (`render, screen, fireEvent, waitFor`) — already the convention.

**Esc/scroll-lock/focus precedent.** Mirror `components/ui/typed-confirm-modal.tsx`:
`window.addEventListener("keydown")` gated on open (lines 81-91), `role="dialog"
aria-modal="true"`, focus-on-open via `requestAnimationFrame` (line 76). Note that
typed-confirm-modal deliberately does NOT Tab-trap; for a fullscreen diagram overlay a Tab
trap is lower-value (the overlay covers the whole viewport, nothing visible behind), so AC10
scopes to focus-IN-on-open + focus-RETURN-on-close, not a full Tab cycle trap — keep it
minimal (YAGNI).

## Test Scenarios

1. Inline KB embed (markdown-renderer): expand → fullscreen → Esc → collapse. Pan/zoom retained.
2. Public `/shared/<token>` readOnly embed: expand → fullscreen shows ONLY the diagram (no
   Code/Concierge) → close button → collapse. Theme intact.
3. Authenticated KB workspace LEFT pane: expand → fullscreen (Concierge/Code panel NOT in
   overlay) → Esc → collapse; Concierge panel state on the right is untouched.
4. Drill-down inside fullscreen: click a node that navigates to a child view → fullscreen
   updates → collapse → inline canvas shows the drilled-to view (shared state).
5. Scroll-lock: page does not scroll behind the overlay; restored after close.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold `none`
  with reason.)
- **Native-prop drift:** the verdict "no native fullscreen prop" is pinned to v1.50.0. If a
  future `@likec4/diagram` bump adds a `fullscreen`/`browser`-equivalent on `LikeC4Diagram`,
  prefer it over this overlay (Phase 0.1 re-checks). Do NOT switch to `LikeC4View` to get the
  native modal — it is ShadowRoot-wrapped (breaks `.soleur-c4` scoping) and conflicts with
  `enableFocusMode`.
- **Test path:** the component test MUST be `apps/web-platform/test/c4-fullscreen.test.tsx`.
  `vitest.config.ts:60` collects `test/**/*.test.tsx` only; a co-located
  `components/kb/*.test.tsx` is silently never run. bun test is fully blocked
  (`bunfig.toml` `pathIgnorePatterns = ["**"]`).
- **Typecheck command:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT
  `npm run -w apps/web-platform typecheck` (repo root declares no `workspaces`; the `-w`
  form aborts with "No workspaces found").
- **Single canvas, shared drill-down state:** instantiating a second `LikeC4Diagram` for the
  overlay would fork drill-down state and double the render cost; keep one mount with lifted
  `currentView`. Verify pan/zoom is retained across the toggle (a re-mount resets the
  viewport — `fitView` would re-fit and lose the user's pan). If a re-mount is unavoidable,
  document the viewport-reset as a known limitation and scope it for a follow-up.
- **Toggle-state alignment:** verify the expand button position in BOTH the inline
  (`h-[600px]`) and workspace (`flex-1`) containers — the parent geometry differs (per
  learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`).

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory — modifies an existing component (`c4-shared.tsx` under `components/**`,
which fires the mechanical UI-surface override), adds one button + a fullscreen overlay of
the SAME read-only canvas; no new page/flow/route, no new persuasive/emotional copy. In
pipeline context ADVISORY auto-accepts.
**Decision:** auto-accepted (pipeline)
**Agents invoked:** ux-design-lead (wireframe producer — one-shot path, plan is sole producer)
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

Wireframe committed at `knowledge-base/product/design/kb-viewer/c4-diagram-fullscreen-expand.pen`
(non-empty, git-tracked). It captures BOTH toggle states (per learning
`2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`):

1. **Inline / collapsed** (the `h-[600px]` embed): tab bar (Diagram | Code; Code hidden in
   readOnly), native LikeC4 controls anchored top-LEFT, and the new **Expand** button
   anchored top-RIGHT so it never collides with the native control cluster.
2. **Fullscreen / expanded overlay**: full-viewport dark backdrop (`position: fixed; inset: 0`
   via `createPortal` to `document.body`), native controls preserved top-left, an
   **Exit fullscreen** (minimize) button top-right with an "Esc to close" affordance, the
   maximized diagram, and an explicit read-only note — **no Code / Concierge / Save**
   affordance is present in fullscreen (the overlay re-parents ONLY `C4Canvas`).

Screenshots of both states are committed under
`knowledge-base/product/design/kb-viewer/screenshots/`. Design tokens follow the Soleur
palette already used in `c4-shared.tsx` (`soleur-bg-*`, `soleur-border-default`, amber accent).

## Observability

(Skipped — pure client-side React view toggle; no `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, or `plugins/*/scripts/` file in Files-to-Edit, and no new infrastructure
surface. Client render errors already flow to the app's existing Sentry boundary; no new
failure mode with a server-side liveness signal is introduced.)
