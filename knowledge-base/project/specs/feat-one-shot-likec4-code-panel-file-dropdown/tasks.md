---
title: "Tasks — C4 Code panel file dropdown + surface README"
plan: knowledge-base/project/plans/2026-06-12-feat-c4-code-panel-file-dropdown-plan.md
branch: feat-one-shot-likec4-code-panel-file-dropdown
lane: single-domain
date: 2026-06-12
---

# Tasks — C4 Code panel: dropdown file selector + surface README

Derived from the finalized (deepened) plan. Decisions locked: **native `<select>`** for the
file picker, **`MarkdownRenderer` early-return** for the read-only README, **exact `README.md`**
filter (not `.endsWith(".md")`). Do NOT touch the public shared path.

## Phase 1 — Server: surface README in owner sources

- [x] 1.1 In `apps/web-platform/app/api/kb/c4/project/route.ts`, change the readdir filter
  (`:118-120`) from `f.endsWith(C4_SOURCE_EXT)` to `f.endsWith(C4_SOURCE_EXT) || f === "README.md"`.
  Keep the existing `isPathInWorkspace` + `O_RDONLY|O_NOFOLLOW` read for the README identical to
  the `.c4` read. Do NOT add a new size cap (matches existing `.c4` per-source behavior).
- [x] 1.2 Confirm `app/api/shared/[token]/c4/route.ts` is NOT edited (public route returns no
  `sources` — owner-only).
- [x] 1.3 Confirm `ProjectResponse.sources` (`c4-shared.tsx:33-39`) needs no type change
  (`Record<string, string>`).

## Phase 2 — Frontend: native `<select>` replaces wrapping file tabs

- [x] 2.1 In `apps/web-platform/components/kb/c4-shared.tsx` `C4CodePanel`, change the header root
  (`:445`) from `flex flex-wrap …` to a non-wrapping `flex items-center gap-2 …`.
- [x] 2.2 Replace the inline file-tab `.map(...)` (`:446-458`) with a styled native `<select>`:
  `appearance-none` + chevron, soleur tokens (`border-soleur-border-default`, `bg-soleur-bg-base`,
  `text-soleur-text-*`), `aria-label="Select C4 source file"`, one `<option>` per `files` entry,
  `value={activeFile}` + `onChange` → `setActiveFile`.
- [x] 2.3 Keep the `useEffect` default-selection logic (`:388-398`, default `model.c4` else first)
  and the `ml-auto` font-stepper + `saveMsg` + Save cluster unchanged for `.c4` files.

## Phase 3 — Frontend: README read-only via MarkdownRenderer

- [x] 3.1 In `C4CodePanel`, derive `isReadmeFile = activeFile === "README.md"`.
- [x] 3.2 When `isReadmeFile`, render the body through `MarkdownRenderer`
  (`components/ui/markdown-renderer.tsx`, `enableC4={false}`) as an early-return branch — no
  CodeMirror editor, no Save button, no PUT. Reuse the `prose-kb … overflow-y-auto` wrapper
  pattern from `c4-workspace.tsx:116`. Keep the dropdown + header chrome.
- [x] 3.3 Verify both owner render paths inherit this automatically (`C4Workspace` full-screen +
  inline `C4Diagram` owner mode share `C4CodePanel`); public `readOnly` inline path shows no Code
  tab — no change needed.

## Phase 4 — Tests + verification

- [x] 4.1 Extend `apps/web-platform/test/c4-code-panel.test.tsx`: add a multi-file `fakeProject()`
  (`spec.c4`, `model.c4`, `views.c4`, `README.md`); mock `MarkdownRenderer` (passthrough/capture).
- [x] 4.2 Test: `<select>` (`getByRole("combobox")`) lists all source keys; default value is
  `model.c4`; `fireEvent.change` to `views.c4` updates the CodeMirror mock `value` prop.
- [x] 4.3 Test: selecting `README.md` → no Save button; CodeMirror mock NOT rendered;
  `MarkdownRenderer` rendered with the README content.
- [x] 4.4 Confirm existing zoom/save/editor-wiring suites (AC1/AC2/AC3/AC4/AC6/AC7 in the file)
  still pass for `.c4` files.
- [x] 4.5 Add a route-level test (`test/c4-project-route.test.ts` or extend an existing route test)
  asserting `README.md` IS in owner `sources` and `c4-model.md` is NOT (exact-match filter),
  exercising the real path guards on the `.md` read. Do NOT extract a pure dir→sources helper.
- [x] 4.6 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] 4.7 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-panel.test.tsx`
  (+ the route test) passes.

## Phase 5 — Pre-ship / post-merge

- [x] 5.1 Pre-merge: re-run the open-code-review overlap check (`gh issue list --label code-review
  --state open …` then `jq … contains($path)` for each edited file) — `gh` was offline at plan time.
- [ ] 5.2 Post-merge (operator, AC9): on a KB C4 page (owner session, `c4-visualizer` on), open the
  Code tab, drag the resize handle to min width, confirm the header stays on ONE row at both wide
  and narrow widths, and selecting `README.md` shows the rendered read-only README. Prefer a
  Playwright MCP check (navigate → open Code tab → resize → screenshot → assert single-row header);
  fall back to the reconstructed-DOM harness if the flag/auth path isn't Playwright-reachable.
