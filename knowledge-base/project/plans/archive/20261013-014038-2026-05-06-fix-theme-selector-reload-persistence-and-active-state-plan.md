---
date: 2026-05-06
type: bug-fix
branch: feat-one-shot-theme-selector-reload-persistence
related_prs: [3318, 3315, 3312, 3309]
related_brainstorm: knowledge-base/project/brainstorms/2026-05-06-theme-toggle-redesign-brainstorm.md
status: plan
deepened: 2026-05-06
---

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Why The Prior PRs Did Not Fix This, Hypotheses, Phase 2a (chosen fix), Risks, Test Plan
**Research grounding:** React 18 hydration semantics (production-build mismatch handling), `next-themes` reference implementation for the mounted-gate pattern, Next.js 15 App Router streaming SSR, repo verification of Playwright wiring and provider singleton, theme-storage-key drift sweep across the codebase.

### Key Improvements

1. **Promoted F1 from "most likely" to "confirmed by mechanism"** — React 18 production builds do NOT re-render on attribute/className hydration mismatches; they keep SSR DOM and log a dev-only warning. Combined with #3318's lazy-initializer-now-matches-canonical change, NO state transition fires after hydration → SSR-painted system-active className stays forever. This is the load-bearing finding; the fix in Phase 2a is now grounded, not speculative.
2. **Verified Playwright wiring** at `apps/web-platform/playwright.config.ts` + `apps/web-platform/playwright/*.e2e.ts` — AC5 is implementable as a `.e2e.ts` file alongside `smoke.e2e.ts`, no infra-creation needed.
3. **Verified provider singleton** — single `<ThemeProvider>` in `app/layout.tsx`; F3 essentially ruled out at deepen time, not deferred to Phase 1. AC4 demoted to a regression-prevention test rather than a diagnostic step.
4. **Verified storage-key non-drift** — every reader/writer of `soleur:theme` (provider, NoFoucScript inline literal, csp-regression test) agrees. F2 narrowed to "inline script blocked / CSP nonce mismatch" only; localStorage value-staleness is not in play.
5. **Mounted-gate code sketch grounded against `next-themes`'s canonical implementation** — same pattern used by `pacocoursey/next-themes` (the React/Next ecosystem reference for theme toggles): render no-active-segment SSR, flip to real-active post-mount via a `useEffect`-set boolean. Pattern is battle-tested at scale.

### New Considerations Discovered

- **React 18 production hydration is more permissive than dev**, which is exactly why #3318 passed unit tests AND dev preview but failed in production. The `theme-toggle-ssr-hydration.test.tsx` MUST run with `react-dom/server.renderToString` then `hydrateRoot` to reproduce the production code path; mocking `window === undefined` in jsdom alone is insufficient because vitest still uses dev React.
- **The `aria-pressed` patching path is separate from the className path.** React patches DOM properties (aria-pressed-as-attribute) more reliably than className strings during hydration mismatch. This is why screenshots can show `aria-pressed="true"` on Dark (correct) AND active className on System (stale SSR). The visual artifact (two pills highlighted) is the className residue.
- **A single-frame "no segment active" blip is acceptable.** `next-themes` ships with this trade-off in its `ThemeProvider`; the React community has accepted it as the standard SSR-safe pattern.

# Fix: Theme Selector Reload Persistence + Reliable Active-State Display

## Overview

