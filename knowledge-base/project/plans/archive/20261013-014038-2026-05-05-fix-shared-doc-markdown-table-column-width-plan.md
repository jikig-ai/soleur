---
type: bug-fix
classification: ui-readability
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** 5 (Research Reconciliation, Acceptance Criteria, Implementation Phases, Risks, Test Strategy)
**Research used:** local codebase grep, Tailwind v4 CSS verification, prior PR #2280 (chat markdown overflow), learning `2026-04-15-flex-column-width-and-markdown-overflow-2229.md`, existing test file `apps/web-platform/test/markdown-renderer.test.tsx`.

### Key Improvements

1. **Verified Tailwind v4.1 supports `w-max`, `min-w-[Xch]`, `max-w-[Xch]` natively** — no plugin/version risk. Tailwind v4 ships with arbitrary-value support and `width: max-content` utility.
2. **Found existing test file `apps/web-platform/test/markdown-renderer.test.tsx`** (not noticed in initial plan) — already has a table assertion at the wrapper level. New test cases append here instead of creating a parallel file. Single source of truth for renderer tests.
3. **Enumerated all 4 MarkdownRenderer call sites** — `app/shared/[token]/page.tsx`, `app/(dashboard)/dashboard/kb/[...path]/page.tsx`, `components/chat/message-bubble.tsx` (3 invocations, two with `wrapCode`). The fix at the renderer touches all four; sidebar-style narrow-column callers require explicit regression check.
4. **Identified prior-art pattern from PR #2280 / learning #2229** — same renderer file already uses the `min-w-0 [overflow-wrap:anywhere]` discipline at the wrapper. Extending that discipline to tables follows the established convention.
5. **Refined the table CSS approach** based on Tailwind v4 + react-markdown 10.x rendering: `w-auto` (not `w-max`) is sufficient + closer to the auto-layout default; `w-max` risks unnecessary expansion. Using `w-auto` lets the browser's table auto-layout compute natural column widths, contained by `overflow-x-auto`.

### New Considerations Discovered

- The renderer is consumed by **chat message bubbles** with `wrapCode={true}` for the sidebar variant. Tables in chat bubbles will now scroll horizontally inside the bubble — this is correct behavior but worth a sidebar regression screenshot.
- `react-markdown@10.1.0` passes through table elements unchanged; no parser-level table-cell-content quirks to handle.
- The dashboard KB viewer (`/dashboard/kb/<path>`) has the same wrapper width (`max-w-3xl`) and shares the renderer — fix lands on both surfaces in one change.
- `tailwindcss@^4.1.0` is configured via `@import "tailwindcss"` in `globals.css` — v4's JIT engine generates arbitrary values like `min-w-[8ch]` on first use, no config changes required.

# fix(shared-doc): widen markdown table columns so content is readable

## Overview

On the public shared-document page (`/shared/[token]`), markdown content rendered by `MarkdownRenderer` is constrained to `max-w-3xl` (768px) by the page wrapper. Inside that column, GFM tables are rendered by the markdown component map as `<div class="mb-3 overflow-x-auto"><table class="w-full">…</table></div>`. The `w-full` table forces the browser's auto layout to fit every column inside 768px regardless of cell content, so columns with prose, URLs, or long identifiers wrap to extreme narrowness (often 1-3 chars per line). The horizontal-scroll wrapper exists but never engages because `w-full` collapses the table to the wrapper's width — the user sees a cramped table, not a scrollable one.

Fix: at the table renderer, switch from `w-full` (auto-fit-to-parent) to `w-auto` so the browser's table auto-layout sizes columns from cell content and the table grows only as much as its content requires; keep `overflow-x-auto` on the wrapper so overflow becomes scrollable rather than truncated. Add `whitespace-nowrap` on `<th>` (header cells should never wrap — the column-name is the primary identifier). Leave `<td>` wrapping enabled so multi-sentence cells still flow, but constrain them with a `min-w-[8ch]`/`max-w-[40ch]` band so single-word cells don't collapse and prose cells don't blow out. Net result: columns size to their content, the wrapper scrolls if the total exceeds 768px, and headers stay readable. (Initial draft proposed `min-w-full w-max`; deepen-plan reconciled to `w-auto` — see Phase 2 Decision below.)

This is a 6-line CSS-classes-only change inside `apps/web-platform/components/ui/markdown-renderer.tsx`. No API, no data, no auth surface.

## Research Reconciliation — Spec vs. Codebase

