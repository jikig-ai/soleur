---
title: "fix(mobile): scope rail collapse to the desktop viewport, restore the drawer back gold, and stop the mobile KB Concierge splitting the screen"
date: 2026-08-03
type: bug
issue: 7222
tracker: 7201
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-7222-mobile-drawer-collapse-leak
---

# fix(mobile): rail-collapse leak, drawer back gold, KB Concierge split

## Implementer's summary

**Product diff: ~20 lines.** In `app/(dashboard)/layout.tsx`, derive
`railCollapsed = collapsed && isDesktop` (one `useSyncExternalStore` on the exact
`(min-width: 768px)` literal Tailwind's `md:` uses) and route 8 render sites +
5 cosmetic `title` attrs through it; leave every `md:`-scoped site on raw
`collapsed`. Recolour one link. Two one-line mobile defaults in the KB. Plus a
`dev`-script fix that closes a 6-week-old blocker.

**Commands:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` ·
`npm run test:ci` · `npx playwright test e2e/nav-states-shell.e2e.ts --grep 7222`

**The three gates:** **AC3** (the CSS-scoped sites still read raw `collapsed`),
**AC5** (mobile, seeded — the fix works), **AC7** (desktop, seeded — collapse
still works). Everything below is *why*.

> **v3 after a 5-agent eng panel + named panel (8 reviewers).** The panel cut a
> 3-candidate probe, a 16-file test sweep, 6 e2e scenarios and 7 ACs; caught a
> self-contradiction in v1's hook reasoning; and found **four P0s v2 shipped**: a
> fractional-viewport dead band, a genuinely leaking nav badge v2 marked "verified
> safe", an unimplementable KB e2e assertion, and a prescribed snippet that would
> have broken the mobile guided tour. All four are fixed below.

## Overview

Four mobile regressions from operator device-mode testing on `app.soleur.ai`
(web-v0.248.0). Three share one root cause.

**A — collapse is a desktop-rail concept that leaks everywhere.**
`app/(dashboard)/layout.tsx:145` reads a localStorage-persisted,
breakpoint-agnostic boolean and feeds it to `<RailCollapsedProvider value={collapsed}>`
at `:304`. That provider wraps `<main>`, not just the rail, so portaled secondary
navs and the theme control render in their 56px icon-only form inside a 256px
mobile drawer that has no collapsed state.

**B — the drawer back link lost its gold**, not carried over when the band-level
back moved into the drawer on 2026-07-24.

**C — the mobile KB Concierge splits the screen.** Mostly deferred to a
wireframe-gated follow-up, **except two one-line defaults folded into PR 1** —
see the sequencing note, which v2 got wrong.

### Sequencing (corrected)

**Ship A + B + two C defaults as PR 1; ship C's structural half separately.**

v2 argued *"pre-A the operator largely cannot reach a document on a phone, so C is
theoretical until A merges."* **That is false.** On a populated mobile KB landing
`treeHost === "content"` (`hooks/use-kb-layout-state.tsx:239-240`) and
`KbMobileLayout` renders the full browse tree in the content column, guarded from
the leak by the `host === "rail"` term. This is pinned green today at
`e2e/nav-states-shell.e2e.ts:1105-1124` (#7186, merged today). **The operator can
already reach any C4 document on a phone, so C's damage is live now.**

That changes two things: the "file C before PR 1 merges" instruction becomes more
warranted, not less; and the two C defects that are *defaults or parity* rather
than *new surfaces* should not wait for a wireframe:

- `hooks/use-kb-layout-state.tsx:281` — seed `embeddedConciergeOpen` `false` on
  mobile. Changes an initial state, not a surface.
- `components/kb/kb-mobile-layout.tsx:71` — consume `state.showChat` so both
  layouts read one derived value (`components/kb/kb-desktop-layout.tsx:70`).
  This closes a **draft-loss** defect, not a squeeze: today a mobile C4 route can
  mount the embedded Concierge *and* the bottom-sheet chat on the same
  `contextPath`, two `ChatSurface` instances sharing one draft key
  (`components/chat/kb-chat-content.tsx:198`), each overwriting the other's
  composer.

Both fall under the same `wg-ui-feature-requires-pen-wireframe` carve-out as B
("copy/style and backend-only", `AGENTS.rules.md:97`) — they alter defaults and
parity, not layout structure. C's structural half (the full-screen overlay) stays
wireframe-gated.

---

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Response |
|---|---|---|
| A: provider wraps `<main>`, fed by a breakpoint-agnostic boolean | **Holds** — `layout.tsx:145`, `:304`; provider closes `:747`, `<main>` opens `:684` | Plan against it |
| A: the consumers are `settings-shell.tsx:74`, `conversations-rail.tsx:106`, `kb-sidebar-shell.tsx:64`, `ThemeToggle` (`layout.tsx:601`) | **Complete for code** — `git grep useRailCollapsed` returns exactly these. `conversations-rail.tsx:107` is `if (collapsed) return null`, so the mobile `/dashboard/chat/*` drawer is **empty** — the worst cell, not in the issue. **Incomplete for the contract**: `components/dashboard/rail-slot.tsx:36-45` and `test/helpers/rail-slot-harness.tsx:16-18` both document the value as "the rail is collapsed" and become false | Sweep the code by fixing the provider; edit the two docstrings (Phase 2.7) |
| A: "the repo has a documented **rule** against a second condition that merely agrees with the first" | **Partly false.** No `AGENTS.rules.md` rule id exists. The principle is **ADR-158:52-54** | Cite ADR-158 §Decision, never a fabricated rule id |
| A: fix by making collapse viewport-aware once at the provider | **Direction holds; the stated scope over-applies.** ~20 of ~30 reads are already `md:`-scoped Tailwind. Swapping `:385` (`md:w-14`) or `:219-220` (the `--*-rail-w` CSS vars) would replace a working **CSS** breakpoint decision with a JS one and re-open PR #4871 | Narrow to the genuinely unscoped sites (Phase 2.3) |
| **v2's claim that all four nav badges are "verified safe"** | **FALSE for two of them.** `components/dashboard/nav-count-badge.tsx` exports two primitives. `NavCountBadge` (`:55-105`) co-renders both forms `md:`-toggled — safe. **`NavDotBadge` (`:115-139`) is a ternary**: collapsed → a corner dot `hidden … md:block` (nothing below 768px); expanded → `ml-auto h-2 w-2` (visible). So under the leak the dot **vanishes on mobile**. `ReleasesNavBadge` (`releases-nav-badge.tsx:68-70`) always uses it; `InboxNavBadge` (`inbox-nav-badge.tsx:63-71`) falls through to it when `count === 0 && hasUnreadFyi`. The component's own docstring ("exactly one paints per viewport via `md:` toggles") is true of its sibling and false of itself | `:517` and `:562` move to the **swap** table; pass `railCollapsed` to all four for uniformity |
| A: mind the SSR/hydration seam | **Holds, and it is closed by short-circuit** — see below | No probe needed |
| **A: `(max-width: 767px)` is the complement of `(min-width: 768px)`** | **FALSE over fractional widths.** CSS media queries evaluate against fractional CSS-px viewport widths, so `767.0 < w < 768.0` (browser zoom, fractional DPI scaling, desktop resize) matches **neither**. v2's `!useIsMobile()` would there yield `railCollapsed = true` while `md:` does not apply — the `w-64` mobile drawer rendering the icon-only column. **The reported bug, reintroduced**, and the `host === "rail"` guard does not cover it (on a doc route `isContentView` forces `treeHost === "rail"`) | Use **one literal**, identical to Tailwind's `md:` — see below |
| B: drawer link is `text-soleur-text-muted`; band chevron is `text-soleur-accent-gold-fg` | **Holds** — `layout.tsx:617` (the `className`; `:616` carries the testid) vs `components/dashboard/workspace-context-band.tsx:141` | Plan against it; DC-2 records two dissents |
| **C: `kb-mobile-layout.tsx` renders doc and chat as flex-row siblings, so they split the width** | **FALSE as a mechanism.** Siblings in source (`:49-77`), but `KbChatSidebar` → `components/ui/sheet.tsx`, whose mobile branch is `createPortal(panel, document.body)` (`:131`) rendering `fixed bottom-0 left-0 right-0` (`:69`). **No in-flow DOM** — it cannot split the width | **Re-scoped** — the width split is `c4-workspace.tsx` |
| C: the sessionStorage restore is the cause | **Holds for markdown docs only.** The operator's surface is a **C4** route, where `embeddedConciergeOpen` is a hardcoded `useState(true)` (`use-kb-layout-state.tsx:281`) with **no restore at all** — default-open on a first-ever visit with empty sessionStorage. A restore-only fix leaves the reported symptom unfixed | C1 primary |
| Testing: "every unit test mocks the breakpoint hook" | **False as stated, true where it matters.** 14 of ~1091 files reference the hooks; only **5** render the dashboard layout. The repo states the operative version at `e2e/nav-states-shell.e2e.ts:1049-1051` | e2e is the proof; a 16-file sweep is not needed |
| Constraint: "local `bun run dev` is broken, so rely on the e2e suite" | **Self-defeating, and the real fix is one line.** `playwright.config.ts:67`/`:80` both run `npm run dev`, so the e2e suite depends on the thing declared broken. Cause: Next writes `.next/package.json` = `{"type":"commonjs"}` during `hot-reloader.start()` (`next/dist/server/dev/hot-reloader-webpack.js:666`), *after* the custom server may already have loaded the instrumentation hook — hence host/`.next`-state dependent, and why CI's `e2e` job is green on a cold checkout. **Open issue #3562 has tracked this since 2026-06-19** | Fold the one-line `dev`-script fix into PR 1 and close #3562 |

### The hydration seam is closed by short-circuit

`hooks/use-sidebar-collapse.ts:38` seeds `useState(false)` and reads localStorage in
a **post-hydration `useEffect`** (`:41-50`). So `collapsed` is `false` at SSR **and**
at the first client render, and `collapsed && isDesktop` is `false` on both sides
**whatever the viewport term returns**. No hydration mismatch is possible.

This rests entirely on that seed staying `false`, and its violation would be
**runtime-undetectable** — React does not reconcile className mismatches in
production builds (ADR-158 fact 2), so a future cookie-seeded `collapsed` would
render the wrong nav in prod with nothing in Sentry. A document cannot hold an
invariant like that, so Phase 2.8 pins it with a comment **at the line a
cookie-seeding change would edit** plus one executable test.

### The hook choice — one literal, one API

v1 and v2 both argued the hook by *mechanism* and contradicted themselves: they
rejected a hand-rolled `useState`+effect hook as *"the same mechanism as
`useMediaQuery`, differing only in the SSR seed"*, then defaulted to `useIsMobile`,
which differs from `useMediaQuery` in **exactly and only the SSR seed**. Five
reviewers converged on the resolution:

```tsx
const MD_QUERY = "(min-width: 768px)";   // EXACTLY the literal Tailwind's md: uses
const isDesktop = useSyncExternalStore(
  (cb) => { const m = window.matchMedia(MD_QUERY); m.addEventListener("change", cb);
            return () => m.removeEventListener("change", cb); },
  () => window.matchMedia(MD_QUERY).matches,   // re-read on EVERY render
  () => false,                                  // SSR-safe seed
);
```

This is the only candidate that resolves all four hazards at once:

| Hazard | Why this resolves it |
|---|---|
| **Fractional dead band** | Same literal as the CSS. JS and Tailwind agree by construction, at every width |
| **Stuck-false** (the measured 2026-06-03 failure in this exact file, and the layout's own comment at `:151-152`: *"no JS media-query state (which did not flip reliably under SSR hydration here)"*) | `getSnapshot` is re-read on every render and React re-checks it after hydration. There is no state to get stuck |
| **Hydration mismatch** | `getServerSnapshot: () => false`, and `collapsed` is false at first render anyway — the `&&` short-circuits |
| **A third breakpoint authority** | One literal, one call site, colocated in the layout |

`useMediaQuery` is rejected (measured failure here); `useIsMobile` is rejected for
*this* call site because its `(max-width: 767px)` default opens the dead band —
it remains correct for its existing consumers, which have no CSS counterpart to
agree with.

**CSS-only cannot work.** `theme-toggle.tsx:67` `return`s a different subtree with
a different **ARIA role**; `conversations-rail.tsx:107` `return null`s;
`settings-shell.tsx` branches `aria-label`/`title`/`data-testid`. CSS cannot
un-`return` a component, and mount-both-hide-one is forbidden by ADR-047/ADR-158.

### The leak is worse than the four reported symptoms

| Drill | Mobile drawer today (leaked `collapsed = true`) | `md:`-guarded? |
|---|---|---|
| `null` | Nav labels **survive** (`:506`, `:557`, `:572`, `:586`, `:594` are `md:hidden`). Lost: the signed-in **email** (`:532`), the three-segment theme selector (`:601`), and the **Inbox FYI dot + Releases "new version" dot** (`:517`, `:562` via `NavDotBadge`) | partial |
| `settings` | **Bare icon column** (`settings-shell.tsx:127`). Worse: `iconForHref` falls to `DotIcon` (`:37`, `:212-217`), so **Members and Team-activity are two identical featureless circles** | NO |
| `kb` | Two icons only — no search, tree, empty-CTA or "Sync now" — **on document routes and the empty/loading/error landing** (`treeHost === "rail"`). On a *populated* landing the drawer is intentionally near-empty per #7186, because the tree is hosted in the content column | NO |
| `chat` | **An empty drawer** — `conversations-rail.tsx:107` returns `null`; the footer group exists only in the `drill === null` branch. One link total | NO |

---

## User-Brand Impact

**If this lands broken, the user experiences:** at 390×844 with
`soleur:sidebar.main.collapsed = "1"`, the hamburger drawer renders Settings as
seven unlabelled glyphs — two of them identical featureless circles — the theme
control as a single cycle button, no signed-in email, no Inbox or Releases dot, the
KB drawer (on document routes) with no search, no file tree, no "Connect a repo"
CTA and no "Sync now", and `/dashboard/chat/*` as an empty drawer with one link. A
founder on a phone cannot tell which Settings row holds their billing and which
holds their API keys, cannot search their knowledge base, and — with an empty KB —
has **no reachable way to retry a stalled sync** (`KbSyncStatus`'s only other mount,
`components/kb/kb-content-header.tsx:166-168`, requires an open document, which an
empty tree cannot provide). Separately, opening a C4 diagram on a phone gives the
diagram ~242px of 390px, and can mount **two chat surfaces on the same document
sharing one draft key**, so each overwrites the other's composer — the operator
loses typed text. And a mobile user who starts the guided tour silently rewrites
their *desktop* rail preference, a setting they cannot see from that device. In the
opposite direction, an over-corrected fix silently reverts every desktop session's
collapsed 56px rail to 224px, eating content width on the primary work surface.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure
vector. The change reads one localStorage boolean and a viewport width to decide
client-side label rendering inside an already-authenticated dashboard shell; it
transmits nothing, persists nothing new, and touches no auth, RLS, billing or
knowledge-base content path. The nearest adjacency is that the affected nav links
*point at* Settings rows holding billing and API keys — the defect governs the
rendering of those links' labels, never the rows' contents or permissions.

**Brand-survival threshold:** `single-user incident`. Bounded blast radius
(client-side render, gated on the user having previously collapsed a desktop rail;
nothing propagates or is destroyed) — but the population for this surface is one,
the draft-loss path destroys typed input, and a single phone session in which the
product's navigation has no words breaks trust in a tool positioned as the
founder's operating system. CPO sign-off required before `/work`.

---

## Implementation Phases

### Phase 1 — Baseline + unblock the local e2e loop

1.1 **Fix the dev server for real (one line, closes #3562).** In
    `apps/web-platform/package.json`, prefix the `dev` script so `.next/package.json`
    exists before the custom server loads the instrumentation hook — byte-identical
    to what Next itself writes at `next/dist/build/index.js:823`:

```jsonc
"dev": "mkdir -p .next && printf '{\"type\": \"commonjs\"}' > .next/package.json && esbuild server/index.ts …"
```

    Idempotent, inside a gitignored dir, cannot reach prod (`start` runs
    `dist/server/index.cjs`), no lockfile change. Verify with
    `rm -rf .next && npm run dev`. Preferred over #3562's uncommitted
    `next.config.ts` webpack-plugin design, which touches the prod build graph for
    a dev-only symptom. **Do not** use the move-`instrumentation.ts`-aside
    workaround: it is a tracked file, so `git commit -am` stages it as a deletion,
    and losing `onRequestError` in prod is silent.
1.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — green baseline.
    **Not** `npm run -w …` (the repo root declares no `workspaces` field).
1.3 `cd apps/web-platform && npm run test:ci` — record the baseline.

### Phase 2 — A: scope collapse to the desktop rail

2.1 **RED.** `apps/web-platform/test/rail-collapse-viewport-scope.test.tsx`
    (component project — `test/**/*.test.tsx`; a co-located
    `components/**/*.test.tsx` is never collected). Uses the Phase 2.6 helper and
    asserts **both** viewport arms — a query-blind stub would make the mobile
    assertion pass whether or not the fix exists. Comment it as fast local signal,
    **not** the proof.

2.2 **GREEN.** In `app/(dashboard)/layout.tsx`, adjacent to `:145` — in the layout
    itself, never in a child that mounts later:

```tsx
import { useSyncExternalStore } from "react";
// …
const [collapsed, toggleCollapsed] = useSidebarCollapse("soleur:sidebar.main.collapsed");
// Collapse is a DESKTOP-RAIL concept (#7222). The mobile drawer is 256px and has
// no collapsed state, but RailCollapsedProvider wraps <main>, so an operator who
// once collapsed their desktop rail got the 56px icon-only rendering on a phone.
//
// MD_QUERY is EXACTLY Tailwind's `md:` literal. Do not "simplify" it to
// (max-width: 767px): media queries evaluate against FRACTIONAL viewport widths,
// so 767.0 < w < 768.0 (zoom, fractional DPI) matches neither, and the JS term
// would disagree with the CSS at :385/:219-220 — reintroducing this exact bug.
//
// useSyncExternalStore, not useState+effect: getSnapshot is re-read every render,
// so the value cannot get stuck at its seed. useMediaQuery has a MEASURED
// stuck-false failure in THIS file (see :151-152).
//
// LOAD-BEARING: `collapsed` is false at SSR AND at the first client render
// (use-sidebar-collapse seeds false, reads localStorage in an effect), so this
// `&&` short-circuits and no hydration mismatch is possible. Seeding `collapsed`
// from a cookie would VOID that — see the pin in use-sidebar-collapse.ts.
const MD_QUERY = "(min-width: 768px)";
const isDesktop = useSyncExternalStore(
  (cb) => {
    const m = window.matchMedia(MD_QUERY);
    m.addEventListener("change", cb);
    return () => m.removeEventListener("change", cb);
  },
  () => window.matchMedia(MD_QUERY).matches,
  () => false,
);
const railCollapsed = collapsed && isDesktop;
```

2.3 **Swap these render sites** to `railCollapsed` — **8 structural + 5 cosmetic**:

| Line | Site | Why it leaks |
|---|---|---|
| `:304` | `<RailCollapsedProvider value={collapsed}>` | **the root cause** |
| `:469` | `` `… ${collapsed ? "px-1" : "px-3"}` `` | unscoped — drawer nav padding |
| `:517`, `:520`, `:523`, `:562` | the four nav badges | `:517`/`:562` reach `NavDotBadge`, a **ternary** whose collapsed arm is `hidden … md:block` → the Inbox FYI dot and the Releases dot **vanish on mobile**. `:520`/`:523` use `NavCountBadge` and are indifferent (`railCollapsed === collapsed` at md+), so pass all four for uniformity and to remove the class of error |
| `:531` | `` `border-t … ${collapsed ? "p-1" : "p-3"}` `` | unscoped — footer padding |
| `:532` | `{userEmail && !collapsed && (…)}` | unscoped — the signed-in email vanishes |
| `:600` | `className={collapsed ? "pt-2" : "px-1 pt-2"}` | unscoped |
| `:601` | `<ThemeToggle collapsed={collapsed} />` | **operator report 4** |
| `:487`, `:548`, `:568`, `:577`, `:590` | `title={collapsed ? … : undefined}` | unscoped; on touch they add a duplicate accessible description with no hover. **Cosmetic — optional; a partial swap is not a failure** |

2.4 **Leave raw `collapsed`, and say why in the file.** Add two in-file comments
    (this is the durability item — without them the next engineer sees `collapsed`
    and `railCollapsed` mixed in one file and "tidies" it):

```tsx
// raw `collapsed` ON PURPOSE — the breakpoint decision stays in CSS (PR #4871,
// #7222). Do NOT route through railCollapsed.
${collapsed ? "md:w-14" : "md:w-56"}            // :385
const kbExpanded = drill === "kb" && !collapsed; // :219-220 → --*-rail-w vars
```

    Also raw, by justification class — state the class per row, because only the
    first is verifiable by grepping the line itself:
    - **same-string `md:` prefix** (locally verifiable): `:493`, `:502`, `:506`,
      `:554`, `:557`, `:569`, `:572`, `:583`, `:586`, `:591`, `:594`
    - **ancestor CSS class**: `:459` (inside `hidden md:block` at `:458`),
      `:434`-`:443` (inside `hidden … md:flex`), `:667` (`RailResizeHandle`,
      `hidden md:block` at `:653-655`)
    - `:145` is the declaration; `:264`/`:272` are owned by Phase 2.5.

2.5 **`:264` — keep BOTH reads imperative.** v2 proposed routing this through
    React state; three reviewers independently showed that breaks the mobile
    guided tour. The effect's deps are `[collapsed, toggleCollapsed]` (`:272`) and
    `collapsed` does not change when the viewport resolves, so a state-based
    handler would close over the seeded value **for the whole session**, and
    `components/tour/tour-provider.tsx:85-88` (plus `help-overlay.tsx:194`,
    `support-launcher.tsx:79`) dispatch long after mount. The current imperative
    read is always correct and dependency-free — keep that property, and only add
    the persistence guard:

```tsx
const desktop = window.matchMedia("(min-width: 768px)").matches;
if (desktop && collapsed) toggleCollapsed();   // was: if (collapsed) …
if (!desktop) setDrawerOpen(true);             // was: if (!matchMedia(…).matches) …
```

    The guard is the real fix: without it a mobile tour start silently rewrites the
    desktop rail preference (`use-sidebar-collapse.ts:52-67` writes localStorage).
    **No dep-array change, no new state, same literal as the CSS.**
    **Do not delete the listener** — the tour is its second dispatcher.

2.6 **Test helper, not a 16-file sweep.** Add `test/helpers/match-media.ts`
    exporting `installMatchMedia({ viewport, colorScheme })`. It must be
    **two-axis**: all five layout tests mount `<ThemeProvider>`, which reads
    `(prefers-color-scheme: dark)` through the same stub, so a one-axis
    viewport-only formula would silently flip the theme under test. Wire it into
    the 5 files that actually render the dashboard layout —
    `dashboard-sidebar-collapse`, `dashboard-layout-sidebar-settings`,
    `dashboard-layout-signout`, `dashboard-layout-inbox-badge`, `nav-rail-drill` —
    and leave the other 11 untouched: a query-blind stub yields
    `isDesktop === false` → `railCollapsed === false`, which cannot false-GREEN a
    test that asserts no mobile arm.
    **Note two tests will invert** — `dashboard-sidebar-collapse.test.tsx:152`
    ("adds title attributes when collapsed") and `:160` — because they probe the
    `title=` sites Phase 2.3 rewrites. Update them to drive the desktop arm.

2.7 **Update the contract docs the change falsifies** (the
    `2026-07-15-false-comment-shipped-the-bug` class):
    - `components/dashboard/rail-slot.tsx:36-45` — the value no longer means "the
      rail is collapsed" but "the rail is collapsed **and we are on desktop**".
      Record there that the provider spans `<main>`, not just the `<aside>`, and
      that **no consumer may re-derive the viewport term**. This module is what
      every consumer imports, so it is the enforcement home.
    - `test/helpers/rail-slot-harness.tsx:16-18` — "mirrors the layout's
      `RailCollapsedProvider`" becomes false; rename the prop `railCollapsed`.
    - `components/kb/kb-sidebar-shell.tsx:57-63` — rewrite; **the guard at `:64`
      stays** (DC-1).

2.8 **Pin the short-circuit invariant where it will be violated.** Add a comment at
    `hooks/use-sidebar-collapse.ts:38` (the exact line a cookie-seeding change
    edits) and one vitest case asserting the hook returns `false` on first render
    **with `localStorage` already set to `"1"`**. That test goes red the instant
    someone seeds from a cookie; an ADR paragraph cannot.

### Phase 3 — B: restore the drawer back link's gold

3.1 `layout.tsx:617` (the `className`; `:616` carries the testid) —
    `text-soleur-text-muted` → `text-soleur-accent-gold-fg`, and
    `hover:text-soleur-text-secondary` → `hover:text-soleur-text-primary`, matching
    `components/dashboard/workspace-context-band.tsx:141`. Keep every other class.
    **Ship the token swap alone** — no separator. Two reviewers proposed
    mitigations for a gold-on-gold adjacency; DC-2 records them and the device
    check decides.
3.2 The hover change is **required, not cosmetic**:
    `knowledge-base/project/learnings/ui-bugs/2026-06-15-small-gold-text-needs-text-token-not-fg-for-aa.md`
    demands hover increase contrast in both themes, which `-primary` does and
    `-secondary` does not.
3.3 **Known, recorded, not introduced here:** measured against `app/globals.css`,
    light-theme `-fg` `#9c7a2e` on `#f4eedf` is **3.49:1 at 14px — below AA 4.5:1**
    (dark passes at 8.25:1; `-text` `#7a5e1f` passes at 5.25:1). The band already
    ships this, so B propagates rather than creates it. AC6 therefore adds a
    **standalone** light-theme contrast assertion — an equality-with-the-band check
    alone is structurally incapable of catching it. The global token fix is a
    follow-up (it covers the band too), and DC-2 notes that `-text` would resolve
    the contrast **and** the adjacency in one token.
3.4 The desktop `rail gold-confinement gate` (`e2e/nav-states-shell.e2e.ts:994-1042`)
    asserts **background** gold on the `aside` at DESKTOP; the link is `md:hidden`
    and changes **text** colour. **Checked: cannot trip it.**
3.5 **Do not sweep `components/kb/kb-mobile-page-header.tsx:40`.** CPO asked for it
    (same `href`, same `aria-label`, a third colour), then withdrew: the real
    question is not *what colour* but *whether that renderer should exist*, since
    `layout.tsx:228-238` records that the drawer's back **always co-renders** with
    it and is in the a11y tree even while closed. Route it to **#7201**, which
    already owns the back census and the inert-drawer fix — not to the C follow-up.

### Phase 4 — C: the two mobile defaults (structural half deferred)

4.1 `hooks/use-kb-layout-state.tsx:281` — seed `embeddedConciergeOpen` `false` when
    the viewport is mobile, so a C4 diagram gets the full 390px. Re-open is the
    existing `KbChatTrigger`.
4.2 `components/kb/kb-mobile-layout.tsx:71` — gate on `state.showChat` instead of
    `chatCtxValue.enabled && contextPath`, restoring parity with
    `components/kb/kb-desktop-layout.tsx:70` and closing the double-`ChatSurface`
    draft-loss path.
4.3 **Deferred to the wireframe-gated follow-up** (its issue body carries the full
    spec — deliberately not duplicated here, because two copies drift). Wireframe:
    `knowledge-base/product/design/kb-mobile-chat/kb-mobile-fullscreen-chat.pen`,
    with `screenshots/05-decisions-and-deltas.png` as the **authoritative** decision
    list (it settles six decisions plus a rejected alternative and a five-file delta
    list; do not work from a précis of two). The follow-up must carry: the
    full-screen overlay covering the 56px top bar at `z-50` — **not** the rejected
    "sits below the top bar" alternative, which leaves the hamburger tappable and
    lets the `z-50` drawer stack over an open chat; the overlay header's
    "ASKING ABOUT <filename>" context block, which is what compensates for the
    takeover; `components/chat/kb-chat-sidebar.tsx` swapping the 60vh `Sheet` for
    the full-screen modal below md while keeping `Sheet` for the md+ push-column;
    `setDrawerOpen(false)` when the overlay opens, so the two `z-50` surfaces are
    exclusive by construction rather than by z-order; `min-h-[44px]` on
    `KbChatTrigger` (now the sole re-open affordance); focus returning to that
    trigger on close; `use-kb-layout-state.tsx:292-295` skipping the
    `kb.chat.sidebarOpen` restore on mobile; `kb-chat-trigger.tsx:68-71` routing
    (a sheet-only fix never reaches mobile C4); and `aria-modal`/body-scroll-lock/
    `inert` verified against `responsive-modal.tsx`'s **existing** trap rather than
    added twice. Do **not** patch `sheet.tsx`'s drag arithmetic — its mobile branch
    is off the path once the swap lands.

### Phase 5 — Records, tracker, ship

5.1 **Amend ADR-047** (`ADR-047-nav-context-band-outside-swap.md`) with the full
    contract: *collapse is defined only at md+; `RailCollapsedProvider`'s value is
    viewport-aware; no consumer may re-derive the viewport term; the provider spans
    `<main>`, not just the rail.* ADR-047 owns the rail contract and `rail-slot.tsx`,
    so it is the document a `useRailCollapsed` consumer will actually find —
    ADR-158's subject is the KB file tree, and `settings-shell.tsx` /
    `conversations-rail.tsx` have no path to it.
5.2 **Amend ADR-158** narrowly: correct its own now-stale corollary at `:61-66` and
    record DC-1's retention rationale. Scope stays intact. **No new ADR** — a third
    document is a third sync target.
5.3 Tick the collapse-leak checklist item on **#7201** (body line 16); link this PR.
5.4 **PR body says `Ref #7222`, NOT `Closes`** — #7222 is an umbrella and PR 1 does
    not fix C's structural half. Also `Closes #3562` (Phase 1.1).
5.5 Amend #7222's `priority/p2-medium` rationale: *"workaround exists"* is false —
    it requires a second device **and** inferring a link between a desktop chevron
    and a phone drawer that nothing communicates. Keep the number, strike the claim.
5.6 File, **before PR 1 merges**: the C follow-up (branch-qualified `.pen` path,
    which 404s until merge), and one combined *"one breakpoint authority for
    viewport-gated render branches"* issue — `useMediaQuery` is live in four files
    (`use-kb-layout-state:82`, `sheet:33`, `responsive-modal:56`,
    `workstream-board:116`) and swapping any changes first-render semantics, so size
    it **medium with regression risk**, not a chore. Fold the `768`-literal item
    into it: a TS constant cannot cover the three CSS sites
    (`globals.css:190, 306, 353`), and shipping one would make the JS value look
    canonical while Tailwind keeps its own — a worse invariant than honest literals.
    Also file: the closed-drawer `inert` gap (`layout.tsx:360`, caused to grow by
    A — post-fix the off-canvas drawer exposes the *full* expanded nav to assistive
    tech on every route) and the light-theme gold-token contrast fix (Phase 3.3).

---

## Decision Challenges

Per ADR-084. Headless run, so these are persisted to
`knowledge-base/project/specs/feat-one-shot-7222-mobile-drawer-collapse-leak/decision-challenges.md`
for `/ship` to render into the PR body. The operator's direction is the default.

- **DC-1 (User-Challenge)** — the operator asked for the `kb-sidebar-shell` guard to
  be **simplified away**; the plan **keeps it** and files the unification follow-up.
  Under the measured stuck-false mode, deleting it ships a 56px icon strip on a
  1280px desktop. The two authorities agree *at rest* but their **seeds are
  deterministically contradictory on the first mobile frame** — at 390px
  `useIsMobile()` seeds `false` ("desktop") while `useMediaQuery("(min-width:768px)")`
  seeds `false` ("mobile"): both literally `false`, opposite meanings. The guard
  covers exactly that frame. Unification is what makes deletion safe.
- **DC-2 (Taste)** — spec-flow argued against the gold entirely (gold is reserved
  for active-state and primary-CTA; it collides with the gold active row in
  `file-tree.tsx:425` **and** `settings-shell.tsx:110` — the latter on the very
  route T1 asserts). ux-design-lead measured light-theme `-fg` at **3.49:1, below
  AA**. CPO argued for gold on rank-parity grounds. The plan **implements the
  operator's literal ask, unmitigated**, and records that a single token change to
  `text-soleur-accent-gold-text` would satisfy the operator's *intent* (gold, band
  rank) while also fixing AA (5.25:1) and the adjacency — i.e. the fallback is
  strictly better, not merely different.