The dashboard theme toggle (`apps/web-platform/components/theme/theme-toggle.tsx`)
exhibits two related defects in production despite four prior PRs (#3309, #3312,
#3315, #3318) attempting fixes:

1. **Reload reverts visual selection to System** — user selects Dark or Light,
   page palette repaints correctly, but on reload the pill highlights System
   instead of the actually-stored theme. The page palette IS correct (CSS
   resolves via `<html data-theme>` which the inline `NoFoucScript` writes
   from localStorage); the visual indicator inside the toggle is wrong.

2. **Multiple segments visually appear "highlighted" simultaneously** — user
   reports a screenshot showing the moon (dark) pill highlighted on the left
   AND the monitor (system) pill highlighted on the right, with the sun
   (light) icon faint in the middle. Only one segment should be active at a
   time.

These are NOT cosmetic-only — defect 1 erodes user trust in their saved
preference (they think the toggle "forgot"); defect 2 makes the control
unreadable.

## Why The Prior PRs Did Not Fix This

PR #3318's fix changed `ThemeProvider`'s `useState` lazy initializer to read
`document.documentElement.dataset.theme` on the client (the canonical
post-bootstrap value the inline script wrote from localStorage). This works in
unit tests because vitest+jsdom always has `window` defined — the lazy
initializer runs once with the correct value and tests pass.

But in production SSR, the lazy initializer runs **twice**: once on the server
(where `typeof window === "undefined"` → returns `"system"`) and once on the
client during hydration. The server-rendered HTML therefore paints the
**System segment as active** with full active styling (`aria-pressed="true"`,
`bg-soleur-bg-surface-1`, gold ring, gold text). Then on the client:

- Lazy initializer correctly returns `"dark"` from `dataset.theme`.
- React renders Dark as active.
- Hydration mismatch: server painted System active, client wants Dark active.

**The actual React 18 hydration behavior (deepen-pass research):** the
"falls back to client rendering" claim above is true only for **structural**
mismatches (different element types, missing children). For **attribute and
className mismatches** in production builds, React 18 logs a `console.error`
in dev mode and **keeps the server-rendered DOM in place** — no client
re-render fires. The state in React-land matches the client-computed value;
the DOM does not. (This is documented behavior; see React 18 release notes
on selective hydration and `onRecoverableError`.)

This means the bug is not a "race condition" or a "timing issue" — it is a
**deterministic** consequence of these three facts in combination:

1. SSR's lazy initializer always returns `"system"` (window undefined →
   `resolveClientInitialTheme()` falls back to `readStoredTheme()` which
   returns `"system"`). SSR HTML therefore paints System as active with
   full active className (`bg-soleur-bg-surface-1 ring-1 ring-inset
   ring-soleur-border-emphasized text-soleur-accent-gold-fg`).
2. Client lazy initializer (post-#3318) reads `dataset.theme` and returns
   `"dark"`. React's vDOM has Dark active.
3. Hydration reconciles attributes: `aria-pressed` mismatches on each
   button are patched (true→false on system, false→true on dark) — but
   className mismatches **are NOT patched** in production. SSR's
   active-className on the System button persists.
4. The first useEffect runs: `prevThemeRef.current = "dark"`,
   `theme === "dark"` → no `setThemeState` call → **no re-render is
   triggered**. The stale className stays forever.

Result: the user sees `aria-pressed="true"` on Dark (correct, screen-reader
correct) AND the active-style className still attached to System (stale
visual residue). Two segments visually look "highlighted" — exactly the
screenshot the user reported. If subsequently the user clicks any segment
or hovers triggers a re-render, React reconciles the className across all
buttons and the visual normalizes; until then, the artifact persists.

**This rules out F1 as "possibly the cause" and confirms it as the actual
mechanism.** F2 (CSP/nonce) and F3 (nested provider) remain as
secondary/tertiary risks worth a quick verification, but the fix path is
deterministic.

The persistence of the bug after #3318 also has a secondary failure mode
worth naming:

- **F1 — Hydration mismatch is swallowed.** A wrapping `suppressHydrationWarning`
  or a stale streaming-render boundary lets the SSR DOM persist visually even
  though client state is correct. Result: aria-pressed is patched but the
  className on the System node is not fully scrubbed → System keeps its
  active styling while Dark renders new active styling on top → BOTH look
  highlighted. (Matches the screenshot.)
- **F2 — The inline `NoFoucScript` is blocked or fails silently** in some
  CSP/nonce / streaming scenarios, leaving `dataset.theme` unset. The lazy
  initializer's fallback path (`readStoredTheme()`) reads localStorage — but
  if localStorage was last written before the storage key was renamed or by
  a different origin, the value is missing and we fall back to "system".
- **F3 — A second ThemeProvider tree mounts** (e.g., a nested
  `ThemeProvider` introduced in dev preview, an MDX wrapper, or a stale
  loader in `(dashboard)/layout.tsx`) and one tree's state diverges from the
  other.

The plan's hypothesis ranking (with confidence): **F1 most likely** (matches
both observed defects in one mechanism), **F2 second** (would only produce
defect 1, not defect 2), **F3 unlikely** (no second `<ThemeProvider>` in the
tree per current code; the audit step below proves it).

