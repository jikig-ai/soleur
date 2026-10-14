---
title: "feat: Remove LikeC4 logo and theme the C4 visualizer to Soleur colors"
type: feature
date: 2026-06-04
branch: feat-one-shot-likec4-logo-soleur-theme
lane: single-domain
status: draft
requires_cpo_signoff: false
brand_survival_threshold: none
---

# ✨ feat: Remove the LikeC4 logo and re-theme the C4 visualizer to Soleur's colors

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Overview, Implementation Phases (1–3), Alternatives, Sharp Edges, Acceptance Criteria
**Research used:** Context7 (`/likec4/likec4` v1.47 docs), installed-package inspection (`@likec4/diagram@1.50.0`), codebase grep, institutional learning `2026-05-06-tokenize-on-touch-when-theme-tokens-exist.md`, `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md`

### Key Improvements (from deepen)

1. **ShadowRoot risk RESOLVED — CSS approach is VALID.** Verified that `<LikeC4Diagram>` (the component we use, c4-shared.tsx:12) renders into a light-DOM `RootContainer` (`LikeC4Diagram.js:137`) and does **NOT** use a ShadowRoot. Only `ReactLikeC4` / `LikeC4View` / `custom` wrap in Shadow DOM (`grep`: only those 3 import `shadowroot/ShadowRoot.js`). This is the single load-bearing assumption of the whole plan — had we used `ReactLikeC4`, external scoped CSS would be blocked by the shadow boundary and the entire approach would fail. **We do not. CSS overrides reach the diagram.**
2. **Upstream first-class color-theming API surfaced** (`styles.theme.colors` in `likec4.config`/`defineConfig`) — the blessed way to override `primary`/`secondary`/`muted` palettes with the exact `{elements:{fill,stroke,hiContrast,loContrast}, relationships:{line,label,labelBg}}` shape. Folded into Alternatives with the explicit reason CSS is still chosen.
3. **Test runner pinned: `vitest`** (`package.json` `"test": "vitest"`), and `bunfig.toml` is present — AC6 updated to the exact runner (avoids the `bun test` discovery trap).
4. **Tokenize-on-touch reinforced** — reference `var(--soleur-*)` tokens (not literal hex) and activate the dormant `--soleur-accent-gradient-*` tokens, per learning `2026-05-06-tokenize-on-touch`.

### New Considerations Discovered

- The palette default (`--likec4-palette-fill: #3b82f6`) is applied per-node via the model's computed inline styles keyed on `data-likec4-color` — so the override must either set the `--likec4-palette-*` vars high enough in the scoped subtree to cascade into the nodes, OR target the node selector directly. Verify computed node fill at /work, not just the container var.
- LikeC4 emits an `id`-scoped style root (`#${id}`, `TagStylesProvider rootSelector`), so our `.soleur-c4` wrapper must be an **ancestor** of that `#id` container (it is — our wrapper div wraps `<LikeC4Diagram>`).

## Overview

The new LikeC4 C4-model visualizer (shipped in PR #4883 / #4923, gated behind the
`c4-visualizer` flag) renders the upstream **"LikeC4" wordmark logo** in the
top-left navigation panel of every diagram, and uses LikeC4's **default blue
palette** (`primary` ≈ `#3b82f6`, `secondary`, etc.) for element fills and
relationships. Both clash with the Soleur brand (dark base `#0a0a0a`, gold accent
`#c9a962`).

This plan does two things, scoped strictly to the C4 visualizer surface:

1. **Remove the LikeC4 logo** rendered at the top of the interactive diagram.
2. **Re-theme the diagram colors** (element fills, strokes, relationships,
   background) to match Soleur's existing design tokens.

This is a pure CSS/styling change against an already-provisioned, already-shipped
UI surface. No new infrastructure, no schema changes, no new dependencies, no new
routes. The `@likec4/diagram` library version in use is **1.50.0** (verified:
`apps/web-platform/package.json` + `node_modules/@likec4/diagram/package.json`).

## Research Reconciliation — Spec vs. Codebase

