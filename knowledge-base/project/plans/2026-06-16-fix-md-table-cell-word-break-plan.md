---
title: Fix markdown table data cells breaking short words mid-character
type: fix
date: 2026-06-16
lane: single-domain
brand_survival_threshold: none
---

# Fix: markdown table data cells break short words mid-character

Rendered markdown **table** data cells break short words mid-character in the
Concierge knowledge-base document viewer ("active" -> "activ e", "deferred" ->
"deferre d", "Cloudflare" -> "Cloudflar e", "observability" -> "observabil
ity"), while table **headers** render fine. Reproduced on the
`operations/expenses.md` view.

## Root Cause (verified against current `origin/main` file state)

`apps/web-platform/components/ui/markdown-renderer.tsx:174-178` wraps all
rendered markdown in:

```tsx
<div className="min-w-0 [overflow-wrap:anywhere]" data-narrow-wrap={...}>
```

`overflow-wrap` is an **inherited** CSS property, so `anywhere` cascades into
every descendant — including each `<td>` (line 78-79):

```tsx
td: ({ children }) => (
  <td className="min-w-[8ch] max-w-[45ch] border border-soleur-border-default px-3 py-1.5 align-top text-soleur-text-secondary">{children}</td>
),
```

The `<td>` className does **not** override `overflow-wrap`. With
`overflow-wrap: anywhere` inherited **and** the `max-w-[45ch]` width constraint,
the browser treats every character as a break opportunity and computes the
table-cell min-content width as if each character can wrap, collapsing columns
and breaking short words mid-character.

`<th>` cells (line 70-71) are immune **only** because they carry
`whitespace-nowrap` (which forces `white-space: nowrap`, suppressing all
wrapping) — which is exactly why headers look correct and data cells do not.

This is a **residual** bug: the table-width fix (`w-full` -> `w-auto` + the
`min-w-[8ch] max-w-[45ch]` band) fixed column compression but never overrode the
inherited `overflow-wrap` on cells.

### Premise Validation

No GitHub issue / PR is cited by reference, so there are no external resolution
premises to validate. The three file/line premises in the source description
were each confirmed against the current worktree file:

- L174-178 wrapper div carries `min-w-0 [overflow-wrap:anywhere]` — **confirmed**.
- L78-79 `<td>` className has the `min-w-[8ch] max-w-[45ch] ... align-top` band
  and **no** `overflow-wrap`/`word-break` override — **confirmed**.
- L70-71 `<th>` carries `whitespace-nowrap` — **confirmed** (explains the
  header-immune asymmetry).
- L65-67 `<table className="w-auto border-collapse text-sm">` — **confirmed**
  (the `w-auto` table-width fix is present).

### `break-normal` semantics — verified against the INSTALLED Tailwind version

The repo uses **Tailwind v4** (`apps/web-platform/package.json`:
`"tailwindcss": "^4.1.0"`). The installed compiled source defines:

```
break-normal -> [["overflow-wrap","normal"],["word-break","normal"]]
```

(grepped from `apps/web-platform/node_modules/tailwindcss/dist/chunk-L5IEUH3R.mjs`).

So `break-normal` emits exactly `overflow-wrap: normal; word-break: normal`. A
direct child-element override of `overflow-wrap` defeats the inherited
`anywhere` on `<td>`, which is the fix. The claim in the source description
holds for the installed version — no drift.

## User-Brand Impact

- **If this lands broken, the user experiences:** unreadable knowledge-base
  tables — short words like "active"/"deferred"/"Cloudflare" rendered with
  mid-word breaks ("activ e") in every markdown table on the KB document viewer
  and the public shared-doc viewer (and, since one renderer serves them all,
  chat bubbles and file previews too).
- **If this leaks, the user's data / workflow / money is exposed via:** N/A —
  pure presentational CSS class change; no data, auth, or network surface is
  touched.
- **Brand-survival threshold:** `none`

This change does not touch any sensitive path (no schema/migration/auth/API/SQL
surface — only a leaf React component className), so no `threshold: none, reason:`
scope-out bullet is required by preflight Check 6.

## Research Reconciliation — Spec vs. Codebase

| Claim (source description) | Reality (verified) | Plan response |
|---|---|---|
| One renderer serves **both** the dashboard KB viewer and the shared-token viewer | True, but there are **more** consumers: `components/chat/message-bubble.tsx`, `components/kb/file-preview.tsx`, `components/kb/c4-workspace.tsx`, `components/kb/c4-shared.tsx` all render via `MarkdownRenderer` + `remarkGfm` (table-capable) | Single-renderer fix is correct and benefits all consumers; blast radius is "every markdown table", all in the desired direction. No per-consumer edits. |
| Fix the `<td>` className; "apply to `<table>` if needed" | `<td>` override alone is **sufficient** — `overflow-wrap` is inherited, so `break-normal` on `<td>` lands `overflow-wrap:normal` on the cell and overrides the inherited `anywhere`. A `<table>`-level override is redundant for cell wrapping. | Edit `<td>` className **only**. Do not touch `<table>` (avoid redundant class). |
| Test asserts `<td>` carries `break-normal` | The test runner is **happy-dom** (`vitest.config.ts`: `test/**/*.test.tsx` -> `environment: "happy-dom"`), which does **not** compute layout / computed-style / inherited CSS. Only className-contract assertions are reliable. | Test asserts className presence (`break-normal`) and absence of a literal `[overflow-wrap:anywhere]` class on the cell — never pixel width. Matches happy-dom's capabilities. |
| (Implicit) wrapper `[overflow-wrap:anywhere]` should change | Prior-art learning `#2229` documents the wrapper-level `[overflow-wrap:anywhere]` as **intentional** for long prose/URLs/code outside tables | Do **NOT** remove the container's `[overflow-wrap:anywhere]`. Existing test (lines 6-16) guards it; keep that test green. |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/components/ui/markdown-renderer.tsx` `<td>` className
      contains `break-normal` (the only source change).
- [ ] The `<td>` className still contains `min-w-[8ch]`, `max-w-[45ch]`,
      `align-top`, and the border/padding/text classes (the table-width-band fix
      is preserved).
- [ ] The container `<div>` className still contains `min-w-0` and
      `[overflow-wrap:anywhere]` (long-prose/URL wrapping for non-table content
      is preserved). Existing test at lines 6-16 stays green.
- [ ] `<th>` className still contains `whitespace-nowrap` (header behavior
      unchanged). Existing test at lines 78-87 stays green.
- [ ] The `<table>` element is **not** modified (no redundant `break-normal`).
- [ ] RED-first: the new `<td>`-asserts-`break-normal` assertion is added/run and
      **fails** against the unmodified component, then passes after the className
      edit (capture both states in the PR body or commit sequence).
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/markdown-renderer.test.tsx`
      — all tests pass (existing 7 + new assertions).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — no **new**
      type errors introduced by this change (pre-existing repo errors, if any,
      are out of scope and noted, not fixed).

### Post-merge (operator)

- None. The `web-platform-release.yml` pipeline restarts the container on merge
  to `main` touching `apps/web-platform/**`; no operator action.

## Test Scenarios

Extend `apps/web-platform/test/markdown-renderer.test.tsx`. The existing
`MarkdownRenderer — table column widths` describe block (lines 64-101) already
renders a GFM table and iterates `<td>` cells (lines 89-100); add the new
assertion to that suite (and/or a focused new `it`), reusing the existing
`tableMd` fixture or a fixture whose data cell contains a short word like
`active` / `deferred`.

- Given a GFM markdown table, when rendered by `MarkdownRenderer`, then every
  `<td>` className contains `break-normal`.
  - RED first: this assertion fails against the current component (the `<td>`
    has no `break-normal`).
- Given a GFM table whose data cell contains a short word (e.g. a row
  `| active | deferred |`), when rendered, then the `<td>` carrying that word
  does **not** carry a literal `[overflow-wrap:anywhere]` class (the cell opts
  back to normal wrapping; it inherits `anywhere` only via the cascade, never as
  its own class, and `break-normal` overrides that inheritance).
  - Note (happy-dom): assert on `td.className` string membership only — do NOT
    use `getComputedStyle`/`getBoundingClientRect`/width; happy-dom does not
    compute layout or resolve the inherited cascade, so a computed-style
    assertion would be a structural no-op (see learning
    `best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`).
- Regression (existing, keep green): container `<div>` retains `min-w-0` +
  `[overflow-wrap:anywhere]`; `<pre>` retains `overflow-x-auto`; `<th>` retains
  `whitespace-nowrap`; `<td>` retains `min-w-[8ch]`/`max-w-[45ch]`/`align-top`;
  table retains `w-auto` and not `w-full`.

## Context

- **The change (single line):** in `buildComponents`, add `break-normal` to the
  `<td>` className.

  Before (`markdown-renderer.tsx:78-79`):
  ```tsx
  td: ({ children }) => (
    <td className="min-w-[8ch] max-w-[45ch] border border-soleur-border-default px-3 py-1.5 align-top text-soleur-text-secondary">{children}</td>
  ),
  ```
  After:
  ```tsx
  td: ({ children }) => (
    <td className="min-w-[8ch] max-w-[45ch] break-normal border border-soleur-border-default px-3 py-1.5 align-top text-soleur-text-secondary">{children}</td>
  ),
  ```
  (Exact intra-className position of `break-normal` is not load-bearing;
  Tailwind class order does not affect specificity. Keep the comment block at
  lines 75-77 intact.)

- **Why `<td>` only and not `<table>`:** `overflow-wrap` is inherited.
  `break-normal` on `<td>` sets `overflow-wrap: normal` directly on the cell,
  overriding the inherited `anywhere`. With normal wrapping, `table-layout: auto`
  computes each column's min-content width from whole words, so columns stop
  collapsing and short words stop breaking. A `<table>`-level `break-normal`
  would also propagate `overflow-wrap: normal` to cells via inheritance, but it
  is redundant once the cells set it themselves — keep the diff minimal.

- **Why NOT remove the container `[overflow-wrap:anywhere]`:** it is intentional
  for long prose / unbroken URLs / inline code outside tables (issue #2229,
  learning `ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md`).
  Only table cells opt back to normal wrapping.

- **Why NOT use `whitespace-nowrap` on `<td>` (the `<th>` approach):** headers
  are short labels that benefit from never wrapping; data cells with
  prose/longer values must still wrap at word boundaries within the
  `max-w-[45ch]` band. `whitespace-nowrap` would force single-line cells and
  blow out the table — wrong tool for `<td>`.

## Files to Edit

- `apps/web-platform/components/ui/markdown-renderer.tsx` — add `break-normal`
  to the `<td>` className (line 78-79). Single-line change.
- `apps/web-platform/test/markdown-renderer.test.tsx` — extend the
  `table column widths` describe block (lines 64-101) with the RED-first
  `break-normal` assertion (and the negative `[overflow-wrap:anywhere]`-class
  assertion).

## Files to Create

- None.

## Open Code-Review Overlap

None checked against open `code-review` issues touching these two files (no
network query run at plan time in this pipeline; the files are leaf
component + its colocated test, low overlap risk). If `/work` or review surfaces
an open scope-out on `markdown-renderer.tsx`, fold in or acknowledge per the
overlap rule.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — leaf presentational CSS change in a
shared React component. No finance/legal/marketing/ops/sales/support/engineering
strategy surface.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface — modifies an existing leaf component's
CSS class only; creates no new page, component file, modal, or flow)

#### Findings

Mechanical UI-surface override check: the only edited UI file is
`components/ui/markdown-renderer.tsx`, which already exists and is **modified**,
not created. No path under `## Files to Create` matches `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx`, so the BLOCKING mechanical escalation
does not fire. This is an ADVISORY-tier change (modifies an existing rendered
surface's wrapping behavior without adding any interactive surface). Running in
pipeline context (plan-file-path argument), so auto-accepted per the ADVISORY
pipeline arm — no wireframe / spec-flow / copywriter pass needed for a
word-wrap CSS fix.

## Observability

Skipped per plan Phase 2.9: this is a pure leaf-component CSS class change with
no new error path, log call, server route, infra surface, or failure mode. The
only "failure mode" is a wrong/missing className, which is gated by the vitest
className-contract assertion at PR time (not a runtime-observability concern).
No `apps/*/server/`, `apps/*/infra/`, or `plugins/*/scripts/` file is touched.

## References

- Component: `apps/web-platform/components/ui/markdown-renderer.tsx`
- Test: `apps/web-platform/test/markdown-renderer.test.tsx`
- Vitest config: `apps/web-platform/vitest.config.ts`
  (`test/**/*.test.tsx` -> happy-dom)
- Prior art (do not regress): `knowledge-base/project/learnings/ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md`
- happy-dom layout limits: `knowledge-base/project/learnings/best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`
- CSS-class-presence (not stylesheet) verification: `knowledge-base/project/learnings/2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet.md`
- Behavior-reversal RED discipline: `knowledge-base/project/learnings/2026-06-01-behavior-reversal-fix-flip-existing-test-as-red.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan fills it: threshold `none`.)
- Test runner is **happy-dom**, not jsdom and not the browser. Assert
  `td.className` string membership only. `getComputedStyle`, `getBoundingClientRect`,
  `clientWidth`, and any inherited-cascade resolution are no-ops in happy-dom —
  a computed-style assertion would pass vacuously and prove nothing.
- Do **not** verify the fix by grepping compiled Tailwind CSS — a class existing
  in the stylesheet does not prove the `<td>` element carries it. The load-bearing
  proof is the runtime `td.className.includes("break-normal")` assertion.
- Typecheck command MUST be `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`,
  NOT `npm run -w apps/web-platform typecheck` — the repo root `package.json` has
  no `workspaces` field, so the `-w` form aborts.
- Single-test command is `./node_modules/.bin/vitest run test/markdown-renderer.test.tsx`
  from inside `apps/web-platform` (the package uses vitest, not bun test;
  `apps/web-platform/bunfig.toml` ignores all test paths).
- Keep the fixture's short word OUTSIDE any character that some other process
  might treat as a token boundary — use a plain alpha word like `active` /
  `deferred` in the test fixture.
