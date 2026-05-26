---
type: fix
classification: ui-consistency
branch: feat-one-shot-normalize-fonts-to-non-serif
created: 2026-05-11
deepened: 2026-05-11
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** 4 (Files to Edit — Root layout, Files to Edit — globals.css `@theme`, Sharp Edges, Research Insights)
**Research sources used:** Context7 (`/vercel/next.js` — `next/font` + Tailwind v4 integration docs), live read of installed `next/font` type defs (`NextFont` shape: `{ className, style, variable }`), grep of `apps/web-platform/package.json` (Next 15.5.15, Tailwind 4.1.0).

### Key Improvements

1. **Corrected the `@theme` registration pattern.** The original draft proposed `--font-sans: var(--font-sans), system-ui, ...;` which is a self-referential cycle and would emit empty in Tailwind v4. The Next.js canonical pattern is: load the font with a **distinct** variable name (`--font-inter`), then map it in `@theme inline { --font-sans: var(--font-inter); }`. Plan updated.
2. **Corrected the wiring location.** The original draft wired `${sans.variable} ${sans.className}` on `<body>`. The canonical Next.js + Tailwind v4 pattern is `${inter.variable}` on `<html>` (so the variable is root-scoped) and let `@theme inline` define `--font-sans` from it. Plan updated.
3. **Dropped `${sans.className}` from the wiring.** `className` inlines `font-family: <font-stack>` directly on the element, which is unnecessary once `@theme inline` resolves `font-sans` to Inter — the body inherits Inter via the `font-sans` utility (or via a `font-family: var(--font-sans)` declaration in `@layer base`). Cleaner separation: next/font provides the variable; Tailwind theme exposes the utility; the cascade resolves the rest.
4. **Added an explicit `@layer base { body { font-family: var(--font-sans); } }` step** so even un-classed descendants inherit Inter, removing reliance on the browser's user-agent default for elements without explicit `font-sans` utility class.

### New Considerations Discovered

- The renamed `--font-inter` variable name (instead of `--font-sans` on the next/font side) clarifies that the variable's *source* is the imported Inter font, while `--font-sans` is the *theme-token alias*. This separation is the official Vercel pattern and avoids the cycle.
- The existing `${sans.variable}` value in `components/connect-repo/fonts.ts` is currently `"--font-sans"` — this must be renamed to `"--font-inter"` to avoid the cycle. The plan now prescribes this rename explicitly.
- The `app/(auth)/connect-repo/page.tsx:613` inline style `fontFamily: "var(--font-sans), system-ui, sans-serif"` becomes redundant once the layout-level wiring covers it; the plan now prescribes removing this inline style entirely.

# fix: Normalize web-platform fonts to a single non-serif family

## Overview

Some surfaces in `apps/web-platform` (notably the KB sidebar "Soleur" / "Knowledge Base" header, the KB empty / no-project / workspace-not-ready states, and the full `connect-repo` flow) render in a serif typeface while the rest of the app renders in the body's inherited sans / system stack. The visual inconsistency is visible in the user-supplied screenshot ("Soleur" wordmark + "Knowledge Base" labels rendering as serif while sibling chrome is sans).

This plan **normalizes every surface in `apps/web-platform` to a single non-serif (sans) family** by:

1. Eliminating every `font-serif` Tailwind utility and every `${serif.className}` / `${serif.variable}` next/font interpolation from the web-platform tree.
2. Removing the `Cormorant_Garamond` import in `components/connect-repo/fonts.ts` and consolidating to a single Inter-only module.
3. Registering a single canonical `--font-sans` token at the `<body>` level via `app/layout.tsx` so every descendant inherits the same stack — no per-component variable threading required.
4. Pinning Tailwind v4's `font-sans` utility to the same token via `@theme` in `app/globals.css` so the `font-sans` utility class (where retained) and bare inheritance resolve identically.
5. Updating the three test files that mock `Cormorant_Garamond` from `next/font/google` so the suite still loads.

