---
title: "fix: loosen markdown spacing in shared documents (and KB viewer)"
type: bug-fix
issue: TBD
branch: feat-one-shot-shared-docs-markdown-spacing
created: 2026-05-04
deepened: 2026-05-04
requires_cpo_signoff: false
---

# fix: loosen markdown spacing in shared documents (and KB viewer)

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** Approach (Tailwind v4 cascade), Spacing changes (8pt-rhythm grounded values), Risks (v4 layer-order correction), Acceptance Criteria, Test Scenarios.
**Research sources used:** Context7 — `/tailwindlabs/tailwindcss.com` (cascade layers, `@utility` migration, `@layer` precedence), Context7 — `/remarkjs/react-markdown` (components prop / GFM table semantics), WebSearch (USWDS, Pimp my Type, modern web typography 2025-2026).

### Key Improvements

1. **Tailwind v4 cascade-order correction.** Original plan placed `.prose-kb` rules in `@layer components`. Tailwind v4's native cascade-layer order is `theme, base, components, utilities` — so utilities (e.g., `mb-3` on the renderer) WIN against `@layer components` declarations regardless of selector specificity. Corrected to **unlayered CSS rules** (declared after `@import "tailwindcss"`), which sit in the implicit highest-priority layer and beat any `@layer utilities` rule of equal or lower specificity. This is the single most load-bearing finding from deepen-plan; an uncorrected plan would ship a no-op CSS block.
2. **Spacing values aligned to 8pt-rhythm grid + WCAG/USWDS readability guidance.** Cell vertical padding lifted to ≥10px (≥0.625rem) — the threshold cited by USWDS and Pimp my Type for table-row legibility. Paragraph `mb` set to 16px (`mb-4`) — the median of "16-24px" cited as the readable paragraph rhythm for 16px body text with 1.6 line-height.
3. **Test strategy hardened.** jsdom does not compute layout; the new contract test asserts class presence + does NOT use the existing `vi.mock` substitutions. Added a "no-`prose-kb`-leak-into-chat" guard test.

### New Considerations Discovered

- React-markdown 9 `components` prop maps `table`/`th`/`td` independently when `remark-gfm` is present (confirmed). The renderer's `table` component already wraps in a `<div class="overflow-x-auto">` — descendant selectors must target both the outer wrapper margin and the inner table/cell padding without breaking the scroll wrapper.
- **No new Tailwind utility names introduced** — all values map to existing utilities (`mt-8`, `mb-4`, `my-6`, `space-y-2`, `px-4`, `py-2.5`). No `tailwind.config` change needed.
- **Telemetry impact:** `hr-weigh-every-decision-against-target-user-impact` PASSES (section present, threshold valid, no sensitive paths in Files to Edit) — no telemetry emitted.

## Overview

Shared-document pages (`/shared/[token]`) render markdown via `MarkdownRenderer` with very tight per-element margins. Headings, paragraphs, lists, and especially tables (cell padding `py-1.5`, table wrapper `mb-3`) lack breathing room — long-form documents read as a wall, and tables sit flush against surrounding paragraphs.

The fix is to introduce a **comfortable-density variant** opt-in via the existing `prose-kb` wrapper (currently a no-op CSS class). The shared-document page and the KB viewer already wrap `MarkdownRenderer` in `prose-kb`; the chat bubble does not. Defining `.prose-kb` once in `globals.css` with descendant selectors that override the base inline-class spacing gives shared docs and KB viewer airier rhythm without changing chat bubbles (where tight spacing is correct for short, conversational messages).

**Scope:** spacing only. No content/structure changes, no library swaps, no component renames.

## User-Brand Impact

- **If this lands broken, the user experiences:** shared documents render with broken layout (e.g., negative margins from a Tailwind typo, table column alignment lost, lists indenting wrong) on the public-facing `/shared/[token]` route — the surface every recipient sees first.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — pure presentation change, no auth/data/credential paths touched.
- **Brand-survival threshold:** none

