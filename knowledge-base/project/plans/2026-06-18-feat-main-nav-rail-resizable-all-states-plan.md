---
title: "feat: Make the MAIN nav rail resizable on every drill state (not KB-only)"
date: 2026-06-18
type: feat
branch: feat-one-shot-main-sidebar-resizable-all-states
lane: cross-domain
brand_survival_threshold: none
status: draft
---

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Design Decisions (D1), Acceptance Criteria, Implementation Phases, Files to
Edit, Test Scenarios, Research Insights
**Agents used:** architecture-strategist, code-simplicity-reviewer, verify-the-negative grep pass
(10/10 plan claims confirmed against code), repo-research-analyst, learnings-researcher,
functional-discovery.

### Key Improvements
1. **D1 reversed to ONE shared width key** (was: separate `soleur:sidebar.main.width`). The
   code-simplicity pass showed the "different ideal width" rationale is unsupported —
   `RAIL_MIN_PX === RAIL_DEFAULT_PX === 224` for both rails, so there is no asymmetry to justify
   two channels. One `useRailWidth()` instance now feeds both. Separate-keys is kept as a recorded,
   one-line operator-flippable alternative. Removed: a second hook instance, the cross-key isolation
   AC, one e2e literal.
2. **Single grip mount, branched props** (architecture P1). Phase 3 + AC1 now state explicitly: ONE
   `RailResizeHandle` under `!collapsed`, with only `ariaLabel` branched on `drill==="kb"` — never
   two co-existing JSX blocks (KB xor non-KB partitions "expanded", so a double-mount is a
   regression risk). The grip keeps the `kb-rail-resize-handle` testid (no second testid — the route
   disambiguates), dropping the `testId`/`gripTestId` props down to ONE `ariaLabel` prop.
3. **Demoted AC5/AC7/AC10 grep-guards to prose** (code-simplicity): they assert code the plan does
   not touch (gold color, kept button, ⌘B). Kept as a "Regression guards" note, not gated ACs.
4. **Added two guard ACs** (architecture P2): the grip must be a SIBLING of (not nested in) the
   `overflow-y-auto rail-secondary-slot` (AC7); the inverted e2e must run EXPANDED (AC-E2E-4).

### New Considerations Discovered
- **Mutual-exclusion is structural, not source-order:** `kbExpanded` and `mainExpanded` partition
  "expanded" (`segmentToDrillLevel` returns exactly one of kb|settings|chat|null), so the two
  `data-*-rail-width` attributes can never co-exist — the CSS-race risk the repo-research raised
  cannot occur. Verified against `segment-to-drill-level.ts:15`.
- **Analytics is a non-KB expanded state** (`/dashboard/admin/analytics` → `drill === null`), so it
  gets the main width + grip alongside Dashboard root. The shared key also governs the top-level
  PRIMARY nav (short labels), not just Settings/Chat — made explicit in D1.

# ✨ feat: Resizable MAIN nav rail across all drill states

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain`
> (TR2 fail-closed). In practice this is a single-domain web-platform frontend change;
> the default is conservative.

## Overview

Today the dashboard nav rail is **drag-to-resize only on the KB page**. The resize grip
(`RailResizeHandle`) mounts solely under the `kbExpanded` predicate
(`app/(dashboard)/layout.tsx:506`), and the rail's expanded width is a **fixed Tailwind
class** `md:w-56` (= 224px) everywhere except KB, where a CSS-var-driven width
(`--kb-rail-w` + `data-kb-rail-width`, consumed by an md+ rule in `globals.css:203-207`)
overrides it.

This plan makes the **main rail genuinely drag-to-resize in EVERY expanded drill state** —
Dashboard (top level), Analytics (admin), Settings, Chat — mirroring the KB rail, by:

1. **Mounting the grip whenever the rail is expanded on md+** (not KB-only). Replace the
   `kbExpanded`-only mount with an `railExpanded = !collapsed` mount, keeping the existing
   `hidden md:block` so it never shows on the mobile drawer.
2. **Making the main rail width CSS-var-driven** with persisted, user-adjustable width and
   sensible min/max — replacing the fixed `md:w-56` with a `--main-rail-w` var applied via a
   `data-main-rail-width` attribute (a sibling of the existing KB rule), so non-KB expanded
   states resize exactly like KB.
3. **Gold-on-active grip** (`soleur-accent-gold-fill`) while dragging or keyboard-focused,
   grey on hover — this is **already true** in the shipped `RailResizeHandle` (`:128`, gold
   `/70` active + focus-visible, grey hover). No color change is required; this plan only has
   to NOT regress it. The single substantive grip change is **de-KB-ifying the a11y label**
   (see Sharp Edges / FR4).
4. **Double-click collapses** — wire `onCollapse={toggleCollapsed}` (already done at `:513`)
   so it fires in every state the grip now mounts in. **Keep the existing floated collapse
   button** (`:367`) verbatim — the request explicitly says keep it.

This is UI chrome, brand-survival threshold `none` (matching PR #5477 / the 2026-06-18
gold+double-click plan's classification). It is **additive**: the floated `PanelToggleIcon`
button stays, ⌘B stays, the collapsed-rail behavior stays.

### Relationship to the 2026-06-18 merged work (READ FIRST)

The directly-preceding plan
(`2026-06-18-feat-sidebar-resizer-gold-active-doubleclick-collapse-plan.md`) shipped
**FR3-Alternative**: it KEPT the button, added gold-on-active to all 3 handles, and added
guarded double-click-to-collapse — but **deliberately did NOT widen the render gate**, leaving
the grip `kbExpanded`-only. That plan recorded (spec-flow + architecture-strategist) two
concerns about widening the gate which THIS plan must answer:

- **"a resize handle that doesn't resize" in 3/4 sections** — because outside KB the rail was
  fixed-width, a mounted grip would be decorative. **This plan removes that objection** by
  making the main rail genuinely resizable (change #2). The grip now resizes everywhere it
  mounts.
- **a11y misnaming** — `role="separator"` + `aria-valuenow` + `aria-label="Resize knowledge
  base sidebar"` rendered in Settings/Chat is factually wrong. **This plan resolves it** by
  parameterizing the grip's `aria-label` / `data-testid` (FR4). The KB mount keeps its current
  literals (so the KB e2e is untouched); non-KB mounts get a neutral "Resize sidebar" label.