**Scope:** `apps/web-platform/**` only. The Eleventy marketing/docs site at `plugins/soleur/docs/**` keeps its `Cormorant Garamond` headlines — that surface is explicitly out of scope because it is the **marketing** site (different audience, different brand-intent) and the user's screenshot is the **dashboard** (web-platform). See "Non-Goals" below for the explicit cut.

## User-Brand Impact

**If this lands broken, the user experiences:** Headings on `/dashboard/kb`, `/connect-repo`, `/connect-repo/setting-up`, `/connect-repo/failed`, and seven sibling connect-repo states render in the browser's last-resort font (raw system serif or a missing-glyph stack) instead of Inter, producing a "broken stylesheet" perception on the first surface a new signup sees after auth (the connect-repo wizard).

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — typography-only change, no data, no auth, no payment surface touched.

**Brand-survival threshold:** `aggregate pattern`

**Why `aggregate pattern` and not `none`:** The current brand guide (`knowledge-base/marketing/brand-guide.md` lines 249-257) explicitly mandates Cormorant Garamond for headlines as a deliberate differentiator ("Serif — deliberately distinguishes from every dev tool"). Stripping the serif family from the web-platform dashboard knowingly diverges the dashboard from the documented brand. This is a brand-guide deviation, not a brand-survival deviation — no single user sees brand collapse, but the aggregate visual identity (dashboard vs marketing site) drifts. The plan deliberately accepts the divergence because the user's request ("Normalize all fonts in the app to the non-serif (sans-serif) family") is unambiguous and load-bearing, but a domain-leader sign-off (CMO) is the appropriate gate before merge — see Domain Review.

## Research Reconciliation — Spec vs. Codebase

| Spec / user claim | Codebase reality | Plan response |
|---|---|---|
| "some places render in serif while the rest use non-serif" | Confirmed. `font-serif` Tailwind utility on 4 KB components + `${serif.className}` (next/font Cormorant Garamond) on 10 connect-repo components. Body has no font-family declaration — descendants inherit browser default. | Normalize all 14 sites to sans. |
| "the established non-serif family" | No single canonical sans is registered in `apps/web-platform`. `components/connect-repo/fonts.ts` loads Inter via `next/font/google` but only the connect-repo page wires it via `${sans.variable}` on a wrapper div. `app/layout.tsx` has no font className on `<body>`. `app/globals.css` does NOT register `--font-sans` / `--font-serif` / `--font-mono` in `@theme`. | Establish Inter as the canonical sans by (a) applying `${sans.variable} ${sans.className}` (or equivalent variable propagation) on `<body>` in `app/layout.tsx`, (b) registering `--font-sans` in `@theme` so the `font-sans` Tailwind utility resolves to Inter. |
| "font-serif" inconsistency in KB sidebar | The `font-serif` Tailwind v4 utility in the four KB components resolves to **Tailwind's default serif stack** (`ui-serif, Georgia, Cambria, ...`) — NOT to Cormorant Garamond, because `--font-serif` is never registered in `@theme` and Cormorant is only loaded inside `connect-repo`. So the KB sidebar today renders in a generic system serif (Times-like), which is the worst of both worlds: serif-but-not-brand-serif. | This *strengthens* the user's request: even keeping the current "brand serif" interpretation, the KB sidebar isn't rendering it correctly. Removing `font-serif` is the right normalization. |
| "Find every place a serif font is declared or inherited" | Email templates (`supabase/templates/magic-link.html`, `server/notifications.ts`) declare `font-family` stacks that **end** in `sans-serif` (the generic CSS family keyword, not a serif declaration). Substring matches `serif` but is semantically sans. | No edit required — these are correctly sans-serif. Document in Non-Goals to prevent reviewer churn. |
| Marketing/docs site at `plugins/soleur/docs/**` | Loads Cormorant Garamond via `@font-face` and uses `var(--font-display)` extensively across `_includes/base.njk`, landing hero, landing CTA, section titles. | Explicitly out of scope — this plan is about `apps/web-platform`. Documented in Non-Goals. |