Reason for `none`: spacing-only CSS change on already-public, already-rendered content. No sensitive paths (no `app/api/**`, no `middleware.ts`, no auth/data/payment surfaces) are modified.

## Research Reconciliation — Spec vs. Codebase

| Claim                                                           | Reality                                                                                                                                                    | Plan response                                                                                                                                |
|-----------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| "Shared docs use a markdown renderer."                          | `apps/web-platform/components/ui/markdown-renderer.tsx` (react-markdown + remark-gfm + rehype-highlight). Per-element margins are inline Tailwind classes. | Confirmed. Edit there OR layer overrides via wrapper class.                                                                                  |
| "`prose-kb` styles the doc."                                    | `prose-kb` appears at 2 call sites (shared page, KB viewer page) but has **no CSS rule** — `grep -rn "prose-kb" apps/web-platform/**/*.css` returns empty. | Use `prose-kb` as the opt-in hook for the new spacing — defining the class is the fix surface.                                               |
| "MarkdownRenderer is used only in shared docs."                 | Used in 4 places: `/shared/[token]/page.tsx`, `/dashboard/kb/[...path]/page.tsx`, `components/chat/message-bubble.tsx` (×3 callsites — user/assistant/tool). | Spacing change MUST be scoped via `prose-kb` so chat bubbles keep tight spacing. Chat bubbles are NOT wrapped in `prose-kb`.                 |
| "Tailwind v3 `@tailwindcss/typography` `prose` class is available." | `apps/web-platform` is on Tailwind v4 (`@import "tailwindcss"` in `globals.css`). The typography plugin is not installed, and Tailwind v4 uses CSS-first config — adding the plugin is a non-trivial dep bump. | Do NOT pull in `@tailwindcss/typography`. Define `.prose-kb` rules directly in `globals.css` `@layer components` — small, targeted, no new deps. |

## Approach

Introduce `.prose-kb` descendant rules in `apps/web-platform/app/globals.css` that override the renderer's per-element inline margins.

### Cascade strategy (Tailwind v4 — load-bearing)

**Do NOT use `@layer components`.** Tailwind v4 emits its cascade-layer declaration as `@layer theme, base, components, utilities` and emits utility classes (`mb-3`, `mt-4`, etc.) into `@layer utilities`. Per CSS cascade-layer ordering, later layers in the declaration list always win against earlier layers regardless of selector specificity. A rule `.prose-kb table { ... }` placed inside `@layer components` would be **silently overridden by every utility class on the renderer's elements** — producing a no-op fix that passes typecheck and lint but shows no visual change.

**Correct placement:** unlayered CSS rules (i.e., declared after `@import "tailwindcss";` but NOT inside any `@layer` block). Unlayered rules belong to the implicit topmost layer in the cascade and win against all named layers (including `utilities`). The `.prose-kb` descendant selectors (specificity 0,2,0) will then beat the renderer's single-class utility (specificity 0,1,0) by both layer order and specificity — defense in depth.

This is verified against Tailwind v4's documented v4 cascade emission (`@layer theme, base, components, utilities;` — Context7 source: `tailwindcss.com/blog/tailwindcss-v4`).

### Why not `@utility`?

Tailwind v4 introduces an `@utility` API (replacing `@layer components` for custom utilities). `@utility` is the right tool for atomic single-property classes that need to be variant-aware (`hover:`, `md:`, etc.). `.prose-kb` is none of those — it's a wrapper class that styles descendants, not a variant-aware atomic utility. Using `@utility` would force one declaration per descendant element and break the natural CSS-descendant-selector model. Plain unlayered rules are the right fit.

### Why not `prose` from `@tailwindcss/typography`?

(1) Plugin not installed; adding it for Tailwind v4 requires version-compatibility verification. (2) `prose` styles too much (link colors, code styling, list markers) — the chrome already overrides those, so `prose` would conflict with existing renderer classes and require `prose-invert`-then-override. (3) Bundle size grows ~10KB minified for a single page concern. Keep it tight: 8 unlayered rules in `globals.css`.