The 2026-06-18 plan's CPO dissent ("keep the visible button for the Phase-4 non-technical
ICP") is **honored here** — the button stays. There is no discoverability regression: pointer
collapse (button + double-click), pointer expand (button), and ⌘B all remain.

## Research Reconciliation — Spec vs. Codebase

| Spec/request claim | Codebase reality | Plan response |
|---|---|---|
| "grip only renders when `kbExpanded` at `layout.tsx`" | TRUE — `{kbExpanded && <RailResizeHandle …/>}` at `:506`; `kbExpanded = drill === "kb" && !collapsed` (`:170`) | Widen mount to `railExpanded = !collapsed` (still `hidden md:block`, collapse still wins). |
| "main rail is a fixed `md:w-56` class" | TRUE — `${collapsed ? "md:w-14" : "md:w-56"}` at `:315`; KB overrides via `data-kb-rail-width` + globals.css `:204` | Add a `--main-rail-w` var + `data-main-rail-width` attribute for non-KB expanded states; KB keeps its own var/attr. |
| "grip turns gold on drag/focus, grey on hover" | ALREADY TRUE — `active:bg-soleur-accent-gold-fill/70 focus-visible:bg-soleur-accent-gold-fill/70 hover:bg-soleur-text-secondary/50` (`rail-resize-handle.tsx:128`) | No color change. Plan must not regress it; an AC asserts gold-active persists. |
| "double-click collapses; wire `onCollapse` to `toggleCollapsed`" | ALREADY wired at `:513` (`onCollapse={toggleCollapsed}`); handler exists at `rail-resize-handle.tsx:94` | No new wiring — widening the mount (change #1) is what makes it fire in non-KB states. |
| "keep the existing collapse button" | The floated `PanelToggleIcon` button at `:367-374` is the only pointer collapse/expand affordance, renders in ALL drill states | Keep it verbatim. NOT removed (this is the explicit divergence from the FR3-Literal direction). |
| "reuse RailResizeHandle + use-rail-width hook" | `RailResizeHandle` (component) + `useRailWidth(storageKey?)` (hook, key is injectable, `:48-50`) | Reuse both. ONE `useRailWidth()` instance (shared key — see D1), fed to whichever rail is expanded. |
| (implicit) `aria-label="Resize knowledge base sidebar"` is generic | KB-specific literal hardcoded at `rail-resize-handle.tsx:112` | Add ONE optional prop `ariaLabel` (default = current KB literal) so non-KB mounts say "Resize sidebar". The `data-testid`s stay as-is (KB xor non-KB never co-mount — route disambiguates; no second testid needed). |
| e2e "resize handle is KB-only — absent on Settings and Chat (AC13)" | TRUE — `nav-states-shell.e2e.ts:941-950` asserts `toHaveCount(0)` on Settings + Chat | **Invert** that test: assert the grip IS present + resizes on Settings/Chat (see Test Scenarios + FR5). |

## Design Decisions (resolved in planning)

### D1 — ONE shared persisted width across KB + non-KB rails (default; separate keys is a recorded alternative)

**Decision (changed at deepen-plan, code-simplicity P1): SHARED key.** Both the KB rail and the
non-KB (main) rail persist to the SAME key `soleur:sidebar.kb.width` — i.e. the layout keeps a
single `useRailWidth()` instance and feeds it to whichever rail is expanded. Rationale:

- **The "different ideal width" argument is not borne out by the geometry.** Both rails share the
  exact same clamp: `RAIL_MIN_PX === RAIL_DEFAULT_PX === 224 === md:w-56` and `railMaxPx() =
  min(480, 40vw)` (`use-rail-width.ts:13-17`). There is no asymmetry in default, min, or max to
  justify two channels — separate keys would be speculative per-surface memory with no evidence.
- **One mental model is simpler:** "the nav rail is this wide" applies everywhere. A single key
  removes a second hook instance, the cross-key-isolation test, and one e2e storage literal.
- The existing key name `soleur:sidebar.kb.width` is RETAINED (no migration / no key rename — a
  user's previously-chosen KB width carries forward and now also applies to Settings/Chat/Dashboard).
  Renaming it to a neutral `soleur:sidebar.width` is **out of scope** (it would orphan stored
  values and add a migration for zero behavioral gain). The key is an implementation detail; its
  `kb` infix is now a misnomer but harmless.
- **The `--main-rail-w` CSS var + `data-main-rail-width` attribute are STILL separate** from the KB
  ones — that separation is at the CSS layer (so the two unlayered rules stay simple and the
  mutual-exclusion guarantee holds), independent of the storage key. Only the *persisted value* is
  shared.

**Recorded alternative (operator may flip):** if real user signal later shows KB needs an
independent width (e.g. users keep KB wide for nested filenames but want a narrow Settings rail),
add a second `useRailWidth("soleur:sidebar.main.width")` instance for `mainExpanded` and re-add the
cross-key-isolation test. This is a one-line change; it is deferred, not designed-in, per YAGNI.

The min (224px = `RAIL_MIN_PX`) and max (`railMaxPx()`) clamps are **reused as-is** —
content-agnostic geometry. **Note (no-narrow floor):** because `RAIL_MIN_PX === RAIL_DEFAULT_PX ===
224`, the rail can only grow WIDER than its default, never narrower — identical to today's KB
behavior. This applies to the primary nav too (short labels); a user cannot shrink the rail below
56px-collapsed / 224px-expanded. This is intended (matches KB); collapse (`md:w-14`) is the only
narrower state.

### D2 — Interaction with the collapsed (`md:w-14`) and KB (`--kb-rail-w`) widths

The aside width resolves in this strict precedence (highest wins):

1. **Collapsed** (`collapsed === true`) → Tailwind `md:w-14` (56px). The grip does NOT mount
   when collapsed (mount gate is `!collapsed`), and neither width var/attribute is applied. The
   collapse class is untouched. **Collapse always wins.**
2. **KB expanded** (`drill === "kb" && !collapsed`) → `data-kb-rail-width` + `--kb-rail-w`
   (existing behavior, `soleur:sidebar.kb.width`). Unchanged.
3. **Non-KB expanded** (`!collapsed && drill !== "kb"`) → NEW `data-main-rail-width` +
   `--main-rail-w`, driven by the SAME persisted width value as KB (D1: one `useRailWidth()`
   instance, shared `soleur:sidebar.kb.width` key). The CSS var/attribute are separate from KB's
   only so the two unlayered globals.css rules stay simple; the *value* is shared.
4. Fallback (no attribute, e.g. mobile drawer) → base class `md:w-56` / `w-64`.

**The two data-attributes are mutually exclusive by construction** — exactly one of
`kbExpanded` / `mainExpanded` is ever true (KB vs non-KB is a partition of "expanded"), so the
"both attributes set → source-order race" risk the repo-research raised **cannot occur**. The
globals.css gets a sibling rule `aside[data-main-rail-width] { width: var(--main-rail-w, 14rem) }`
in the same unlayered `@media (min-width: 768px)` block (so it beats Tailwind's layered
`md:w-56` identically to the KB rule). The mobile `w-64` drawer stays on the base class because
neither attribute is applied at <md (the attribute is set whenever expanded, but the CSS rule is
md+-gated, so the mobile drawer is never affected — same trick the KB rule already uses).

## User-Brand Impact

**If this lands broken, the user experiences:** a primary nav rail that either won't resize in
Settings/Chat/Dashboard (feature absent) OR resizes the wrong rail / swallows the content area
(clamp/precedence bug) OR shows a screen-reader label "Resize knowledge base sidebar" on the
Settings rail (a11y misnaming). All are visible polish defects on the primary nav chrome;
none touches data.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is client-side
CSS/interaction chrome. No data, auth, network, or persistence boundary is touched beyond the
existing `localStorage` rail-width/collapse keys (one new width key, same data class — a number).

**Brand-survival threshold:** none — UI chrome. Reason: matches PR #5477 / the 2026-06-18 plan's
classification; no regulated-data or single-user-incident surface. (Threshold `none` + no
sensitive-path diff ⇒ no preflight Check-6 scope-out bullet required; this section satisfies
preflight.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (grip mounts in all expanded drill states — SINGLE mount, branched props):** the
      layout renders exactly ONE `RailResizeHandle`, mounted under `!collapsed` (md+), in Dashboard
      root / Settings / Chat / Analytics / KB, and NOT when collapsed. Its props are branched on
      `drill === "kb"` (KB literals when KB; `ariaLabel="Resize sidebar"` otherwise) — it is NOT two
      co-existing JSX blocks (KB xor non-KB partitions "expanded", so only one is ever live). Verify:
      `grep -q 'kbExpanded && <RailResizeHandle' …` returns NOTHING (the KB-only gate is gone) and
      the file has exactly one `<RailResizeHandle` JSX site; plus a vitest assertion rendering a
      NON-KB expanded layout (Settings) finds the handle, and a collapsed layout finds none.
- [x] **AC2 (main rail is genuinely drag-to-resize, CSS-var-driven):** in a non-KB expanded
      state the aside width is driven by `--main-rail-w` via `data-main-rail-width`, NOT the fixed
      `md:w-56`. Verify: `grep -q 'data-main-rail-width' apps/web-platform/app/\(dashboard\)/layout.tsx`
      AND `globals.css` contains `aside[data-main-rail-width]` with `width: var(--main-rail-w, 14rem)`
      in the unlayered md+ block; e2e drag on Settings widens the aside (AC-E2E-2).
- [x] **AC3 (shared persisted width):** the layout uses ONE `useRailWidth()` instance (default key
      `soleur:sidebar.kb.width`), feeding its width to whichever rail is expanded (D1). Verify: there
      is exactly one `useRailWidth(` call in `layout.tsx`; a width set while on Settings is read back
      on KB (and vice-versa). (If the operator flips D1 to separate keys, re-add the second instance
      + the cross-key-isolation test.)
- [x] **AC4 (sensible min/max reused):** the rail clamps to `[RAIL_MIN_PX, railMaxPx()]`
      (224px .. min(480, 40vw)) in every expanded state — reusing the existing `use-rail-width.ts`
      clamp. Verify: `RailResizeHandle` receives `min={RAIL_MIN_PX}` / `max={railMaxPx()}`; the
      existing `use-rail-width.test.tsx` clamp/over-range cases stay green (they are key-agnostic).
- [x] **AC5 (a11y label de-KB-ified for non-KB mounts):** when the grip is on a non-KB rail its
      accessible name is "Resize sidebar" (NOT "Resize knowledge base sidebar"); on KB it keeps
      "Resize knowledge base sidebar". Verify: `RailResizeHandle` accepts ONE optional `ariaLabel`
      (default = current KB literal); a vitest case asserts the Settings mount's accessible name is
      "Resize sidebar" and the KB mount keeps its literal.
- [x] **AC6 (double-click collapses everywhere the grip mounts):** double-clicking the grip in a
      non-KB expanded state toggles `collapsed` to true via the existing `onCollapse={toggleCollapsed}`.
      Verify by a vitest case (RTL) firing `fireEvent.doubleClick` on the grip in a Settings-rendered
      layout and asserting collapse; the existing `onCollapse`-fires-once unit case stays green.
- [x] **AC7 (grip is a SIBLING of, not nested inside, the secondary slot):** the `RailResizeHandle`
      is a direct child of `<aside>` (positioned `absolute` against it), NOT inside the
      `overflow-y-auto` `rail-secondary-slot` div — otherwise `overflow` would clip it. Verify: in
      `layout.tsx` the handle JSX sits after the drill ternary closes (sibling of the slot), and an
      e2e/vitest assertion confirms the grip is not a descendant of `[data-testid="rail-secondary-slot"]`.
- [x] **AC8 (mobile drawer untouched):** the grip is `hidden md:block` (never on the mobile
      drawer) and the mobile `w-64` drawer width is unaffected by `--main-rail-w` (the CSS rule is
      md+-gated). Verify: the existing mobile e2e (`no resize handle on mobile`) stays green; a
      vitest/e2e mobile case confirms the drawer width is 256px (w-64), not the main var.
- [x] **AC9 (collapse precedence):** when collapsed, the rail is `md:w-14` (56px), neither
      width attribute is applied, and the grip is absent — in every drill state. Verify: a vitest
      case rendering collapsed Settings asserts no `data-main-rail-width`, no grip; the existing
      `collapse takes precedence` KB e2e stays green.
- [x] **AC10 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] **AC11 (tests green):** `cd apps/web-platform && ./node_modules/.bin/vitest run` passes,
      including the updated `nav-states-shell` describe blocks (new + inverted), `rail-resize-handle.test.tsx`,
      `use-rail-width.test.tsx`, and any new layout test. New `.test.tsx` files live under
      `apps/web-platform/test/` (the happy-dom include glob is `test/**/*.test.tsx` — co-located
      `components/**/*.test.tsx` is silently skipped).
- [ ] **AC-E2E-1 (grip present + gold on drag, NON-KB):** in `nav-states-shell.e2e.ts`, a new
      scenario on **Settings** (and/or Dashboard) asserts the grip is VISIBLE, and on
      pointer-down/drag the handle wash class includes `soleur-accent-gold-fill` (gold on active).
- [ ] **AC-E2E-2 (drag resizes a NON-KB rail + persists):** dragging the grip on Settings widens
      the aside (> default + 50px) and the width persists across reload (read back from the SHARED
      key `soleur:sidebar.kb.width` — D1). The new scenario seeds/reads that literal (declared in
      the e2e alongside the existing `RAIL_WIDTH_KEY`).
- [ ] **AC-E2E-3 (double-click collapses, NON-KB):** double-clicking the Settings grip collapses
      the rail to `md:w-14`; the floated button re-expands it.
- [ ] **AC-E2E-4 (INVERTED — old KB-only assertion replaced; rail EXPANDED):** the former
      `"resize handle is KB-only — absent on Settings and Chat (AC13)"` test
      (`nav-states-shell.e2e.ts:941-950`) is REPLACED by a test asserting the grip IS present on
      Settings AND Chat. The replacement MUST run with an EXPANDED rail (no `seedCollapsed`) — else
      the grip won't mount and the assertion false-fails. Verify: `grep -q 'KB-only'
      apps/web-platform/e2e/nav-states-shell.e2e.ts` returns NOTHING (the stale text is gone).

#### Regression guards (prose, not gated ACs — the plan changes none of these)

These were demoted from gated ACs at deepen-plan (code-simplicity): they assert code this plan does
NOT touch, so a grep-AC would be ceremony. The implementer must simply not regress them; the
existing suites already cover them.

- **Gold-on-active unchanged:** the grip's `active:`/`focus-visible:` wash stays
  `soleur-accent-gold-fill/70`, hover stays grey, zero `amber-500` (`rail-resize-handle.tsx:128`).
  No color edit is in scope. (If the AC5 vitest a11y-label test touches the component, confirm the
  class string is untouched in the same diff.)
- **Floated collapse button KEPT:** the `PanelToggleIcon` `<button>` (`layout.tsx:~367`) and its
  SVG are NOT removed; `onClick={toggleCollapsed}` intact. (The explicit divergence from FR3-Literal.)
- **⌘B preserved:** the global `Meta/Ctrl+B` keydown handler (`layout.tsx:199`) is untouched.

### Post-merge (operator / automatable)

- [ ] **AC15 (visual verify, Playwright):** drive Dashboard / Settings / Chat, drag the rail grip
      → confirm gold (#c9a962) wash on active, grey on hover; double-click → collapse; button →
      expand; width persists per-section. Automatable via Playwright MCP — fold into `/soleur:qa`
      or a `test-browser` run, NOT a manual checklist.

## Implementation Phases

> TDD order: write failing vitest/e2e cases first (RED), then implement (GREEN). Color/class
> swaps that no test asserts are verified by the AC greps + Playwright post-merge.

### Phase 1 — Add ONE `ariaLabel` prop to `RailResizeHandle` (RED first)

- `apps/web-platform/components/dashboard/rail-resize-handle.tsx`:
  - Extend `RailResizeHandleProps` with a SINGLE optional `ariaLabel?: string` (default
    `"Resize knowledge base sidebar"` — preserves KB behavior). Apply it to `aria-label` (`:112`).
  - Do NOT add `testId`/`gripTestId` props: KB and non-KB grips never co-mount (route
    disambiguates), so the existing `data-testid="kb-rail-resize-handle"`/`-grip` literals stay —
    a Settings-page `getByTestId("kb-rail-resize-handle")` resolves to the one grip present
    (code-simplicity P1). Keep the testids as-is.
  - **No color change** — the gold-active/focus + grey-hover classes (`:128,:132`) are left verbatim.
- Tests (write first) in `apps/web-platform/test/rail-resize-handle.test.tsx`: a render with
  `ariaLabel="Resize sidebar"` exposes that accessible name; default render keeps the KB literal
  (AC5). The existing `onCollapse`/drag/keyboard cases must stay green.

### Phase 2 — Main-rail CSS-var width + sibling globals.css rule

- `apps/web-platform/app/globals.css`: add, inside the SAME unlayered `@media (min-width: 768px)`
  block as the KB rule (`:203-207`), a sibling:
  ```css
  aside[data-main-rail-width] {
    width: var(--main-rail-w, 14rem);
  }
  ```
  with a comment mirroring the KB rule's (deterministic, unlayered so it beats `md:w-56`;
  md+-gated so the mobile `w-64` drawer is untouched; the two attributes are mutually exclusive
  by construction — KB vs non-KB partitions "expanded").
- No JS yet — this rule is inert until Phase 3 sets the attribute.

### Phase 3 — Widen the mount + apply the main-rail width in the layout (RED first)

> **Contract-order note:** Phase 1 (handle accepts `ariaLabel`) MUST precede this — the layout
> passes `ariaLabel` for the non-KB branch.

- `apps/web-platform/app/(dashboard)/layout.tsx`:
  - Keep the SINGLE existing `useRailWidth()` instance (shared `soleur:sidebar.kb.width` key — D1).
    Define `mainExpanded = !collapsed && drill !== "kb"`.
  - On the `<aside>`: set `data-main-rail-width` + `style={{ "--main-rail-w": `${railWidth}px` }}`
    when `mainExpanded` (mirroring the existing `kbExpanded` block at `:299-304`, fed by the SAME
    `railWidth`). Keep the `kbExpanded` block as-is. The `${collapsed ? "md:w-14" : "md:w-56"}`
    class stays (the fallback under the unlayered var rules + the collapsed width). `mainExpanded`
    and `kbExpanded` are mutually exclusive, so at most one attribute is ever set.
  - **Widen the grip mount to a SINGLE mount with branched props** (`:506`): replace
    `{kbExpanded && (<RailResizeHandle …/>)}` with `{!collapsed && (<RailResizeHandle … />)}` — ONE
    JSX site (the `hidden md:block` on the handle keeps it off mobile). Branch ONLY the
    `ariaLabel` prop: `ariaLabel={drill === "kb" ? undefined : "Resize sidebar"}` (undefined →
    the KB default). All other props are unconditional: `width={railWidth}`,
    `onWidthChange/onCommit` → `setRailWidth`, `min={RAIL_MIN_PX}`, `max={railMaxPx()}`,
    `onCollapse={toggleCollapsed}`. **Do NOT write two JSX blocks** (architecture P1 — a double
    mount is a regression risk; KB xor non-KB is already a partition of expanded).
  - **Place the grip as a direct child of `<aside>`** (after the drill ternary closes, `:498`) —
    NOT inside the `overflow-y-auto rail-secondary-slot` div, so `overflow` cannot clip it (AC7).
  - **Keep** the floated `PanelToggleIcon` button (`:367`) and its SVG verbatim.
- Tests (write first) under `apps/web-platform/test/` (NOT co-located):
  - non-KB expanded (Settings) mounts the grip with `aria-label="Resize sidebar"` (AC1, AC5);
    collapsed Settings has no grip + no `data-main-rail-width` (AC1, AC9); double-click fires
    collapse (AC6); KB still mounts the grip with the KB label (AC1); a width set on Settings is
    read back on KB (shared key — AC3); the grip is not a descendant of `rail-secondary-slot` (AC7).

### Phase 4 — e2e: invert the KB-only assertion + add NON-KB scenarios

- `apps/web-platform/e2e/nav-states-shell.e2e.ts`:
  - **Replace** the `"resize handle is KB-only — absent on Settings and Chat (AC13)"` test
    (`:941-950`) with `"resize handle present on Settings AND Chat (resizable main rail)"` —
    `await expect(resizeHandle(page)).toBeVisible()` on both `/dashboard/settings` and
    `/dashboard/chat`, with NO `seedCollapsed` (rail must be expanded) (AC-E2E-4). REUSE the
    existing `resizeHandle = (page) => page.getByTestId("kb-rail-resize-handle")` locator (`:389`)
    — the grip keeps the KB testid (Phase 1: no second testid), and on Settings/Chat there is
    exactly one grip, so the locator resolves uniquely.
  - Add a `test.describe("resizable main rail — desktop")` block (mirror the existing
    `widenable KB rail` block's `dragHandleBy` + hydration-wait helper, but navigate to
    `/dashboard/settings`):
    - drag widens the Settings aside (> default + 50) (AC-E2E-2);
    - width persists across reload, read back from the SHARED key `soleur:sidebar.kb.width`
      (declare the literal alongside the existing `RAIL_WIDTH_KEY`) (AC-E2E-2);
    - drag turns the handle gold (assert the active class includes `soleur-accent-gold-fill`)
      (AC-E2E-1);
    - double-click collapses to `md:w-14`, the floated button re-expands (AC-E2E-3).
  - Mobile: confirm the existing `no resize handle on mobile` invariant still holds (AC8).

### Phase 5 — Verification sweep

- AC greps (AC1: `! grep 'kbExpanded && <RailResizeHandle'` + exactly one `<RailResizeHandle` site;
  AC2: `data-main-rail-width` + the globals.css rule; AC-E2E-4: stale "KB-only" text gone);
  `tsc --noEmit`; `vitest run`. Confirm no co-located test files (happy-dom glob is
  `test/**/*.test.tsx`).

## Domain Review

**Domains relevant:** Product (Engineering is the implementer, not a review domain).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — reuses the wireframes committed by the directly-preceding
2026-06-18 merged plan at `knowledge-base/product/design/dashboard/screenshots/` (handle
idle/hover/active-gold states `01-…`, expanded rail `02-…`, double-click tooltip `03-…`,
collapsed rail `04-…`, splitter `05-…`). This plan modifies an EXISTING UI surface (the nav
rail's resize affordance) and adds NO new component files, page.tsx, or layout.tsx — so the
mechanical BLOCKING escalation (new `components/**/*.tsx` / `app/**/page.tsx` creation) does NOT
fire; tier is ADVISORY. The visible change (grip now also appears on Settings/Chat/Dashboard, the
rail there now resizes) is already depicted by the handle-state + expanded-rail frames; no new
wireframe is load-bearing. ux-design-lead is NOT skipped for a UI feature — a committed `.pen`
already exists (`sidebar-resizer-gold-doubleclick.pen`) and is referenced.
**Agents invoked:** none re-run (carry-forward from the 2026-06-18 plan's spec-flow + cpo +
ux-design-lead pass — same nav-rail surface, same grip component).
**Skipped specialists:** copywriter (no persuasive/marketing copy in scope) — none required.
**Pencil available:** yes — committed wireframe at
`knowledge-base/product/design/dashboard/sidebar-resizer-gold-doubleclick.pen` (6 frames; produced
by the prior plan, covers the handle idle/hover/active-gold states + expanded/collapsed rail that
this plan's all-states widening reuses). Re-referenced here so the deepen-plan UI-wireframe gate
(`wg-ui-feature-requires-pen-wireframe`) resolves it as committed.

#### Findings

- The prior 2026-06-18 spec-flow + CPO + architecture-strategist pass on the SAME nav-rail grip
  surface raised exactly the two concerns this plan resolves (decorative-grip + a11y-misnaming);
  see "Relationship to the 2026-06-18 merged work". No new flow gap is introduced — the gesture
  set (pointer collapse via button + double-click; pointer expand via button; ⌘B; drag-resize)
  is a strict superset of today's, in more states. No dead-ends: the button (kept) serves
  expand/collapse in every state including collapsed, so the FR3-Literal "self-destroying
  gesture" dead-ends (which required removing the button) do not apply here.

## Architecture Decision (ADR/C4)

None. This is an interaction/visual change on existing UI chrome — no data-model, tenancy,
substrate, resolver, or trust-boundary decision. **ADR-047** (singular drill-state authority via
`segmentToDrillLevel`) is HONORED: the mount/width predicates derive from the existing `drill`
variable + `collapsed`, adding no parallel pathname check. **ADR-049** (headless VRT gate) is
EXTENDED in-place (the same `nav-states-shell.e2e.ts` gate gains the inverted + new scenarios) —
this is in-scope for that gate, not a new ADR. No ADR or C4 view changes.

## Observability

Skip — none of the Files-to-Edit match the Phase 2.9 code-class trigger set (`apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, or a new infra surface). They are all
client-component / CSS / test paths: `apps/web-platform/components/**`,
`app/(dashboard)/layout.tsx` (a `"use client"` layout), `app/globals.css`, `test/**`, `e2e/**`. No
new server code, route, Inngest function, or infra surface; no new error path, log, or failure mode
reachable from Sentry/Better Stack. (Matches the directly-preceding 2026-06-18 plan's skip on the
same nav-rail surface.)

## Open Code-Review Overlap

Three same-file matches, no real scope overlap:

- **#2193** (unify past_due/unpaid banners, extract `useDismissiblePersistent`) names
  `(dashboard)/layout.tsx` — but at the `PaymentWarningBanner` + inline `unpaid` banner region
  (`:36-93`, `:524-540`), a different region than this plan's edits (grip mount gate ~506, aside
  width attributes ~299-316). **Disposition: Acknowledge** — different
  concern (billing banner extraction), no shared lines; scope-out remains open.
