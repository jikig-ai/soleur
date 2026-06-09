---
title: "feat: Shared CTA banner collapse/reopen micro-interaction"
date: 2026-06-09
branch: feat-one-shot-shared-banner-collapse-reopen
type: enhancement
lane: single-domain
status: draft
requires_cpo_signoff: false
brand_survival_threshold: none
---

# feat: Shared-document CTA banner — collapse to a thin bar and re-open without reload

## Enhancement Summary

**Deepened on:** 2026-06-09
**Sections enhanced:** Implementation Phase 1 (animation + ARIA + chevron), Test Phase 2, Acceptance Criteria, Risks, Sharp Edges, Alternatives.
**Review lenses applied (run inline — nested Task spawning is unavailable inside the one-shot subagent):** frontend-design (flash-risk), code-simplicity (YAGNI), test-design (happy-dom determinism), accessibility (WAI-ARIA disclosure), plus the deepen-plan realism passes (verify-the-negative, precedent-diff Phase 4.4).

### Key Improvements
1. **`motion-reduce:` is the correct reduced-motion mechanism — and is now load-bearing-justified.** Confirmed Tailwind **4.2.1** ships the `motion-reduce:` variant built-in (present in `node_modules/tailwindcss/dist/lib.js`) — no `@custom-variant` definition needed (unlike `dark`, which IS custom-defined at `globals.css:13` because it maps to `data-theme`). Crucially, **happy-dom does NOT provide `window.matchMedia` by default** (confirmed at `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx:71` — that suite must `vi.stubGlobal("matchMedia", …)`). A JS `matchMedia`-based reduced-motion gate would force every test in the rewritten suite to stub matchMedia or crash; the CSS-only `motion-reduce:` variant needs zero test plumbing. This is the decisive reason the CSS approach wins.
2. **ARIA disclosure pattern corrected to match repo precedent.** The three existing disclosure controls (`debug-stream-panel.tsx:105`, `org-switcher.tsx:116`, `kb/file-tree.tsx:204`) all carry `aria-expanded={state}` on the toggle and none use `aria-controls`. Plan retains `aria-expanded` on each rendered control (the control legitimately swaps here) and explicitly drops `aria-controls` as YAGNI for a marketing banner. See Research Insights → Accessibility.
3. **Honest animation framing (no over-claim).** Conditional-render of two mutually-exclusive panels animates the *entry* of the incoming panel (transform+opacity transition on mount) but the outgoing panel unmounts instantly — there is no exit animation. The plan no longer implies a full crossfade; "smooth" = the incoming panel eases in. This is the YAGNI-correct choice for a banner (an exit animation needs always-mount-both + orchestration; not worth it here). See Research Insights → Animation.
4. **Up-chevron aligned to the repo's existing form.** Use `<polyline points="5 12 12 5 19 12" />` (+ optional stem `<line x1="12" y1="19" x2="12" y2="5" />`), the exact up-chevron already in `chat-input.tsx:691-694`, instead of an arbitrary lucide variant — visual + maintenance consistency.

### New Considerations Discovered
- **Lint is a non-functional gate for web-platform** (`knowledge-base/project/learnings/2026-06-05-web-platform-lint-gate-is-non-functional-tsc-vitest-are-authoritative.md`): `next lint` drops into an interactive prompt and CI does not run it. The authoritative gates are `tsc --noEmit` + `vitest run` — already what AC7/AC8 prescribe. Do NOT add a lint AC or treat a lint non-zero exit as a regression.
- **`safeSession` is a sensitive-path file** (`apps/web-platform/lib/safe-session.ts` matches the preflight Check-6 / deepen Phase-4.6 `SENSITIVE_PATH_RE`). Confirmed at gate-check time that it is NOT in Files-to-Edit, so the `none` threshold needs no scope-out bullet. Re-confirms the "remove usage, keep the file" sharp edge — touching the file would also trip the sensitive-path gate.

---

## Overview

