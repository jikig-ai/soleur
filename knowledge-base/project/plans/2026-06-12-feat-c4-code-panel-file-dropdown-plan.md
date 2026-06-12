---
title: "C4 Code panel — file dropdown selector + surface README"
type: feat
date: 2026-06-12
branch: feat-one-shot-likec4-code-panel-file-dropdown
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: none
status: draft
---

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Design Decision, README treatment, ACs, Files-to-Create, Observability, Sharp Edges
**Agents used:** verify-the-negative (Explore), framework-docs (CodeMirror types), code-simplicity-reviewer, agent-native-reviewer, security-sentinel

### Key Improvements (applied)
1. **README → `MarkdownRenderer` early-return** (not read-only CodeMirror). Simplicity review:
   simpler *and* better UX; kills AC7's conditional syntax-strip / Save-disable wiring inside the
   editor render path. The README branch becomes `if (isReadOnlyFile) return <MarkdownRenderer>`.
2. **Native `<select>` committed** — no "review fallback" hedge. For a 4-item, no-search picker the
   custom-widget machinery (outside-click/focus-trap/arrow-key/`aria-activedescendant`) is dead
   weight; `<select>` is a11y-correct for free and non-wrapping with `appearance-none`.
3. **CodeMirror read-only prop resolved**: `@uiw/react-codemirror@4.25.10` exposes top-level
   `readOnly?: boolean` + `editable?: boolean` (no extension needed) — but the README no longer
   uses CodeMirror at all (point 1), so this is moot for the README and Phase 0.3 is dropped.
4. **Filter = exact `file === "README.md"`** (not `.endsWith(".md")`) — security + intent: avoids
   surfacing the `c4-model.md` view-embed page and any future `.md` additions.
5. **Cut ceremony**: AC8 (public-path zero-diff) folds into the Sharp Edge; AC9 (inline parity) is
   structural (shared component) → one-line note on AC2; optional helper test file dropped (test the
   route directly); Phase 0 dissolved into Phase 1.

### New Considerations Discovered
- All 6 negative safety claims CONFIRMED by grep (public route is sources-free; `readOnly` hides the
  Code tab; owner filter is `.c4`-only today; `C4CodePanel` does not render `@likec4/diagram`;
  `isC4DiagramPath` already permits `.md` writes).
- **Doc fix:** `MAX_C4_BYTES` (4 MiB) is applied only to the `model.likec4.json` read, NOT to the
  per-source `.c4`/`.md` read loop (pre-existing; out of scope to add here). Observability section
  corrected to not overclaim it as a reused guard for the source read.
- Agent-native parity OK (Concierge already reads the README via generic `Read`/`Grep` workspace
  tools); security LOW, no must-fix.

---

# ✨ feat: C4 Code panel — replace flex-wrap file tabs with a clean dropdown + surface the diagrams README

## Overview

In the LikeC4 visualizer's full-screen workspace (`C4Workspace`, the KB diagram page),
the RIGHT panel toggles between **Concierge** and **Code**. The **Code** tab renders
`C4CodePanel` (in `apps/web-platform/components/kb/c4-shared.tsx`). Its header is a single
`flex flex-wrap` row holding, left-to-right: the per-file tab buttons (`spec.c4`,
`model.c4`, `views.c4`) and, pushed right (`ml-auto`), the font-size stepper (`A−` /
`12px` / `A+`) plus the **Save** button.

When the user narrows the resizable right panel (the `Panel minSize="28%"` in
`c4-workspace.tsx`), the `flex-wrap` causes the file tabs and the font-size/Save cluster
to **wrap onto a second (and sometimes third) line** — a ragged, cramped header. This plan
replaces the wrapping file-tab strip with a **clean, non-wrapping dropdown file selector**,
so the header stays on one row at any panel width, and the file picker is a compact control.