- **#3564** (Core Web Vitals infra) and **#2349** (qa skill port-probe) name `globals.css` for
  unrelated CWV / QA concerns; this plan touches only the unlayered rail-width rule region
  (`:193-207`). **Disposition: Acknowledge** — no shared lines.

(Verified against `gh issue list --label code-review --state open --json …`, 63 issues.)

## Files to Edit

- `apps/web-platform/components/dashboard/rail-resize-handle.tsx` — add ONE optional `ariaLabel` prop (default = KB literal); apply to `aria-label`. No testid props, no color change (Phase 1).
- `apps/web-platform/app/globals.css` — add sibling `aside[data-main-rail-width] { width: var(--main-rail-w, 14rem) }` in the unlayered md+ block (Phase 2).
- `apps/web-platform/app/(dashboard)/layout.tsx` — `mainExpanded = !collapsed && drill !== "kb"`; set `data-main-rail-width` + `--main-rail-w` (from the SAME `railWidth`) when `mainExpanded`; widen the grip to a SINGLE mount under `!collapsed` with `ariaLabel` branched on `drill==="kb"`; place the grip as a sibling of the secondary slot; KEEP the floated button + `PanelToggleIcon` SVG (Phase 3).
- `apps/web-platform/test/rail-resize-handle.test.tsx` — new case for the `ariaLabel` prop (AC5); existing cases stay green (Phase 1).
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — REPLACE the `KB-only … absent on Settings and Chat` test; add the `resizable main rail — desktop` describe block (AC-E2E-1..4) (Phase 4).

