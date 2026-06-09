---
type: feat
lane: single-domain
brand_survival_threshold: none
branch: feat-one-shot-banner-rotating-arrow-twoway-anim
created: 2026-06-09
component: apps/web-platform/components/shared/cta-banner.tsx
---

# ✨ feat: CTA banner — single rotating arrow + two-way collapse animation

## Enhancement Summary

**Deepened on:** 2026-06-09
**Sections enhanced:** Research Insights (Tailwind/inert/motion-reduce verification), Risks (happy-dom inert), Domain Review (wireframe reference)
**Verification passes used:** verify-the-negative, Tailwind-arbitrary-value confirmation (installed v4.2.1 + in-repo precedent), inert precedent-diff (Phase 4.4), mandatory gates 4.6/4.7/4.8/4.9

### Key Improvements
1. Confirmed the one novel-to-this-file technique (`grid-rows-[0fr↔1fr]` + `transition-[grid-template-rows]`) compiles under the installed Tailwind v4.2.1 — proven by in-repo `grid-cols-[1fr_auto…]` and `transition-[width]` usage, including a ternary-of-two-whole-literals precedent at `team-membership-list.tsx:52`.
2. Pinned the exact `inert={cond || undefined}` precedent (`layout.tsx:293,519`) and the in-file `motion-reduce` idiom — both adopted verbatim, zero novelty.
3. Resolved the Phase 4.9 wireframe gate via the already-committed `cta-banner-waitlist.pen` (PR #5035) for this exact surface.

### New Considerations Discovered
- happy-dom `inert` IDL reflection is unreliable → assert on `hasAttribute("inert")` / `aria-hidden`, not `.inert`.
- The state-swapped shell padding (`py-2`/`py-3`) from PR #5075 collapses to a single `py-3` since height now animates via the grid, not padding.

## Overview

Refine the shared-document waitlist CTA banner (`apps/web-platform/components/shared/cta-banner.tsx`, last changed by **PR #5075** which added collapse/reopen) with two presentational UX improvements:

1. **Animate both directions** (open AND close). Re-architect from two mutually-exclusive conditionally-rendered panels (each wrapped in the `<Reveal>` mount-flag helper that animates only the *incoming* panel) to a **single persistent structure**: a persistent header row + a collapsible body animated with the CSS `grid-template-rows: 0fr ↔ 1fr` technique. Both open and close ease smoothly with no JS height measurement.
2. **One rotating arrow** (no cross). Replace the X close icon with a **single persistent chevron** `<button>` that stays mounted across both states and rotates 180° between them via `transition-transform`. No X/cross icon anywhere.

Single-component change plus its test rewrite. **No backend/API change** — `/api/waitlist` and the form-submit state machine (`idle | submitting | success | error`) stay byte-for-byte identical. Persistence stays in-memory only (reload restores expanded); sessionStorage/safeSession are NOT reintroduced.

**Scope:** `apps/web-platform/components/shared/cta-banner.tsx` + `apps/web-platform/test/shared-cta-banner-close.test.tsx`. The waitlist test (`shared-cta-banner-waitlist.test.tsx`) must stay green **and unedited**.

## Premise Validation

- **PR #5075** (`feat(shared): collapse shared-doc waitlist banner to a reopenable bar`) — `gh pr view 5075` confirms `state: MERGED`, `mergedAt: 2026-06-09T08:18:12Z`. The current-state description (expanded/collapsed `useState`, `<Reveal>` helper, `data-testid="cta-banner-dismiss"` X-icon with two `<line>`, `data-testid="cta-banner-reopen"` up-chevron polyline) was confirmed by reading the file directly — **matches exactly**.
- **Legacy sessionStorage key** `"soleur:shared:cta-dismissed"` — the component already does NOT read or write it (grep of the file shows zero `sessionStorage`/`safeSession` references; the test pre-seeds the key purely to assert the component ignores it). Premise holds.
- No external blocker/dependency issues cited. No stale premise found.

## Research Reconciliation — Spec vs. Codebase

| Spec/args claim | Codebase reality | Plan response |
| --- | --- | --- |
| `cta-banner-dismiss` = X-icon (two `<line>` cross) in expanded; `cta-banner-reopen` = up-chevron in collapsed | Confirmed at `cta-banner.tsx:137-152` (cross) and `:90-113` (polyline `18 15 12 9 6 15`) | Both testids retired; replaced by a single `cta-banner-toggle` |
| `<Reveal>` mount-flag helper animates incoming panel only | Confirmed at `cta-banner.tsx:17-38` (rAF `entered` flag, `transition-[transform,opacity]`) | Helper deleted entirely |
| Persistence already removed; in-memory only | Confirmed — no `sessionStorage` in file | Unchanged; do NOT reintroduce |
| Waitlist test must stay green & unedited | `shared-cta-banner-waitlist.test.tsx` renders default (expanded) state, exercises form/success/error swap; line 60 asserts `queryByPlaceholderText(...)` is `null` **on success** | The form↔success conditional (`status === "success" ? … : <form>`) is ORTHOGONAL to collapse and is preserved verbatim inside the collapsible body. Line 60 stays true because success still swaps the form out. The aria-live region (test line 34-41) renders in default-expanded state → present. ✅ No component change is forced by this suite. |
| 5 other test files reference the banner | `shared-image-a11y`, `shared-page-diagram`, `shared-page-head-first`, `shared-page-ui`, `shared-token-content-changed-ui` all `vi.mock` `CtaBanner` to a stub `<div data-testid="cta-banner" />` | Fully insulated — they never touch internals. No edits needed. |
| `inert` attribute support | Prior art at `app/(dashboard)/layout.tsx:289,293,519` uses React's `inert={cond \|\| undefined}` pattern (React 19 strips `undefined`; `inert` is a real boolean attr) | Adopt verbatim: `inert={collapsed \|\| undefined}` on the body wrapper |
| `grid-rows-[1fr]/[0fr]` technique | **No prior art** in `apps/web-platform/**/*.tsx` (grep returned zero) | Pattern is novel in this repo but is a well-established CSS idiom; documented inline with a comment |

## User-Brand Impact

**If this lands broken, the user experiences:** a shared-document viewer whose waitlist banner either fails to collapse/expand (stuck panel), shows a janky snap instead of a smooth animation, or has a tab-trap (form inputs reachable while visually collapsed). Worst realistic case: the toggle does nothing and the banner is permanently expanded — annoying, not destructive; the document content above it is unaffected.

**If this leaks, the user's data is exposed via:** N/A — this component sends only the email the user voluntarily types into the existing waitlist form to the unchanged `/api/waitlist` endpoint. No new data flow, no new persistence, no PII surface introduced.

**Brand-survival threshold:** `none`. Rationale: presentational micro-interaction on an already-shipped banner; a regression degrades polish, not user data, money, or workflow. The diff touches no sensitive path (component is client-only presentational TSX; no schema/auth/API/migration). `threshold: none, reason: presentational micro-interaction on an existing client component; no data/money/workflow surface and no sensitive-path file touched.`

## Implementation Phases

> TDD: rewrite the close test first (RED), then re-architect the component (GREEN). The waitlist test must stay green throughout — run it after every component change.

### Phase 0 — Preconditions (verify before editing)

- [ ] `tsc --noEmit` baseline clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w` — repo root declares no `workspaces`).
- [ ] Both target suites green at baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx`.
- [ ] Confirm React major supports bare `inert` boolean prop (prior art `app/(dashboard)/layout.tsx:293` already ships `inert={cond || undefined}` → supported).

### Phase 1 — Rewrite the close test (RED)

Rewrite `apps/web-platform/test/shared-cta-banner-close.test.tsx` for the single-toggle structure. Drive ALL transitions via `fireEvent.click` on the **same render** (in-component state machine; never remount). Keep `STORAGE_KEY = "soleur:shared:cta-dismissed"`, `beforeEach`/`afterEach` `sessionStorage.clear()` + `vi.restoreAllMocks()`.

Required cases (the test file is the contract):

1. **Default render**: form present (`queryByPlaceholderText(/you@company.com/i)` truthy) + single toggle `getByTestId("cta-banner-toggle")` with `aria-expanded === "true"`.
2. **Click toggle collapses**: after one click — `aria-expanded === "false"`; `aria-label` matches `/reopen soleur signup banner/i`; the persistent "Built with Soleur" header is **still visible** (`getByText(/built with/i)` truthy — it lives in the always-rendered header now); the collapsible **body wrapper is `inert` OR `aria-hidden="true"`**. **Do NOT assert the form is removed** — grid-collapse keeps it in the DOM. Assert on the body wrapper via a stable hook (`data-testid="cta-banner-body"`): `body.hasAttribute("inert") || body.getAttribute("aria-hidden") === "true"`.
3. **Click again re-expands**: `aria-expanded === "true"`; `aria-label` matches `/collapse signup banner/i`; body no longer `inert` (and `aria-hidden` absent/false).
4. **Toggle is a single persistent `<button>`**: `getByTestId("cta-banner-toggle").tagName === "BUTTON"`; present in BOTH states (capture the element ref before the first click, assert the same testid resolves after collapse and after re-expand — it does not unmount). A clean way: assert `getByTestId("cta-banner-toggle")` is non-null in default, after collapse, and after re-expand.
5. **No sessionStorage write on toggle**: `vi.spyOn(Storage.prototype, "setItem")` not called after a collapse click; `sessionStorage.getItem(STORAGE_KEY)` null; `sessionStorage.length === 0`.
6. **Fresh mount with legacy key pre-seeded still renders expanded**: `sessionStorage.setItem(STORAGE_KEY, "1")` then `render(<CtaBanner />)` → form present + `aria-expanded === "true"` on the toggle.

Retire the old selectors entirely: no `cta-banner-dismiss`, no `cta-banner-reopen`, no `reopenPresent()` helper. Run → expect RED (component still uses old structure).

### Phase 2 — Re-architect the component (GREEN)

Edit `apps/web-platform/components/shared/cta-banner.tsx`:

1. **Delete the `<Reveal>` helper** (lines 12-38) and its `ReactNode` import usage if now unused (keep `FormEvent`; drop `ReactNode` and the `useEffect` import if `Reveal` was their only consumer — verify with `tsc`).
2. **Remove the two-panel conditional return** (the `if (panel === "collapsed") return …` block and the separate expanded `return`). Keep the `Panel = "expanded" | "collapsed"` type and `useState<Panel>("expanded")`; rename handlers to a single `toggle()` that flips the panel (or inline an `onClick={() => setPanel(p => p === "expanded" ? "collapsed" : "expanded")}`).
3. **Single persistent shell** keeping the exact footprint: `fixed bottom-0 left-0 right-0 z-40 border-t border-soleur-border-default bg-soleur-bg-surface-1/95 backdrop-blur-sm`. Inner `mx-auto max-w-3xl`. (Note: the shell's vertical padding previously differed by state — `py-2` collapsed vs `py-3` expanded. Use a single stable padding, e.g. `px-4 py-3`, since the body now collapses to 0fr; document that the strip height shrinks via the grid, not via padding swap.)
4. **Persistent header row** (always rendered): left = the "Built with **Soleur**" line (gold `text-soleur-accent-gold-fg` on "Soleur"); right = the toggle button. Keep the "— AI agents for every department of your startup." tail copy in the expanded header if desired, but the load-bearing test text is "Built with" + "Soleur", which must always render. (Simplest: keep the full sentence in the header at all times — it is short and reads fine above the collapsed strip.)
5. **Toggle button** — single persistent `<button type="button" data-testid="cta-banner-toggle">`:
   - `onClick` flips `expanded ↔ collapsed`.
   - `aria-expanded={panel === "expanded"}`.
   - `aria-label`: `"Collapse signup banner"` when expanded, `"Reopen Soleur signup banner"` when collapsed (flips with state).
   - One chevron-up svg: `<polyline points="18 15 12 9 6 15" />` (points up). Wrap the svg (or apply to it) `transition-transform duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0` and toggle `rotate-180` by state.
   - **Mapping comment (verbatim intent):** `// COLLAPSED = rotate-0 (chevron points UP = "expand toward me"); EXPANDED = rotate-180 (points DOWN = "collapse"). Arrow points toward the action; 180° via transition-transform.`
6. **Collapsible body** — the grid technique:
   ```tsx
   {/* grid-template-rows 0fr↔1fr animates height in BOTH directions, no JS measurement. */}
   <div
     data-testid="cta-banner-body"
     className={`grid transition-[grid-template-rows] duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0 ${
       panel === "expanded" ? "grid-rows-[1fr]" : "grid-rows-[0fr]"
     }`}
     inert={panel === "collapsed" || undefined}
     aria-hidden={panel === "collapsed" || undefined}
   >
     <div className="overflow-hidden">
       {/* form OR success message — UNCHANGED conditional */}
     </div>
   </div>
   ```
   - The inner `overflow-hidden` div holds the existing `status === "success" ? <success-message> : <form>` block **verbatim** (preserve the form, honeypot, Privacy Policy link, and the persistent `role="status" aria-live="polite"` error region exactly — these are the waitlist-test selectors).
7. **Reduced motion**: every `transition-*`/`duration-*` utility (the grid-rows transition AND the transform rotation) MUST be paired with `motion-reduce:transition-none motion-reduce:duration-0`. The file already imports this idiom (it was on `<Reveal>`); re-apply to both new transition sites.

Run both suites → expect GREEN. Run `./node_modules/.bin/tsc --noEmit` → clean.

### Phase 3 — Verify

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx test/shared-cta-banner-waitlist.test.tsx` — both green.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [ ] Grep the component for residue: no `Reveal`, no `cta-banner-dismiss`, no `cta-banner-reopen`, no `<line `, no `sessionStorage`/`safeSession`.
- [ ] Grep both transition utilities are motion-reduce-paired (`transition-[grid-template-rows]` and `transition-transform` each followed by `motion-reduce:transition-none motion-reduce:duration-0`).
- [ ] (Optional, broader confidence) full component-project run: `./node_modules/.bin/vitest run test/shared-*.test.tsx` — the 5 mocked sibling suites should be unaffected.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — two-way animation**: component contains a single body wrapper with `grid transition-[grid-template-rows] … ease-out` toggling `grid-rows-[1fr]` (expanded) ↔ `grid-rows-[0fr]` (collapsed); the `<Reveal>` helper and the two-mutually-exclusive-panel conditional returns are gone. Verify: `grep -c "Reveal" cta-banner.tsx` returns 0; `grep -E "grid-rows-\[1fr\]|grid-rows-\[0fr\]" cta-banner.tsx` matches both.
- [x] **AC2 — single rotating arrow, no cross**: exactly one `<polyline points="18 15 12 9 6 15" />` chevron, wrapped in `transition-transform … rotate-180` toggled by state; **no `<line ` element anywhere** (`grep -c "<line " cta-banner.tsx` returns 0). Single `data-testid="cta-banner-toggle"`; old `cta-banner-dismiss`/`cta-banner-reopen` testids absent.
- [x] **AC3 — reduced motion**: both the grid-rows transition and the transform rotation are paired with `motion-reduce:transition-none motion-reduce:duration-0` (every `transition-`/`duration-` utility on the component has the motion-reduce pairing).
- [x] **AC4 — accessibility**: collapsed body wrapper carries `inert` (and `aria-hidden`); expanded removes both. Toggle has correct `aria-expanded` (`true` expanded / `false` collapsed) and flipping `aria-label` (`/collapse signup banner/i` expanded, `/reopen soleur signup banner/i` collapsed). Toggle is a real keyboard-operable `<button>` (`tagName === "BUTTON"`).
- [x] **AC5 — persistence unchanged**: no `sessionStorage`/`safeSession` in the component; the close-test's "no setItem on toggle" + "legacy key pre-seeded still renders expanded" cases pass.
- [x] **AC6 — close test rewritten & green**: `shared-cta-banner-close.test.tsx` covers the six cases above and passes; transitions driven via `fireEvent.click` on a single render (no remount).
- [x] **AC7 — waitlist test green & UNEDITED**: `shared-cta-banner-waitlist.test.tsx` is byte-for-byte unchanged and passes (`git diff --quiet -- apps/web-platform/test/shared-cta-banner-waitlist.test.tsx` returns clean after the work). If it would break, fix the **component**, not the test.
- [x] **AC8 — typecheck clean**: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.

### Post-merge (operator)

- None. Pure client-component change; no migration, deploy gate, or external-service config. The `web-platform-release.yml` path-filtered pipeline restarts the container on merge to `main` touching `apps/web-platform/**` — no separate operator step.

## Test Scenarios

| Scenario | Expectation |
| --- | --- |
| Default mount | Header "Built with Soleur" visible; body expanded (`grid-rows-[1fr]`); form present; toggle `aria-expanded=true`, chevron rotate-0 |
| Click toggle (collapse) | `grid-rows-[0fr]`; body `inert`+`aria-hidden`; form still in DOM but out of tab order; toggle `aria-expanded=false`, `aria-label` → reopen; chevron rotate-180 |
| Click toggle (re-expand) | Round-trips to default; body no longer inert; `aria-label` → collapse |
| Submit success (no collapse) | Form swaps to "You're on the list ✓" inside the body; email input gone (waitlist test line 60) — unaffected by collapse mechanism |
| Reload | In-memory state resets → expanded (no sessionStorage) |
| prefers-reduced-motion | Both collapse and rotation instant (motion-reduce pairing) — manual/visual; not unit-asserted |

## Risks & Mitigations

- **Waitlist test regression (highest risk).** The single-structure rewrite must NOT disturb the form/success/error conditional or its selectors (placeholder `you@company.com`, `/^join$/i` button, Privacy Policy link, the `role="status" aria-live="polite"` error region, the success `/you're on the list/i` copy). *Mitigation:* move the existing Tier-2 block **verbatim** into the inner `overflow-hidden` div; run the waitlist suite after every edit; AC7 asserts the test file is unedited.
- **Success-state + collapse interaction.** Test line 60 asserts the email input is `null` on success. This holds because success swaps `<form>`→`<success>` regardless of expand/collapse — orthogonal axes. *Mitigation:* keep `status === "success" ? … : <form>` as the inner conditional; do NOT gate it on `panel`.
- **`inert` + `aria-hidden` double-application.** React strips `false`/`undefined` boolean attrs; use `inert={panel === "collapsed" || undefined}` (prior art `layout.tsx:293`). Avoid `inert={false}` (renders `inert=""` in some DOM impls). *Mitigation:* the `|| undefined` idiom; the close test asserts the attribute is absent when expanded.
- **happy-dom `inert` reflection.** The component-project env is happy-dom; assert via `hasAttribute("inert")` (attribute presence), not the `.inert` IDL property, to avoid env-specific reflection gaps. *Mitigation:* test on the attribute; allow `aria-hidden="true"` as the OR-fallback per the args.
- **`grid-rows-[0fr]` arbitrary-value purge.** Tailwind must emit the arbitrary `grid-template-rows` utilities. *Mitigation:* both classes are static string literals in the className (not interpolated fragments), so Tailwind's content scanner picks them up; the ternary selects between two whole literals. Do NOT build the class via string concatenation of `grid-rows-[` + value.

## Domain Review

**Domains relevant:** Product (UI-surface override — edits `components/shared/cta-banner.tsx`).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — ADVISORY tier modifies an existing component without adding a new page, multi-step flow, or new interactive surface (the collapse/expand toggle already exists from PR #5075; this refines its icon and animation). No new `*.tsx` file is created, so the BLOCKING mechanical escalation (`components/**/*.tsx` *new file*) does not fire. `ux-design-lead` is N/A — no new user-facing surface to wireframe.
**Pencil available:** N/A (no new UI surface; presentational refinement of an existing control)

#### Findings

Presentational micro-interaction. No new flow, copy, or surface. Brand-survival threshold `none`. Auto-accepted per pipeline ADVISORY path.

**Wireframe reference:** This surface already has a committed wireframe — `knowledge-base/product/design/shared-document/cta-banner-waitlist.pen` (committed in PR #5035, 20.6 KB). This change refines the icon and animation of the *already-wireframed* shared-document CTA banner; it adds no new surface requiring a fresh `.pen`. The existing wireframe is the design-of-record for the banner's layout (header line + email-capture body), which this plan preserves structurally (header row + collapsible form body). Per `wg-ui-feature-requires-pen-wireframe`, the committed `.pen` for this surface satisfies the wireframe requirement.

## Infrastructure (IaC)

None. No server, service, cron, secret, DNS, cert, or vendor surface introduced. Pure client-component edit under `apps/web-platform/components/`. Phase 2.8 skipped.

## Observability

Skipped — no Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface. The only edited code file is a client-only presentational component (`apps/web-platform/components/shared/cta-banner.tsx`) plus its test. Phase 2.9 skip condition (pure client/component change, no new code/infra runtime surface) applies.

## Research Insights

**Deepened on:** 2026-06-09 (single-component presentational change — targeted verification rather than broad fan-out).

### Tailwind arbitrary-value support (the one novel-to-this-file technique) — VERIFIED

The `grid-rows-[1fr]`/`grid-rows-[0fr]` + `transition-[grid-template-rows]` technique has no prior art in `cta-banner.tsx`, but is fully supported by the installed toolchain and used elsewhere in the repo:

- **Installed Tailwind: v4.2.1** (`package.json` declares `tailwindcss: ^4.1.0`). Tailwind v4 JIT-compiles arbitrary values with no `safelist` config needed for static class literals.
- **Arbitrary `fr` grid values already ship**: `components/settings/delegation-funded-pane.tsx:57,68` and `team-membership-list.tsx:52,145` use `grid-cols-[1fr_auto_auto…]`. Arbitrary `fr` units compile correctly here.
- **Arbitrary-property transitions already ship**: `app/(dashboard)/layout.tsx:309`, `components/chat/review-gate-card.tsx:63`, `components/connect-repo/setting-up-state.tsx:29` all use `transition-[width]`. `transition-[grid-template-rows]` uses the identical arbitrary-property mechanism → will emit.
- **Ternary-of-two-whole-literals is a proven pattern**: `team-membership-list.tsx:52` selects between two whole arbitrary-value class strings via a ternary — exactly the `panel === "expanded" ? "grid-rows-[1fr]" : "grid-rows-[0fr]"` shape the plan prescribes. Confirms the content scanner picks up both branches when each is a complete literal (do NOT build the class via `"grid-rows-[" + value + "]"` concatenation).

### `inert` precedent (Phase 4.4 precedent-diff) — VERIFIED

`app/(dashboard)/layout.tsx:293` (`inert={signOutModalOpen || undefined}`) and `:519` (`inert={drawerOpen || undefined}`) ship the exact `inert={cond || undefined}` form the plan prescribes. React strips `false`/`undefined` boolean attrs; `inert` is a real boolean DOM attribute in React 19. Adopt verbatim. No deviation from precedent.

### `motion-reduce` precedent — VERIFIED

The current `<Reveal>` helper (`cta-banner.tsx:31`) already pairs `transition-[transform,opacity] duration-300 ease-out` with `motion-reduce:transition-none motion-reduce:duration-0`. The plan re-applies this exact pairing to the two new transition sites (grid-rows + transform). Idiom already in-file; zero novelty.

### Verify-the-negative pass — all CONFIRM

- "No `sessionStorage`/`safeSession`/`localStorage` in the component" → grep of `cta-banner.tsx` returns zero. CONFIRMS.
- "Only consumer is `app/shared/[token]/page.tsx`" → grep CONFIRMS (one import + one `{data && <CtaBanner />}` mount).
- "Waitlist test renders default (expanded) and never touches collapse controls" → grep of `shared-cta-banner-waitlist.test.tsx` for any collapse/toggle/reopen selector returns zero. CONFIRMS the form/success/error selectors are reachable in the default-expanded render and are unaffected by the collapse mechanism.
- "5 sibling shared-page test files mock `CtaBanner`" → each `vi.mock`s it to `<div data-testid="cta-banner" />`; fully insulated. CONFIRMS.

### Edge cases surfaced

- **happy-dom `inert` reflection**: assert via `element.hasAttribute("inert")` (attribute presence), not the `.inert` IDL property — happy-dom's IDL reflection of `inert` is less reliable than attribute presence. The args already allow `aria-hidden="true"` as the OR-fallback, which is robust in happy-dom.
- **Single padding vs state-swapped padding**: PR #5075 used `py-2` (collapsed) vs `py-3` (expanded) on the shell. With grid-collapse the body height is driven by `0fr↔1fr`, so collapse no longer needs a padding swap; use one stable `py-3`. The visible collapsed height is header-row + padding, which is intentional (a slim strip), matching the PR #5075 collapsed footprint closely enough for a polish change.
- **Success state inside the collapsible body**: the `status === "success" ? <success> : <form>` conditional must live INSIDE the inner `overflow-hidden` div and must NOT be gated on `panel`. The waitlist test's success case (input removed on success) depends on this being orthogonal to collapse.

### References

- Tailwind v4 arbitrary values / arbitrary properties: https://tailwindcss.com/docs/grid-template-rows (and the arbitrary-property `transition-[…]` form) — cross-checked against installed v4.2.1 and in-repo usage above.
- CSS `grid-template-rows: 0fr ↔ 1fr` height-animation technique: a well-established idiom for animating to/from auto height without JS measurement (works because `fr` is an interpolatable length-percentage in grid track sizing).

## Files to Edit

- `apps/web-platform/components/shared/cta-banner.tsx` — re-architect to single persistent structure; delete `<Reveal>`; single rotating-chevron toggle; grid-rows two-way animation; `inert`/`aria-hidden` on collapsed body; motion-reduce pairing on both transitions.
- `apps/web-platform/test/shared-cta-banner-close.test.tsx` — rewrite for the single-toggle structure (six cases above); retire `cta-banner-dismiss`/`cta-banner-reopen`; assert on `cta-banner-toggle` + `cta-banner-body`.

## Files to Create

- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (63 open) scanned against all three planned paths (`components/shared/cta-banner.tsx`, `shared-cta-banner-close.test.tsx`, `shared-cta-banner-waitlist.test.tsx`) — zero matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold `none` with reason.)
- **Both toggle states must render correctly** (collapse/expand control alignment + icon). Per learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`: verify the chevron and header align in BOTH expanded and collapsed states — the single-structure rewrite makes them share one DOM subtree, which de-risks this vs. the old two-panel split, but confirm the collapsed strip (header-only, body at 0fr) still aligns the chevron right.
- **Typecheck command is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`** — NOT `npm run -w apps/web-platform typecheck` (repo root declares no `workspaces`; the `-w` form aborts with "No workspaces found").
- **Test runner is vitest, not bun** — `apps/web-platform/bunfig.toml` has `[test] pathIgnorePatterns = ["**"]` blocking bun test discovery. Run `./node_modules/.bin/vitest run <path>`. Test files MUST live under `test/**/*.test.tsx` (the component-project `include:` glob) — both target files already do.
- **Waitlist test is load-bearing and unedited** — its success-case (line 60) and aria-live-region (lines 34-41) selectors constrain the component's inner form/success conditional. Do not move or rename those.