**Rejected alternatives** (recorded so deepen-plan and review do not rediscover):

**Rejected alternatives** (recorded so deepen-plan and review do not rediscover):

1. **Add a new `density="comfortable"` prop to `MarkdownRenderer`.** Adds prop surface, requires test updates, and forces every call site to opt in by name. The `prose-kb` wrapper already exists as the implicit "this is a long-form document" signal — promote it from no-op to load-bearing.
2. **Bump base inline margins inside `MarkdownRenderer`.** Affects chat bubbles (which intentionally use tight spacing for conversational rhythm). Two of the three chat callsites pass through `MarkdownRenderer` for assistant + tool output; spacing them airier breaks the bubble visual contract.
3. **Install `@tailwindcss/typography` and apply `prose prose-invert`.** Requires v4 plugin compatibility check, is over-scoped for the bug, and the dark-on-amber chrome already overrides most of what `prose` would set.

## Spacing changes (table form)

Per-element targets, current (inline class on `MarkdownRenderer`) → comfortable (overridden via `.prose-kb <selector>`). Values follow the 8pt-rhythm grid (4px/8px multiples), aligned with the existing renderer's Tailwind spacing scale; cell `py-2.5` (10px) lifts row legibility above the 8px floor cited by USWDS/Pimp my Type for table rows.

| Element        | Current (renderer)                                  | Comfortable (`.prose-kb <sel>`)                          | Computed (current → new)              | Why                                                                                  |
|----------------|------------------------------------------------------|-----------------------------------------------------------|----------------------------------------|--------------------------------------------------------------------------------------|
| `h1`           | `mt-4 mb-3`                                          | `mt-8 mb-4`                                              | mt 16→32px, mb 12→16px                | Section breaks need clearer hierarchy in a stand-alone document.                     |
| `h2`           | `mt-3 mb-2`                                          | `mt-7 mb-3`                                              | mt 12→28px, mb 8→12px                 | Same.                                                                                 |
| `h3`           | `mt-3 mb-2`                                          | `mt-6 mb-3`                                              | mt 12→24px, mb 8→12px                 | Same.                                                                                 |
| `p`            | `mb-2`                                               | `mb-4`                                                    | mb 8→16px                              | Median of "16-24px" cited as readable paragraph rhythm for 16px body + 1.6 lh.        |
| `ul`/`ol`      | `mb-2 ml-4 space-y-1`                                | `mb-4 ml-5 space-y-2`                                    | mb 8→16px, ml 16→20px, gap 4→8px      | Looser list items + slightly deeper indent.                                          |
| `table` wrap   | `mb-3` outer div                                     | `my-6` outer div                                          | mb 12px → my 24/24px                  | The headline cramped element — separate tables clearly from surrounding prose.       |
| `th`/`td`      | `px-3 py-1.5`                                        | `px-4 py-2.5`                                            | px 12→16px, py 6→10px                 | Cells get visible breathing room above the 8px legibility floor without spreadsheet-tall rows. |
| `pre`          | `mb-3`                                               | `my-5`                                                    | mb 12px → my 20/20px                  | Code blocks separated from prose top and bottom.                                     |
| `blockquote`   | `mb-2 pl-3`                                          | `my-5 pl-4`                                              | mb 8px → my 20/20px, pl 12→16px       | Same.                                                                                 |

The renderer's inline classes are the "compact default" used in chat. The `.prose-kb` overrides apply only when the wrapper is present.

### CSS implementation sketch (verbatim — to land in `apps/web-platform/app/globals.css`)