## Files to Create

- `apps/web-platform/test/main-rail-resize.test.tsx` — IF no existing layout test surface covers AC1/AC3/AC6/AC7/AC9 for the non-KB mount; place under `test/` (happy-dom glob `test/**/*.test.tsx`). (Prefer extending an existing `test/` layout suite if one exists; only create if needed.)

## Test Scenarios

1. Non-KB expanded (Settings/Dashboard/Chat) mounts the grip; collapsed does not (AC1, AC9).
2. Drag the Settings grip → aside widens, persists to the SHARED key `soleur:sidebar.kb.width`;
   reading it back on KB shows the same width (AC2, AC3, AC-E2E-2).
3. Drag turns the grip gold (`soleur-accent-gold-fill`); hover is grey (AC-E2E-1; regression-guard
   prose).
4. Double-click the Settings grip → collapse to `md:w-14`; floated button re-expands (AC6,
   AC-E2E-3).
5. ⌘B toggles collapse in both directions; floated button still present (regression-guard prose).
6. Non-KB grip aria-label is "Resize sidebar"; KB grip keeps "Resize knowledge base sidebar"
   (AC5).
7. Grip is a sibling of `rail-secondary-slot`, not nested inside it (no `overflow` clip) (AC7).
8. Mobile: no grip; `w-64` drawer width unaffected by `--main-rail-w` (AC8).
9. The stale "KB-only — absent on Settings and Chat" e2e text is gone (AC-E2E-4).