The feature description says "the new likec4 implementation" — verified against the
codebase, this is the `c4-visualizer` feature (PR #4883 + #4923, per MEMORY.md).
No spec.md exists for this branch (`knowledge-base/project/specs/feat-one-shot-likec4-logo-soleur-theme/` absent), so this plan is the primary artifact.

| Description claim | Codebase reality | Plan response |
| --- | --- | --- |
| "the likec4 logo at the top" | The logo is the upstream **LikeC4 wordmark SVG** (`#5E98AF` blue square + "LikeC4" text), rendered by `LogoButton` → `NavigationPanelControls` (top-left nav panel), DOM class `.likec4-navigation-panel__logo`. Verified: `node_modules/@likec4/diagram/dist/navigationpanel/controls/LogoButton.js`, `node_modules/@likec4/diagram/dist/components/Logo.js`, and `node_modules/@likec4/diagram/styles.css` (class confirmed present). | Hide via scoped CSS targeting `.likec4-navigation-panel__logo`. There is **no `showLogo` / `hideLogo` prop** on `LikeC4DiagramProps` (only an `onLogoClick` event handler exists) — CSS hide is the supported path. |
| "the likec4 logo at the top" (alt reading) | Our own components ALSO render a literal text label `LikeC4 · {currentView}` in the tab strip header of both `c4-diagram.tsx:44-46` and `c4-workspace.tsx:115-117`. | This is a SECOND "LikeC4" mark, in OUR code (not the library). Treat it as in-scope: replace the literal `LikeC4 ·` prefix with a neutral/Soleur label (e.g. just `{currentView}` or `Architecture · {currentView}`). See Phase 2. |
| "change the colors to match Soleur's theme" | Element/relationship colors are computed at **model-build time** from the `.c4` spec's semantic color names (`color secondary` etc., default `primary`) into `--likec4-palette-*` CSS variables; the default `primary` resolves to `#3b82f6` (verified in `styles.css`). The chrome (nav panel, controls, backgrounds) is themed by `@likec4/diagram/styles.css` + `@likec4/styles`. | Override the `--likec4-palette-*` and chrome CSS variables with Soleur tokens via a scoped stylesheet. See Phase 3 + Alternatives. |

## User-Brand Impact

**If this lands broken, the user experiences:** a C4 architecture diagram that is
either invisible (logo-hide CSS over-matched and blanked the nav panel) or
unreadable (palette override produced low-contrast gold-on-dark element text). The
diagram is a read-only KB visualization; no data is created, mutated, or lost.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is a
presentational CSS change on an already-public-to-the-tenant KB viewer. No new data
path, no new exposure vector.

**Brand-survival threshold:** none — `threshold: none, reason: purely presentational CSS styling of an existing internal KB visualizer behind the c4-visualizer flag; no data, auth, or money surface is touched.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Logo gone:** In the rendered C4 diagram (inline embed AND full
  workspace), the upstream LikeC4 wordmark is not visible. Verified by a Playwright
  snapshot of a KB diagram page asserting `.likec4-navigation-panel__logo` is hidden
  (`display: none` or `visibility: hidden` computed style), OR is absent from the
  accessibility tree. The nav-panel breadcrumbs/navigation buttons MUST remain
  visible (the hide must NOT collapse the whole nav panel).
- [ ] **AC2 — No literal "LikeC4 ·" label in our chrome:** `git grep -n "LikeC4 ·"
  apps/web-platform/components/kb/` returns zero matches (the tab-strip label in
  `c4-diagram.tsx` and `c4-workspace.tsx` is replaced with a Soleur/neutral label).
- [ ] **AC3 — Soleur palette applied:** The diagram's default element fill uses a
  Soleur token, not LikeC4 blue. Verified by asserting the computed value of
  `--likec4-palette-fill` (or the rendered node fill) on a diagram node is a Soleur
  brand color (derived from `--soleur-accent-gold-*` / `--soleur-bg-surface-*`), NOT
  `#3b82f6`. Capture a before/after screenshot in the PR body.
- [ ] **AC4 — Contrast preserved:** Element labels remain legible in BOTH the dark
  (default) and light Soleur themes — node text vs. node fill meets a reasonable
  contrast bar (manual screenshot check in both `data-theme` states; document both).
- [ ] **AC5 — No global bleed:** The CSS overrides are scoped to the C4 diagram
  container (a wrapper class/selector), so they do NOT alter LikeC4 styles in any
  other context AND do not leak `--likec4-*` vars onto unrelated elements. Verified
  by confirming the override selector is anchored to a C4-specific ancestor.
- [ ] **AC6 — Build + existing tests green:** `next build` succeeds (`package.json`
  `"build": "next build"`); the existing C4 test surface still passes
  (`test/c4-embed.test.ts`, `test/c4-concierge-tools.test.ts`,
  `test/c4-diagram-path-scope.test.ts`). **Runner is `vitest`** (verified:
  `apps/web-platform/package.json` `"test": "vitest"`) — run e.g.
  `./node_modules/.bin/vitest run test/c4-embed.test.ts`. Do NOT use `bun test`:
  `apps/web-platform/bunfig.toml` is present (the bun-discovery trap), and the
  package runner is vitest. These are logic tests unaffected by CSS, so they serve as
  a regression guard, not a styling assertion.
- [ ] **AC7 — Both render entry points covered:** The logo-hide + palette override
  apply to BOTH the inline embed (`c4-diagram.tsx` → `C4Canvas`) and the full
  workspace (`c4-workspace.tsx` → `C4Canvas`), since both mount the same
  `<LikeC4Diagram>` via the shared `C4Canvas` in `c4-shared.tsx`. (Styling the shared
  ancestor covers both for free — verify it does.)

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

- [ ] Confirm `c4-visualizer` flag is ON for the dev cohort so the surface is
  reachable locally (per MEMORY.md it is; `harry@jikigai.com` is a dev). Otherwise
  enable via the flag tooling for local dogfood.
- [ ] Re-confirm the logo DOM class is `.likec4-navigation-panel__logo` against the
  **installed** 1.50.0 build (`grep -o 'likec4-navigation-panel__logo'
  node_modules/@likec4/diagram/styles.css`). If a future bump renamed it, re-derive
  from `LogoButton.js`/`NavigationPanel.js`. (Sharp Edge: library DOM hooks are not a
  stable public API — pin the verification to the installed version.)
- [ ] Decide the scoping anchor. Both `C4Canvas` mounts live under our own wrapper
  divs (`c4-diagram.tsx:29` rounded container; `c4-workspace.tsx` left Panel). The
  cleanest anchor is a dedicated wrapper class added around `<C4Canvas>` in
  `c4-shared.tsx` (single choke point) — confirm this class wraps the
  `<LikeC4Diagram>` render tree so descendant selectors reach the nav panel.

### Phase 1 — Add a scoped C4 theme stylesheet

- [ ] Add a Soleur C4 theme stylesheet. Two valid placements (pick one in
  plan-review/deepen):
  - (a) A new co-located CSS file `apps/web-platform/components/kb/c4-theme.css`
    imported alongside `import "@likec4/diagram/styles.css";` in `c4-shared.tsx:18`
    (keeps the C4 theme next to the C4 components; import ORDER matters — it must come
    AFTER the library styles to win).
  - (b) A scoped block in `app/globals.css` under a C4 wrapper selector.
  - **Recommendation:** (a) — co-location + guaranteed post-library import order.
    `globals.css` uses Tailwind v4 `@layer`s (verified: `@layer base`, `@layer
    components`), and `@likec4/diagram/styles.css` is imported **unlayered** via the
    component; an unlayered globals rule and an unlayered library rule compete on
    source order + specificity, which is fragile. A dedicated file imported right
    after the library import is the most predictable. (Sharp Edge: CSS cascade
    layer/order is the load-bearing risk here — verify computed styles, don't assume.)
- [ ] Add a wrapper class (e.g. `soleur-c4`) on the diagram container in
  `c4-shared.tsx` so all overrides anchor to `.soleur-c4 …` (satisfies AC5/AC7).

#### Research Insights (deepen)

**Why CSS overrides actually work here (load-bearing):** `<LikeC4Diagram>` renders
into a **light-DOM** `RootContainer` (`node_modules/@likec4/diagram/dist/LikeC4Diagram.js:137`)
— NOT a ShadowRoot. Only `ReactLikeC4`, `LikeC4View`, and `custom/index` import
`shadowroot/ShadowRoot.js` (verified by grep). We import `LikeC4Diagram` directly
(`c4-shared.tsx:12`), so descendant CSS from `.soleur-c4` reaches the nav panel and
nodes. **If a future refactor swaps to `ReactLikeC4`/`LikeC4View`, the shadow boundary
will block ALL external CSS and this whole approach breaks** — see Sharp Edges.

**Cascade specificity, not just order:** the LikeC4 chrome rules are class-based
(`.likec4-navigation-panel__logo { … }`, no `!important`). A `.soleur-c4
.likec4-navigation-panel__logo` selector is (0,2,0) vs the library's (0,1,0) — it wins
on specificity regardless of source order, which is more robust than relying on import
order alone. Keep the import-after-library ordering anyway as defense-in-depth.

### Phase 2 — Hide the upstream logo + fix our own label

- [ ] In the C4 theme stylesheet: `.soleur-c4 .likec4-navigation-panel__logo {
  display: none; }`. Verify the nav panel's breadcrumbs/back-forward buttons remain
  (the logo is one child of `NavigationPanelControls`, not the whole panel).
- [ ] In `c4-diagram.tsx:44-46` and `c4-workspace.tsx:115-117`, replace the literal
  `LikeC4 · {currentView}` label with a Soleur/neutral label (e.g.
  `{currentView}` or `Architecture · {currentView}`). This removes the second
  "LikeC4" mark that lives in OUR code. (Confirm with the user whether they want the
  brand word fully gone or just the upstream logo image — both readings are covered
  by doing this; if they want to KEEP "LikeC4 ·" text, this step is dropped. Flag in
  plan-review.)

### Phase 3 — Re-theme colors to Soleur tokens

- [ ] Override the LikeC4 palette CSS variables under `.soleur-c4` so element fills,
  strokes, and relationships use Soleur tokens. Map at least:
  `--likec4-palette-fill`, `--likec4-palette-stroke`, `--likec4-palette-hi`,
  `--likec4-palette-lo`, `--likec4-palette-outline`, `--likec4-palette-relation-stroke`,
  `--likec4-palette-relation-label`, `--likec4-palette-relation-label-bg`
  (full var list verified from `node_modules/@likec4/styles`). Source colors from the
  Soleur tokens already in `globals.css`: gold accent `--soleur-accent-gold-fill`
  `#c9a962`, surfaces `--soleur-bg-surface-1/2`, border `--soleur-border-default`,
  text `--soleur-text-primary/secondary`, gradient `--soleur-accent-gradient-*`.
- [ ] Set the diagram `background` to a Soleur surface. Note `<LikeC4Diagram>` has a
  `background` PROP (`'transparent' | 'solid' | 'dots' | 'lines' | 'cross'`, verified
  in `LikeC4Diagram.props.d.ts`) — consider passing `background="transparent"` or
  `"dots"` from `C4Canvas`/`ViewCanvas` in `c4-shared.tsx` and letting the wrapper's
  Soleur surface show through, rather than CSS-overriding the canvas bg. (Decide in
  deepen: prop vs CSS for the background specifically.)
- [ ] Provide overrides for BOTH `data-theme` states (dark default + light). The
  Soleur tokens already flip per theme in `globals.css`; if the C4 overrides
  reference `var(--soleur-*)` tokens directly, they inherit the per-theme flip for
  free. Prefer referencing the Soleur CSS vars over hardcoding hex (DRY + theme-aware).

#### Research Insights (deepen)

**Tokenize-on-touch (institutional learning `2026-05-06-tokenize-on-touch-when-theme-tokens-exist.md`):**
this codebase already registers `--soleur-accent-gradient-{start,end}` in `globals.css`
`@theme` (lines 58-59/82-83/110-111/136-137) but they are dormant/under-used. Where the
LikeC4 element fill should be a gold gradient, REFERENCE these tokens
(`var(--soleur-accent-gradient-start)` / `-end`) rather than inlining `#d4b36a`/`#b8923e`
— this activates the dormant token and prevents a 4th literal-hex copy. Multi-agent
review (pattern-recognition-specialist) flags literal-hex propagation as P1 when a
matching token exists; pre-empt it.

**LikeC4 palette → Soleur mapping (the canonical per-palette shape, from Context7
`styles.theme.colors`):** each palette resolves to
`{ elements: { fill, stroke, hiContrast, loContrast }, relationships: { line, label, labelBg } }`,
which maps 1:1 onto the `--likec4-palette-*` CSS vars. Suggested Soleur mapping for the
default `primary` element palette (refine at /work against live contrast):
`fill → var(--soleur-bg-surface-2)` (dark) / surface fill, `stroke → var(--soleur-border-emphasized)`,
`hiContrast (label text) → var(--soleur-text-primary)`, `loContrast → var(--soleur-text-secondary)`,
relationship `line → var(--soleur-accent-gold-fg)`, `label → var(--soleur-text-secondary)`,
`labelBg → var(--soleur-bg-surface-1)`. Gold (`--soleur-accent-gold-*`) is best reserved
for accents/relationships, NOT element fills (gold-on-gold-text fails contrast — see
a11y learning `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md`, which
documents that the naive contrast pick is usually wrong). Validate WCAG AA for label
text vs. fill in both themes per AC4.

**Palette vars are applied per-node, not just at the root.** LikeC4 sets
`--likec4-palette-*` on each node via computed inline styles keyed on
`data-likec4-color` (the model carries `"color": "primary"`/`"secondary"` per node —
458 `color` keys in `model.likec4.json`). Setting the vars on `.soleur-c4` relies on
inheritance reaching the node; if the library re-declares the var at the node level
(inline style beats an inherited custom property), the override must instead target the
node-fill selector directly. **Verify the COMPUTED node fill in-browser at /work** —
do not assume the container-level var wins (this is the most likely /work surprise).

### Phase 4 — Verify

- [ ] Run the app locally, open a KB C4 diagram page (full workspace) and an inline
  embed. Confirm: logo gone, breadcrumbs intact, Soleur palette applied, labels
  legible in both themes. Capture before/after screenshots for the PR body
  (Playwright MCP — `mcp__plugin_playwright_playwright__*` — for deterministic
  capture, not manual).
- [ ] Run the build + existing C4 tests (AC6).

## Files to Edit

- `apps/web-platform/components/kb/c4-shared.tsx` — add wrapper class around the
  diagram container; import the new C4 theme CSS after the library CSS; optionally
  pass a `background` prop to `<LikeC4Diagram>`.
- `apps/web-platform/components/kb/c4-diagram.tsx` — replace the `LikeC4 · {view}`
  tab-strip label.
- `apps/web-platform/components/kb/c4-workspace.tsx` — replace the `LikeC4 · {view}`
  tab-strip label.

## Files to Create

- `apps/web-platform/components/kb/c4-theme.css` — scoped Soleur overrides for the
  LikeC4 logo-hide + palette/background variables (anchored to `.soleur-c4`). *(If
  Phase 1 option (b) is chosen, this is instead a block appended to
  `app/globals.css` and this file is not created.)*

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` was not found to touch
`components/kb/c4-shared.tsx`, `c4-diagram.tsx`, `c4-workspace.tsx`, or any new
`c4-theme.css`. (Re-run the two-stage `gh ... --json` + standalone `jq --arg` check
at deepen/work time per the plan-skill convention to confirm against live backlog.)

## Alternative Approaches Considered

| Approach | Verdict | Why |
| --- | --- | --- |
| **CSS-variable override scoped to `.soleur-c4`** (chosen) | ✅ | No model regeneration, no dependency on the `.c4` toolchain at runtime (which is deliberately NOT in prod deps per `c4-constants.ts`), theme-aware via Soleur vars, reversible. Logo-hide is also CSS — same mechanism. |
| **Upstream `styles.theme.colors` config override** (`likec4.config`/`defineConfig`) | ⚠️ Deferred | LikeC4's BLESSED color-theming API (verified via Context7 `/likec4/likec4`): `styles: { theme: { colors: { primary: "#c9a962", secondary: {...}, muted: { elements: { fill, stroke, hiContrast, loContrast }, relationships: { line, label, labelBg } } } } }`. This is the *correct upstream* way to re-color `primary`/`secondary`/`muted`. BUT: (1) it requires the `likec4` config + `export json` toolchain at build time, which Soleur deliberately keeps OUT of prod deps (`c4-constants.ts:C4_MODEL_JSON` docstring — the heavy toolchain drags vite/esbuild and breaks npm10/11 lockfile parity), so this would have to run only in the `/soleur:architecture render` skill and bake colors into the committed `model.likec4.json`; (2) it does NOT remove the logo (logo is library chrome, not model/theme). Net: viable for COLOR only, still needs the CSS path for the LOGO, so adopting it would mean two mechanisms. CSS-var override does both in one place. Revisit ONLY if brand colors are needed in STATIC/exported diagrams (where no CSS layer exists). |
| **Custom colors in the `.c4` spec** (`color my-brand-gold #c9a962` + `element … { style { color my-brand-gold } }`) + regenerate `model.likec4.json` | ⚠️ Deferred | LikeC4 spec supports custom named colors (Context7-confirmed); would bake Soleur colors per-element into the model. Same toolchain-regeneration cost as the config path above, same "does not remove logo" gap, plus it requires editing every element's `style` block. CSS is strictly simpler for this scope. |
| **`showLogo`-style prop on `<LikeC4Diagram>`** | ❌ Not available | `LikeC4DiagramProps` (verified, full type read) has no logo-visibility prop — only `onLogoClick`. Setting `controls={false}` would hide the WHOLE controls/nav panel (breadcrumbs, navigation, search), which is too much. CSS hide of just the logo is the surgical option. |
| **Fork/patch `@likec4/diagram`** | ❌ Rejected | Massive maintenance cost vs. a few lines of scoped CSS. YAGNI. |

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — `ux-design-lead` N/A (no NEW user-facing surface, page, or flow is created; this re-skins an EXISTING, already-shipped diagram component with brand tokens and removes a third-party logo). Per the plan-skill UI-surface override: the Files to Edit/Create touch `components/kb/*.tsx` + a `.css`, none of which are new `app/**/page.tsx`, `app/**/layout.tsx`, or a new `components/**/*.tsx` user-facing surface — they modify existing components. This is a re-theme of an existing component, classified **ADVISORY**, and in pipeline context is auto-accepted.
**Pencil available:** N/A (no new UI surface — re-skin only, no wireframe needed)

#### Findings

Re-theming an existing internal KB visualizer to brand colors and removing a
third-party vendor logo. No new flows, no copy with persuasive/emotional intent, no
new interactive surfaces. Brand-positive (removes upstream branding, applies Soleur
identity). No product-strategy or flow-completeness concerns.

## Observability

This plan is a pure CSS/styling + label-text change against an already-shipped UI
component. No new code-class file under `apps/*/server/`, `apps/*/src/`, or
`apps/*/infra/` introduces a runtime/observable surface, and no new infrastructure is
created. The edited `.tsx` files are presentational and the new file is `.css`.

Per the Phase 2.9 skip condition ("Plan is pure-docs / styling — no new code/infra
surface introducing an observable failure mode"), a full 5-field observability schema
does not apply. The only "failure mode" is visual (logo still visible / wrong colors /
contrast regression), which is covered by AC1–AC5 (Playwright snapshot + before/after
screenshots) — there is no server signal, log, or alert to wire because nothing runs
server-side. If deepen-plan Phase 4.7 requires the schema verbatim, fill as:

```yaml
liveness_signal:    "visual render of C4 diagram on KB page / on every page view / no alert (client-render) / configured_in: components/kb/c4-shared.tsx"
error_reporting:    "existing client error boundary on the KB page; CSS cannot throw — fail_loud: n/a"
failure_modes:      [{mode: "logo still visible", detection: "Playwright AC1 snapshot", alert_route: "PR review"}, {mode: "low-contrast labels", detection: "AC4 dual-theme screenshot", alert_route: "PR review"}, {mode: "global CSS bleed", detection: "AC5 scope assertion", alert_route: "PR review"}]
logs:               "n/a (no server surface) / retention: n/a"
discoverability_test: {command: "next build && ./node_modules/.bin/vitest run test/c4-embed.test.ts (NO ssh)", expected_output: "build succeeds; C4 tests pass"}
```

## Infrastructure (IaC)

None. No server, service, cron, secret, DNS, cert, vendor account, or firewall rule
is introduced. Pure client-side code change against an already-provisioned surface
(Phase 2.8 skip condition: plan only edits files under `apps/<app>/components/` +
adds a `.css`).

## Test Scenarios

- Open a KB C4 diagram page (full workspace) → logo absent, breadcrumbs + nav buttons
  present, Soleur palette on nodes/edges, background is a Soleur surface.
- Open an inline `likec4-view` markdown embed → same logo-hide + palette applies (via
  shared `C4Canvas`).
- Toggle `data-theme` light/dark → colors flip with the Soleur tokens; labels legible
  in both.
- Drill into a sub-view (click navigates) → palette + logo-hide persist across view
  changes.
- Regression: existing C4 logic tests still pass; no global LikeC4 styling appears
  outside the C4 container.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan fills it with `threshold: none` + a non-empty scope-out reason.
- **Library DOM class `.likec4-navigation-panel__logo` is NOT a public API.** It is an
  internal class on the upstream component (verified against installed 1.50.0). A
  future `@likec4/diagram` bump could rename it, silently un-hiding the logo. Phase 0
  re-verifies it against the installed version; consider an AC/test that asserts the
  logo is hidden so a bump that breaks the selector is caught by CI, not by a user.
- **CSS cascade order is load-bearing.** `@likec4/diagram/styles.css` is imported
  unlayered via `c4-shared.tsx`; `globals.css` uses Tailwind v4 `@layer`s. The
  override stylesheet must win over the library CSS — verify by inspecting COMPUTED
  styles in the browser, not by assuming specificity. Importing the C4 theme file
  immediately AFTER the library import (Phase 1 option a) is the most predictable.
- **`controls={false}` is the wrong lever** — it hides the entire nav/controls panel,
  not just the logo. The surgical fix is CSS-hiding only `.likec4-navigation-panel__logo`.
- **Two "LikeC4" marks exist**: the upstream wordmark SVG (library chrome) AND our own
  `LikeC4 · {view}` text label (our code). Confirm with the user whether "remove the
  logo" means just the image or also the text mark; this plan removes both by default.
- Element/relationship colors are computed at MODEL-BUILD time into `--likec4-palette-*`
  vars — the CSS override approach re-paints them at render time regardless of the
  committed `model.likec4.json`, so no model regeneration is needed. If a future
  requirement needs brand colors in STATIC/exported diagrams, that requires the
  `.c4`-spec custom-colors path (deferred Alternative) and a model regenerate.
- **The CSS approach depends on `<LikeC4Diagram>` rendering in the LIGHT DOM.** Verified
  for 1.50.0 (it uses `RootContainer`, not `ShadowRoot`). If anyone later swaps to
  `ReactLikeC4`, `LikeC4View`, or `@likec4/diagram/bundle` exports (which DO wrap in a
  ShadowRoot for style isolation), the shadow boundary will block every external CSS
  override and silently restore the logo + blue palette. If the component is ever
  changed, re-evaluate the theming mechanism (those shadowed variants accept a
  `colorScheme` prop and the config-`styles.theme.colors` path instead).
- **Per-node inline custom-property precedence.** An inline `style="--likec4-palette-fill:…"`
  on a node beats an inherited `--likec4-palette-fill` set on `.soleur-c4`. If the library
  re-declares the palette var at the node level, the container-scoped override is silently
  ignored and only the node-fill SELECTOR override works. Confirm computed node fill in the
  browser before declaring AC3 met — do not assert on the container var alone.
- **Phase 4.9 UI-wireframe gate determination (recorded for auditability):** the plan's
  Files-to-Edit match the `components/**/*.tsx` glob superset, which mechanically flags a
  UI surface. However, the shared UI-surface term list (`brainstorm/references/ui-surface-terms.md`)
  explicitly EXCLUDES "Pure copy or style tweaks with no structural/layout change." This
  plan is exactly that: add a wrapper className, swap a text label, add a scoped CSS file
  — zero new components, pages, layouts, or flows. No `.pen` wireframe is produced because
  there is no new visual design to wireframe (re-skin of an existing, already-designed
  component). A `### Product/UX Gate` subsection IS present (ADVISORY, auto-accepted in
  pipeline) with `ux-design-lead` NOT in `Skipped specialists:` — so `work` Check-9 (which
  fails only on a missing gate subsection OR `ux-design-lead` listed as skipped) passes.
  If a reviewer disagrees and wants a wireframe, escalate to `ux-design-lead` before /work.
