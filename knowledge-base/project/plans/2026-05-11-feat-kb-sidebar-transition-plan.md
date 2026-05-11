---
title: "Knowledge Base sidebar collapse/expand transition"
type: feat
branch: feat-one-shot-kb-sidebar-transition
date: 2026-05-11
status: planning
requires_cpo_signoff: false
deepened: 2026-05-11
---

# feat: Knowledge Base sidebar collapse/expand transition

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview, Risks, Sharp Edges, Phase 1, Phase 2, Phase 3, Phase 4, Acceptance Criteria
**Research inputs:** PR bodies for #3557, #3573, #3579, #3584, #3585 (the full settings-sidebar
polish chain); `apps/web-platform/components/settings/settings-shell.tsx` (the canonical pattern);
`apps/web-platform/node_modules/react-resizable-panels/dist/react-resizable-panels.d.ts:193-280`
(library API); learning `2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`
(QA-degradation pattern for pure-CSS fixes).

### Key Improvements

1. **Sidestep the box-border + padding sliver trap (#3585).** Plan now explicitly
   prescribes the two-layer recipe: nav has NO padding, inner wrapper has
   fixed width + padding. Without this, `md:w-0` + `box-border` + `px-4` forces a
   32 px residual sliver where users see the first letter of each file-tree entry
   at the screen edge mid-collapse.
2. **Lock the inner-content position during transition (#3584).** Plan now requires
   that the inner wrapper's padding be on its ALWAYS-on base classes, not on
   conditional classes — otherwise the file-tree contents snap from (16, 20)
   to (0, 0) on the first frame while the eased width transition lags behind.
3. **Animate doc-shell `padding` not just `padding-left` (#3573 pattern).** Plan
   already had this; deepen-pass confirms the recipe is identical to settings —
   `md:transition-[padding] md:duration-200 md:ease-out` in BOTH states (never
   conditional), only the value of `pl-*` toggles.
4. **Anchor centered KB document content during the slide (#3579 pattern, KB
   variant).** New Risk added: KB doc viewer renders Markdown / PDF inside a
   `flex-1` well that grows continuously as the sidebar collapses. Any
   `mx-auto max-w-*` content (markdown prose body) will drift leftward over the
   200 ms transition. Phase 4 manual verification adds a check for this; if the
   drift is perceptible, mitigation lives in `KbDocShell` (see new Sharp Edge).
5. **Dev-server gating risk (#3562 → see learning).** Local Playwright
   verification is currently blocked by an `instrumentation.ts` ESM/CJS bug on
   `main`. Plan now explicitly accepts degraded QA via unit-test className
   contracts, mirroring the precedent set by the settings PR chain.
6. **Test-runner sharp edge for vitest + JSDOM.** Settings PR chain learned that
   `getBoundingClientRect()` returns zero in JSDOM, so pixel-level drift cannot
   be asserted in unit tests — only className/transition tokens. Plan tests are
   correctly scoped to className contracts (no geometry asserts in vitest).

### New Considerations Discovered

- The settings sidebar took **five iterations** (PRs #3557, #3573, #3579, #3584,
  #3585) to land cleanly. Each iteration revealed a non-obvious bug. Aim to
  collapse those five learnings into the KB plan up-front so the KB version
  lands in one PR.
- Two settings PRs in the chain (#3573, #3579, #3584, #3585) reused
  `settings-sidebar-collapse.test.tsx` as the regression gate. The KB version
  should follow suit — every Sharp Edge in this plan should be backed by a
  unit-test assertion so future-KB-style polish PRs cannot silently regress.

## Overview

The Knowledge Base file-tree sidebar (`apps/web-platform/components/kb/`) collapses
and expands instantly with no animation, while the Settings nav has a smooth 200 ms
width transition that the team polished across PRs #2494, #2504, #3557, #3573, #3579,
#3584, #3585. This plan applies the same CSS-driven width-transition pattern from
`SettingsShell` to the KB sidebar so the open/close action is visually consistent
across the dashboard.

The root cause of the current snap behavior is that the KB desktop sidebar is a
`<Panel collapsible collapsedSize="0%">` from `react-resizable-panels` v4.10. The
library's collapse / expand imperative API (`panelRef.current.collapse()` /
`.expand()`) writes inline `flex` styles synchronously — there is no built-in
animation, and CSS `transition-[flex]` on the panel does not engage cleanly because
the library writes style values imperatively rather than via React's declarative
style prop. See "Research Reconciliation" below for the inspected typedef.

The fix mirrors `SettingsShell` precisely: the file-tree sidebar becomes a plain
`<aside>` with `md:transition-[width] md:duration-200 md:ease-out`, an inner wrapper
that holds fixed-width padding so the contents stay anchored at (16, 20) during the
collapse, and `md:overflow-hidden` on the outer container to clip the wrapper
right-to-left as the width animates to `md:w-0`. The doc-viewer + chat-panel pair
remain a `<Group>` of `<Panel>`s so the existing chat-vs-doc drag-resize is
preserved.

## User-Brand Impact

**If this lands broken, the user experiences:** The KB sidebar fails to render or
flashes/jumps when toggling, breaking the most-used navigation surface for reading
project docs. Worst plausible failure: the sidebar reappears at a stale width on
remount, or the doc viewport mis-aligns mid-transition.

**If this leaks, the user's data is exposed via:** N/A — this change is purely
CSS / layout. No data crosses a trust boundary. No new persistence keys, no new API
surface, no new auth path.

**Brand-survival threshold:** none — UI polish on a navigation control. A single
broken-toggle incident is a paper cut, not a brand event. Existing
`kb-sidebar-collapse.test.tsx` will gate against regressions of the
collapse/expand behavior; this plan adds tests for the transition contract on top.

Sensitive-path check: edited files (`apps/web-platform/components/kb/**`,
`apps/web-platform/hooks/use-kb-layout-state.tsx`) do not match the canonical
sensitive-path regex from `plugins/soleur/skills/preflight/SKILL.md` Check 6
(no `migrations/`, `auth/`, `payment`, `webhook`, RLS, headers). No
`threshold: none, reason: …` scope-out bullet is required.

## Research Reconciliation — Spec vs. Codebase

Verified the four load-bearing claims this plan relies on before drafting:

| Claim | Reality | Plan response |
| --- | --- | --- |
| Settings sidebar uses CSS width transition with 200 ms duration | `apps/web-platform/components/settings/settings-shell.tsx:38-40` — `md:transition-[width] md:duration-200 md:ease-out`; toggles `md:w-0 md:border-r-0` ↔ `w-48`; inner wrapper has fixed `w-48 px-4 py-5`. Confirmed. | Mirror this exact recipe on the KB sidebar `<aside>` (replacing the desktop `<Panel>` wrapper). |
| KB desktop sidebar uses `react-resizable-panels` `<Panel>` with `collapsedSize="0%"` and snaps on collapse | `apps/web-platform/components/kb/kb-desktop-layout.tsx:52-66` — `<Panel collapsible collapsedSize="0%" panelRef={sidebarPanelRef}>`; toggle calls `sidebarPanelRef.current.collapse()` / `.expand()` from `apps/web-platform/hooks/use-kb-layout-state.tsx:153-163`. Confirmed. | Remove the file-tree `<Panel>` wrapper; replace with a regular `<aside>` outside the resizable `<Group>`. The doc-viewer + chat-panel `<Group>` remains so drag-resize between those two siblings is preserved. |
| `react-resizable-panels` v4.10 supports collapse/expand animation natively | `apps/web-platform/node_modules/react-resizable-panels/dist/react-resizable-panels.d.ts:206-216` — `collapse()` and `expand()` jsdoc says nothing about animation; the library snaps. No `animate` / `transitionDuration` prop on `PanelProps` (lines 247-280). Confirmed: library does NOT animate. | Reason for choosing the CSS-transition refactor rather than "keep Panel + add transition prop." |
| KB sidebar collapse state is persisted to localStorage like Settings is | `apps/web-platform/hooks/use-kb-layout-state.tsx:55` — `const [kbCollapsed, setKbCollapsed] = useState(false)`. NOT persisted. Settings uses `useSidebarCollapse("soleur:sidebar.settings.collapsed")` from `apps/web-platform/hooks/use-sidebar-collapse.ts`. **Drift from settings pattern.** | The bug-as-reported is only about transition. Persistence is filed as an explicit Non-Goal with a tracking issue (see Non-Goals) so it does not silently bloat this PR but is also not forgotten. |

## Implementation Phases

### Phase 1 — Refactor KB desktop layout to drop the file-tree `<Panel>`

**Files to edit:**

- `apps/web-platform/components/kb/kb-desktop-layout.tsx` — replace the file-tree
  `<Panel>` + its `<ResizeHandle>` with a plain `<aside>` rendered as a flex
  sibling of the resizable `<Group>` that holds the doc + chat panels. The `<aside>`
  is the transition target.
- `apps/web-platform/hooks/use-kb-layout-state.tsx` — `toggleKbCollapsed` no longer
  reads `sidebarPanelRef.current?.isCollapsed()`. It becomes a pure
  `setKbCollapsed((prev) => !prev)` on both desktop and mobile (matching the
  settings hook shape). Remove `sidebarPanelRef` from the returned state shape.
  Remove the `setKbCollapsed(size.asPercentage < 1)` `onResize` callback because
  there is no longer a resizable file-tree panel.

**Files to create:** none.

**Approach notes:**

- The new desktop structure becomes:

  ```text
  <div className="flex h-full">                          {/* mobile + desktop root */}
    <aside className="...md:transition-[width]...">      {/* file-tree, animated */}
      <div className="w-72 px-... py-...">               {/* fixed-width inner wrapper */}
        <KbSidebarShell onCollapse={toggleKbCollapsed} />
      </div>
    </aside>
    <Group orientation="horizontal" className="...flex-1...">   {/* doc + chat */}
      <Panel minSize="40%">{KbDocShell}</Panel>
      {showChat && contextPath && (<>
        <ResizeHandle />
        <Panel panelRef={chatPanelRef} ...>{KbChatContent}</Panel>
      </>)}
    </Group>
  </div>
  ```

- The fixed inner-wrapper width is the load-bearing detail. Settings uses `w-48`;
  KB currently sizes the panel at `defaultSize={showChat ? "18%" : "22%"}`. On a
  1440 px viewport that is ~258–317 px. Choose a single fixed width that lands in
  that range — `md:w-72` (288 px) — and note that file names will wrap one tier
  earlier than they did when the panel was 317 px. If reviewers push back on
  wrapping, swap to `md:w-80` (320 px); both are inside the settings
  300-ish-pixel ballpark and avoid an awkward `min/max-w-[18rem]` clamp.

### Research Insights

**Two-layer width recipe (lifted verbatim from settings PR #3585):**

```tsx
<aside
  inert={kbCollapsed || undefined}
  className={`hidden shrink-0 border-r border-soleur-border-default md:block md:overflow-hidden
    md:transition-[width] md:duration-200 md:ease-out
    ${kbCollapsed ? "md:w-0 md:border-r-0" : "md:w-72"}`}>
  <div className="w-72 px-3 py-4">
    {/* Inner wrapper. Width AND padding live HERE on the always-on base classes,
        NEVER on a conditional. KbSidebarShell already has its own internal
        py-4/px-3 spacing via `<header>` — keep this wrapper minimal so the SETTINGS-
        style "header anchored at (top-left during transition)" invariant holds.
        Per #3584: padding on a conditional would snap the header to (0, 0) on
        frame 1 while the eased width lags behind. */}
    <KbSidebarShell onCollapse={toggleKbCollapsed} />
  </div>
</aside>
```

**Why the nav itself MUST NOT carry padding (#3585):**

`box-sizing: border-box` (Tailwind default since v3) makes padding count toward
the box width. With `width: 0` + `padding: 16px 0`, the rendered width is
`max(0, 2 × 16) = 32px`. Users see a 32 px sliver showing the first letter of
each file-tree entry at the viewport edge during the entire 200 ms transition,
and again any time the sidebar is in the collapsed state. The fix is what
settings landed on: padding ONLY on the inner wrapper, nav has none. The
test in Phase 3 codifies this with the same assertion that
`settings-sidebar-collapse.test.tsx:160-174` uses.

**Why `md:overflow-hidden` on the nav is load-bearing:**

Per the flexbox spec, `overflow: hidden` nullifies the `min-width: auto`
default, so the nav can reach `width: 0` without its min-content forcing a
minimum. Without `overflow-hidden`, the nav cannot collapse below the
content's intrinsic min-width (the longest file name).

**KbSidebarShell internal layout — already compatible:**

`KbSidebarShell` already renders as `flex h-full flex-col` with its own header
`px-4 pb-3 pt-4`, search overlay `px-3 pb-3`, and tree `px-2 pb-4` (file:
`apps/web-platform/components/kb/kb-sidebar-shell.tsx:14-49`). It will render
correctly inside a `w-72` wrapper without modification — the inner padding
choices stay where they are.
- The `<aside>` carries `md:transition-[width]`, `md:duration-200`, `md:ease-out`,
  `md:overflow-hidden`, and toggles `md:w-0 md:border-r-0` ↔ `md:w-72` exactly as
  the settings nav does at `settings-shell.tsx:38-40`.
- Apply `inert={kbCollapsed || undefined}` on the `<aside>` so the file tree
  cannot be focus-trapped when fully collapsed — matches `settings-shell.tsx:37`
  and matches the existing mobile `<aside>` at `kb-mobile-layout.tsx:33`.
- Keep `KbSidebarShell` itself untouched — it is presentation only and already
  works as a flex-column inside a fixed-width wrapper.
- The doc viewer is now inside a `<Group>` instead of being the second `<Panel>`
  of the outer `<Group>`. The doc-vs-chat resize handle still works because the
  `<Group>` containing `<Panel minSize="40%">` (doc) and the chat `<Panel>` is
  intact. **What goes away:** dragging between sidebar and doc viewer. The
  sidebar is now toggle-only, matching settings.

### Phase 2 — Animate the doc viewport's left-anchor during the transition

**Files to edit:**

- `apps/web-platform/components/kb/kb-doc-shell.tsx` — currently applies a static
  `pl-10` when `collapsed`. Add a `md:transition-[padding] md:duration-200
  md:ease-out` class on the content well so the doc viewport's left edge slides
  in sync with the sidebar's width, mirroring the
  `settings-shell.tsx:106` content-area `md:transition-[padding]` recipe.
- Same file — when **expanded**, the doc viewport has its left edge against the
  sidebar's right border; no extra padding is needed because the sidebar provides
  it. When collapsed, the existing `pl-10` reserves space for the floating
  "Expand file tree" chevron. **Both states must render the same transition class
  set** so React does not toss the transition between mounts (this was the bug
  fixed in PR #3573 for settings — keep the transition class on the element in
  both states, only toggle the padding value).

**Approach notes:**

- The KB collapsed-state expand chevron at `kb-doc-shell.tsx:27-48` is `absolute
  left-2 top-5` — identical absolute geometry to the settings expand chevron at
  `settings-shell.tsx:108-118`. No alignment changes are required (the chevron
  alignment work already landed for KB in PRs #1850-class history).

### Research Insights

**Why `md:transition-[padding]` must be present in BOTH states (#3573 +
#3584):**

The settings PR chain showed that toggling the `md:transition-[padding]` class
conditionally (only when collapsed) causes React to throw away the mid-render
transition because the element's class set differs. The fix: keep the
transition class on the element in BOTH states; only the value of `pl-*`
toggles. Apply the same to `KbDocShell`'s outer content well:

```tsx
<div
  className={`min-h-0 flex-1 overflow-y-auto
    md:transition-[padding] md:duration-200 md:ease-out
    ${collapsed ? "md:pl-10" : ""}`}
>
  ...
</div>
```

Note the second arm is empty (no `md:pl-0` token) because the absent class
defaults to 0 padding and `padding-left: 0` ↔ `padding-left: 2.5rem` is a
valid transition. Tailwind's JIT will emit the transition rule from
`md:transition-[padding]` regardless of which side `pl-10` is on.

**Why we do NOT replicate the settings `md:pl-[14.5rem]` anchor recipe (#3579
does NOT apply here):**

Settings's `md:pl-[14.5rem]` on the collapsed content area is solving a
different problem: `<div className="mx-auto max-w-2xl">` in settings re-centers
continuously as its parent flex grows, so the content drifts ~100 px leftward
over the transition. The KB doc viewer is NOT `mx-auto max-w-2xl`-wrapped —
it renders the document directly inside the content well (file:
`apps/web-platform/components/kb/kb-doc-shell.tsx:49-55`), so there is no
horizontal-center re-flow to anchor against. The `pl-10` collapsed-state
padding is solely to reserve space for the absolute-positioned expand chevron
at `absolute left-2 top-5`, not for centering geometry.

**Caveat — markdown / PDF children of `KbDocShell` may render their own
`mx-auto max-w-*` containers.** If they do, the user will perceive the
settings-style horizontal drift when toggling the sidebar. Phase 4 manual
verification adds a check for this; the mitigation, if needed, is to add
a `mx-auto`-anchoring `pl-[<width-of-sidebar>+padding]` to the content well
in the collapsed state (mirroring settings's `md:pl-[14.5rem]`). Listed as
Risk + Sharp Edge below — not implemented preemptively because it adds
weight that may be unneeded.

### Phase 3 — Tests

**Files to create:**

- `apps/web-platform/test/kb-sidebar-transition.test.tsx` — new file. Mocks
  `useMediaQuery: () => true` (desktop mode) so the rendered tree includes
  `KbDesktopLayout`. Asserts the transition contract:
  - The `<aside>` has `md:transition-[width]`, `md:duration-200`,
    `md:ease-out` in **both** open and collapsed states (the #3573 lesson:
    transition class must be unconditional).
  - The `<aside>` collapses to `md:w-0 md:border-r-0` with
    `md:overflow-hidden` so the file tree clips right-to-left and
    contributes zero width.
  - The `<aside>` carries NO `px-*` / `py-*` (the #3585 lesson: padding on the
    `<aside>` + `box-border` + `md:w-0` forces a 32 px sliver).
  - The fixed-width inner wrapper carries `w-72` (or chosen width) so the
    contents stay anchored during the transition.
  - `KbDocShell`'s content well carries
    `md:transition-[padding] md:duration-200 md:ease-out` in both states.

**Files to edit:**

- `apps/web-platform/test/kb-sidebar-collapse.test.tsx` — keep the existing
  mobile-mode tests untouched. The collapse-toggle-behavior asserts continue
  to validate the click + keyboard + input-focus + mobile class-swap
  contracts. Do not migrate these into the new file.

**Test runner:** verified `apps/web-platform/package.json` exposes
`"test": "vitest run"`. Per the AGENTS.md sharp-edge "always reference
`package.json scripts.test`," the GREEN gate is `bun run --cwd apps/web-platform
test apps/web-platform/test/kb-sidebar-collapse.test.tsx`.

### Research Insights

**JSDOM limitation — assertions are className-only, NOT geometry (#3557 / #3562
learning):**

`getBoundingClientRect()` returns zeros in JSDOM. The settings PR chain
established the convention that unit tests assert **className/transition
tokens**, not pixel-level alignment. Phase 3 tests follow suit. Per the learning
at `knowledge-base/project/learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`:

> classname tests are regression gates; Playwright is the alignment source of
> truth.

If the dev server is broken (see Risk re. #3562 below), Playwright verification
is degraded; unit tests are the regression gate that prevents future-KB-style
polish PRs from silently regressing the transition contract.

**Test fixture pattern — mirror settings tests verbatim:**

The settings test suite at `apps/web-platform/test/settings-sidebar-collapse.test.tsx`
lines 149-197 is the canonical reference. Lift each assertion shape:

```ts
describe("sidebar transition contract", () => {
  it("aside has md:transition-[width] in both open and collapsed states", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    const aside = document.querySelector("aside");
    expect(aside).not.toBeNull();
    expect(aside?.className).toMatch(/(?:^|\s)md:transition-\[width\](?:\s|$)/);
    expect(aside?.className).toMatch(/\bmd:duration-200\b/);
    expect(aside?.className).toMatch(/\bmd:ease-out\b/);
    // After collapse, the transition classes MUST still be present (the #3573
    // bug: conditional transition class throws the animation away).
    await userEvent.click(screen.getByLabelText("Collapse file tree"));
    const asideAfter = document.querySelector("aside");
    expect(asideAfter?.className).toMatch(/(?:^|\s)md:transition-\[width\](?:\s|$)/);
  });

  it("collapsed aside contributes zero width (md:w-0 + md:border-r-0 + md:overflow-hidden)", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    await userEvent.click(screen.getByLabelText("Collapse file tree"));
    const aside = document.querySelector("aside");
    expect(aside?.className).toMatch(/\bmd:w-0\b/);
    expect(aside?.className).toMatch(/\bmd:overflow-hidden\b/);
    expect(aside?.className).toMatch(/\bmd:border-r-0\b/);
  });

  it("aside has NO padding (so md:w-0 collapses fully); inner wrapper holds w-72 + padding", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    const aside = document.querySelector("aside");
    // Per #3585: padding on the aside would force a 32px sliver via box-border.
    expect(aside?.className).not.toMatch(/\bpx-\d\b/);
    expect(aside?.className).not.toMatch(/\bpy-\d\b/);
    // The fixed-width inner wrapper holds the padding so contents stay anchored
    // at (top-left) the entire 200ms — clipped right-to-left as the aside collapses.
    const wrapper = aside?.firstElementChild as HTMLElement | null;
    expect(wrapper).not.toBeNull();
    expect(wrapper?.className).toMatch(/\bw-72\b/);
  });

  it("KbDocShell content well carries md:transition-[padding] in both states", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    // Open state
    const wellOpen = document.querySelector(".min-h-0.flex-1.overflow-y-auto");
    expect(wellOpen?.className).toMatch(/(?:^|\s)md:transition-\[padding\](?:\s|$)/);
    expect(wellOpen?.className).toMatch(/\bmd:duration-200\b/);
    expect(wellOpen?.className).toMatch(/\bmd:ease-out\b/);
    // Collapsed state — class must still be present (the #3573 lesson)
    await userEvent.click(screen.getByLabelText("Collapse file tree"));
    const wellCollapsed = document.querySelector(".min-h-0.flex-1.overflow-y-auto");
    expect(wellCollapsed?.className).toMatch(/(?:^|\s)md:transition-\[padding\](?:\s|$)/);
  });
});
```

**Important — test-environment caveat.** The current
`kb-sidebar-collapse.test.tsx` mocks `useMediaQuery: () => false` (mobile mode)
so that `KbLayout` renders `<KbMobileLayout>`, NOT `<KbDesktopLayout>`. The
desktop layout is the surface this plan rewrites. The new transition-contract
tests therefore need a **second `describe` block** with a desktop-mode mock,
or a per-test `vi.doMock(...)` swap. The settings tests don't have this
complication because settings uses the same DOM in both viewports (just the
mobile-tab-bar is shown on small screens).

Recommended approach: add a NEW test file
`apps/web-platform/test/kb-sidebar-transition.test.tsx` that mocks
`useMediaQuery: () => true` and exercises only `KbDesktopLayout` directly
(or `KbLayout` with the desktop mock), so the existing mobile-mode tests in
`kb-sidebar-collapse.test.tsx` keep passing untouched. The new file owns the
transition-contract assertions; the existing file keeps the
collapse-toggle-behavior assertions. Splitting avoids fighting vi.mock
hoisting (mocks are module-scope; toggling them mid-file is fragile).

### Phase 4 — Manual visual confirmation

**Files to edit:** none. This is a smoke check after Phases 1-3 land.

- Run `bun run --cwd apps/web-platform dev` and visit `/dashboard/kb` on a
  ≥768 px viewport.
- Toggle the sidebar via the chevron and via `⌘B`. Confirm: smooth 200 ms width
  transition, file tree clips right-to-left during collapse (no flash to width
  0 then crossfade), doc viewport's left edge slides in sync with the sidebar
  edge.
- Mobile (<768 px): confirm the existing `hidden`/`block` class swap still
  works — the transition classes are `md:`-prefixed, so they should be inert
  below the breakpoint. The `inert` attribute should still toggle on the mobile
  `<aside>` so the file tree cannot be focused while a doc is showing.
- Both states with chat panel open: confirm the doc-vs-chat resize handle in
  the inner `<Group>` still drags correctly.
- **Open a long markdown doc AND a PDF doc**, toggle the sidebar, and confirm
  the rendered content does NOT drift horizontally during the transition. If
  it does, the doc content has its own `mx-auto max-w-*` wrapper and the
  #3579-style anchor pad is required (see Risk + Sharp Edge). Add the fix
  before merge; do not defer.
- **Dev-server caveat (#3562).** If `bun run --cwd apps/web-platform dev`
  fails with the `instrumentation.ts` ESM/CJS error, use a Vercel preview
  build of the branch instead. Document the blocker in the PR body
  (`#3562`) so the reviewer knows local QA is degraded. Unit tests
  remain the regression gate.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open --json
number,title,body --limit 200` and grepped each entry's body against the
`Files to Edit` list (`kb-desktop-layout.tsx`, `kb-doc-shell.tsx`,
`use-kb-layout-state.tsx`, `kb-sidebar-collapse.test.tsx`). Zero matches.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] On `/dashboard/kb` at ≥768 px, clicking the collapse chevron or pressing
      `⌘B` produces a smooth 200 ms ease-out width animation on the file-tree
      sidebar. No snap, no flash.
- [ ] The doc viewport's left edge slides in sync with the sidebar edge — no
      mid-transition gap or jump.
- [ ] When the sidebar is fully collapsed, the `<aside>` contributes zero
      rendered width (no border sliver, no padding-induced 32 px ghost).
      Verified by `kb-sidebar-collapse.test.tsx` assertions on `md:w-0`,
      `md:border-r-0`, `md:overflow-hidden`.
- [ ] In the collapsed state, the floating "Expand file tree" chevron renders at
      `absolute left-2 top-5` and stays aligned with the main-nav chevron above.
      Existing chevron-alignment tests in `kb-sidebar-collapse.test.tsx`
      continue to pass.
- [ ] The chat panel, when open, still resizes against the doc panel via the
      `<Group>`'s inner `<ResizeHandle>`. (The sidebar-vs-doc resize handle
      goes away by design — see Non-Goals.)
- [ ] Mobile (<768 px) `hidden`/`block` class swap on `<aside>` is unchanged.
      `kb-sidebar-collapse.test.tsx` "preserves mobile class-swap behavior"
      asserts this and must stay green.
- [ ] `bun run --cwd apps/web-platform test
      apps/web-platform/test/kb-sidebar-collapse.test.tsx` is green.
- [ ] `bun run --cwd apps/web-platform tsc --noEmit` is green.

### Post-merge (operator)

- None. No external service config, no migration, no deploy step. Vercel
  preview will pick up the change at PR open.

## Non-Goals

- **Persist `kbCollapsed` to localStorage.** Settings uses
  `useSidebarCollapse("soleur:sidebar.settings.collapsed")`; KB currently uses
  bare `useState(false)`. Adding persistence is a closely-related drift from the
  settings pattern but is **out of scope** for the transition fix because (a)
  the user-reported bug is only about the transition, and (b) persistence
  changes session behavior (refresh keeps the sidebar collapsed) which deserves
  its own UX decision. **Tracking issue:** to be filed at plan-commit time as
  `feat(kb): persist file-tree sidebar collapse state to localStorage`, label
  `area/kb`, milestone matching `Phase 5 — Polish` if present in
  `knowledge-base/product/roadmap.md`, else `Post-MVP / Later`.

- **Drag-to-resize the file-tree sidebar.** Today the sidebar's width is
  draggable between 10 % and 30 % of the viewport. After this refactor the
  sidebar is a fixed `md:w-72` toggle. **Tracking issue:** to be filed as
  `feat(kb): restore drag-resize on file-tree sidebar`, label `area/kb`,
  milestone `Post-MVP / Later`. Re-evaluation criterion: if 2+ users ask in
  Discord for a wider file tree, restore drag-resize via a wrapper that
  preserves the CSS-width transition (likely a thin `useResize` hook setting
  a CSS variable; out of scope for this plan).

- **Animate the chat panel open/close.** The chat panel is mount/unmount via
  `{showChat && <Panel>}` in `kb-desktop-layout.tsx:84-102`. Animating its
  open/close is a separate concern.

- **Change settings sidebar behavior.** Settings is the reference; this plan
  changes nothing under `apps/web-platform/components/settings/`.

## Risks

- **`react-resizable-panels` `<Group>` re-layout when its `Panel` count changes
  (showChat true → false).** The chat Panel is mount/unmount-conditional today
  and that still holds. The new outer flex container (`<aside>` + `<Group>`)
  should be insulated from this re-layout because the `<aside>` is no longer
  part of the `<Group>`. **Verification:** Phase 4 manual check covers
  open-chat → close-chat → toggle-sidebar in sequence.

- **`md:w-72` fixed width may feel narrow on 1080 p displays compared to today's
  ~317 px panel.** Mitigation: choose `md:w-72` initially; if reviewers or
  Discord feedback push back, upgrade to `md:w-80` in the same PR (single-class
  swap, no regression risk).

- **Server-side render width vs. client-side hydration.** The settings sidebar
  starts expanded (`useSidebarCollapse` starts `false`, hydrates from localStorage
  post-mount). KB will continue to start expanded with this plan since
  persistence is out of scope. No SSR hydration mismatch risk.

- **`inert` attribute support.** Confirmed to ship in all evergreen browsers
  (Chrome 102+, Firefox 112+, Safari 15.5+). Settings already uses `inert` at
  `settings-shell.tsx:37` — no new compatibility concern.

- **`mx-auto max-w-*` content inside the doc viewer may drift horizontally
  during the transition (#3579 echo).** The doc-shell content well is
  `flex-1`, so it grows continuously as the sidebar collapses. If any child
  rendered into it uses `mx-auto max-w-*`, the child's screen-x position
  shifts ~144 px leftward over 200 ms — perceived as "content flashing to
  where the sidebar was." Mitigation, if visual QA shows the drift:
  add a collapsed-state `md:pl-[<sidebar-width-in-rem + open-pad>]` to the
  KB content well (settings's value was `14.5rem` for a `w-48` sidebar +
  `px-10` open pad; KB would be `w-72` ÷ 16 = 18rem + chosen pad). Defer
  unless Phase 4 shows the drift.

- **Dev-server bug (#3562) blocks local Playwright QA.** Per
  `knowledge-base/project/learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`,
  `npm run dev` on `apps/web-platform/` currently fails with
  `ReferenceError: require is not defined in ES module scope` from
  `.next/server/instrumentation.js`. This blocks the Phase 4 visual
  verification on the local machine. Mitigation: accept degraded QA via
  unit-test className contracts (Phase 3 covers this); attach a Vercel
  preview link to the PR for the reviewer to verify in a browser; if the
  reviewer asks for screenshots, document `#3562` as the blocker in the
  PR body and defer screenshots until `#3562` is resolved. This is the same
  posture the settings PR chain (#3573, #3579, #3584, #3585) took.

- **Test environment + media-query mocking.** Existing
  `kb-sidebar-collapse.test.tsx` mocks `useMediaQuery: () => false` (mobile)
  so the `<KbDesktopLayout>` branch is never exercised. The transition
  contract being added in this plan lives in the desktop layout. Create a
  separate test file with a desktop-mode mock (per Phase 3) rather than
  trying to toggle the mock mid-file.

- **Drag-resize affordance loss may be noticed by power users.** Today the
  KB sidebar's width can be dragged between 10 % and 30 % of the viewport.
  After this refactor it is a fixed `md:w-72` toggle. Settings has been
  toggle-only since launch and has not produced complaints, so the user-
  facing risk is small — but a power user accustomed to dragging the sidebar
  wider may file an issue. Pre-emptively filed as a non-goal with a tracking
  issue (see Non-Goals).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
  (This plan's section is filled with `threshold: none` and a concrete
  failure-mode artifact.)
- **Keep transition classes on the element in BOTH open and collapsed states.**
  PR #3573 fixed exactly this for settings — the transition class was being
  swapped conditionally and React tossed the animation between renders. The
  Phase 2 approach note above already calls this out; flag it again at PR
  review time if a reviewer suggests conditionally toggling
  `md:transition-[padding]`.
- **Do not silently re-introduce a sliver of nav padding.** Per the settings
  tests at `settings-sidebar-collapse.test.tsx:160-174`, the nav element MUST
  NOT carry `px-4` / `py-5`; the padding lives on the inner fixed-width
  wrapper. With `box-border` plus `md:w-0`, a `px-4` on the outer would force
  the box to a 32 px min-visible width. The KB plan inherits this constraint
  directly — the new `<aside>` carries `md:overflow-hidden md:w-0` only, the
  wrapper inside carries the padding.
- **Verify both toggle states in Phase 4.** Per AGENTS.md sharp edge "when a
  plan addresses alignment of a toggleable UI control, verify alignment in
  BOTH toggle states." Phase 4 explicitly covers expanded + collapsed + chat
  open + chat closed.

- **Do not chain conditional transitions.** The settings chain spent THREE
  PRs (#3573, #3584, #3585) learning that conditional class swaps interact
  badly with CSS transitions. Two failure modes to avoid in this plan:
  (a) toggling `md:transition-[width]` itself on a condition — React tosses
  the running animation between renders; (b) toggling padding tokens on a
  condition while leaving the transition class only on one side — content
  snaps on frame 1 then eases on subsequent frames. The plan's recipe puts
  every transition + duration + ease class on the always-on base, with
  only the value of width/padding toggled. Reviewers should flag any new
  conditional `transition-*` / `duration-*` / `ease-*` token at PR time.

- **If a markdown / PDF child uses `mx-auto`, settings's `pl-[14.5rem]`
  recipe is the prescribed fix — but defer it.** Adding the anchor padding
  preemptively means the doc viewport has a wide left gutter when the sidebar
  is collapsed. That visual cost is only worth paying if the drift is
  perceptible. Phase 4 manual verification is the gate. If drift exists,
  the fix is one line: change the `kbDocShell` content well to
  `md:pl-[18.625rem]` (the `w-72 + px-3` settings-equivalent for KB) when
  `collapsed` is true, with the existing `md:transition-[padding]` already
  in place handling the easing.

- **`react-resizable-panels` `<Group>` does not animate inner Panel mount /
  unmount.** When the chat panel opens/closes (`showChat` toggle), the inner
  `<Group>` re-lays out its panels instantly. This was already the case
  before this plan and is out of scope. Mention here so reviewers don't ask
  for the chat-panel slide-in as part of this work.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — front-end CSS / layout refactor with
no data, security, payments, marketing, or product-flow surface area. Settings
pattern is the established precedent; this plan transplants it onto a sibling
component.