---

## Files to Edit

- `apps/web-platform/app/(dashboard)/layout.tsx` — Phases 2.2-2.5, 3.1
- `apps/web-platform/package.json` — Phase 1.1 (`dev` script only; no deps, no lockfile)
- `apps/web-platform/hooks/use-sidebar-collapse.ts` — Phase 2.8 comment
- `apps/web-platform/hooks/use-kb-layout-state.tsx` — Phase 4.1
- `apps/web-platform/components/kb/kb-mobile-layout.tsx` — Phase 4.2
- `apps/web-platform/components/dashboard/rail-slot.tsx` — Phase 2.7 (docstring)
- `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — Phase 2.7 (comment; `:64` unchanged)
- `apps/web-platform/components/theme/theme-toggle.tsx` — touch target (below)
- `apps/web-platform/test/helpers/rail-slot-harness.tsx` — Phase 2.7
- `apps/web-platform/test/{dashboard-sidebar-collapse,dashboard-layout-sidebar-settings,dashboard-layout-signout,dashboard-layout-inbox-badge,nav-rail-drill}.test.tsx` — Phase 2.6
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — Test Scenarios
- `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md`
- `knowledge-base/engineering/architecture/decisions/ADR-158-kb-file-tree-host-is-a-derived-value.md`

**Touch-target fix (`theme-toggle.tsx`, folded in because A causes it):** restoring
the three-segment control on mobile *shrinks* the touch target — the collapsed
cycle button is `min-h-[44px]` (`:88`) while the expanded group is `h-8` = 32px
(`:130`) with `h-3 w-3` icons (`:157`). Use `h-11 md:h-8` and
`h-4 w-4 md:h-3 md:w-3`; desktop renders byte-identical. This is the one place the
fix would otherwise make mobile measurably worse than the bug did.

**Files to Create:** `apps/web-platform/test/rail-collapse-viewport-scope.test.tsx`,
`apps/web-platform/test/helpers/match-media.ts`.

**Verified as needing no code edit** (swept by the provider fix):
`settings-shell.tsx`, `conversations-rail.tsx`, `nav-count-badge.tsx`, and the 11
`matchMedia`-stubbing test files that never render the dashboard layout.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `./node_modules/.bin/tsc --noEmit` exits 0; `npm run test:ci` shows no
  regression against the Phase 1.3 baseline; the new unit test passes on **both**
  viewport arms; `rm -rf .next && npm run dev` reaches `Server ready`.
- **AC2** `apps/web-platform/instrumentation.ts` is **unmodified** in the diff, and
  `git grep -c "data-probe" -- apps/web-platform` is 0 (no throwaway probe residue).
- **AC3** *(content anchors, not line numbers — the Phase 2.2 insert shifts every
  number)*: `md:w-14`/`md:w-56` and the `kbExpanded`/`mainExpanded` derivations
  still read bare `collapsed`; the two "raw `collapsed` ON PURPOSE" comments from
  Phase 2.4 are present; all four `NavBadge collapsed={` props now read
  `railCollapsed`.
- **AC4** The expression `useRailCollapsed() && host === "rail"` in `KbSidebarShell`
  is **byte-identical**, and the comment above it no longer claims the provider
  leaks.
- **AC5 (mobile, seeded — load-bearing)** Real Chromium, 390×844, `addInitScript`
  seeding `soleur:sidebar.main.collapsed = "1"` **before** navigation. Assertions
  must key on **visible text**, not accessible name: `settings-shell.tsx:100` sets
  `aria-label={collapsed ? tab.label : undefined}`, so `getByRole("link", {name:"General"})`
  resolves in **both** states and would pass vacuously. Assert
  `settingsRailNav.getByText("General", { exact: true })` **and**
  `settings-rail-icons` count **0**.
- **AC6 (mobile, seeded)** On `/dashboard`: `role="group"[name="Theme"]` has **3**
  buttons, its client height is **≥44px**, `theme-cycle-button` count **0**, the
  signed-in email row is present, and the Inbox/Releases dot testids
  (`inbox-nav-badge-dot`, `releases-nav-badge-dot`) resolve. Plus:
  `drawer-back-to-menu`'s computed `color` equals `nav-back-chevron`'s (**both
  measured at 390×844** — the desktop band is `display:none`, not unmounted, and
  `getComputedStyle().color` still resolves, so no viewport switch is needed), its
  class list contains `hover:text-soleur-text-primary`, and a standalone
  light-theme contrast ratio is reported for it (Phase 3.3).
- **AC7 (desktop-unchanged — the anti-regression gate)** Same seed, 1280×900,
  `/dashboard/settings`: `settings-rail-icons` count **1** and `theme-cycle-button`
  count **1**. Both **provider-derived**, so they move when `railCollapsed` is
  wrong. (v2 asserted `md:w-14` here — insensitive, since `:385` keeps raw
  `collapsed`.) **Without AC7 the fix could silently disable rail collapse and every
  other AC would still pass.**
- **AC8 (the KB cell — on a DOCUMENT route, not the landing)** 390×844, seeded, on
  a mobile KB **document** route (`e2e/nav-states-shell.e2e.ts:1129`'s existing
  long-filename fixture): `secondarySlot(page).getByTestId("kb-tree-scrollport")`
  resolves and `kb-rail-collapsed-expand` count is **0**. *A populated
  `/dashboard/kb` landing would assert the opposite — `treeHost === "content"`
  there and `e2e/nav-states-shell.e2e.ts:1124` already pins the rail slot empty.*
- **AC9 (the empty-KB dead end)** 390×844, seeded, `routeEmptyKbTree`: the drawer
  contains `kb-rail-empty` **and** `KbSyncStatus`'s `Sync now` control
  (`components/kb/kb-sync-status.tsx`, `aria-label="Sync now"`).
- **AC10 (the chat cell)** 390×844, seeded, `/dashboard/chat` (no conversation id
  needed — the portal is in the segment layout and `setupNavMocks` seeds the list):
  assert **containment**, not the wrapper — `secondarySlot(page).getByText("Recent conversations")`
  and `getByRole("link", { name: "New conversation" })`.
  `conversations-rail-portal.tsx` mounts `data-testid="conversations-rail"`
  unconditionally, so a wrapper check is green today with the bug live.
- **AC11 (the tour guard)** 390×844, seeded: dispatch `RAIL_EXPAND_EVENT`; the
  drawer opens **and** `localStorage["soleur:sidebar.main.collapsed"]` is still
  `"1"`. Nothing else covers Phase 2.5.
- **AC12** `hooks/use-sidebar-collapse.ts` carries the Phase 2.8 comment and the
  vitest case asserting first render is `false` with `localStorage` pre-set to `"1"`.
- **AC13** New e2e blocks run in the existing `authenticated` project
  (`testMatch` already covers `**/nav-states-*.e2e.ts`) — no new project — and the
  required CI `e2e` check is green. Reuse the file's existing `seedCollapsed`
  (`:329-334`), `MOBILE` (`:384`), `DESKTOP` (`:383`), `routeEmptyKbTree` (`:1057`);
  **do not redeclare them** (duplicate implementation error).
- **AC14** `components/kb/kb-mobile-page-header.tsx` still contains
  `text-soleur-text-secondary` — the Phase 3.5 deferral is auditable.
- **AC15** ADR-047 and ADR-158 each carry an amendment referencing #7222.
- **AC16** The PR body says `Ref #7222` and `Closes #3562`; the C follow-up and the
  breakpoint-authority issue both exist and are linked.

### Post-merge (operator-free)

- **AC17** #7201's collapse-leak checklist item ticked with a link to this PR.
  *Automation: `gh issue edit`.*
- **AC18** Prod device-mode check at 390×844 with the collapse key seeded, asserting
  the AC5 + AC6 subset against the deployed `web-vX.Y.Z`. *Automation: Playwright
  MCP against `app.soleur.ai` (not `.com`), sandbox disabled.*

---

## Test Scenarios

Extends `apps/web-platform/e2e/nav-states-shell.e2e.ts` in the existing
`authenticated` project. **Reuse** the file's `seedCollapsed` (`:329-334`), `MOBILE`,
`DESKTOP`, `setupNavMocks`, `gotoOrSkip`, `routeEmptyKbTree`, `secondarySlot`.
Group as two `describe` blocks with one `test.use({ viewport })` each.

| # | Viewport | Route | Assertion (collapsed=1 seeded throughout) |
|---|---|---|---|
| T1 | 390×844 | `/dashboard/settings` | visible text `General`; `settings-rail-icons` count 0; `drawer-back-to-menu` colour == `nav-back-chevron` colour; hover class present |
| T2 | 390×844 | `/dashboard` | theme group has 3 buttons and height ≥44px; `theme-cycle-button` count 0; email row present; both nav dots resolve |
| T3 | 390×844 | KB **document** route | `secondarySlot` contains `kb-tree-scrollport`; `kb-rail-collapsed-expand` count 0 |
| T4 | 390×844 | `/dashboard/kb` (**empty**) | `kb-rail-empty` **and** `Sync now` reachable in the drawer |
| T5 | 390×844 | `/dashboard/chat` | `secondarySlot` contains "Recent conversations" + "New conversation" |
| T6 | 390×844 | `/dashboard` | dispatch `RAIL_EXPAND_EVENT` → drawer opens **and** the localStorage key is still `"1"` |
| T7 | **1280×900** | `/dashboard/settings` | `settings-rail-icons` count 1; `theme-cycle-button` count 1 — **desktop collapse still works** |

Deliberately **not** included: a no-seed run (`railCollapsed === collapsed === false`
with or without the fix — it can never fail because of this diff) and a
client-side-nav run (`/dashboard` → `/dashboard/settings` stays inside the
`(dashboard)` segment, so the layout is not remounted).

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Scope overreach** — swapping `:385`/`:219-220` re-opens PR #4871 | **High if the brief's scope is taken literally** | Phase 2.3/2.4 + the two in-file "ON PURPOSE" comments + AC3 |
| **Fractional dead band** (`767.0 < w < 768.0`) reintroduces the bug | **Certain if two literals are used** | One literal, identical to Tailwind's `md:` (Phase 2.2) |
| Viewport term sticks → desktop collapse dies silently (React does not reconcile className in prod) | Low | `useSyncExternalStore` re-reads every render; **AC7/T7 fail the build** |
| **Stale closure breaks the mobile guided tour** | **High if v2's snippet is used** | Phase 2.5 keeps both reads imperative — no state, no dep change; AC11/T6 |
| `NavDotBadge` sites left raw → Inbox/Releases dots stay missing on mobile | Medium | Phase 2.3 swaps all four badges; AC6 asserts both dot testids |
| A future edit to `nav-count-badge.tsx` reintroduces the leak with AC3 still green | Medium | AC3 pins the four props; add one assertion in the badge test that the collapsed branch carries `md:hidden`/`hidden md:flex` |
| A future cookie-seeded `collapsed` voids the short-circuit | Low now, silent when it happens | Phase 2.8: comment **at the line that would change** + an executable test (AC12) |
| Restoring the theme group shrinks the touch target below 44px | **Certain without the fix** | `h-11 md:h-8`; AC6 asserts ≥44px |
| Issue C's stated mechanism is wrong, so an implementer "fixes" `kb-mobile-layout.tsx`'s flex row and the symptom persists | High if unaddressed | Research Reconciliation; C1 is `c4-workspace.tsx` |
| `Closes #7222` auto-closes the umbrella | Medium | AC16 |
| Gold-on-gold adjacency; light-theme `-fg` below AA | Medium | DC-2 + AC6's standalone contrast report; token fix is a follow-up |
| The closed off-canvas drawer now exposes the **full** expanded nav to assistive tech | Medium | Named and filed (Phase 5.6); `layout.tsx:232-238` already tracks the inert fix |

---

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **Narrow the provider to the rail subtree, or nest `<RailCollapsedProvider value={false}>` around the drawer** (the strong-model advisor's proposal — structurally superior if it worked) | **Refuted by the codebase.** There is exactly ONE `<aside>` (`layout.tsx:359-674`) and ONE `rail-secondary-slot` (`:636-637`): the drawer and the desktop rail are the *same element*, differing only in CSS. There is no drawer subtree to wrap. `kb-sidebar-shell.tsx:61-63` records this; a second provider would be mount-both-hide-one, forbidden by ADR-047/ADR-158 |
| Guard each consumer | Four sites today, unbounded tomorrow; ADR-158:52-54 |
| Swap **every** render read (the brief's scope) | ~20 are already `md:`-scoped; swapping `:385`/`:219-220` re-opens PR #4871 |
| CSS-only | Cannot un-`return` a component, restore an `aria-label`, or change an ARIA role |
| `useMediaQuery` | Measured stuck-false failure in this exact file; the file's own comment at `:151-152` records it |
| `!useIsMobile()` (v2's choice) | Opens the fractional dead band — its `(max-width: 767px)` default has no CSS counterpart to agree with |
| A hand-rolled `useState` + effect | Same mechanism as `useMediaQuery`, and a third authority |
| A 3-candidate Playwright probe before implementation (v1/v2) | Cut — it measured what T7 asserts in CI on every push, via a throwaway patch against a hand-patched dev server. `useSyncExternalStore` removes the risk rather than measuring it |
| Sweep all 16 `matchMedia` stub files (v2) | Cut — only 5 render the layout; a query-blind stub yields `isDesktop === false`, byte-identical to today |
| A separate mobile-drawer density preference | YAGNI (CPO): the drawer is a transient overlay with no width to buy back, and the collapsed form drops *function*, not just pixels |
| Create a new ADR | Amend ADR-047 (which owns the rail contract) + ADR-158 narrowly; a third document is a third sync target |
| A shared `768` TS constant | A TS constant cannot cover the three CSS sites; it would make the JS value look canonical while Tailwind keeps its own |
| Ship all of C in PR 1 | Its structural half needs a wireframe **and** operator sign-off; only the two defaults ride along |

---

## Domain Review

**Domains relevant:** Product, Engineering.

### Engineering (CTO)

**Status:** reviewed. Rejected v1's scope (~7 sites, not ~30; never `:385`/`:219-220`);
ruled the `kb-sidebar-shell` guard not provably redundant (DC-1); recommended
amending ADR-047 + ADR-158 rather than a new ADR; found the `bun run dev` blocker is
a one-line `dev`-script fix closing open issue **#3562**; flagged query-blind
`matchMedia` stubs and required a **two-axis** helper (viewport *and* colour-scheme —
a one-axis stub silently flips the theme in the five `ThemeProvider`-wrapping layout
tests); required Table 2.4's rationale to move **into the file**. Sizing: small
(hours) + ~1h.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `app/**/layout.tsx` and
`components/**/*.tsx` match the glob superset in
`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** copywriter — none recommended; no new user-facing copy
**Pencil available:** yes — `.pen` on disk, non-empty (67 KB)
**Wireframe review:** headless arm — ready for async review at
`knowledge-base/product/design/kb-mobile-chat/screenshots/`; `05-decisions-and-deltas.png`
is the authoritative decision list (six decisions, one rejected alternative, a
five-file delta list). No interactive pause, per `plan/SKILL.md` §Product/UX Gate 4b.

#### Findings

**CPO** — endorsed the split on one non-negotiable condition (no `Closes #7222`);
ranked the unlabelled Settings column and the lost "Sync now" as the top damages;
showed the `priority/p2-medium` "workaround exists" rationale is false; confirmed
the threshold; rejected a density preference as YAGNI; caught that
`embeddedConciergeOpen` is a hardcoded `true`; and **withdrew** the
`kb-mobile-page-header` gold sweep, rerouting it to #7201 as "resolve the duplicate
Back-to-menu affordance".

**spec-flow-analyzer** — folded into PR 1: the empty chat drawer, the unreachable
"Sync now", the tour mutation, and the hook recommendation. Found v2's KB e2e row
**unimplementable** (populated landing hosts the tree in the content column, and
`e2e:1124` pins the rail slot empty), v2's conversations-rail assertion **vacuous**
(the portal wrapper mounts unconditionally), v2's `General` assertion **vacuous**
(`aria-label` supplies the same name in both states), and v2's sequencing rationale
**factually false** (mobile document access already works via #7186).

**ux-design-lead** — produced the `.pen`; found the restored theme control **shrinks
the touch target 44px → 32px**; measured light-theme `-fg` at **3.49:1, below AA**;
and flagged that Phase 4.3's deferred list had lost `kb-chat-sidebar.tsx`, the
context block, the drawer-close coupling, the 44px trigger and focus restore.

### Plan review (5-agent eng panel + named panel)

DHH, code-simplicity and the strong-model advisor independently caught that v1/v2
rejected a hand-rolled hook as *"the same mechanism, differing only in the SSR
seed"* while defaulting to a hook that differs in exactly and only the SSR seed;
v3 resolves it with `useSyncExternalStore`. architecture-strategist found the
**fractional dead band** (P0) and that the contract module `rail-slot.tsx` still
documents the old meaning. Kieran found the **`NavDotBadge` leak** (P0) that v2
marked "verified safe" and that AC3 would have locked in. The panel also cut the
probe, the 16-file sweep, 6 scenarios, 7 ACs and the `border-b` compromise.

---

## Architecture Decision (ADR/C4)

**ADR:** no new ADR — amend **ADR-047** (the full `useRailCollapsed` contract; it
owns the rail contract and `rail-slot.tsx`, so it is what a consumer finds) and
**ADR-158** narrowly (correct its own stale corollary at `:61-66` + DC-1's
rationale). Noted: ADR-047 is taking its third amendment; if the
breakpoint-authority follow-up ships, that PR should create the consolidating ADR
and absorb these clauses.

**C4: no impact.** Enumerated against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: the
only actor is `founder` (`model.c4:8-9`) and the edge `founder -> webapp`
(`:322`) already covers every viewport; no external system or vendor is added; the
surface is `platform.webapp.dashboard` (`:42-46`), whose description a
viewport-scoped render predicate does not falsify; no ownership, tenancy, sharing or
trust-boundary relationship changes. No `.c4` edit, so `regenerate-c4-model.sh` is
not required.

## Observability

The Phase 2.9 trigger set does not fire (no `apps/*/server|src|infra` files). The
fact that matters: **React does not reconcile className mismatches in production
builds** (ADR-158 fact 2), so a viewport divergence renders the wrong nav in prod
and emits nothing to Sentry. Confidence comes from the CI gate, not monitoring.

Failure modes and where each is caught: the mobile fix silently no-ops → AC5/AC6/AC8-AC10;
desktop collapse silently dies → **AC7**; the tour regression → AC11; a
cookie-seeded `collapsed` → AC12's executable pin.

```yaml
discoverability_test:
  command: cd apps/web-platform && npx playwright test e2e/nav-states-shell.e2e.ts --grep "7222"
  expected_output: T1-T7 pass; no ssh, no dashboard
liveness_signal: the required CI `e2e` check (.github/workflows/ci.yml:811-861), every push
```

## Other gates

GDPR/compliance, Infrastructure-as-Code, and Encryption Posture: **skipped** — no
regulated-data surface, no new infrastructure, no persistent store or new
cross-component connection.

## Open Code-Review Overlap

`app/(dashboard)/layout.tsx` → **#2193** (billing-banner refactor).
**Acknowledge:** it concerns the payment banners inside `<main>` (`:687+`); this
plan touches the `<aside>` and the provider value. Zero line overlap; #2193 stays
open. All other paths: no matches across the 64 open `code-review` issues.

---

## Sharp Edges

- **The plan's line numbers shift.** Phase 2.2 inserts ~15 lines near `:145`, so
  every anchor below it moves. AC3 is written as **content anchors** for that
  reason (`cq-cite-content-anchor-not-line-number`); do the same for any new AC.
- A query-blind `matchMedia` stub (`() => ({ matches: false })`) makes a *mobile*
  assertion pass whether or not the fix exists — and a **one-axis** viewport stub
  silently flips `prefers-color-scheme` in the five layout tests that mount
  `<ThemeProvider>`. Use the two-axis helper.
- `settings-shell.tsx:100` sets `aria-label={collapsed ? tab.label : undefined}`, so
  a role-and-name query resolves in **both** states. Mobile assertions must key on
  **visible text**.
- `conversations-rail-portal.tsx` mounts its wrapper testid unconditionally — assert
  containment, never the wrapper.
- On a **populated** mobile `/dashboard/kb` landing the rail slot is empty **by
  design** (#7186 hosts the tree in the content column, pinned at `e2e:1124`).
  Assert the KB drawer on a **document** route.
- `e2e/nav-states-shell.e2e.ts` already defines `seedCollapsed`, `MOBILE`,
  `DESKTOP`, `routeEmptyKbTree` — redeclaring is a duplicate-implementation error.
- Repo environment facts (`npm run -w` fails, `bun test` ignores
  `apps/web-platform/**`, component tests must live in `test/**/*.test.tsx`, prod is
  `app.soleur.ai`) live in `AGENTS.md` and are not restated per-plan.