## Research Reconciliation — Spec vs. Codebase

| Spec/PR claim | Codebase reality | Plan response |
|---|---|---|
| PR #3318 desc: "React 18 hydration reuses the server-rendered state and does NOT re-call lazy initializers on the client" | Incorrect. React 18 `useState` lazy initializer IS invoked on the first client render after SSR. The reason #3318's fix works is the initializer now reads dataset.theme; the doc-prose is misleading. | Plan does not rely on the misleading prose. The actual mechanism (SSR snapshot is "system", client computes correct theme, hydration mismatch repaints subtree) is documented in the Why section above. |
| User-Brand Impact framing in brainstorm: "recoverable annoyance, not single-user incident" | Confirmed: theme palette IS correct (data-theme writes from inline script); only the toggle's own visual indicator is wrong. No data, auth, or money exposure. | Threshold remains `none`. Section retained for completeness. |
| Brainstorm scopes implementation to `theme-toggle.tsx` + `(dashboard)/layout.tsx` + `theme-toggle.test.tsx` | This bug additionally implicates `theme-provider.tsx` (lazy initializer), `no-fouc-script.tsx` (CSP/nonce path), and a new SSR-shaped test file. | Files-to-edit list extends the brainstorm's scope to cover provider + nonce audit + new SSR test. |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` for `theme-toggle.tsx`,
`theme-provider.tsx`, and `no-fouc-script.tsx` returned zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** the theme selector visual
  indicator that disagrees with the page palette they actually see — they
  click Dark, page goes Dark, reload, palette stays Dark but the toggle
  "looks like" System is active (and possibly Dark too). User concludes the
  setting is unreliable; some click around to "fix" it.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  N/A — no credential, auth, billing, or user-data surface is touched. The
  toggle is a pure UI control over a CSS variable.
- **Brand-survival threshold:** none. (Brainstorm framing carried forward;
  the surface modified is not on the sensitive-paths regex enforced by
  preflight Check 6.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Reload persistence (real Next.js SSR):** A new test
  `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` SSR-renders
  `<ThemeProvider><ThemeToggle collapsed={false} /></ThemeProvider>` with
  `window` undefined (server snapshot), seeds `document.documentElement.dataset.theme = "dark"`,
  hydrates with `hydrateRoot`, and asserts that exactly **one** segment has
  `aria-pressed="true"` AND that segment is the Dark button — for each of the
  three stored values (`dark`, `light`, `system`). Currently fails on at
  least the `dark` and `light` cases.
- [ ] **AC2 — Single-active visual invariant:** A new test asserts that at
  any post-hydration moment, exactly one of the three segments has the
  active className token (`bg-soleur-bg-surface-1`) attached. Catches F1
  (residual SSR active className).
- [ ] **AC3 — NoFoucScript runs under CSP nonce in test:** A test confirms
  the rendered `<script>` tag carries a `nonce` attribute when the request
  has `x-nonce` header set, AND the script-content actually executes
  `document.documentElement.dataset.theme = ...` when run in a JSDOM
  scaffold. (Currently `theme-no-fouc-script.test.tsx` verifies content
  parity with globals.css palette; it does NOT exercise the script
  end-to-end.) Catches F2.
- [ ] **AC4 — No nested ThemeProvider:** A grep test (similar to existing
  drift-guards) asserts `<ThemeProvider` appears at most once in the
  hydration tree of `app/layout.tsx` and `app/(dashboard)/layout.tsx`.
  Catches F3.
- [ ] **AC5 — Both displayed states verified by Playwright** (per AGENTS.md
  alignment-fix sharp edge): expanded pill AND collapsed cycle button each
  verified after reload for `dark`, `light`, `system`. Implemented as
  `apps/web-platform/playwright/theme-reload.e2e.ts` (Playwright config and
  e2e directory verified during deepen-pass at
  `apps/web-platform/playwright.config.ts` and
  `apps/web-platform/playwright/*.e2e.ts` — no new test infrastructure
  needed). Six screenshots saved as Playwright artifacts.
- [ ] **AC6 — Existing test suites stay green:** `theme-toggle` (15),
  `theme-provider` (13), `theme-csp-regression` (3),
  `dashboard-sidebar-collapse` (11), `dashboard-layout-drawer-rail` (2),
  `theme-no-fouc-script` (current count) all pass.
- [ ] **AC7 — `tsc --noEmit` clean** at apps/web-platform.

### Post-merge (operator)

- [ ] **AC8 — Manual reload check on production:** load
  `https://soleur.ai/dashboard`, click Dark, reload, verify Dark stays
  highlighted (single segment); repeat for Light and System; repeat for the
  collapsed-sidebar cycle button. Capture screenshots for the changelog.

## Hypotheses

The plan does NOT predetermine which of F1/F2/F3 is the cause. Phase 1 is a
**diagnostic phase** that produces empirical evidence, then Phase 2 chooses
the fix path. This is intentional — committing to a specific code change
before measuring would repeat the #3318 mistake (fix shipped without an
SSR-shaped repro test).