## Research Insights

**Gold-on-active is already shipped.** `rail-resize-handle.tsx:128` uses
`active:bg-soleur-accent-gold-fill/70 focus-visible:bg-soleur-accent-gold-fill/70` (gold at /70,
chosen because /50 fails 1.4.11 non-text contrast on `bg-surface-1`) and grey hover
`hover:bg-soleur-text-secondary/50`. This plan does NOT change color; AC5 is a regression guard.
`brand-hex-commit-gate` scans raw hex, not Tailwind builtins — never introduce literal `#c9a962`;
use the `soleur-accent-gold-fill` token.

**One shared `useRailWidth()` instance (D1).** The KB rail's existing hook instance (default key
`soleur:sidebar.kb.width`) now also feeds the non-KB rail's `--main-rail-w`. The clamp helpers
(`railMaxPx`, `clampRailWidth`) and constants (`RAIL_MIN_PX=224`, `RAIL_DEFAULT_PX=224`,
`RAIL_MAX_ABS_PX=480`, `RAIL_MAX_VW=0.4`, `use-rail-width.ts:13-18`) are content-agnostic and
reused verbatim. Because `RAIL_MIN_PX === RAIL_DEFAULT_PX`, the rail only ever widens past 224px,
never narrows below it (collapse `md:w-14` is the sole narrower state) — intentional, matches KB.
The hook IS singleton-free (`:48-50,65,86`, effects key on `[storageKey]`), so if D1 is later
flipped to separate keys a second `useRailWidth("soleur:sidebar.main.width")` instance is clean.