```css
/*
 * .prose-kb is the long-form-document spacing variant — opt-in via wrapper.
 * Used by /shared/[token] and /dashboard/kb/[...path]. Do NOT add to chat
 * bubbles (components/chat/message-bubble.tsx) — chat keeps the compact
 * defaults baked into MarkdownRenderer's inline Tailwind classes.
 *
 * Cascade note (Tailwind v4): these rules are intentionally UNLAYERED
 * (declared outside any @layer block). Tailwind v4 emits utilities into
 * @layer utilities, which beats @layer components by cascade-layer order.
 * Unlayered rules sit in the implicit topmost layer and beat all named
 * layers — that, plus the 0,2,0 descendant specificity vs the utility's
 * 0,1,0, gives defense-in-depth. If you move these into @layer components
 * the fix becomes a no-op.
 */
.prose-kb h1 { margin-top: 2rem; margin-bottom: 1rem; }
.prose-kb h2 { margin-top: 1.75rem; margin-bottom: 0.75rem; }
.prose-kb h3 { margin-top: 1.5rem; margin-bottom: 0.75rem; }
.prose-kb p { margin-bottom: 1rem; }
.prose-kb ul,
.prose-kb ol { margin-bottom: 1rem; margin-left: 1.25rem; }
.prose-kb li + li { margin-top: 0.5rem; }
.prose-kb > div:has(> table),         /* outer wrapper from MarkdownRenderer */
.prose-kb table { margin-top: 1.5rem; margin-bottom: 1.5rem; }
.prose-kb th,
.prose-kb td { padding-left: 1rem; padding-right: 1rem; padding-top: 0.625rem; padding-bottom: 0.625rem; }
.prose-kb pre { margin-top: 1.25rem; margin-bottom: 1.25rem; }
.prose-kb blockquote { margin-top: 1.25rem; margin-bottom: 1.25rem; padding-left: 1rem; }
```

Alternative implementation if `:has()` browser-support is a concern (verify Baseline coverage at deepen review): replace `.prose-kb > div:has(> table)` with a class on the wrapper div via the renderer (would change `markdown-renderer.tsx`). `:has()` is Baseline 2023 / >93% global support per caniuse — acceptable for the app's browser matrix; document the choice.

## Files to Edit

- `apps/web-platform/app/globals.css` — add `.prose-kb` UNLAYERED descendant rules (NOT inside `@layer components`) per the CSS sketch above. Place after `@import "tailwindcss";` and the `@layer base` and `@layer components` blocks, at the bottom of the file, so they sit in the implicit topmost cascade layer.
- `apps/web-platform/test/markdown-renderer.test.tsx` — add a regression test that the wrapper-less render keeps tight defaults (chat-bubble path), so a future "let me just bump the base class" change is caught.

## Files to Create

- `apps/web-platform/test/prose-kb-spacing.test.tsx` — DOM-level spacing assertions: render `<div className="prose-kb"><MarkdownRenderer content={fixture} /></div>`, query for `table`, `h2`, `p`, `td`, and assert via `getComputedStyle` (or class presence + a CSS-loaded fixture) that the comfortable-density rules apply. **Note:** jsdom does NOT load globals.css; the test instead asserts that (a) the `.prose-kb` ancestor class is present, and (b) a manual style-injection helper applies the expected rules — i.e., the test verifies the wrapper-class contract, not jsdom-rendered geometry. Cite `2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md` for jsdom layout trap.

## Files to Edit (no-change verification)