## Implementation Phases

### Phase 1 — Lightweight Confirmation (deepen-pass evidence pre-confirms F1)

The deepen-pass found F1 is the deterministic mechanism (React 18
production hydration does not patch className mismatches; #3318 removed
the prior effect-driven re-render that compensated). Phase 1 is therefore
a **confirmation pass**, not a diagnostic discovery pass — it should
take ~30 minutes, not several hours.

1. **Reproduce via the new SSR-shaped test (RED state).** Write
   `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` (vitest
   `node` environment for `renderToString`, jsdom-like environment for
   `hydrateRoot`). Use `react-dom/server.renderToString` to produce SSR
   HTML, then `hydrateRoot` in a JSDOM document with `dataset.theme = "dark"`
   pre-set. Assert the post-hydration DOM has `data-active="true"` exactly
   once and on the Dark button. Expectation: this test fails on `main`
   and on `feat-one-shot-theme-selector-reload-persistence` BEFORE the
   Phase 2a fix lands. Failure confirms F1; passing means F1 was wrong.
2. **Verify F2 in ~5 min.** Inspect the rendered `<NoFoucScript>` in
   dev preview's DOM (`view-source:` on `/dashboard`). Confirm the
   `nonce="..."` attribute is present and the script body executes
   (set a `localStorage.setItem("soleur:theme", "dark")`, reload, confirm
   `document.documentElement.dataset.theme === "dark"` from DevTools
   console BEFORE clicking anything). If yes → F2 ruled out.
3. **F3 verified at deepen-pass.** `git grep -n "<ThemeProvider"
   apps/web-platform/` returns exactly one match (the root layout). No
   nested provider exists. F3 ruled out at deepen time. AC4 demoted from
   Phase 1 diagnostic to a regression-prevention test.
4. **Document confirmation** in a one-paragraph `### Phase 1 Results`
   appended to this plan before starting Phase 2. If F1 is NOT
   confirmed by step 1, re-open the diagnostic gate and walk the original
   Phase 1 tree (DOM inspection of post-hydration className residue,
   etc.).

### Phase 2 — Fix

The fix branches by Phase 1 result:

#### Phase 2a — F1 fix path (default; mounted-gate)

Given the deepen-pass evidence that F1 is the deterministic mechanism, this
is the chosen fix path. Phase 1 still runs to confirm and to surface any
F2/F3 secondary issues, but the implementation does NOT block on Phase 1.

**Root cause:** SSR-rendered active className persists through React 18
production hydration because attribute/className mismatches do not trigger
a client re-render, and #3318's lazy-initializer-now-canonical change
eliminated the prior-version's effect-driven setState that used to repaint
the className. We can either (a) make SSR render with the same value the
client will compute (requires moving the source of truth out of
client-only localStorage — large surface change), or (b) defer rendering
of the toggle's "active state" to post-hydration so SSR paints NO
segment as active.