The request's second clause — *"add the README.md file which describes the different
files"* — resolves (after premise validation, below) to **surfacing the already-committed
`README.md`** (it exists at `knowledge-base/engineering/architecture/diagrams/README.md`,
merged in #4936) **inside the Code panel's new file dropdown**, read-only, so a user
browsing the diagram sources can open the directory index and read what each `.c4` file is
without leaving the viewer. The README *file* already exists; what is missing is its
**reachability from the viewer**.

This is a frontend-only change plus one narrow server-side filter widening (include `.md`
in the owner project-sources response). No new infrastructure, no new dependency, no schema
change.

## Research Reconciliation — Spec vs. Codebase

The feature description cites two artifacts/claims by reference; both were premise-validated
against `origin/main` (offline — verified via `git log` + file reads, `gh` unavailable).

| Description claim | Codebase reality | Plan response |
|---|---|---|
| "the part with files and font size uses a wrap" | Confirmed. `c4-shared.tsx:445` — header is `className="flex flex-wrap items-center gap-1 …"`; file tabs are inline `<button>`s (`:446-458`); font-size stepper + Save are in an `ml-auto` cluster (`:459-507`). At narrow panel widths the row wraps. | Replace `flex-wrap` with a non-wrapping `flex` row; replace the inline file-tab `<button>` list with a single dropdown file selector. Keep font-size + Save in the same `ml-auto` cluster. |
| "add the README.md file which describes the different files" | **The README already exists** — `knowledge-base/engineering/architecture/diagrams/README.md`, committed in #4936 (`3d03c167`), comprehensive "File taxonomy" table. The 2026-06-04 plan that authored it is marked `complete`. It is **NOT** surfaced in the viewer: the owner project API (`app/api/kb/c4/project/route.ts:118-120`) filters `data.sources` to `f.endsWith(C4_SOURCE_EXT)` (`.c4` only), so the README never reaches `C4CodePanel`. | Re-scope from *create file* (already done) to *surface existing file*: widen the owner sources filter to also include `README.md` (or `.md`), and add a read-only branch in `C4CodePanel` so a selected `.md` renders without the `.c4` syntax/save affordances. See Directional Decision below. |

### Directional Decision (ambiguity gate)

"Add the README" has two readings: **(A)** author a new README (already done — #4936), or **(B)**
make the existing README reachable from the viewer's file picker. Reading (A) is a no-op
(the file is present and complete), so this plan adopts **(B)** as the only interpretation
that produces actionable, non-duplicative work. If the operator actually wanted the README
*body rewritten/expanded*, that is out of scope here and should be a separate docs change —
this plan does not modify the README's content.

## User-Brand Impact

**If this lands broken, the user experiences:** a Code-panel header that still wraps at
narrow widths (no regression — same as today), OR a dropdown that fails to switch files /
loses the active-file selection, leaving the user unable to view/edit a `.c4` source in the
viewer. Worst plausible: the README branch leaks a Save/PUT affordance on a doc that
shouldn't be edited as a source.

**If this leaks, the user's data / workflow is exposed via:** N/A — no new data surface.
The README and `.c4` sources are owner-scoped KB content the user already owns; the **public
shared** viewer (`app/shared/[token]/page.tsx`) passes `readOnly` and its API
(`api/shared/[token]/c4/route.ts`) **does not return `sources` at all** (owner-only by
construction). This change does not touch the public path, so the README is never exposed to
an anonymous recipient.

**Brand-survival threshold:** none — owner-only UI affordance over content the user already
owns; no new data-movement, no external API, no regulated surface.

> `threshold: none, reason: pure owner-scoped frontend UI affordance + a read-only widening of an already-owner-only sources filter; no sensitive path, no public surface, no data movement.`

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — No wrap.** `C4CodePanel`'s header root no longer uses `flex-wrap`. Grep:
  `grep -n "flex-wrap" apps/web-platform/components/kb/c4-shared.tsx` returns **zero** matches
  inside the `C4CodePanel` header (the only current occurrence is the header row at `:445`).
- [x] **AC2 — Dropdown file selector.** The file tabs are replaced by a single selector
  control. The control exposes an accessible name (`aria-label="Select C4 source file"` or a
  `<label>`-associated native `<select>`), lists every entry in `data.sources` keys, shows
  the active file, and selecting an entry sets `activeFile` (and loads `data.sources[file]`
  into the editor draft). Verified by a vitest test that renders the panel, asserts the
  selector lists all source keys, fires a selection change, and asserts the editor `value`
  prop updates to the newly-selected source.
- [x] **AC3 — Default-file selection preserved.** On mount the panel still defaults to
  `model.c4` when present, else the first source key (current behavior at `:388-395`). Test
  asserts the selector's initial value is `model.c4` for a fixture containing it.
- [x] **AC4 — Font-size + Save unchanged.** The `A−` / `12px` (reset) / `A+` controls and
  the **Save** button remain, with the same aria-labels and clamp behavior. The existing
  `c4-code-panel.test.tsx` zoom/save suites (AC1/AC2/AC3/AC7 in that file) continue to pass
  **unmodified** except where they assert the *file-tab* markup (those assertions, if any, are
  updated to the dropdown shape — current test file does NOT assert file tabs, so likely zero
  edits there).
- [x] **AC5 — Editor wiring intact.** CodeMirror still receives `[c4SyntaxExtensions,
  codeFontTheme(zoom)]` for `.c4` files; the existing AC4/AC6 editor-wiring tests in
  `c4-code-panel.test.tsx` pass.
- [x] **AC6 — README surfaced (owner path).** `app/api/kb/c4/project/route.ts` includes
  **exactly `README.md`** (`file === "README.md"`, NOT a blanket `.endsWith(".md")` — that would
  also surface the `c4-model.md` view-embed page and any future `.md`) in `sources` in addition
  to `.c4`. The dropdown lists `README.md`. Tested at the route level (which also proves the
  `isPathInWorkspace` + `O_NOFOLLOW` guards stay wired for the `.md` read — a pure-predicate unit
  test would miss that). AC2's `fakeProject()` fixture containing `README.md` also proves the
  dropdown surfaces it.
- [x] **AC7 — README rendered read-only via `MarkdownRenderer`.** When the selected file is
  `README.md`, the panel renders it through the existing `components/ui/markdown-renderer.tsx`
  (`MarkdownRenderer`) as a clean early-return branch — **no CodeMirror editor, no Save button,
  no PUT wired** for the `.md`. (Deepen simplicity review: simpler — no conditional
  syntax-strip/Save-disable threaded through the editor — and better UX than a monospace
  line-numbered read-only editor for a directory index.) Test asserts: selecting `README.md` →
  no Save button present, the CodeMirror mock is NOT rendered, README content is rendered.
- [x] **AC8 — Typecheck + tests green.** `cd apps/web-platform && ./node_modules/.bin/tsc
  --noEmit` passes, and `./node_modules/.bin/vitest run test/c4-code-panel.test.tsx` passes.

> Folded (deepen-plan simplicity review): the former **AC8 (public-path zero-diff)** is now a
> Sharp Edge, not a standalone AC. The former **AC9 (inline-embed parity)** is structural — both
> owner render paths (`C4Workspace`, inline `C4Diagram`) consume the same `C4CodePanel`, so the
> dropdown + README branch apply to both automatically; the public `readOnly` inline path still
> shows no Code tab (existing `c4-diagram.tsx` `!readOnly` guard, confirmed). No separate AC/test.

### Post-merge (operator)

- [ ] **AC9 — Visual confirmation in both panel-width states.** After deploy, on a KB C4
  page (`c4-visualizer` flag on, owner session), open the Code tab and drag the resize handle
  to the minimum panel width; confirm the header stays on **one row** (no wrap) at both wide
  and narrow widths, and that selecting `README.md` shows the rendered (read-only) README.
  `Automation:` feasible
  via Playwright MCP against the deployed owner session — prescribe a Playwright check
  (navigate → open Code tab → resize panel → screenshot → assert single-row header) rather
  than dashboard-eyeballing, per `hr-no-dashboard-eyeball-pull-data-yourself`. If the
  flag/auth path is not reachable from Playwright MCP in the deploy env, fall back to the
  reconstructed-DOM harness (see Sharp Edges) for the single-row assertion.

## Implementation Phases

> Deepen note: the former numbered Phase 0 (preconditions) is dissolved — its items were either
> already verified in this plan (the `flex-wrap` header line, `sources` keyed by basename) or
> resolved by deepen research (CodeMirror read-only prop is now moot since the README uses
> `MarkdownRenderer`, not the editor; the selector mechanism is committed to native `<select>`).
> Any residual confirmation folds into Phase 1.

### Phase 1 — Server: surface README in owner sources (AC6)
- `apps/web-platform/app/api/kb/c4/project/route.ts` — widen the readdir filter at `:118-120`
  from `f.endsWith(C4_SOURCE_EXT)` to **`f.endsWith(C4_SOURCE_EXT) || f === "README.md"`**.
  Use the **exact** `=== "README.md"` form (NOT `.endsWith(".md")`): the dir contains
  `c4-model.md` (the view-embed page) AND `README.md`, and a blanket `.md` would surface the
  embed page as a browsable "source" + auto-surface any future `.md`. Keep the existing
  `isPathInWorkspace` + `O_NOFOLLOW` guards for the README read identical to the `.c4` read.
  (Note: the per-source read loop does NOT apply `MAX_C4_BYTES` — that cap is on the
  `model.likec4.json` read only; matching the existing `.c4` behavior, no new cap added here.)
  **Do NOT touch** `app/api/shared/[token]/c4/route.ts` — it returns no `sources` (owner-only).
- Confirm `ProjectResponse.sources` type (`c4-shared.tsx:33-39`) needs no change — it is
  `Record<string, string>`, file-extension-agnostic.

### Phase 2 — Frontend: dropdown selector replaces wrapping tabs (AC1, AC2, AC3)
- `apps/web-platform/components/kb/c4-shared.tsx`, `C4CodePanel`:
  - Replace the header root `flex flex-wrap` (`:445`) with a non-wrapping `flex
    items-center gap-2` (one row; the `<select>` + `ml-auto` cluster never wrap).
  - Replace the inline file-tab `.map(...)` (`:446-458`) with a **styled native `<select>`**
    (`appearance-none` + a chevron, soleur tokens), bound to `activeFile` / `setActiveFile`
    via `onChange`. One `<option>` per `files` entry. Add `aria-label="Select C4 source file"`.
    Keep the `useEffect` default-selection logic (`:388-398`) as-is.
  - Keep the font-size stepper + `saveMsg` + Save in the existing `ml-auto` cluster.
- Style with soleur design tokens (`border-soleur-border-default`, `bg-soleur-bg-base`,
  `text-soleur-text-*`). No custom widget, no headless-UI lib, no outside-click/focus-trap code
  — the native `<select>` is a11y-complete for a 4-item single-select picker (committed below).

### Phase 3 — Frontend: README rendered read-only via MarkdownRenderer (AC7)
- In `C4CodePanel`, derive `isReadmeFile = activeFile === "README.md"`. When true, **early-return**
  a branch that renders the source through the existing `MarkdownRenderer`
  (`components/ui/markdown-renderer.tsx`, `enableC4={false}`) instead of the CodeMirror editor —
  **no Save button, no font-stepper-on-editor, no PUT**. The dropdown + header chrome stay; only
  the body swaps editor → rendered markdown. (This is the deepen simplicity decision: a clean
  early-return is fewer moving parts than threading `readOnly` + conditional-syntax-strip +
  Save-disable through the editor, and reads better for a directory index.)
- Shared automatically by `C4Diagram` (inline) and `C4Workspace` (full-screen) since both
  consume `C4CodePanel`. The public `readOnly` inline path renders no Code tab, so no leak.

### Phase 4 — Tests (AC2, AC3, AC5, AC6, AC7, AC8)
- Extend `apps/web-platform/test/c4-code-panel.test.tsx` (it already mocks CodeMirror +
  `@likec4/diagram` and asserts via **props**, not pixels — keep that discipline). The README
  branch uses `MarkdownRenderer`; mock it the same way (capture-props or a passthrough stub) so
  the test can assert it rendered and the CodeMirror mock did NOT.
  - Add a multi-file `fakeProject()` variant (`spec.c4`, `model.c4`, `views.c4`, `README.md`).
  - Test: `<select>` lists all keys (`getByRole("combobox")` options); default = `model.c4`;
    `fireEvent.change` to `views.c4` updates the editor `value` prop.
  - Test: selecting `README.md` → no Save button; CodeMirror mock NOT rendered; MarkdownRenderer
    rendered with the README content.
- Add a **route-level** test (`test/c4-project-route.test.ts` or extend an existing route test)
  asserting `README.md` IS in the returned owner `sources` and `c4-model.md` is NOT (proves the
  exact-match filter) — this also exercises the real `isPathInWorkspace`/`O_NOFOLLOW` guards on
  the `.md` read. Do NOT extract a pure dir→sources helper just to test the predicate (deepen
  simplicity: indirection to test one boolean; test the route directly).

## Design Decision — native `<select>` (COMMITTED)

The codebase uses **zero** headless-UI libraries and builds dropdowns as custom
button + absolute-positioned `role="listbox"` widgets (`at-mention-dropdown.tsx`,
`share-popover.tsx`). Those exist for genuinely harder problems — `at-mention-dropdown` needs
filtering + custom row rendering + inline positioning over a textarea; `share-popover` needs
arbitrary floating content. Neither is "pick one of N strings."

For this **4-item, no-search, no-multiselect** file picker the choice is settled (deepen-plan
code-simplicity-reviewer, strong): a **styled native `<select>`** (`appearance-none` + a
chevron, soleur tokens). It is a11y-correct for free (keyboard nav, screen-reader semantics),
non-wrapping, trivially testable (`fireEvent.change` / `getByRole("combobox")`), and the
smallest diff. Cloning the custom-widget machinery here would add outside-click handling,
focus management, arrow-key navigation, and an `aria-activedescendant` listbox dance — all of
which `<select>` provides bug-free — purely to make the *briefly-open* option list match app
chrome. That trade is not worth ~80-150 lines of stateful interaction + its own test surface.
**No fallback hedge** — this is committed; do not relitigate to a custom widget at review.

## Files to Edit
- `apps/web-platform/components/kb/c4-shared.tsx` — `C4CodePanel`: remove `flex-wrap`,
  replace file tabs with a native `<select>`, add the `README.md` → `MarkdownRenderer`
  early-return branch.
- `apps/web-platform/app/api/kb/c4/project/route.ts` — include exactly `README.md` in owner
  sources (`f.endsWith(C4_SOURCE_EXT) || f === "README.md"`).
- `apps/web-platform/test/c4-code-panel.test.tsx` — `<select>` + README-MarkdownRenderer +
  multi-file tests.

## Files to Create
- `apps/web-platform/test/c4-project-route.test.ts` — route-level test that `README.md` IS in
  owner `sources` and `c4-model.md` is NOT (exact-match filter), exercising the real path
  guards on the `.md` read. (If an existing route test is a cleaner home, extend it instead and
  create nothing. Do NOT extract a pure dir→sources helper just to unit-test the predicate.)

## Open Code-Review Overlap

None. (Checked the planned files against open `code-review`-labelled issues; `gh` is offline
in this session, so this MUST be re-run at /work time: `gh issue list --label code-review
--state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` then
`jq -r --arg path "apps/web-platform/components/kb/c4-shared.tsx" '.[] | select(.body //
"" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json` for each
planned file. If any match, fold-in / acknowledge / defer per the overlap contract.)

## Domain Review

**Domains relevant:** Product (UI surface — mechanical override)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none — this modifies an EXISTING UI surface (the Code-panel header)
without adding a new page, new route, or a new persuasive/emotional interstitial. The
mechanical UI-surface override fires (the plan edits `components/kb/c4-shared.tsx`), forcing
Product-relevant = true; the change is a layout/control swap (wrapping tabs → dropdown) +
surfacing an existing read-only doc, which is the ADVISORY class (modifies existing
component, no new interactive surface, no new `components/**/*.tsx` / `app/**/page.tsx` file).
On the one-shot pipeline path with no new component file created, this auto-accepts. No
`.pen` wireframe is required: no new page/flow/component file is created (the override that
would force BLOCKING — a new `components/**/*.tsx` — does not fire; the work edits an existing
component in place).

#### Findings

Replacing a `flex-wrap` tab strip with a non-wrapping dropdown is a strict UX improvement at
narrow widths and neutral at wide widths. Surfacing the README read-only adds discoverability
of the file taxonomy without a new surface. No brand/positioning/flow concerns.

## Infrastructure (IaC)

N/A — no new infrastructure. Pure code change against the already-provisioned web-platform
surface (edits under `apps/web-platform/components/` + one already-existing API route + a
test). No server, secret, vendor, cron, DNS, or persistent runtime process introduced.

## Observability

N/A under the Phase 2.9 skip rule? **No** — Files-to-Edit includes `apps/web-platform/app/...`
(a route) and `apps/web-platform/components/...`, so the section is required. The change adds
**no new failure mode**: the widened readdir filter reuses the existing try/catch
(`route.ts:117-135`) whose `catch` already treats sources as best-effort optional, and any
read error is already swallowed there by design (sources are optional for rendering). No new
error path, log call, or alert is introduced.

```yaml
liveness_signal:
  what: existing GET /api/kb/c4/project returns 200 with sources (now incl. README.md)
  cadence: on-demand (owner opens the Code tab)
  alert_target: none-new — covered by existing route-level Sentry.captureException (route.ts:142)
  configured_in: apps/web-platform/app/api/kb/c4/project/route.ts
error_reporting:
  destination: Sentry (existing route.ts:142 Sentry.captureException on the outer catch)
  fail_loud: false-for-sources — sources read is best-effort by existing design (route.ts:133-135); a README read failure degrades to "README not listed", never a 500. The outer catch (model JSON read) is unchanged and still fail-loud to Sentry.
failure_modes:
  - mode: README.md unreadable / oversized
    detection: inner per-file catch already swallows (sources optional); README simply absent from the dropdown
    alert_route: none required (non-fatal, non-regression — same as a missing .c4 today)
  - mode: dropdown fails to switch file (client)
    detection: vitest AC2/AC3 (props-level); no runtime telemetry (client-only state, no network)
    alert_route: none (caught pre-merge by tests)
logs:
  where: existing route logger.error (route.ts:144) on the outer catch only — unchanged
  retention: existing Better Stack / Sentry retention (no new log line added)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-panel.test.tsx"
  expected_output: "all tests pass — selector lists README.md, README is read-only, .c4 save path intact"
```

## Test Scenarios

1. Multi-file fixture (`spec.c4` / `model.c4` / `views.c4` / `README.md`) → dropdown lists 4
   entries, default `model.c4`.
2. Change selection to `views.c4` → editor `value` prop becomes the `views.c4` source.
3. Change selection to `README.md` → Save absent/disabled, editor read-only, no `.c4` syntax
   extension applied (or markdown-rendered).
4. Font-size stepper + Save behavior unchanged on a `.c4` file (existing suite).
5. Owner sources filter includes `README.md`; public route omits `sources` entirely.

## Risks & Mitigations

- **Risk: blanket `.md` pulls in `c4-model.md` (the view-embed page) as a "source".**
  Mitigation: filter to exactly `f === "README.md"` (Phase 1), not `.endsWith(".md")`. Confirm
  the dir listing at /work time (`git ls-files knowledge-base/engineering/architecture/diagrams/`
  — currently: `spec.c4`, `model.c4`, `views.c4`, `model.likec4.json`, `c4-model.md`, `README.md`).
- **Risk: README rendered via `MarkdownRenderer` differs in overflow/scroll behavior from the
  editor body.** Mitigation: the README branch is a self-contained early-return; reuse the
  `prose-kb … overflow-y-auto` wrapper pattern from `c4-workspace.tsx:116` (the Notes strip
  already renders markdown the same way). No editor props involved — moot the former CodeMirror
  read-only-prop concern (the README does not use the editor).
- **Risk: happy-dom can't lay out CodeMirror → pixel/visual alignment of the dropdown not
  testable in vitest.** Mitigation: assert **props/state** (the existing test discipline);
  visual single-row confirmation is an explicit post-merge Playwright/harness step (AC9), not
  a unit test. (Learning: `2026-06-05-codemirror-streamlanguage-for-unsupported-dsl.md`.)
- **Risk: vendored `@likec4/diagram` CSS interaction.** Low — `C4CodePanel` does NOT render
  `@likec4/diagram` (it is CodeMirror + plain markup); the dropdown is app-owned chrome, not a
  vendored-library DOM override, so the vendored-CSS-hook learnings
  (`2026-06-04-vendored-library-css-hook-...`) do not bite here. Noted for completeness so
  /work does not over-engineer a reconstructed-DOM CSS-cascade harness for app-owned chrome.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's
  section is filled with a concrete artifact + vector + `threshold: none` scope-out reason.
- **Do NOT touch the public shared path** (this folds the former AC8). `api/shared/[token]/c4/
  route.ts` returns no `sources` (verified — response is `{ dir, dump, viewIds }` only) and
  `app/shared/[token]/page.tsx` passes `readOnly`. The README must remain owner-only. Phase 1
  edits only the owner route; the public files must show **no change** in `git diff --stat` —
  if /work finds itself editing them, the scope has drifted.
- **`isC4DiagramPath` already permits `.md`** (`c4-constants.ts:63`), so the README is
  technically a *writable* path via the existing PUT route — but this plan deliberately renders
  the README **read-only** (via `MarkdownRenderer`, no Save wired). Do not "simplify" by
  surfacing an editor + Save on the README; it is a directory index, not an editable source.
  (Security review confirmed this is a UX choice, not a security boundary — an owner editing
  their own KB README is within scope and not a vuln either way.)
- **Native `<select>` styling caveat:** the OS renders the open option list, so it won't
  perfectly match soleur token chrome for the fraction of a second it's open. This is the
  accepted, committed trade-off (Design Decision) — the *closed* control IS fully tokened
  (`appearance-none` + chevron). Do NOT swap to a custom widget for this; it was considered and
  rejected.

## Alternative Approaches Considered

| Approach | Why not (chosen instead) |
|---|---|
| Keep tabs, just add `overflow-x-auto` (horizontal scroll instead of wrap) | Doesn't satisfy "clean dropdown menu" — the request explicitly asks for a dropdown; a scrolling tab strip is still a strip. |
| Read-only CodeMirror for the README (instead of `MarkdownRenderer`) | **Rejected at deepen-plan.** Keeps the editor element but requires conditionally stripping the `.c4` syntax extension, disabling Save, and wiring the read-only prop — more conditional branches threaded through the editor render path, and a worse reading experience (monospace + line numbers) for a prose directory index. `MarkdownRenderer` early-return is both simpler and better UX. |
| Custom listbox widget (clone `at-mention-dropdown`) for the file picker | **Rejected at deepen-plan.** More code + its own keyboard/focus/outside-click tests for a 4-item, no-search list; native `<select>` is simpler and a11y-complete. The custom widgets exist for filtering/floating-content problems this picker does not have. |
| Re-author / expand the README content | Out of scope — the README already exists and is complete (#4936). Reading (A) of the ambiguous clause is a no-op; this plan adopts reading (B), surface-not-create. |