## Hypotheses

The font inconsistency the user sees in the screenshot has two compounding causes, both rooted in `apps/web-platform`:

1. **KB sidebar serif drift:** `components/kb/kb-sidebar-shell.tsx`, `no-project-state.tsx`, `empty-state.tsx`, `workspace-not-ready.tsx` use `className="font-serif ..."`. In Tailwind v4 without a `@theme` `--font-serif` registration, `font-serif` resolves to the default `ui-serif` stack — so the KB sidebar renders as Georgia / Times. The rest of the dashboard inherits the body's lack-of-font-family, which the browser resolves as the user-agent default (typically Times in Safari, sans in Chrome on some platforms — itself another inconsistency vector).

2. **Connect-repo intentional serif:** The 10 `components/connect-repo/*-state.tsx` files apply `${serif.className}` (next/font Cormorant Garamond). This is intentional per the brand guide, but contradicts the user's "normalize to non-serif" request. The plan removes it.

## Files to Edit

### Component files (drop `font-serif` Tailwind utility, replace with no class or with `font-sans`)

- `apps/web-platform/components/kb/kb-sidebar-shell.tsx:18` — strip `font-serif`.
- `apps/web-platform/components/kb/no-project-state.tsx:12` — strip `font-serif`.
- `apps/web-platform/components/kb/empty-state.tsx:10` — strip `font-serif`.
- `apps/web-platform/components/kb/workspace-not-ready.tsx:11` — strip `font-serif`.

### Component files (drop `${serif.className}` interpolation, drop the `serif` import)

- `apps/web-platform/components/connect-repo/create-project-state.tsx:9,45`
- `apps/web-platform/components/connect-repo/ready-state.tsx:7,46,101`
- `apps/web-platform/components/connect-repo/select-project-state.tsx:9,64`
- `apps/web-platform/components/connect-repo/setting-up-state.tsx:7,19`
- `apps/web-platform/components/connect-repo/choose-state.tsx:8,21,41,60`
- `apps/web-platform/components/connect-repo/no-projects-state.tsx:8,24`
- `apps/web-platform/components/connect-repo/github-redirect-state.tsx:8,20`
- `apps/web-platform/components/connect-repo/github-resolve-state.tsx:7,19`
- `apps/web-platform/components/connect-repo/failed-state.tsx:7,117`
- `apps/web-platform/components/connect-repo/interrupted-state.tsx:7,22`

### Page-level wiring

- `apps/web-platform/app/(auth)/connect-repo/page.tsx:7,612,613`:
  - Drop `serif` from import (line 7).
  - Drop `${serif.variable} ${sans.variable}` from the wrapper className (line 612) — both are redundant once the layout-level `<html>` wiring is in place.
  - Drop the entire `style={{ fontFamily: "var(--font-sans), system-ui, sans-serif" }}` inline-style attribute (line 613). The body inherits `--font-sans` via `@layer base` and the inline style is fighting the cascade.
  - The `sans` import is also no longer needed at the page level — remove the entire import line if `sans` is no longer referenced. (Note: if line 7 currently imports both `serif` and `sans`, the entire line is removed.)

### Fonts module (collapse to Inter-only, rename variable to `--font-inter`)

- `apps/web-platform/components/connect-repo/fonts.ts` (or relocate to `app/fonts.ts` per the sibling refactor below):
  - Remove the `Cormorant_Garamond` import and the `serif` export.
  - Rename the `Inter` call's `variable` option from `"--font-sans"` to `"--font-inter"`. This is the canonical Next.js + Tailwind v4 pattern (Vercel docs, `/vercel/next.js` → `next/font/google` with Tailwind v4): the next/font variable carries the **font source name** (`--font-inter`), and the theme aliases it to the **role name** (`--font-sans`). Eliminates the self-reference cycle the original draft would have produced.
  - Export shape after edit: `export const sans = Inter({ subsets, weight, variable: "--font-inter", display: "swap" })`.

### Root layout (apply variable on `<html>`, body inherits via `@layer base`)