**Choice: option (b).** This is the canonical pattern used by
`pacocoursey/next-themes` (the React/Next ecosystem reference for theme
toggles, ~14k stars), Radix UI's docs site, shadcn/ui's theme switcher
example, and Vercel's own dashboard. It is structurally simpler and
bulletproof against any future SSR/CSR snapshot divergence.

Changes to `apps/web-platform/components/theme/theme-toggle.tsx`:

```tsx
"use client";

import { useEffect, useRef, useState } from "react";
import { useTheme, type Theme } from "./theme-provider";

// ...SEGMENTS unchanged...

export function ThemeToggle({ collapsed }: { collapsed: boolean }) {
  const { theme, setTheme } = useTheme();
  const buttonsRef = useRef<Array<HTMLButtonElement | null>>([]);

  // Mounted-gate: SSR and the first client paint render no segment as
  // active (data-active="false" on every button, no active className).
  // After hydration completes, the useEffect flips `mounted` to true and
  // React re-renders with the real active segment based on `theme`.
  //
  // Why this is needed:
  //   - SSR has no access to localStorage / dataset.theme; lazy initializer
  //     returns "system" on the server.
  //   - Client lazy initializer (post-PR #3318) returns the correct value.
  //   - React 18 production hydration does NOT patch className mismatches.
  //   - Without this gate, the SSR-painted active className on the System
  //     segment persists in the DOM even though React state says Dark.
  //
  // Trade-off: one paint frame where no segment is highlighted, then the
  // correct segment lights up. The user already sees the NoFoucScript-
  // driven palette correctly during this frame; only the toggle's
  // indicator catches up. Same trade-off accepted by next-themes.
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);

  const activeFor = (segValue: Theme): boolean => mounted && theme === segValue;

  // ...collapsed branch: also gate `data-theme-current` to render
  //    a stable "system" placeholder pre-mount so cycle-button SSR
  //    matches client first-paint, then flip post-mount.

  return (
    <div role="group" aria-label="Theme" /* ... */>
      {SEGMENTS.map((seg, index) => {
        const active = activeFor(seg.value);
        return (
          <button
            key={seg.value}
            type="button"
            data-active={active ? "true" : "false"}  /* AC2 probe */
            aria-pressed={active}
            /* ...rest unchanged; className branches on `active` ... */
          />
        );
      })}
    </div>
  );
}
```

**Collapsed-mode handling.** The cycle button in collapsed mode also has an
SSR/client divergence (`current` and `next` are derived from `theme`,
which is "system" on SSR and the real value on client). Apply the same
mounted-gate: pre-mount, render the System icon as the visible glyph
(matching SSR's "system"); post-mount, switch to the real current/next.
Without this, the cycle button has the same className stale-residue
risk plus an icon-glyph mismatch.

**Why not approach (a) — make SSR read dataset.theme too?** Server
rendering runs at build/request time on Node, where `document` does not
exist. The server *cannot* read dataset.theme. The provider would need to
take a `theme` prop sourced from a cookie set on first toggle — much
larger surface change, new cookie path, and re-introduces deeper concerns
(per-route cookie scope, SSG vs. SSR rendering modes). Defer to a later
iteration if the single-frame-blip from option (b) proves user-visible
in real session-replay data.

**`next-themes` reference.** The same pattern is implemented in
`packages/next-themes/src/index.tsx` of the canonical library:
```tsx
const [mounted, setMounted] = React.useState(false);
React.useEffect(() => { setMounted(true); }, []);
// ...consumers branch on `mounted` to avoid SSR-vs-client className mismatch.
```
Copying the pattern (not the library) keeps our zero-runtime-deps stance
and avoids a 4 KB add for a 12-line solution.

#### Phase 2b — If F2 confirmed (NoFoucScript blocked / not running)

Likely causes:
- **CSP nonce missing.** Verify `headers().get("x-nonce")` returns a value
  in production; check `middleware.ts` actually injects the header.
- **Streaming hydration window.** Next.js 15 may stream the body before the
  head script in some configurations. Confirm `<NoFoucScript>` is rendered
  in `<head>` of `app/layout.tsx` (it is, per current code).
- **localStorage access denied.** Try/catch in the script wraps this;
  fallback writes `dataset.theme = "system"`, matching the symptom.

Fix: add a CSP-aware fallback that, if `dataset.theme` is unset 50ms after
hydration, reads localStorage from React-land directly and writes
`dataset.theme`. Mirrors Sentry on the failure mode. (Mostly belt-and-
suspenders; Phase 1 should reveal the actual cause.)

#### Phase 2c — If F3 confirmed (nested provider)

Remove the duplicate `<ThemeProvider>` and add the AC4 grep-test
permanently to prevent regression.

#### Phase 2d — Universal hardening (always applied)

Regardless of which fix path Phase 1 selects, ALSO apply:

- Add a `data-active="true|false"` attribute on each segment in addition
  to `aria-pressed`. Tests and Playwright probes can assert on this single
  source of truth instead of a className token (which can drift if the
  Tailwind utility set changes). Active-className becomes a *visual*
  concern only; the *semantic* active state lives on `data-active`.
- Add an `assert exactly one data-active="true"` invariant test (AC2).

### Phase 3 — Tests

1. **`apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` (new).**
   Use `react-dom/server` `renderToString` to produce SSR HTML with
   `window` mocked as undefined (or use vitest's `node` environment for
   this single file). Then in a jsdom scaffold, call `hydrateRoot` and
   assert the post-hydration `data-active` count is exactly 1 and lands
   on the correct segment for each of `dark`, `light`, `system`.
2. **Extend `theme-toggle.test.tsx`** with an explicit "no segment is
   active before mount" test (when `mounted` is false, all three buttons
   carry `data-active="false"`).