**Two data-attributes cannot race.** `kbExpanded` (`drill==="kb" && !collapsed`) and
`mainExpanded` (`!collapsed && drill!=="kb"`) are a partition of "expanded" — exactly one is true.
So the repo-research "both attributes set → CSS source-order race" risk does not materialize; two
sibling unlayered rules are safe.

**Mount widening is what makes double-click fire elsewhere.** `onCollapse={toggleCollapsed}` and
the `onDoubleClick` handler already exist (`layout.tsx:513`, `rail-resize-handle.tsx:94`); they
were simply never mounted outside KB. Widening the mount gate is the entire wiring change for the
double-click requirement — no new handler code.

**vitest glob trap.** happy-dom tests are collected via `test/**/*.test.tsx`
(`vitest.config.ts:64`); a co-located `components/**/*.test.tsx` is silently never run. New tests
MUST live under `apps/web-platform/test/`. Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
(NOT `npm run -w …` — root has no `workspaces` field).

**e2e localStorage seeding.** The e2e seeds collapse via `addInitScript` setting
`soleur:sidebar.main.collapsed="1"` and width via the `RAIL_WIDTH_KEY` literal
(`= "soleur:sidebar.kb.width"`, `nav-states-shell.e2e.ts:31-35,308-312`). With D1's SHARED key, the
new non-KB width assertions seed/read that SAME `RAIL_WIDTH_KEY` literal — no new key literal is
needed (the existing one already maps to `soleur:sidebar.kb.width`).