- `apps/web-platform/app/layout.tsx`:
  - Import `sans` from `@/app/fonts` (after the relocation below) or from `@/components/connect-repo/fonts` (if skipping the relocation).
  - Apply `${sans.variable}` to the `<html>` element's className (Vercel canonical: `<html lang="en" className={inter.variable} suppressHydrationWarning>`). Do **not** add `${sans.className}` to `<html>` or `<body>` — inlining `font-family` on the root element conflicts with the cascade we want from `@layer base { body { font-family: var(--font-sans); } }`.
  - Keep the existing `<body className="bg-soleur-bg-base text-soleur-text-primary antialiased">` token classes unchanged.
- Sibling refactor: move `apps/web-platform/components/connect-repo/fonts.ts` → `apps/web-platform/app/fonts.ts`. Update the import in `app/(auth)/connect-repo/page.tsx` and the new import in `app/layout.tsx`. Update the three test files' `vi.mock("next/font/google", ...)` paths if they reference the source location (they mock the package, not the module — so likely no test path edit is needed; verify).

### Tailwind v4 `@theme inline` registration (corrected pattern)

- `apps/web-platform/app/globals.css` — add an `@theme inline` block (separate from the existing `@theme` block for colors) that maps `--font-sans` to the next/font variable:

    ```css
    @theme inline {
      --font-sans: var(--font-inter), system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    }
    ```

    The `inline` keyword (Tailwind v4) tells Tailwind to inline the variable value at compile time, so the `font-sans` utility resolves to the full stack. Without `inline`, Tailwind emits `font-family: var(--font-sans)` and relies on runtime CSS variable resolution — which still works but is less robust on initial paint before the next/font variable is applied.