3. **Extend `theme-no-fouc-script.test.tsx`** to actually execute the
   script content in a JSDOM scaffold and assert
   `document.documentElement.dataset.theme` matches the seeded localStorage
   value.
4. **Add Playwright reload-persistence test** under
   `apps/web-platform/playwright/theme-reload.spec.ts` if Playwright is
   already wired (verify before adding); else defer to a tracked issue.

### Phase 4 — Manual QA

Run the AC8 post-merge checklist in dev preview before requesting review.

## Files to Edit

- `apps/web-platform/components/theme/theme-toggle.tsx` — add `mounted` gate;
  add `data-active` attribute on each segment.
- `apps/web-platform/components/theme/theme-provider.tsx` — minor: ensure
  the lazy initializer's defense-in-depth fallback also writes to a single
  source of truth (no behavior change expected; cleanup only).
- `apps/web-platform/test/components/theme-toggle.test.tsx` — extend with
  pre-mount-no-active-segment test and `data-active`-based assertions.
- `apps/web-platform/test/components/theme-no-fouc-script.test.tsx` —
  extend to actually execute the script.

## Files to Create

- `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` — new SSR
  repro test (AC1, AC2).
- `apps/web-platform/playwright/theme-reload.spec.ts` — new Playwright
  reload-persistence verification (AC5), if Playwright wiring exists in
  the repo. If not, file a follow-up issue and remove AC5 from the AC
  list with a tracking-issue link.
- `### Phase 1 Results` section appended to this plan during Phase 1.

## Risks

- **Mounted-gate first-paint blip.** Users may briefly see a toggle with no
  segment highlighted (~1 frame, typically <16ms). Mitigation: keep the
  pill *track* fully styled even pre-mount (so the control is visibly
  there); only the active segment indicator is deferred. The
  NoFoucScript-driven palette is already correct during this frame, so
  the user does not perceive a "broken" page — only a momentarily
  un-indicated toggle. If user research / session replay shows the blip
  is noticeable, the next iteration can move to a cookie-based SSR theme
  source. This is the same trade-off accepted by `next-themes`.
- **Phase 1 may reveal a fourth root cause** not in F1/F2/F3. The plan
  treats Phase 1 as a **lightweight confirmation** of the deepen-pass
  finding rather than a fresh diagnostic. If the SSR-hydration test
  passes on `main` (i.e., F1 is NOT the cause), Phase 1 step 4 re-opens
  the full diagnostic tree. Probability of F4: low — the deepen-pass
  evidence is mechanistic, not statistical.