- `apps/web-platform/components/chat/message-bubble.tsx` — verified: NOT wrapped in `prose-kb`. Chat-bubble spacing is unaffected. (No edit, but listed so deepen-plan does not re-investigate.)
- `apps/web-platform/components/ui/markdown-renderer.tsx` — NO edits. The base inline classes remain the "tight/chat" default.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.prose-kb` UNLAYERED rules defined in `apps/web-platform/app/globals.css` (NOT inside `@layer components` — see Approach §Cascade strategy), covering h1/h2/h3/p/ul/ol/li/table-wrapper/th/td/pre/blockquote per the spacing table and CSS sketch.
- [ ] DevTools cascade verification on a dev build: open `/shared/<token>` for a markdown doc, inspect a `td` element, confirm `.prose-kb td { padding-top: 0.625rem; ... }` is the winning rule (no struck-through utility overriding it). Capture the DevTools screenshot in the PR description.
- [ ] Visual before/after on `/shared/<token>` for a fixture markdown doc containing: a table (≥3 cols, ≥3 rows), an h1 + h2 + h3, two adjacent paragraphs, an unordered list, an ordered list, a code block, a blockquote. Tables show ≥16px vertical separation from preceding/following block; cells show ≥10px vertical padding; paragraph-to-paragraph rhythm is ~16px.
- [ ] No spacing change to chat bubbles. Visual-spot-check `/dashboard/chat` with an assistant message containing a table — table renders at the **current** tight spacing (tables in chat already wrap in `overflow-x-auto`, but the wrapper is NOT inside `prose-kb`).
- [x] `bun test apps/web-platform/test/markdown-renderer.test.tsx` passes (existing tests + the new wrapper-less-default regression test).
- [x] `bun test apps/web-platform/test/prose-kb-spacing.test.tsx` passes (new contract test — class-presence + `:has(prose-kb)` ancestor + a guard test that `components/chat/message-bubble.tsx` does NOT contain the string `prose-kb`).
- [x] `bun run typecheck` and `bun run lint` clean for `apps/web-platform`.
- [ ] PR body includes `Closes #<N>` for the issue filed at plan time.
- [ ] Browserslist check: confirm `:has()` selector is supported by the app's target browsers — read `apps/web-platform/package.json` `browserslist` field (or default Next.js targets if not set). If older Safari/Edge support is required, switch to the renderer-side data-attribute fallback documented in Risks.

### Post-merge (operator)

- [ ] After Vercel deploy, open a real shared-doc URL and confirm spacing on production. (Vercel auto-deploys; no operator action beyond verification.)

## Test Scenarios

1. **Shared doc with table — wrapper-class contract.** Render `<article className="prose-kb"><MarkdownRenderer content="| A | B |\n|---|---|\n| 1 | 2 |\nbefore\n\n# Heading\n\npara" /></article>`. Assert: (a) `article` has `prose-kb` class, (b) descendant `table` and `td` elements exist, (c) the rendered DOM tree is the structure the CSS rules target (i.e., `.prose-kb td` matches via querySelectorAll, proving the selectors will fire when the stylesheet loads in a browser).
2. **Chat bubble keeps tight spacing.** Render `<MarkdownRenderer content="| A | B |\n|---|---|\n| 1 | 2 |" />` WITHOUT a `prose-kb` wrapper. Assert `.prose-kb table` selector matches NOTHING in the rendered tree (querySelectorAll returns empty). The renderer's inline `mb-3` class on the table wrapper remains the only spacing rule.
3. **Heading rhythm — DOM contract.** Markdown with three sequential `## h2` blocks under `prose-kb`. Assert all three h2 elements are descendants of `.prose-kb` (querySelectorAll(`.prose-kb h2`) returns 3 elements).
4. **List item spacing — DOM contract.** `- a\n- b\n- c` under `prose-kb`. Assert the rendered `<ul>` is matched by `.prose-kb ul`, and contains 3 `<li>` children.
5. **No regression in code-block wrap.** `<MarkdownRenderer content="```ts\nconst x = 1;\n```" wrapCode />` retains `whitespace-pre-wrap` on the `pre` (existing assertion). Adding a `prose-kb` wrapper does not remove the `whitespace-pre-wrap` class — wrap behavior is independent of spacing.
6. **`prose-kb` does not leak into chat bubbles.** Static-source-grep test: read `apps/web-platform/components/chat/message-bubble.tsx` as a string and assert it does NOT contain `"prose-kb"`. This is the runtime backstop for the CSS-rule-head code comment that says "do not add to chat bubbles." Failure mode this catches: a future contributor wraps `MarkdownRenderer` inside a `prose-kb`-classed div in chat, ballooning chat-message spacing.