| Claim in feature description | Codebase reality | Plan response |
|---|---|---|
| "Content is too tight" on shared document page | Confirmed: `app/shared/[token]/page.tsx:98` wraps content in `mx-auto max-w-3xl` (768px); the same wrapper is used by the dashboard KB viewer (`app/(dashboard)/dashboard/kb/[...path]/page.tsx:153`). | Fix at the renderer (shared by both surfaces) — both views benefit from the same change. |
| "The column in a table shows not enough characters in width" | Confirmed: `markdown-renderer.tsx:42-54` renders tables with `<table className="w-full">` inside an `overflow-x-auto` div. `w-full` forces auto-layout to fit the 768px column, collapsing column widths. | Switch table to `min-w-full w-max`; add per-cell width band; keep wrapper scrollable. |
| Issue is shared-doc-specific | Renderer is shared by `shared/[token]/page.tsx` AND `dashboard/kb/[...path]/page.tsx` AND `kb-chat-sidebar` (the latter passes `wrapCode`). | Fix at the renderer applies everywhere; sidebar variant is the narrowest column (380px) and benefits most. Verify sidebar still degrades gracefully (scroll vs. cram). |
| `prose-kb` class adds typography | `prose-kb` is **not defined** anywhere in `apps/web-platform/app/globals.css` or any other CSS file. It's a vestigial className without rules. | Out of scope for this PR — note in Risks; no behavior change from leaving it. |

## User-Brand Impact

**If this lands broken, the user experiences:** A regression in the markdown table rendering (columns overflow the page horizontally without a scroll wrapper, or headers wrap mid-word) on a public-facing share link — the first surface a recipient sees when a Soleur user shares a document with them.

**If this leaks, the user's data is exposed via:** N/A — this is presentation-only on already-public content. No data exposure vector. The change does not alter what is rendered, only the width of cells.

**Brand-survival threshold:** none — UI readability change on already-public content with no auth or data implications.

Per `plugins/soleur/skills/preflight/SKILL.md` Check 6 sensitive-path regex, `apps/web-platform/components/ui/**` and `apps/web-platform/app/shared/**` are NOT in the sensitive-path set (no `auth/`, `api/`, `server/`, `lib/byok/`, `lib/crypto/`, etc.), so the `threshold: none` resolution requires no scope-out bullet.

## Acceptance Criteria

### Pre-merge (PR)

- [x] On `/shared/<token>` rendering a markdown document containing a GFM table with 4+ columns and prose cells (~30 chars), each header cell renders on a single line (`whitespace-nowrap`) and each data cell shows ≥8 chars before wrapping.
- [ ] When the table's natural width exceeds 768px, the wrapper `<div>` scrolls horizontally (mouse-wheel/trackpad swipe + visible scrollbar on desktop, touch-swipe on mobile). The page itself does NOT scroll horizontally. *(QA phase)*
- [ ] On the same page, a table that fits in 768px renders at its natural width (no forced fill). Verify with a 2-column short-cell fixture. *(QA phase)*
- [ ] On the kb-chat sidebar (380px column), the same renderer's table either scrolls horizontally or wraps to readable widths — verify no layout breakage on the sidebar surface (regression check). *(QA phase)*
- [ ] On the dashboard KB viewer (`/dashboard/kb/<path>`), the same fix applies and renders identically to the shared page (renderer is shared). *(QA phase)*
- [x] `tsc --noEmit` clean, `bun test` clean (no new test failures); existing `apps/web-platform/test/shared-page-ui.test.tsx` still passes unchanged.
- [ ] PR body uses `Closes #<N>` (will need to file the issue or `Ref` if descriptive only). *(ship phase)*

### Post-merge (operator)

- [ ] None — pure UI change, no infra/migrations/secrets.

## Implementation Phases

### Phase 1 — Test (RED)

- **File:** `apps/web-platform/test/markdown-renderer.test.tsx` (EDIT — append, do not create new file)
- An existing `describe("MarkdownRenderer — chat markdown overflow (issue #2229)", …)` block already exists with a table assertion (`it("retains overflow-x-auto for GFM tables")`) — append a new `describe` block below it: `describe("MarkdownRenderer — table column widths (this PR)", …)`.
- New test cases:
  1. **Header cells must not wrap.** Render a 3-column table where one header is a single long word ("ConfigurationKey"); assert every `<th>` className includes `whitespace-nowrap`.
  2. **Data cells have a width band.** Render any table; assert every `<td>` className includes `min-w-[8ch]` and `max-w-[40ch]`.
  3. **Table uses auto layout, not full-width fill.** Assert the `<table>` className includes `w-auto` (or `min-w-full` — pick one explicitly per Phase 2 below) and does NOT include `w-full` (the regression guard).
  4. **Wrapper still scrolls.** Existing assertion `div.overflow-x-auto` must still pass — keep the existing test untouched and let it serve as the wrapper-scrollable invariant.