- **Vitest can't fully reproduce production React.** Vitest uses dev
  React, which logs hydration warnings AND attempts subtree re-render
  on mismatch — the production-mode "keep SSR DOM, no re-render"
  behavior may not be reproducible in unit tests. Mitigation: AC1's
  SSR-hydration test asserts on `data-active` post-hydration; the
  Playwright AC5 test runs against the actual production build
  (`bun run build && bun run start`) and is the load-bearing assertion
  that the bug is fixed in the user's actual rendering path.
- **Tailwind v4 `&:where()` data-theme cascade interaction.** The
  `globals.css` dark/light tokens are scoped via `&:where([data-theme="dark"], ...)`.
  If the mounted-gate causes a `data-theme` attribute lookup miss
  during the un-mounted frame on a route that doesn't use NoFoucScript
  (e.g., a static error page), the un-themed segment paint could use
  the `:root:not([data-theme])` fallback (dark). Mitigation: this is
  the EXISTING behavior — NoFoucScript runs in `app/layout.tsx` which
  wraps all dashboard routes. No new risk introduced.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan's section is filled.
- Both pill states (expanded sidebar AND collapsed cycle button) must be
  verified after the fix per AGENTS.md sharp edge "alignment fixes must
  verify both toggle states." AC5 covers both.
- The lazy-initializer prose in PR #3318's description is incorrect about
  React 18 hydration semantics. Do NOT cite it as authority — cite the
  React 18 hydration mismatch behavior directly (server-rendered subtree
  is replaced when attribute/className mismatch is detected, but
  className mismatches near the boundary may produce a partial-patch
  failure mode in production builds).
- The drift-guard for hex literal parity in `no-fouc-script.tsx` (against
  `globals.css` palette) is a separate test from the script-execution
  test we are adding. Do not consolidate the two — they protect different
  invariants.
- When adding `data-active`, do NOT also remove `aria-pressed`.
  `aria-pressed` is the accessible name for screen readers; `data-active`
  is the test/agent probe. Both must coexist.

## Domain Review

**Domains relevant:** none.

This is a UI bug fix on an already-shipped capability. Per `hr-new-skills-
agents-or-user-facing`, the CPO+CMO mandate fires for *new* user-facing
capabilities; this is iteration on an existing one. The brainstorm
explicitly assessed no domains as relevant for the same reason. Skipping
the domain sweep.

### Product/UX Gate

**Tier:** none. The fix is mechanical (single-active visual invariant);
no new screens, flows, copy, or interactive surfaces. The visual treatment
is unchanged — the bug is that the wrong segment receives the existing
visual treatment.

## Test Plan (summary, links to ACs above)

1. Run `bun test apps/web-platform/test/components/theme-toggle.test.tsx` —
   covers AC2 partially (pre-mount no-active assertion).
2. Run `bun test apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` —
   covers AC1, AC2 fully.
3. Run `bun test apps/web-platform/test/components/theme-no-fouc-script.test.tsx` —
   covers AC3 (script execution in JSDOM).
4. Run `bun test apps/web-platform/test/` (full suite) — covers AC6.
5. Run `bun run --filter=web-platform tsc:check` — covers AC7.
6. Manual: AC4 grep, AC5 Playwright (or screenshot equivalent), AC8
   production reload QA.

## Test Implementation Sketch

### `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` (new)