**Note on jsdom + CSS:** jsdom does NOT load `globals.css` and does NOT compute `getComputedStyle` against external stylesheets. The contract tests above assert (a) selector targets exist in the rendered DOM and (b) wrapper-class presence — proving that when the real browser loads `globals.css`, the rules will apply. The actual computed-margin value is verified in the Acceptance Criteria DevTools-cascade screenshot, not in unit tests.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` and grep for `markdown-renderer.tsx`, `prose-kb`, `globals.css` against open issues. To be run by deepen-plan / pre-implement:

- [ ] Run `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`
- [ ] `jq -r --arg path "components/ui/markdown-renderer.tsx" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`
- [ ] `jq -r --arg path "prose-kb" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`
- [ ] `jq -r --arg path "app/globals.css" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`

If matches: fold-in / acknowledge / defer per plan-skill rules. If no matches: record `None` in deepen-plan output.

## Risks

- **Tailwind v4 cascade-layer order — RESOLVED in deepen-plan.** Original plan put rules in `@layer components`, which loses to `@layer utilities` (where renderer's `mb-3` etc. live) regardless of specificity. **Resolution:** unlayered rules — see Approach §Cascade strategy. Verify in DevTools on dev build by inspecting a `.prose-kb table` element: the unlayered `.prose-kb table { margin-top: 1.5rem; }` rule MUST appear with no struck-through `mb-3` overriding it. If utilities still win after the change, the rules were inadvertently placed inside an `@layer` block — re-check `globals.css`.
- **`:has()` selector dependency.** The CSS sketch uses `.prose-kb > div:has(> table)` to target the renderer's wrapper-div around tables without changing the renderer. `:has()` is Baseline 2023 / >93% global support (caniuse) — acceptable for this app. If the app explicitly supports Safari <15.4 / older Edge, fall back to changing `markdown-renderer.tsx` to add a `data-prose-table` attr or class on the wrapper div, then target via attribute selector. Verify the app's browserslist / package.json `browserslist` field at implementation time.
- **`MarkdownRenderer` is co-mounted with chat bubbles.** Confirmed via grep: chat bubbles are NOT wrapped in `prose-kb`, so the descendant-selector approach naturally scopes the change. Acceptance criterion #3 explicitly checks this.
- **Existing test mocks substitute MarkdownRenderer.** Five test files (`shared-page-ui.test.tsx`, `shared-page-head-first.test.tsx`, `kb-page-routing.test.tsx`, `shared-image-a11y.test.tsx`, `shared-token-content-changed-ui.test.tsx`) `vi.mock` the renderer to a plain `<div>`. Spacing tests must NOT use these mocks — they must import the real renderer.
- **Visual regression coverage gap.** No automated screenshot diff currently runs on `/shared/[token]`. The work phase MUST capture a Playwright screenshot pair (before/after) on a representative shared-doc fixture (with table + headings + paragraph + list + code block) and attach to the PR description. If Playwright MCP is unavailable in CI, the screenshot is captured locally and attached manually.
- **`prose-kb` already exists as a wrapper at 2 sites.** Promoting it from no-op to load-bearing means any future call-site that adds the class WILL inherit comfortable spacing. Documented in the CSS rule-head code comment (see CSS sketch). The "no-prose-kb-leak-into-chat" guard test (Test Scenario #6) is the runtime backstop.
- **Cell-padding override interacts with `border-collapse`.** The renderer's table uses `border-collapse: border-collapse` (default Tailwind `border-collapse`). Increased cell padding does not interact pathologically with `border-collapse` — borders remain shared, padding grows symmetrically. Verified mentally; double-check in DevTools.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above.
- jsdom does not compute layout, so spacing tests can only assert class/wrapper presence and (optionally) inject a fragment of `globals.css` via `<style>` to verify rule application. Real-pixel visual verification is the screenshot in Acceptance Criteria #2.
- If a future contributor moves chat bubbles into `prose-kb` (e.g., to "match the docs feel"), spacing in chat will balloon. The CSS-rule-head code comment is the only gate; consider a unit test that asserts `chat/message-bubble.tsx` does NOT contain the string `prose-kb`.

## Hypotheses

N/A — feature description does not match SSH/network/handshake/timeout patterns.

## Domain Review

**Domains relevant:** Product (advisory)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (advisory tier in pipeline mode)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

This plan modifies an existing user-facing surface (the shared-document render) without introducing new pages, flows, or components. Per the plan-skill mechanical-escalation rule, no new file matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` is created — the only "new" file is a test (`test/prose-kb-spacing.test.tsx`), which does not trigger BLOCKING. Tier resolves to **advisory**; in pipeline mode, advisory auto-accepts without invoking ux-design-lead or copywriter. Visual sign-off via screenshot is captured in Acceptance Criteria #2.