- All three new assertions fail against the current `w-full`-only `<table>` and bare `<th>`/`<td>`.

### Phase 2 — Implementation (GREEN)

- **File:** `apps/web-platform/components/ui/markdown-renderer.tsx` (edit)

**Decision: use `w-auto` (not `w-max`).** Browser table auto-layout computes natural column widths from cell content. `w-auto` is the non-fighting default — `w-max` (`width: max-content`) would force the table to its widest possible width, which can over-expand for tables that would naturally fit. Since the wrapper has `overflow-x-auto`, auto-layout handles both narrow-fits-naturally and wide-overflows-scrollable cases correctly. Drop `min-w-full` to avoid forcing a stretch on narrow tables — let them render at natural width.

- Modify `table` component map (lines 42-46):
  ```tsx
  table: ({ children }) => (
    <div className="mb-3 overflow-x-auto">
      <table className="w-auto border-collapse text-sm">{children}</table>
    </div>
  ),
  ```
- Modify `th` component map (lines 47-51) — add `whitespace-nowrap`:
  ```tsx
  th: ({ children }) => (
    <th className="whitespace-nowrap border border-neutral-700 bg-neutral-800/50 px-3 py-1.5 text-left font-semibold text-neutral-200">
      {children}
    </th>
  ),
  ```
- Modify `td` component map (lines 52-54) — add a width band so cells don't collapse to 1ch and don't blow out:
  ```tsx
  td: ({ children }) => (
    <td className="min-w-[8ch] max-w-[40ch] border border-neutral-700 px-3 py-1.5 align-top text-neutral-300">{children}</td>
  ),
  ```
  - `align-top` added because cells with prose vs. cells with single tokens otherwise vertical-center differently when row heights diverge — top-align reads cleaner in tables of mixed content.
- Verify Phase 1 tests now pass.

### Phase 3 — Manual visual QA

- Render a fixture markdown document with:
  - 2-col short table → renders at natural width, no forced fill.
  - 4-col mixed-content table → headers single-line, cells readable, wrapper scrolls when total > 768px.
  - 8-col wide table → wrapper scrolls horizontally, page does not.
- Surfaces to check:
  - `/shared/<token>` (primary surface from feature description).
  - `/dashboard/kb/<path>` (shared renderer).
  - kb-chat sidebar at 380px (narrow-column regression check).
- Capture before/after screenshots of the 4-col case for the PR description.

## Files to Edit

- `apps/web-platform/components/ui/markdown-renderer.tsx` — table/th/td className updates (Phase 2).
- `apps/web-platform/test/markdown-renderer.test.tsx` — append new `describe` block with table-width assertions (Phase 1).

## Files to Create

- None. (Initial plan proposed a new test file; deepen-plan discovered the existing renderer-test file `apps/web-platform/test/markdown-renderer.test.tsx` and consolidates there. Single source of truth for renderer test invariants.)

## Test Strategy

- **Framework:** Vitest + `@testing-library/react`. Verified from `apps/web-platform/package.json`:
  - `"test": "vitest"` (script)
  - `"vitest": "^3.1.0"` (devDependency)
  - Existing `markdown-renderer.test.tsx` uses `import { describe, it, expect } from "vitest"` and `import { render } from "@testing-library/react"` — follow the same pattern.
- **Verification commands:**
  - Single-file during GREEN: `cd apps/web-platform && bun run test -- test/markdown-renderer.test.tsx`
  - Full suite before PR: `cd apps/web-platform && bun run test`