```tsx
/**
 * @vitest-environment jsdom
 *
 * SSR-hydration repro for the "two pills highlighted" / "system stuck on
 * reload" defect class. Reproduces the production code path by:
 *   1. Calling renderToString in a context where typeof window === "undefined"
 *      (use a server-component test scaffold or mock globalThis.window).
 *   2. Pre-seeding documentElement.dataset.theme to the "stored" value (the
 *      value the inline NoFoucScript would have written).
 *   3. Calling hydrateRoot and asserting post-hydration data-active state.
 *
 * The bug surfaces when post-hydration data-active="true" is on a different
 * segment than data-active="true" was on in the SSR HTML.
 */
import { describe, it, expect, beforeEach } from "vitest";
import { renderToString } from "react-dom/server";
import { hydrateRoot } from "react-dom/client";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { ThemeToggle } from "@/components/theme/theme-toggle";

const STORAGE_KEY = "soleur:theme";

function ssrSnapshot() {
  // SSR shape: window undefined, document undefined. We use renderToString
  // which already runs in a server-shaped environment per react-dom/server.
  return renderToString(
    <ThemeProvider>
      <ThemeToggle collapsed={false} />
    </ThemeProvider>,
  );
}

describe.each([
  ["dark", "Dark theme"],
  ["light", "Light theme"],
  ["system", "Follow system theme"],
])("SSR→hydrate with stored=%s", (stored, expectedAccessibleName) => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
  });

  it("post-hydration: exactly one segment has data-active='true' and it is the stored theme", async () => {
    // Arrange: SSR HTML (system-active by construction).
    const ssrHtml = ssrSnapshot();
    document.body.innerHTML = `<div id="root">${ssrHtml}</div>`;
    // Simulate the inline NoFoucScript having written dataset.theme.
    localStorage.setItem(STORAGE_KEY, stored);
    document.documentElement.dataset.theme = stored;

    // Act: hydrate.
    const container = document.getElementById("root")!;
    hydrateRoot(
      container,
      <ThemeProvider>
        <ThemeToggle collapsed={false} />
      </ThemeProvider>,
    );

    // Allow useEffect (mounted gate) to run.
    await new Promise((r) => setTimeout(r, 0));

    // Assert: exactly one data-active="true", and on the right button.
    const buttons = container.querySelectorAll<HTMLButtonElement>("button");
    const active = Array.from(buttons).filter(
      (b) => b.getAttribute("data-active") === "true",
    );
    expect(active).toHaveLength(1);
    expect(active[0].getAttribute("aria-label")).toBe(expectedAccessibleName);

    // AC2 visual invariant: the active className is on exactly one segment.
    const withActiveBg = Array.from(buttons).filter((b) =>
      b.className.includes("bg-soleur-bg-surface-1"),
    );
    expect(withActiveBg).toHaveLength(1);
  });
});
```

### `apps/web-platform/playwright/theme-reload.e2e.ts` (new)

```ts
import { test, expect } from "@playwright/test";

/**
 * AC5 — both pill states (expanded sidebar + collapsed cycle button)
 * verified after reload for each of dark/light/system.
 *
 * Runs against the production build (configured by playwright.config.ts).
 * This is the load-bearing assertion that the fix works in the user's
 * actual rendering path — vitest cannot reproduce production hydration.
 */
const STATES = ["dark", "light", "system"] as const;

for (const state of STATES) {
  test(`expanded pill: stored=${state} reloads with single segment active`, async ({ page }) => {
    await page.goto("/dashboard");
    await page.evaluate((v) => localStorage.setItem("soleur:theme", v), state);
    await page.reload();
    const buttons = page.getByRole("group", { name: "Theme" }).getByRole("button");
    const activeCount = await buttons.evaluateAll(
      (els) => els.filter((e) => e.getAttribute("data-active") === "true").length,
    );
    expect(activeCount).toBe(1);
    await expect(page).toHaveScreenshot(`theme-reload-expanded-${state}.png`);
  });

  test(`collapsed cycle: stored=${state} reloads with correct current/next`, async ({ page }) => {
    await page.goto("/dashboard");
    await page.evaluate((v) => {
      localStorage.setItem("soleur:theme", v);
      localStorage.setItem("soleur:sidebar.main.collapsed", "1");
    }, state);
    await page.reload();
    const cycle = page.getByTestId("theme-cycle-button");
    await expect(cycle).toHaveAttribute("data-theme-current", state);
    await expect(page).toHaveScreenshot(`theme-reload-collapsed-${state}.png`);
  });
}
```

## Out of Scope / Non-Goals

- No changes to `--soleur-*` token values in `globals.css`.
- No changes to the cycle order in collapsed mode (Dark → Light → System).
- No avatar-menu / dropdown alternative placement (rejected in brainstorm).
- No relocation to `/dashboard/settings` (rejected in brainstorm).
- No new desktop topbar component (rejected in brainstorm).
