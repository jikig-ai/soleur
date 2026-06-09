---
lane: single-domain
plan: knowledge-base/project/plans/2026-06-09-feat-cta-banner-rotating-arrow-two-way-animation-plan.md
branch: feat-one-shot-banner-rotating-arrow-twoway-anim
---

# Tasks — CTA banner: single rotating arrow + two-way collapse animation

Single-component change + its test rewrite. No backend/API/infra change. TDD: rewrite the close test (RED) → re-architect the component (GREEN). Waitlist test stays green AND unedited.

## Phase 0 — Setup & Preconditions

- [x] 0.1 Baseline typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`; repo root declares no `workspaces`).
- [x] 0.2 Baseline both target suites green: `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx`.
- [x] 0.3 Re-confirm structure of `components/shared/cta-banner.tsx`: `<Reveal>` helper (lines ~12-38), two conditional-return panels, `cta-banner-dismiss` X (two `<line>`), `cta-banner-reopen` up-chevron.

## Phase 1 — Rewrite close test (RED)

- [x] 1.1 Rewrite `test/shared-cta-banner-close.test.tsx` for the single-toggle structure. Keep `STORAGE_KEY = "soleur:shared:cta-dismissed"`, `beforeEach/afterEach` `sessionStorage.clear()` + `vi.restoreAllMocks()`. Drive all transitions via `fireEvent.click` on the SAME render (no remount). Retire `cta-banner-dismiss`/`cta-banner-reopen` and the `reopenPresent()` helper.
  - [x] 1.1.1 Default render: form present (`queryByPlaceholderText(/you@company.com/i)`) + `getByTestId("cta-banner-toggle")` with `aria-expanded === "true"`.
  - [x] 1.1.2 Click toggle collapses: `aria-expanded === "false"`; `aria-label` matches `/reopen soleur signup banner/i`; "Built with" header still visible (persistent); body wrapper (`data-testid="cta-banner-body"`) has `inert` OR `aria-hidden="true"`. Do NOT assert the form is removed.
  - [x] 1.1.3 Click again re-expands: `aria-expanded === "true"`; `aria-label` matches `/collapse signup banner/i`; body no longer `inert`/`aria-hidden`.
  - [x] 1.1.4 Toggle is a single persistent `<button>` (`tagName === "BUTTON"`), resolvable by `cta-banner-toggle` in default, after collapse, and after re-expand (does not unmount).
  - [x] 1.1.5 No sessionStorage write on toggle: `vi.spyOn(Storage.prototype, "setItem")` not called; `sessionStorage.getItem(STORAGE_KEY)` null; `sessionStorage.length === 0`.
  - [x] 1.1.6 Fresh mount with legacy key pre-seeded (`sessionStorage.setItem(STORAGE_KEY, "1")`) still renders expanded (form present + toggle `aria-expanded="true"`).
- [x] 1.2 Run close test → expect RED (component still old structure). Confirm waitlist test still green (untouched).

## Phase 2 — Re-architect component (GREEN)

- [x] 2.1 Delete the `<Reveal>` helper; drop now-unused imports (`ReactNode`, and `useEffect` if `Reveal` was its only consumer — confirm via `tsc`). Keep `FormEvent`.
- [x] 2.2 Remove the two conditional-return panels. Keep `Panel = "expanded" | "collapsed"` + `useState<Panel>("expanded")`. Add a single `toggle()` (or inline `setPanel(p => p === "expanded" ? "collapsed" : "expanded")`).
- [x] 2.3 Single persistent shell, exact footprint preserved: `fixed bottom-0 left-0 right-0 z-40 border-t border-soleur-border-default bg-soleur-bg-surface-1/95 backdrop-blur-sm`; inner `mx-auto max-w-3xl`; single stable `px-4 py-3` (no state-swapped padding).
- [x] 2.4 Persistent header row (always rendered): left = "Built with **Soleur**" (gold `text-soleur-accent-gold-fg` on "Soleur"; keep the full "— AI agents…" sentence); right = the toggle button.
- [x] 2.5 Toggle `<button type="button" data-testid="cta-banner-toggle">`:
  - [x] 2.5.1 `onClick` flips panel; `aria-expanded={panel === "expanded"}`.
  - [x] 2.5.2 `aria-label`: "Collapse signup banner" (expanded) / "Reopen Soleur signup banner" (collapsed).
  - [x] 2.5.3 One chevron-up svg `<polyline points="18 15 12 9 6 15" />` with `transition-transform duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0`; toggle `rotate-180` by state.
  - [x] 2.5.4 Mapping comment: `// COLLAPSED = rotate-0 (chevron points UP = "expand"); EXPANDED = rotate-180 (points DOWN = "collapse").`
- [x] 2.6 Collapsible body wrapper `data-testid="cta-banner-body"`: `grid transition-[grid-template-rows] duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0` + ternary `panel === "expanded" ? "grid-rows-[1fr]" : "grid-rows-[0fr]"` (two WHOLE literals, no string concat); `inert={panel === "collapsed" || undefined}`; `aria-hidden={panel === "collapsed" || undefined}`. Inner `<div className="overflow-hidden">` holds the form/success block.
- [x] 2.7 Move the existing `status === "success" ? <success-message> : <form>` block VERBATIM into the inner `overflow-hidden` div. Preserve: email input + placeholder, honeypot `url` field, Privacy Policy link, success copy, and the persistent `role="status" aria-live="polite"` error region. Do NOT gate this conditional on `panel`.
- [x] 2.8 Run close test → GREEN. Run waitlist test → still GREEN (and unedited).

## Phase 3 — Verify

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx` — both green.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] 3.3 Component residue grep: no `Reveal`, no `cta-banner-dismiss`, no `cta-banner-reopen`, no `<line `, no `sessionStorage`/`safeSession`.
- [x] 3.4 Motion-reduce pairing grep: both `transition-[grid-template-rows]` and `transition-transform` are each paired with `motion-reduce:transition-none motion-reduce:duration-0`.
- [x] 3.5 `git diff --quiet -- apps/web-platform/test/shared-cta-banner-waitlist.test.tsx` returns clean (waitlist test unedited).
- [x] 3.6 (Optional) `./node_modules/.bin/vitest run test/shared-*.test.tsx` — the 5 mocked sibling suites unaffected.

## Acceptance Criteria (see plan for full text)

AC1 two-way grid animation · AC2 single rotating chevron / no cross · AC3 reduced-motion pairing on both transitions · AC4 inert/aria-hidden + aria-expanded + flipping aria-label + keyboard-operable button · AC5 persistence unchanged (no sessionStorage) · AC6 close test rewritten & green · AC7 waitlist test green & UNEDITED · AC8 tsc --noEmit clean.

Post-merge (operator): none.