No domain leader recommended a copywriter — there is no copy change in this plan.

## Research Insights

### Codebase

- `MarkdownRenderer` source: `apps/web-platform/components/ui/markdown-renderer.tsx` (130 lines).
- Call sites: `app/shared/[token]/page.tsx:145`, `app/(dashboard)/dashboard/kb/[...path]/page.tsx:155`, `components/chat/message-bubble.tsx:195,263,266`.
- `prose-kb` definition: NONE — `grep -rn "prose-kb" apps/web-platform --include="*.css"` returns empty. Currently a load-free marker class. Used at exactly 2 sites: `app/shared/[token]/page.tsx:144` and `app/(dashboard)/dashboard/kb/[...path]/page.tsx:154`.
- Tailwind version: v4 (`@import "tailwindcss"` in `apps/web-platform/app/globals.css`).
- No `@tailwindcss/typography` plugin installed (verified by absence in `apps/web-platform/package.json` dependencies).
- Existing CSS layer pattern: `@layer base { ... } @layer components { ... }` already used for `.safe-top`, `.safe-bottom`, `.message-bubble-active`. Note: `.prose-kb` deliberately does NOT slot into `@layer components` — see Approach §Cascade strategy.
- Existing test fixture pattern: `vi.mock("@/components/ui/markdown-renderer", ...)` is used in 5 files when the test does not care about render output. The new spacing tests deliberately import the real component.

### Tailwind v4 cascade behavior (Context7-verified)

- **Layer declaration order:** Tailwind v4 emits `@layer theme, base, components, utilities;` — meaning utilities is the LAST named layer and wins against earlier layers regardless of selector specificity.
- **`@layer components` is being phased out for utilities** in favor of `@utility`. Custom-component classes that need to coexist with utilities should now either use `@utility` (for atomic, variant-aware utilities) or be declared **unlayered** (for descendant-selector-style rules like `.prose-kb table`).
- **`@apply` inside unlayered rules** is supported in v4 — useful if the implementation prefers `@apply mt-8 mb-4` over hand-written `margin-top` / `margin-bottom` for tighter alignment with the design system.

### Typography / spacing references

- USWDS Typography: 8pt rhythm grid for spacing; ≥1.4 line-height for body text.
- Pimp my Type "Ideal line length & line height": paragraph margin-bottom should exceed line-height gap; for 16px body + 1.6lh, 16-24px paragraph spacing is the readable range.
- Modern typography 2025-2026 guides converge on: 8pt-multiples, paragraph rhythm 16-24px, table-cell vertical padding ≥10px for legibility, table top/bottom margins 24-32px to separate from prose.

## References

- Tailwind v4 cascade layers and `@utility`: `https://github.com/tailwindlabs/tailwindcss.com/blob/main/src/docs/upgrade-guide.mdx` (Context7 source).
- Tailwind v4 modern CSS features (cascade layers): `https://github.com/tailwindlabs/tailwindcss.com/blob/main/src/blog/tailwindcss-v4/index.mdx`.
- react-markdown components prop + remark-gfm tables: `https://github.com/remarkjs/react-markdown/blob/main/readme.md` (Context7 source).
- USWDS Typography: `https://designsystem.digital.gov/components/typography/`.
- Pimp my Type — line length & line height: `https://pimpmytype.com/line-length-line-height/`.
- MDN `:has()` selector + Baseline status: caniuse `:has()` — Baseline 2023.