The shared-document waitlist CTA banner (`apps/web-platform/components/shared/cta-banner.tsx`, shipped in #5035) currently has a terminal close: clicking the dismiss button writes `sessionStorage["soleur:shared:cta-dismissed"]="1"`, sets `dismissed=true`, and the component returns `null` — the banner unmounts with no way back without clearing storage or reloading.

This enhancement replaces that terminal "gone" state with a **collapse/re-open micro-interaction**: closing the banner collapses it to a thin full-width bar (same fixed-bottom footprint, showing the "Built with Soleur" gold-accent line + an up-chevron). Clicking anywhere on the strip re-expands the full banner (message + waitlist form) with a smooth slide/fade animation that respects `prefers-reduced-motion`. State is **in-memory only** — a page reload restores the full banner.

This is a **single-component UI change plus its tests**. No backend/API change: `/api/waitlist` and the form-submit behavior are unchanged.

**Scope:** one component file, one test file rewrite, one test file kept green, one optional wireframe extension. No new dependencies, no new files (the component already imports `useState`; reduced-motion is handled via Tailwind's built-in `motion-reduce:` variant — no JS, no `matchMedia`).

## Locked Decisions (brainstorm 2026-06-09)

1. **Current behavior being replaced:** close button (`data-testid="cta-banner-dismiss"`) does `setDismissed(true)` + `safeSession(STORAGE_KEY, "1")`, then `if (dismissed) return null`.
2. **New behavior:** closing **collapses** to a thin full-width bar at `fixed bottom-0` (same `border-t`, `bg-soleur-bg-surface-1/95`, `backdrop-blur` footprint) showing "Built with **Soleur**" (gold accent) + an up-chevron (⌃). Clicking anywhere on the strip re-expands the full banner.
3. **State model:** replace terminal `dismissed: boolean` with a two-value UI state (`expanded | collapsed`) via `useState`. No longer returns `null`.
4. **Animation:** re-open (and collapse) use a smooth slide/translate + fade via plain Tailwind/CSS transitions (no animation lib). MUST respect `prefers-reduced-motion`.
5. **Persistence:** IN-MEMORY ONLY. Remove the `STORAGE_KEY` `safeSession` read/write in this component. A reload restores the full banner.
6. **Accessibility:** the collapsed strip is a `<button>` with `aria-label="Reopen Soleur signup banner"` and `aria-expanded` reflecting state; expand/collapse is keyboard-operable. Keep the dismiss-icon aria semantics consistent with the new collapse meaning.

## Premise Validation

Checked the references the task cites:

- **PR #5035** (the shipping PR) — the target component `apps/web-platform/components/shared/cta-banner.tsx` **exists on `origin/main`** (`git show origin/main:...` returns content). This is an **enhancement of a live component**, not a build-from-absent — the plan shape is "modify existing", confirmed.
- **`STORAGE_KEY = "soleur:shared:cta-dismissed"` + `safeSession`** — confirmed present at `cta-banner.tsx:4,6,14-16,22-25`.
- **`data-testid="cta-banner-dismiss"`** — confirmed at `cta-banner.tsx:64`.
- **Test files** — both `apps/web-platform/test/shared-cta-banner-close.test.tsx` (asserts unmount + sessionStorage) and `apps/web-platform/test/shared-cta-banner-waitlist.test.tsx` (form submit) exist as described.
- **Wireframe** — `knowledge-base/product/design/shared-document/cta-banner-waitlist.pen` exists (v2.11, 30 frames: Idle / Success / Mobile).

No stale premises. Nothing to re-scope.

## Research Reconciliation — Spec vs. Codebase

| Task claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Remove the existing STORAGE_KEY sessionStorage write/read logic (`safeSession`) as part of this change." | `safeSession` (`apps/web-platform/lib/safe-session.ts`) is a **shared** util also consumed by `components/chat/chat-input.tsx` and `hooks/use-kb-layout-state.tsx`. | Remove **only the import + the two call sites in `cta-banner.tsx`** and the `STORAGE_KEY` constant. **Do NOT delete `lib/safe-session.ts`** — it is shared infrastructure. (Sharp Edge below.) |
| "collapsed bar … up-chevron (⌃)" | The component currently renders an inline X icon as an inline `<svg>` (`cta-banner.tsx:66-79`); no chevron asset exists in the component. | Render the up-chevron as an inline `<svg>` (polyline `18 15 12 9 6 15`) in the same inline-SVG style already used for the X, for visual consistency. No icon import needed. |
| Reduced-motion via JS `matchMedia` | Tailwind v4 (`tailwindcss ^4.1.0`, `@import "tailwindcss"` in `app/globals.css`) ships the `motion-reduce:` variant built-in. There is a `useMediaQuery` hook (`hooks/use-media-query.ts`) but it is heavier than needed. | Use the **CSS-only `motion-reduce:` Tailwind variant** (`motion-reduce:transition-none`, `motion-reduce:duration-0`) — matches locked decision #4 "plain Tailwind/CSS transitions", needs no JS, and avoids happy-dom `matchMedia` test plumbing. (See Alternatives.) |
| Test runner / path | Component tests run under **vitest** `component` project (happy-dom), glob `test/**/*.test.tsx`. `bun test` is blocked repo-wide (`apps/web-platform/bunfig.toml` `pathIgnorePatterns = ["**"]`). | Run/verify with `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx`. Both target files already live at `test/*.test.tsx` (correct glob). |

## User-Brand Impact

**If this lands broken, the user experiences:** a shared-document visitor (a prospect viewing a Soleur-generated artifact) clicks the close button and either the banner disappears entirely with no way back (regression to old behavior — acceptable degradation) or the collapsed bar renders but the click target is dead / does not re-expand (a visibly broken micro-interaction on the brand's most public surface).

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is a presentational micro-interaction. No data is read, written, transmitted, or persisted by this change (the change *removes* a sessionStorage write). The waitlist `/api/waitlist` path and its data handling are untouched.

**Brand-survival threshold:** none. Rationale: a purely presentational collapse/expand toggle on a marketing banner; worst-case failure is a non-functional toggle, not a data/auth/money exposure. The diff touches no sensitive path (no schema, auth, API route, `.sql`). No CPO sign-off required.

## Implementation Phases

### Phase 1 — Rewrite `cta-banner.tsx` state model and render

File: `apps/web-platform/components/shared/cta-banner.tsx`

**1.1 — Remove sessionStorage persistence (this component only).**
- Delete the `import { safeSession } from "@/lib/safe-session";` line.
- Delete `const STORAGE_KEY = "soleur:shared:cta-dismissed";`.
- **Keep** `lib/safe-session.ts` untouched (shared util — see Sharp Edges).

**1.2 — Replace the state model.**
- Replace `const [dismissed, setDismissed] = useState<boolean>(() => safeSession(STORAGE_KEY) === "1");` with an explicit two-value UI state:
  ```tsx
  type Panel = "expanded" | "collapsed";
  const [panel, setPanel] = useState<Panel>("expanded");
  ```
- Keep `email` and `status` state unchanged (form behavior is unchanged).
- Delete the `if (dismissed) return null;` early-return — the component never returns `null` now.
- Replace `handleDismiss` (which wrote storage + set dismissed) with `handleCollapse = () => setPanel("collapsed")` and add `handleExpand = () => setPanel("expanded")`.

**1.3 — Collapsed strip (new render branch).**
When `panel === "collapsed"`, render a slim full-width strip that reuses the banner footprint:
- Outer container: same `fixed bottom-0 left-0 right-0 z-40 border-t border-soleur-border-default bg-soleur-bg-surface-1/95 backdrop-blur-sm` footprint, but slim vertical padding (e.g. `py-2` instead of `py-3`).
- The strip itself is a **`<button type="button">`** spanning the full width (`w-full`), so clicking anywhere on it re-expands:
  - `onClick={handleExpand}`
  - `aria-label="Reopen Soleur signup banner"`
  - `aria-expanded={false}`
  - `data-testid="cta-banner-reopen"`
  - Inner content: `<div class="mx-auto flex max-w-3xl items-center justify-between gap-4">` with the "Built with **Soleur**" line (gold `text-soleur-accent-gold-fg` accent on "Soleur") on the left and an up-chevron `<svg>` on the right.
  - Up-chevron: inline `<svg>` using the **repo's existing up-chevron form** from `chat-input.tsx:691-694` — `<line x1="12" y1="19" x2="12" y2="5" />` + `<polyline points="5 12 12 5 19 12" />` (or just the polyline if the stem reads too heavy at strip scale), `viewBox="0 0 24 24"`, `stroke="currentColor"`, `strokeLinecap="round"`, `strokeLinejoin="round"`, `aria-hidden="true"`. (Do NOT invent a new chevron path — match the existing one.)

**1.4 — Expanded banner (existing render, with collapse semantics).**
When `panel === "expanded"`, keep the existing two-tier banner markup, with these changes to the close button (`cta-banner.tsx:59-80`):
- `onClick={handleCollapse}` (was `handleDismiss`).
- `aria-label="Collapse signup banner"` (was "Dismiss signup banner") — reflects the new collapse meaning, not a terminal dismiss.
- Add `aria-expanded={true}` to the close button so the expand/collapse control's state is exposed consistently in both states.
- Keep `data-testid="cta-banner-dismiss"` (stable selector the close test keys on; the *behavior* it triggers changes, the test-id does not).
- The X icon SVG stays (the close button still "closes"/collapses).

> **ARIA disclosure pattern (deepen — accessibility).** The canonical WAI-ARIA disclosure pattern puts `aria-expanded` on a *single persistent toggle* that controls the disclosed region. Here the control physically swaps (X button when expanded ↔ full-width strip when collapsed), so each rendered control carries `aria-expanded` reflecting the *current* state: expanded close button → `aria-expanded={true}`, collapsed strip → `aria-expanded={false}`. This matches the repo's three existing disclosure controls — `chat/debug-stream-panel.tsx:105`, `dashboard/org-switcher.tsx:116`, `kb/file-tree.tsx:204` — all of which expose `aria-expanded={state}` on the toggle. **Do NOT add `aria-controls`** (none of the three precedents do; it is YAGNI for a marketing banner with no separately-identifiable controlled region). **Focus management:** do not script focus moves on collapse/expand. The collapse button and the reopen strip are adjacent in the DOM/tab order, so a keyboard user who activates collapse lands naturally on the reopen strip on next tab; an explicit `focus()` call is unnecessary complexity for this surface and risks a focus-trap-flavored surprise.

> **Note — close-button label change is intentional and the waitlist test does NOT key on it.** `shared-cta-banner-waitlist.test.tsx` keys on the email input, the `/^join$/i` submit button, the privacy link, and the aria-live region — none reference the dismiss button's `aria-label`. Verified by grep (no `dismiss`/`Dismiss signup` reference in that file). The close test (`shared-cta-banner-close.test.tsx`) DOES reference `/dismiss signup banner/i` at line 25 and is being rewritten in Phase 2 — so the label change is absorbed there.

**1.5 — Animation (Tailwind/CSS, reduced-motion aware).**
- Wrap the expand/collapse transition on the **expanded panel's inner content** (the `mx-auto flex … flex-col` wrapper) with a transform+opacity transition: `transition-all duration-300 ease-out` plus `motion-reduce:transition-none motion-reduce:duration-0`.
- Drive the visual slide/fade off the `panel` value: expanded → `translate-y-0 opacity-100`; while collapsing, the collapsed strip mounts (the collapsed strip itself can carry a matching `transition-all duration-300 … motion-reduce:transition-none`).
- **Reduced-motion contract:** every `transition-*`/`duration-*` utility added MUST be paired with a `motion-reduce:` reset (`motion-reduce:transition-none` and/or `motion-reduce:duration-0`) so that under `prefers-reduced-motion: reduce` the state change is instant. Tailwind v4's `motion-reduce:` variant compiles to `@media (prefers-reduced-motion: reduce)` — no JS needed.
- Keep the animation simple: a CSS class swap on state, not a JS-timed mount/unmount sequence. The collapsed strip and expanded panel are **conditionally rendered on `panel`** (mutually exclusive); the transition utilities make the swap feel smooth without an animation library or exit-animation orchestration. (See Sharp Edges on why a class-swap, not a height-animated single element, is the YAGNI choice.)

> **Animation scope — entry eases in, exit is instant (deepen — frontend honesty).** Because the two panels are conditionally rendered (mutually exclusive), the *outgoing* panel unmounts immediately — a Tailwind transform/opacity transition only animates the *incoming* panel as it mounts (CSS transitions need the element present to animate). So "smooth animation" here means: on collapse, the thin strip eases in; on re-open, the full banner eases in. There is **no exit animation** on the panel being replaced. This is deliberate and YAGNI-correct for a marketing banner — a true crossfade would require always-mounting both panels and toggling `opacity`/`translate`/`pointer-events` by state plus managing the collapsed height during the expanded→collapsed transition, which is disproportionate complexity for this surface. The locked-decision phrase "re-open (and collapse) use a smooth animation" is satisfied by the incoming-panel ease-in; do not over-build an exit-animation orchestration to chase a crossfade. **Entry-animation mechanic:** the cleanest CSS-only way to ease in a freshly-mounted element is a small initial-mount transition. If a pure `transition-*` class on a conditionally-rendered element does not visibly animate (the element mounts already at its final transform), use the `starting-style`-free approach: mount the incoming panel and toggle a one-frame state via a `useEffect(() => setEntered(true), [])`-style flag that flips `translate-y-1 opacity-0` → `translate-y-0 opacity-100`. Keep this minimal; if the unanimated conditional-render swap reads acceptably in QA, the entry flag can be dropped entirely (simplest path — verify visually at /work time).

**1.6 — Unchanged:** `handleSubmit`, the `Status` type, the success branch, the form markup, the honeypot, the privacy line, and the aria-live error region all stay byte-identical. `/api/waitlist` is not touched.

### Phase 2 — Rewrite `shared-cta-banner-close.test.tsx`

File: `apps/web-platform/test/shared-cta-banner-close.test.tsx`

Rewrite the suite to assert the new collapse/reopen contract. Delete the four sessionStorage-coupled / unmount-coupled cases; replace with collapse→reopen→form-restored coverage. Keep the `beforeEach`/`afterEach` cleanup shape.

New cases (names indicative):
1. **renders the waitlist form and the collapse (close) button by default** — `getByPlaceholderText(/you@company.com/i)` truthy; `getByTestId("cta-banner-dismiss")` truthy; the reopen button (`cta-banner-reopen`) is absent (`queryByTestId(...)` null).
2. **collapsing shows the thin bar — the banner is NOT unmounted** — click `cta-banner-dismiss`; assert the collapsed strip is present (`getByTestId("cta-banner-reopen")` truthy, OR `getByRole("button", { name: /reopen soleur signup banner/i })` truthy); assert the form input is gone (`queryByPlaceholderText(/you@company.com/i)` null); assert the "Built with"/"Soleur" label text is present in the collapsed strip.
3. **the collapsed bar exposes the reopen affordance with correct aria** — after collapse, the reopen button has `aria-label="Reopen Soleur signup banner"` and `aria-expanded="false"`. (Use `getByRole("button", { name: /reopen soleur signup banner/i })` and assert `getAttribute("aria-expanded") === "false"`.)
4. **clicking the collapsed bar re-expands the full banner with the form** — click the reopen button; assert the email input is back (`getByPlaceholderText(/you@company.com/i)` truthy) and the reopen button is gone (`queryByTestId("cta-banner-reopen")` null). This is the round-trip without reload.
5. **the close control is keyboard-operable** — the collapsed strip and the close button are real `<button>` elements; assert `getByTestId("cta-banner-reopen").tagName === "BUTTON"` (and likewise the expanded close control). (A `<button>` is inherently Enter/Space-activatable; asserting the element type is the deterministic, jsdom-stable proxy for keyboard operability — see Sharp Edges on why we assert the element, not synthesize a keydown.)
6. **does NOT persist collapsed state — no sessionStorage write occurs on collapse** — spy or read: after clicking collapse, `sessionStorage.getItem("soleur:shared:cta-dismissed")` is `null` AND `sessionStorage.length === 0` (nothing written). This is the explicit "no persistence remains" guard.
7. **a fresh mount always starts expanded even if the old key is set** — pre-seed `sessionStorage.setItem("soleur:shared:cta-dismissed", "1")`, then `render(<CtaBanner />)`; assert the form is present (expanded) — proves the component no longer reads the old key (reload-restores-full-banner behavior at the unit level).

Remove the two `safeSession`-throwing cases (lines 56-75 of the current file): the component no longer touches sessionStorage on this path, so those error-tolerance cases are now vacuous. (If a reviewer wants belt-and-suspenders, a single "render does not throw" smoke case may remain, but the storage-throw mocks are dead.)

### Research Insights — Test determinism under happy-dom

- **No `matchMedia` stub needed (confirmed load-bearing).** happy-dom does not provide `window.matchMedia` (see `test/dashboard-sidebar-collapse.test.tsx:71`). Because reduced-motion is handled by the CSS-only `motion-reduce:` variant (not JS), the rewritten suite needs **zero** matchMedia plumbing. If a future revision switches to JS `matchMedia`, every case here would need a `vi.stubGlobal("matchMedia", …)` in `beforeEach` or crash — another reason to keep the CSS approach.
- **Case 5 (`tagName === "BUTTON"`) is the correct keyboard-operability assertion under happy-dom.** Synthesizing `fireEvent.keyDown(el, { key: "Enter" })` on a `<button>` does NOT auto-dispatch a `click` in happy-dom/jsdom the way a real browser's native button activation does — so a keydown-based test would assert nothing meaningful unless the component hand-rolls a keydown handler (it should not; native `<button>` is keyboard-activatable by platform contract). Asserting the element IS a `<button>` is the deterministic proxy. Do not add a synthetic keydown.
- **Case 6 (`sessionStorage.length === 0`) is robust.** `beforeEach` calls `sessionStorage.clear()` and `setup-dom.ts` also scrubs storage between files; after a collapse click the only way `length` is non-zero is an errant write — exactly what the case guards. The paired `getItem("soleur:shared:cta-dismissed") === null` makes the intent explicit.
- **Waitlist suite independence confirmed by grep.** `grep -c "dismiss\|Dismiss\|cta-banner-dismiss" test/shared-cta-banner-waitlist.test.tsx` → **0**. The close button's `aria-label` change (`Dismiss signup banner` → `Collapse signup banner`) cannot break the waitlist suite; it keys only on the email input, `/^join$/i`, the privacy link, and the aria-live region. Phase 3 "no edits" holds.

### Phase 3 — Keep `shared-cta-banner-waitlist.test.tsx` green (no edits expected)

File: `apps/web-platform/test/shared-cta-banner-waitlist.test.tsx`

Do **not** edit this file. The form-submit behavior is unchanged, and the suite keys on the email input, the `/^join$/i` button, the privacy link, the aria-live region, and the success copy — none of which this change touches. Run it to confirm green after Phase 1.

> If Phase 1 inadvertently changes a selector this suite depends on, that is a regression in Phase 1 — fix the component, not the test.

### Phase 4 (optional) — Extend the wireframe with the collapsed state

File: `knowledge-base/product/design/shared-document/cta-banner-waitlist.pen`

Add a frame "Desktop — Collapsed (thin bar)" mirroring the existing "Desktop — Idle (two-tier)" frame's Banner Bar footprint (`width 768`, `fill #141414F2`, `stroke top 1 #2A2A2A`) but with a single horizontal row: the "Built with Soleur" text (gold `#…` accent on "Soleur") on the left and an up-chevron glyph on the right. This is optional polish; it does not gate the code change. If Pencil tooling is unavailable at work-time, the `.pen` extension may be deferred (documentation artifact, not a UI-feature wireframe gate — the wireframe for this surface already exists from #5035).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Collapse shows a thin bar, not an empty/unmounted state.** After clicking `cta-banner-dismiss`, `screen.getByTestId("cta-banner-reopen")` is truthy and the "Built with"/"Soleur" label is present in the collapsed strip. Verified by `shared-cta-banner-close.test.tsx` case 2.
- [ ] **AC2 — Reopen restores the full banner with the form, no reload.** After collapse, clicking the reopen button makes `screen.getByPlaceholderText(/you@company.com/i)` truthy again and removes `cta-banner-reopen`. Verified by case 4.
- [ ] **AC3 — Reload restores the full banner (no sessionStorage persistence).** Collapse writes nothing to sessionStorage: after collapse, `sessionStorage.getItem("soleur:shared:cta-dismissed") === null` and `sessionStorage.length === 0`. A fresh mount with the old key pre-seeded still renders expanded. Verified by cases 6 + 7. Source-level guard: `grep -c "safeSession\|STORAGE_KEY\|sessionStorage" apps/web-platform/components/shared/cta-banner.tsx` returns `0`.
- [ ] **AC4 — `prefers-reduced-motion` is honored.** Every `transition-*`/`duration-*` utility added in the component is paired with a `motion-reduce:` reset. Source-level guard: `grep -nE "transition-|duration-" apps/web-platform/components/shared/cta-banner.tsx` — for each match on an animated element, a `motion-reduce:transition-none` (and/or `motion-reduce:duration-0`) appears on the same element's `className`. (Manual review of the diff; no runtime assertion since happy-dom does not evaluate `@media`.)
- [ ] **AC5 — Collapsed bar is an accessible, keyboard-operable button with correct aria.** The reopen control is a `<button>` with `aria-label="Reopen Soleur signup banner"` and `aria-expanded="false"`; the expanded close control carries `aria-expanded="true"`. Verified by cases 3 + 5.
- [ ] **AC6 — Waitlist form submit behavior unchanged; its test stays green.** `./node_modules/.bin/vitest run test/shared-cta-banner-waitlist.test.tsx` passes with zero edits to that file.
- [ ] **AC7 — Full target suite green.** From `apps/web-platform/`: `./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx` passes.
- [ ] **AC8 — Typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (NOT `npm run -w` — repo root declares no `workspaces`).
- [ ] **AC9 — `lib/safe-session.ts` is untouched.** `git diff --name-only` does not include `apps/web-platform/lib/safe-session.ts`. Its other consumers (`chat-input.tsx`, `use-kb-layout-state.tsx`) are unaffected.

## Test Scenarios

1. Default render → form + collapse button visible, no reopen button. (close-test case 1)
2. Click collapse → thin bar present, form gone, banner still mounted. (case 2)
3. Collapsed bar aria → `aria-label="Reopen Soleur signup banner"`, `aria-expanded=false`. (case 3)
4. Click reopen → full banner + form restored. (case 4)
5. Both controls are `<button>` elements (keyboard-operable). (case 5)
6. Collapse writes nothing to sessionStorage. (case 6)
7. Fresh mount with stale key set → still expanded. (case 7)
8. Form submit success/error/in-flight → unchanged. (waitlist suite, untouched)

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — `ux-design-lead` not required: this modifies an existing user-facing component (the banner shipped in #5035 with its `.pen` wireframe already committed at `knowledge-base/product/design/shared-document/cta-banner-waitlist.pen`). No NEW user-facing page/flow/component file is created (the change edits one existing `.tsx`; `## Files to Create` is empty). The mechanical BLOCKING escalation (new `components/**/*.tsx`) does NOT fire — no new component file. Per the gate's ADVISORY rule, a UI-modifying change with no new interactive surface auto-accepts in pipeline context. The optional `.pen` collapsed-state frame (Phase 4) extends the existing wireframe rather than producing a net-new one.

#### Findings

Presentational micro-interaction on an already-designed surface. Footprint, palette, copy, and gold accent are reused verbatim from the shipped banner. No new copy of persuasive/emotional weight (the collapsed strip reuses the existing "Built with Soleur" line). No conversion-flow change — the waitlist form is byte-identical. No CMO/CRO/CPO concerns surfaced.

## Infrastructure (IaC)

None. Pure client-component code change against an already-provisioned surface (`apps/web-platform/components/**` + `test/**`). No server, service, secret, vendor, cron, DNS, or persistent runtime process introduced. Phase 2.8 skip conditions met.

## Observability

Not applicable — skip per Phase 2.9 skip conditions. This is a presentational client-component change; Files-to-Edit are `apps/web-platform/components/shared/cta-banner.tsx` (client `"use client"` React component) and `apps/web-platform/test/**`. No code under `server/`, `infra/`, no new infrastructure surface, no new runtime process, no liveness/error-reporting/failure-mode surface. The component does not log, emit telemetry, or fetch on the collapse/expand path (the form-submit `fetch` is unchanged and already covered by the waitlist suite). There is no dark-observability surface to declare.

## Files to Edit

- `apps/web-platform/components/shared/cta-banner.tsx` — state model (`expanded|collapsed`), collapsed strip `<button>`, reduced-motion-aware transitions, remove `safeSession`/`STORAGE_KEY`, close-button aria/handler change.
- `apps/web-platform/test/shared-cta-banner-close.test.tsx` — full rewrite to collapse/reopen/no-persistence contract.
- `knowledge-base/product/design/shared-document/cta-banner-waitlist.pen` — (optional, Phase 4) add a "Desktop — Collapsed (thin bar)" frame.

## Files to Create

None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` cross-referenced against `cta-banner` (and the edited file paths) returned zero matches at plan-write time.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| JS `matchMedia('(prefers-reduced-motion: reduce)')` (or the `useMediaQuery` hook) to gate animation | Heavier than needed and adds happy-dom `matchMedia` test plumbing. Tailwind v4's built-in `motion-reduce:` variant is CSS-only, matches locked decision #4 ("plain Tailwind/CSS transitions"), and needs no JS. **Chosen: `motion-reduce:` variant.** |
| Single always-mounted element animated by `max-height`/`height` transition (true collapse animation) | `height: auto` is not animatable in CSS without a JS-measured pixel height or a grid-rows hack; brings exit-animation orchestration and layout-measurement complexity for a marketing banner. YAGNI — a conditional-render class-swap with transform+opacity transitions reads as smooth enough and is far simpler. **Chosen: conditional render + transform/opacity transition.** |
| Persist collapsed state to sessionStorage (keep the key, flip semantics) | Explicitly rejected by locked decision #5 — reload must restore the full banner. Removing the write is part of the spec. |
| Delete `lib/safe-session.ts` entirely | Shared util with two other live consumers (`chat-input.tsx`, `use-kb-layout-state.tsx`). Deleting it breaks them. Only the cta-banner usage is removed. |
| Synthesize `keyDown` Enter/Space in the test to "prove" keyboard operability | happy-dom does not translate a synthetic `keydown` on a `<button>` into a `click` the way a real browser does; asserting `tagName === "BUTTON"` is the deterministic proxy (a native button IS keyboard-activatable by platform contract). **Chosen: assert element type.** |

## Risks & Mitigations

- **Risk: a leftover `dismissed`/`return null` path or stray `safeSession` import.** Mitigation: AC3 source guard greps the component for `safeSession|STORAGE_KEY|sessionStorage` → must be 0.
- **Risk: the close test's old `/dismiss signup banner/i` label assertion (line 25) breaks after the aria-label change.** Mitigation: that test file is fully rewritten in Phase 2; the new case 1 asserts the new label semantics. The label change lives entirely within the rewritten suite.
- **Risk: an added `transition-*` utility without a `motion-reduce:` pair silently ships an animation that ignores reduced-motion.** Mitigation: AC4 diff-review pairing rule; the plan enumerates the exact paired utilities.
- **Risk: vitest never collects the test because of a wrong path glob.** Mitigation: both target files are already at `test/*.test.tsx`, which the `component` project's `include: ["test/**/*.test.tsx"]` collects (verified against `vitest.config.ts`). Run command uses `./node_modules/.bin/vitest`, not `bun test` (blocked by `bunfig.toml`).

## Sharp Edges

- **`lib/safe-session.ts` is shared — remove the import + call sites in `cta-banner.tsx`, never the file.** `grep -rln safeSession apps/web-platform --include='*.tsx' --include='*.ts'` shows three non-test consumers: `cta-banner.tsx` (being changed), `chat-input.tsx`, and `hooks/use-kb-layout-state.tsx`. Deleting the util would break the latter two.
- **Test runner is vitest, not bun.** `apps/web-platform/bunfig.toml` sets `[test] pathIgnorePatterns = ["**"]` — `bun test <file>` reports "filter did not match" even when the file exists. Use `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.
- **Typecheck is the in-package `tsc`, not `npm run -w`.** The repo root `package.json` declares no `workspaces` field, so `npm run -w apps/web-platform typecheck` aborts with "No workspaces found". Use `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **happy-dom does not evaluate `@media (prefers-reduced-motion)`.** AC4 is a static diff-review guard (utility pairing), not a runtime assertion — do not attempt to assert computed transition values in the component test.
- **A plan whose `## User-Brand Impact` section is empty or placeholder-only will fail `deepen-plan` Phase 4.6.** This plan's section is filled with a concrete artifact, exposure-vector N/A justification, and a `none` threshold — complete.

## PR-body reminder

Use `Closes #<issue>` in the PR **body** (not title) if a tracking issue is filed. No operator post-merge steps — pure client-component change; a merge to `main` touching `apps/web-platform/**` triggers the standard `web-platform-release.yml` container restart automatically.