- **Regression coverage:**
  - Existing `markdown-renderer.test.tsx` tests stay untouched and must pass (esp. the `overflow-x-auto for GFM tables` assertion at line ~28-32 — it's the wrapper invariant).
  - Existing `shared-page-ui.test.tsx`, `shared-page-head-first.test.tsx`, `shared-token-content-changed-ui.test.tsx` — all page-level tests; they don't touch table cell widths and should pass unchanged.
- **Why tests asserting className strings are sufficient:** Tailwind classes are static literals in JSX. JSDOM renders the HTML but doesn't compute layout — so we cannot assert on actual computed widths in unit tests. The class assertion + Phase 3 visual QA combine to give full confidence: unit-test guarantees the right classes ship, manual QA guarantees Tailwind v4 generates the expected CSS for them. This matches the existing test pattern (`overflow-x-auto`, `min-w-0`, `[overflow-wrap:anywhere]` are all string-asserted).

## Open Code-Review Overlap

None. (Verified: `gh issue list --label code-review --state open --json number,title,body --limit 200` returned no matches against `markdown-renderer.tsx` or `app/shared/[token]/page.tsx`.)

## Domain Review

**Domains relevant:** none (UI readability fix; no data/auth/payments/infra implications).

No cross-domain implications detected — pure presentation-layer CSS-classes change inside an existing component used by an already-public page.

## Risks

- **`min-w-[8ch]` × N columns can exceed 768px even for short cells.** This is the desired behavior (the table scrolls horizontally inside the wrapper rather than truncating), but verify in Phase 3 that wrapper scrolling does not bleed onto the page. The page wrapper at `app/shared/[token]/page.tsx:98` is `mx-auto max-w-3xl` with no `overflow-hidden` — relying on the inner `overflow-x-auto` to contain the scroll. If the inner wrapper fails to contain (e.g., a parent transform), the page itself would scroll. Mitigation: confirm `overflow-x-auto` engages on the inner div in Phase 3.
- **Chat sidebar regression (`message-bubble.tsx`).** `MarkdownRenderer` is invoked from chat message bubbles at three call sites in `apps/web-platform/components/chat/message-bubble.tsx` (lines 195, 263, 266), all with `wrapCode={true}` for the sidebar variant. The new table CSS will cause tables in chat bubbles to scroll horizontally inside the bubble — this is correct behavior, but verify in Phase 3 that the bubble's `min-w-0` flex container correctly contains the scroll (it does, per learning #2229 — but a screenshot regression check is cheap insurance). If the bubble overflows, gate the table widening behind a new `wrapTable` prop (mirror of `wrapCode`) and have the sidebar caller opt out — but this is unlikely needed because the existing PR #2280 work already established `min-w-0` containment on the bubble.
- **`prose-kb` className is undefined CSS — confirmed.** Verified via `grep -rn "prose-kb" apps/web-platform/ --include="*.css"`: zero hits. The `prose-kb` className on `app/shared/[token]/page.tsx:144` and `app/(dashboard)/dashboard/kb/[...path]/page.tsx:154` is dead — likely vestigial from a removed `@tailwindcss/typography` dependency. Out of scope for this PR; **file as a tracking issue post-merge** (`chore: remove or define prose-kb className`). This is the right disposition because removing it could mask a future intentional `prose-kb` definition; either define rules or remove the className, but as a separate decision.
- **Tailwind v4.1 — `w-auto` and arbitrary values verified.** Confirmed `tailwindcss@^4.1.0` in `apps/web-platform/package.json`, configured via `@import "tailwindcss"` (v4 syntax) in `globals.css`. Tailwind v4 ships `w-auto` (`width: auto`), `w-max` (`width: max-content`), and arbitrary-value support (`min-w-[8ch]`, `max-w-[40ch]`) in the core utility set with no plugin required. The JIT engine generates class CSS on first use — no config or content-glob updates needed.
- **`max-w-[40ch]` may produce too-narrow cells for very long URLs.** A URL like `https://example.com/some/very/long/path?query=value` exceeds 40 characters and will wrap mid-string. Acceptable per the existing `[overflow-wrap:anywhere]` discipline at the renderer wrapper (line 115). Alternative: drop `max-w-[40ch]` and let cells grow unbounded, relying entirely on wrapper-scroll for tables and content wrapping for prose paragraphs. Reviewer call: keep the 40ch cap (current plan) for prose readability, or remove it (simpler, lets the browser decide). Default to keeping it; can be removed at review-time if reviewers prefer simpler.
- **react-markdown 10.x compatibility.** Verified `"react-markdown": "^10.1.0"` in package.json. v10 passes `<table>`/`<th>`/`<td>` through to the components map unchanged — no parser-level table-cell-content quirks affect this fix.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none` with reason — fill in the actual threshold language inline if any reviewer disputes "none" classification (e.g., if shared-doc rendering is upstream of brand-credibility signals).
- When widening table classes, do NOT switch to `table-fixed` — that re-introduces the original cramming bug under a different class name. The intent here is auto-layout that grows with content, contained by an overflow-scroll wrapper.
- `whitespace-nowrap` on `<th>` is intentional: the column header is the primary identifier of a column. If a header is long enough to push the table beyond the page, the wrapper scrolls — better than wrapping the header to 3 chars/line and forcing the user to mentally reassemble the column name.
- Do not add `prose` (`@tailwindcss/typography`) plugin to fix the empty `prose-kb` class as part of this PR — that's a much wider design decision (typography defaults across the whole shared-doc surface) and should be brainstormed separately.

## Out of Scope

- Defining `prose-kb` CSS rules (typography overhaul; separate brainstorm).
- Changing the page-level `max-w-3xl` to a wider container (would affect non-table content layout; needs CMO/CPO design review for shared-doc reading width).
- PDF/image preview surfaces — they don't render markdown.
- Server-side markdown rendering changes — `MarkdownRenderer` is client-only via `"use client"`.

## Research Insights

### Best Practices (HTML Table Auto-Layout)

- **`table-layout: auto` (the default) sizes columns from cell content.** In a wrapper that allows overflow, this gives the most natural reading experience — wide tables scroll, narrow tables don't stretch. Forcing `width: 100%` (`w-full`) on the table while keeping `auto` layout is the original bug class — the browser cannot honor "be 100% wide" and "size columns to content" simultaneously without compressing.
- **`table-layout: fixed` is the wrong fix here.** It would force every column to equal width, which is even worse than the current bug for tables with mixed content (a 1-char ID column + a 200-char prose column would each get 50%).
- **`whitespace-nowrap` on `<th>` is the conventional choice.** Almost every documentation site (Stripe, Tailwind, Vercel docs) uses non-wrapping headers — column names are identifiers, and a wrapped column name is harder to read than a horizontally-scrolled table.

### Performance Considerations

- **No re-render risk.** Classes are static literals in the components map; the `useMemo` already in place on `buildComponents` prevents object identity churn. The change is CSS-only at runtime.
- **No layout-thrash risk.** `table-layout: auto` is the browser's native fast path. `min-w-[8ch]` / `max-w-[40ch]` are absolute constraints (no JS), evaluated once during layout.

### Implementation Details (Final Code)

The complete diff applied in Phase 2:

```tsx
// apps/web-platform/components/ui/markdown-renderer.tsx (lines 42-54)

table: ({ children }) => (
  <div className="mb-3 overflow-x-auto">
    <table className="w-auto border-collapse text-sm">{children}</table>
  </div>
),
th: ({ children }) => (
  <th className="whitespace-nowrap border border-neutral-700 bg-neutral-800/50 px-3 py-1.5 text-left font-semibold text-neutral-200">
    {children}
  </th>
),
td: ({ children }) => (
  <td className="min-w-[8ch] max-w-[40ch] border border-neutral-700 px-3 py-1.5 align-top text-neutral-300">{children}</td>
),
```

Three-line CSS-classes change. No imports added, no new files, no API changes.

### Edge Cases

- **Empty cells.** GFM emits `<td></td>` for empty cells; `min-w-[8ch]` keeps the column visible (no zero-width column). Verified: the current rendering also handles this fine; the `min-w-[8ch]` only improves it.
- **Single-column tables.** `w-auto` will render at natural content width — the table will not stretch to wrapper width, which is the correct behavior (no awkward huge whitespace).
- **Tables nested in blockquotes/lists.** The renderer's component map applies regardless of nesting; the wrapper `overflow-x-auto` lives inside the blockquote/list and scrolls correctly.
- **Right-to-left content.** Tailwind's `text-left` on `<th>` is hard-coded; not affected by this PR. RTL is a separate cross-cutting concern.

### Cross-References from Prior Work

- **PR #2280 / Issue #2229 (`fix(ui): stabilize command-center row width and chat markdown overflow`)** — established the pattern of width-discipline at the `MarkdownRenderer` wrapper (`min-w-0 [overflow-wrap:anywhere]` at line 115). This PR extends the same pattern to the table sub-tree. Same author convention, same testing pattern.
- **Learning `knowledge-base/project/learnings/ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md`** — documents the `min-w-0` flexbox + `[overflow-wrap:anywhere]` recipe. Direct lineage; this PR is the table-specific follow-up to the prose-overflow work in #2229.

## References

- `apps/web-platform/components/ui/markdown-renderer.tsx` — renderer with table component map
- `apps/web-platform/app/shared/[token]/page.tsx` — shared document page
- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` — dashboard KB viewer (also affected)
- PR #2280 (`fix(ui): stabilize command-center row width and chat markdown overflow`) — prior overflow fix established the `min-w-0 [overflow-wrap:anywhere]` pattern on the renderer wrapper; this PR extends the same width-discipline pattern to tables.
- `knowledge-base/project/learnings/2026-04-22-markdown-table-parser-papercuts-and-review-diff-direction.md` — markdown table parser caveats (tangential — relates to table parsing, not rendering width).