**Precedent diff (Phase 4.4):** the CSS-var-driven rail width + persisted hook + grip is a DIRECT
in-repo precedent — the KB rail (PR #5477 grip bar; the 2026-06-17 width work). This plan mirrors
it for a second rail. No SQL/atomic-write/lock/RPC patterns in scope; no novel pattern.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/TBD or omits the threshold fails
  `deepen-plan` Phase 4.6. This section is filled (threshold `none`).
- **Both toggle states must be verified** (learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`):
  test the rail in BOTH collapsed and expanded for every changed state (grip mount, main width
  attribute, collapse precedence each render different DOM per state).
- **Class-assertion sweeps use the bare token** (learning `2026-06-02-test-class-assertion-sweep-must-use-bare-token-not-bracketed.md`):
  when grepping for `soleur-accent-gold-fill` / `data-main-rail-width`, use the bare substring,
  not a bracketed regex-literal, and run the full affected suite green — not just the first match.
- **Floating-control clearance in both branches** (learning `2026-06-08-floating-absolute-control-needs-clearance-in-both-render-branches.md`):
  the KEPT floated collapse button is an absolute control whose `aria-label` flips
  Expand/Collapse — match it with a regex (`/^(Expand|Collapse) sidebar$/`) in any VRT locator;
  it must keep clearance in both the collapsed and expanded branches (already true; do not regress).
- **CSS-var naming consistency** (learning `2026-02-22-docs-site-css-variable-inconsistency.md`):
  the var is `--main-rail-w` (all-lowercase, hyphenated) in BOTH the inline `style` and the
  `globals.css` rule — grep both to confirm no camelCase typo (a mismatch silently falls back to
  `14rem` / `md:w-56` with no build error).
- **e2e Playwright testMatch globs, not regex** (learning `2026-04-10-e2e-authenticated-dashboard-tests-mock-supabase.md`):
  this plan adds scenarios to the EXISTING `nav-states-shell.e2e.ts` (already routed) rather than
  a new file, so no new testMatch is needed — but if a new e2e file is ever added, use a glob, not
  a regex that could match the `…-sidebar-resizable-…` worktree path.
- **The grip is `position: absolute` against the `aside`** — if the rail ever gains
  `backdrop-filter`/`transform`/`filter`, fixed-position math would break (learning
  `2026-02-17-backdrop-filter-breaks-fixed-positioning.md`); the current handle uses `absolute
  inset-y-0 right-0` against the `md:relative` aside — unchanged here, do not switch to fixed.
- **Do NOT remove the floated button.** The explicit divergence from the FR3-Literal direction:
  the request says keep it. Removing it would re-introduce the 2026-06-18 plan's dead-ends
  (no pointer expand once collapsed, since the grip unmounts when collapsed).

## Resume prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-06-18-feat-main-nav-rail-resizable-all-states-plan.md. Branch: feat-one-shot-main-sidebar-resizable-all-states. Worktree: .worktrees/feat-one-shot-main-sidebar-resizable-all-states/. Plan deepened (architecture + simplicity reviews applied). Reuses RailResizeHandle + the ONE existing useRailWidth() instance (SHARED key soleur:sidebar.kb.width — D1). Build on the 2026-06-18 merged gold+double-click work (FR3-Alternative kept the button). KEEP the button; widen grip to a SINGLE mount under !collapsed with ariaLabel branched on drill==="kb"; add data-main-rail-width CSS-var width for non-KB; invert the e2e KB-only assertion (run expanded).
```