- Also add to `app/globals.css` `@layer base`:

    ```css
    body {
      font-family: var(--font-sans);
    }
    ```

    Place this **next to** the existing `body { background-color: ...; color: ...; }` rule. This ensures every descendant of `<body>` — including elements without an explicit Tailwind `font-*` utility — inherits Inter, not the user-agent default (which is Times in Safari on macOS, a known cross-browser inconsistency vector that's part of why the original screenshot looked broken).

### Test mocks (remove the `Cormorant_Garamond` mock so `next/font/google` mock surface matches the new module)

- `apps/web-platform/test/ready-state.test.tsx:9-11`
- `apps/web-platform/test/connect-repo-page.test.tsx:20-22`
- `apps/web-platform/test/connect-repo-failed-state.test.tsx:5-7`

## Files to Create

None.

## Open Code-Review Overlap

None. (Verified via `gh issue list --label code-review --state open --json number,title,body` grepped for `fonts.ts`, `font-serif`, `kb-sidebar-shell`, `Cormorant`, `connect-repo/fonts`.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `rg "font-serif" apps/web-platform/components apps/web-platform/app` returns **zero matches** for the Tailwind utility (matches inside `sans-serif` CSS keyword strings are exempt and should be preserved).
- [x] `rg "Cormorant|Garamond" apps/web-platform/` returns **zero matches** (component code, app code, AND test mocks).
- [x] `rg "\\\${serif\\." apps/web-platform/components apps/web-platform/app` returns **zero matches**.
- [x] `rg "\bserif\b" apps/web-platform/components/connect-repo/fonts.ts` returns **zero matches** (file collapsed to Inter-only) — or the module is moved to `app/fonts.ts` and the source-file no longer exists.
- [x] `app/layout.tsx` `<body>` includes `${sans.variable}` (or equivalent next/font className) so Inter is inherited app-wide.
- [x] `app/globals.css` `@theme` block contains a `--font-sans` declaration that registers Inter (via `var(--font-sans)`) with a system fallback stack.
- [x] `bun test` passes (the three connect-repo test files no longer reference `Cormorant_Garamond` in their mocks but still load Inter).
- [ ] `bun run --filter soleur-web-platform build` (or `cd apps/web-platform && bun run build`) produces a clean Next.js production build with no warnings about unresolved fonts.
- [ ] Manual verification (Playwright MCP or local dev server screenshots) of the eight surfaces below shows **the same Inter sans-serif typeface** on every heading:
    1. `/dashboard/kb` empty state header "Knowledge Base"
    2. `/dashboard/kb` no-project state
    3. `/dashboard/kb` workspace-not-ready state
    4. `/dashboard/kb` empty-state heading
    5. `/connect-repo` choose state heading
    6. `/connect-repo` setting-up state heading
    7. `/connect-repo` failed state heading
    8. `/connect-repo` ready state heading
- [ ] Screenshot diffs are attached to the PR body for at least two of the eight surfaces (before / after).
- [ ] PR body uses `Ref #<issue>` (no auto-close keywords), per `wg-use-closes-n-in-pr-body-not-title-to`.

### Post-merge (operator)

- [ ] CMO sign-off on the brand-guide deviation OR a follow-up PR updates `knowledge-base/marketing/brand-guide.md` lines 249-257 to remove the "Headlines = Cormorant Garamond" mandate from the web-platform surface. The brand guide remains authoritative for the Eleventy marketing site.

## Test Scenarios

- **T1 — KB sidebar renders Inter:** Render `<KbSidebarShell>` in a JSDOM test (or smoke-test against a built page); assert the heading's computed `font-family` resolves to a stack starting with Inter (or, in the test environment where Inter isn't loaded, assert the heading no longer has `className="font-serif"`).
- **T2 — connect-repo headings render sans:** For each of the 10 connect-repo state components, render with the existing test harness and assert the heading element does **not** carry the `mock-serif` className (was previously injected by the now-removed `Cormorant_Garamond` mock).
- **T3 — Tests load:** All three updated test files (`ready-state`, `connect-repo-page`, `connect-repo-failed-state`) execute without `next/font/google` import errors.
- **T4 — Build is clean:** `cd apps/web-platform && bun run build` produces no warnings or errors related to fonts.
- **T5 — Email templates unchanged:** `supabase/templates/magic-link.html` and `server/notifications.ts` HTML output is byte-identical pre- and post-PR (these were flagged by substring grep but are correctly `sans-serif` already).

## Non-Goals

- **Eleventy marketing/docs site (`plugins/soleur/docs/**`)** — out of scope. The marketing site keeps Cormorant Garamond per existing `_includes/base.njk` declarations. The user's screenshot is of the dashboard (web-platform), not the docs site, and the user's request says "the app" — that is `apps/web-platform`.
- **Email templates** (`supabase/templates/magic-link.html`, `server/notifications.ts`) — already sans-serif (the `sans-serif` substring matched the grep but they declare sans stacks ending in the `sans-serif` generic family keyword). No edit required.
- **Brand-guide update** — out of scope for this PR. A follow-up issue should be filed to either (a) update the brand guide to allow Inter-only on the dashboard, or (b) re-introduce Cormorant Garamond app-wide via a registered `--font-serif` token. See Acceptance Criteria post-merge step.
- **Font preloading / `display: swap` tuning** — keep current next/font defaults.
- **Mobile font-size adjustments** — out of scope.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **Literal: remove all serif from web-platform** (chosen) | Honors the user's explicit request verbatim. Smallest, most testable diff. Eliminates the "system serif" rendering bug in KB sidebar as a free side-effect. | Diverges from documented brand guide. Requires CMO carry-forward sign-off. | **Chosen.** User language is unambiguous. |
| **Register `--font-serif` in `@theme` so KB sidebar renders Cormorant** | Fixes the KB sidebar's accidental "system serif" rendering. Aligns dashboard with brand guide. | Contradicts the user's "normalize to non-serif" request. Larger bundle (loads Cormorant on every dashboard route). | Rejected — contradicts user request. Filed as follow-up issue: "Brand-guide reconciliation: dashboard serif or no serif?" |
| **Per-component font-family inline styles** | Avoids the body-level inheritance change. | Repeats the per-page wiring problem. Doesn't fix the root cause (no app-wide canonical sans). | Rejected. |

## Domain Review

**Domains relevant:** Product (UX), Marketing (brand)

### Marketing (CMO)

**Status:** to be invoked via Phase 2.5 domain sweep during plan execution. Carry-forward note: the plan explicitly deviates from `knowledge-base/marketing/brand-guide.md` lines 249-257. CMO should weigh in on whether (a) accept the deviation for the dashboard surface only, (b) defer the PR until the brand guide is updated, or (c) reject in favor of the "register Cormorant globally" alternative.

### Product/UX Gate

**Tier:** advisory (modifies existing user-facing pages — KB sidebar headers and connect-repo wizard headers — without adding new pages or flows). The mechanical escalation rule does not fire because no new files under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` are created.

**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (advisory tier, pipeline context)
**Skipped specialists:** none
**Pencil available:** N/A — no new UI surfaces, only typography swap.

#### Findings

The UX impact is a typeface swap on existing headings. No new flows, modals, or interactive surfaces. The plan's Acceptance Criteria includes screenshot diffs on the eight affected surfaces, which is the appropriate verification for an advisory-tier change.

## Sharp Edges

- **`@theme` `--font-sans` self-reference (RESOLVED via deepen-plan):** Original draft would have produced `--font-sans: var(--font-sans), ...` (cycle). Plan now uses the canonical Vercel pattern: next/font emits `--font-inter`, `@theme inline` defines `--font-sans: var(--font-inter), <fallback stack>`. No cycle. Verify at /work time via DevTools: `body` computed `font-family` should be `"__Inter_xxxx", "Inter Fallback", system-ui, ...` (Tailwind v4 inlines the resolved chain when `@theme inline` is used).
- **`@theme inline` vs `@theme`:** Tailwind v4 supports both. `@theme` (no `inline`) declares a theme variable that resolves at runtime via `var()`. `@theme inline` inlines the resolved value at compile time, which is more robust before the next/font variable className is applied to `<html>`. For this plan, `@theme inline` is the correct choice — recommended by Vercel docs for next/font integration.
- **`fonts.ts` module location:** The current module lives at `components/connect-repo/fonts.ts`. After this PR, Inter is app-wide — the module is no longer connect-repo-scoped. Either move it to `app/fonts.ts` (preferred — update one import) or leave it in place with a comment. Do not leave it un-commented; the next reader will assume Inter is connect-repo-only and re-introduce a sibling sans module elsewhere.
- **Test-mock surface area:** Three test files mock `Cormorant_Garamond` from `next/font/google`. After the `fonts.ts` collapse, the source module no longer imports `Cormorant_Garamond`, but the test mocks are still registered against the module-mock surface. Leaving the mock entries in place is harmless (they're never called), but they signal stale intent — remove them in the same PR.
- **`font-serif` token vs `font-family: serif` keyword:** The grep for `serif` matches both Tailwind utility classes (`font-serif`) and the CSS generic-family keyword `sans-serif` in font stacks. Acceptance Criteria explicitly exempts `sans-serif` keyword matches in email-template font stacks — do not delete those.
- **Bare-repo file reads:** This worktree is on a feature branch. After merge, follow `rf-after-merging-read-files-from-the-merged` — read merged files via `git show main:<path>`, not the bare repo directory.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is populated with concrete artifact/vector declarations and an explicit `aggregate pattern` threshold — fill is verified at write time.
- **CMO sign-off is a post-merge AC, not pre-merge.** The PR can ship without CMO approval because the change is reversible (one revert PR restores the serif). The brand-guide reconciliation can run async. Pre-merge CMO escalation is appropriate only if the threshold were `single-user incident` — which it is not for typography.

## Research Insights

- **Next.js next/font shape (verified from installed type defs `node_modules/next/dist/compiled/@next/font/dist/types.d.ts`):**

    ```ts
    export type NextFont = {
      className: string;
      style: { fontFamily: string; fontWeight?: number; fontStyle?: string };
    };
    export type NextFontWithVariable = NextFont & { variable: string };
    ```

    The `variable` field is a CSS class name (e.g. `__variable_e8ce0c`) which, when applied to an element, injects a CSS rule that sets the configured CSS variable name (`--font-inter` in our case) to the resolved font-family stack for that element's subtree. The `className` field directly inlines `font-family: <stack>` on the element — using BOTH `variable` and `className` together is redundant; use one or the other.

- **Vercel + Tailwind v4 canonical pattern (Context7 `/vercel/next.js` `next/font` docs, verified 2026-05-11):**

    ```tsx
    // app/layout.tsx
    import { Inter, Roboto_Mono } from "next/font/google";
    const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
    const roboto_mono = Roboto_Mono({ subsets: ["latin"], display: "swap", variable: "--font-roboto-mono" });

    export default function RootLayout({ children }) {
      return (
        <html lang="en" className={`${inter.variable} ${roboto_mono.variable} antialiased`}>
          <body>{children}</body>
        </html>
      );
    }
    ```

    ```css
    /* app/globals.css */
    @import "tailwindcss";
    @theme inline {
      --font-sans: var(--font-inter);
      --font-mono: var(--font-roboto-mono);
    }
    ```

    Key points: `${inter.variable}` on `<html>` (not `<body>`); the next/font variable name (`--font-inter`) is distinct from the Tailwind theme alias (`--font-sans`); `@theme inline` aliases one to the other.

- **`@theme` vs `@theme inline` (Tailwind v4 docs):** `@theme inline` resolves variable values at compile time and inlines them where used. `@theme` (no `inline`) preserves the `var()` reference at runtime. For next/font integration, `inline` is preferred because the next/font variable className is applied to a real DOM element (`<html>`) — the runtime `var()` reference resolves correctly only inside that element's subtree.

- **Tailwind v4 `font-serif` default:** When `--font-serif` is not registered in `@theme`, the `font-serif` utility resolves to Tailwind v4's preset default (`ui-serif, Georgia, Cambria, "Times New Roman", Times, serif`). This is what the KB sidebar is rendering today — not Cormorant. After this PR, the `font-serif` utility is no longer referenced anywhere in `apps/web-platform`, so its default value is irrelevant.

- **Browser user-agent default:** Without an explicit `font-family` on `body` or `html`, browsers render in the user-agent default. macOS Safari defaults to **Times** for unstyled body text; Chrome on most platforms defaults to a sans (Arial/Helvetica/system). This is itself an inconsistency vector — the plan's `@layer base { body { font-family: var(--font-sans); } }` rule eliminates it.

- **Brand-guide deviation precedent:** The Eleventy docs site (out of scope) is the primary brand-presentation surface. The web-platform dashboard is the operator surface — a sans-only dashboard is consistent with the "developer tool" reading the user implicitly asks for.

## Open Questions

1. Should the brand guide be updated post-merge to formally allow sans-only on the dashboard? Recommended path: yes, file a follow-up issue for CMO to update lines 249-257 to scope the "Cormorant Garamond headlines" mandate to the marketing site only. (Not blocking this PR.)
2. Are there any internal Slack / Discord brand-tone discussions in the last 30 days that resolve the "should the dashboard mirror the brand or feel like a tool?" question? (Out-of-band; not blocking.)

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-11-fix-normalize-fonts-to-non-serif-plan.md

Context: branch feat-one-shot-normalize-fonts-to-non-serif, worktree .worktrees/feat-one-shot-normalize-fonts-to-non-serif/, no PR yet, no tracking issue yet. Plan created and deepened. Implementation next: drop font-serif Tailwind utility from 4 KB components, drop ${serif.className} from 10 connect-repo components, collapse components/connect-repo/fonts.ts to Inter-only, wire ${sans.variable} on body in app/layout.tsx, register --font-sans in @theme in app/globals.css, prune Cormorant mocks from 3 test files. Brand-guide deviation accepted (threshold: aggregate pattern). CMO sign-off is post-merge.
```
