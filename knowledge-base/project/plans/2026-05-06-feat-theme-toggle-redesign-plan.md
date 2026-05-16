---
type: feat
status: ready
branch: feat-theme-toggle-redesign
issue: 3316
pr: 3315
brainstorm: knowledge-base/project/brainstorms/2026-05-06-theme-toggle-redesign-brainstorm.md
spec: knowledge-base/project/specs/feat-theme-toggle-redesign/spec.md
mock: knowledge-base/product/design/web-platform/theme-toggle-mock.html
requires_cpo_signoff: false
---

# feat: Theme Toggle Redesign — Sidebar-Header Pill + Collapsed Cycle Button

## Overview

Move the dashboard theme toggle from the sidebar footer to the sidebar header. Expanded sidebar renders a 3-segment rounded pill (Dark / Light / System); collapsed sidebar renders a single 36px circular cycle button. Theme tokens (`--soleur-*` light + dark values) are unchanged. UX validated via the interactive mock at `knowledge-base/product/design/web-platform/theme-toggle-mock.html`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a missing or non-interactive theme control on the sidebar — annoying but recoverable; theme persistence in `theme-provider.tsx` is untouched.
- **If this leaks, the user's data is exposed via:** N/A — feature touches no credentials, auth, data, payments, or user-owned resources.
- **Brand-survival threshold:** none. Reason: pure UI relocation/restyle of an existing accessible control; the redesign actively *fixes* the worst case (collapsed-sidebar invisibility) named in the brainstorm framing. No sensitive-path globs match.

## Files to Edit

- `apps/web-platform/components/theme/theme-toggle.tsx` — accept a **required** `collapsed: boolean` prop. When `false`, render today's exact 3-segment pill JSX (no class changes, no key handler changes, no `SEGMENTS` change). When `true`, render a single 36×36 `rounded-full` button that cycles `Dark → Light → System` on click and calls `setTheme(next.value)`.
- `apps/web-platform/app/(dashboard)/layout.tsx` — **two adjacent hunks only, per spec TR7:**
  1. **Insert** `<ThemeToggle collapsed={collapsed} />` (wrapped in a 1px-bordered container) between the brand-row `</div>` and the `<nav>`.
  2. **Delete** the existing footer-block mount (lines ~323–333: the `{!collapsed && (<div>…<p>Theme</p><ThemeToggle /></div>)}` block, including its label `<p>`).

  Do NOT modify: brand row (incl. its `safe-top` and `py-5` padding — see AC), collapse button, mobile drawer top bar, mobile-close button, nav items, ConversationsRail mount, footer email line, status link, docs link, sign-out button.
- `apps/web-platform/test/components/theme-toggle.test.tsx` — keep all existing pill-mode tests green (rendered without the `collapsed` prop won't compile after the prop is required, so all existing renders must pass `collapsed={false}`). Add a `describe("collapsed mode")` block with one behavioral test: cycle advances `system → dark → light → system` over three clicks, asserting `localStorage.getItem("soleur:theme")` after each.

## Files to Create

- None.

## Research Reconciliation — Spec vs. Codebase

The spec's line-number references for both insertion (~250–274) and deletion (~323–333) anchors in `(dashboard)/layout.tsx` were verified directly against the worktree before the plan was written. No drift.

## Open Code-Review Overlap

TR7's narrow scope keeps `#3039` (signOut Sentry mirror) and `#2193` (banner consolidation) disjoint from this PR's hunks; both stay open.

## Implementation Phases

### Phase 1 — Component rewrite (`theme-toggle.tsx`)

1. Change the function signature to `export function ThemeToggle({ collapsed }: { collapsed: boolean })`. Required, no default — every call site is forced to think about which mode it wants.
2. When `collapsed === false`, return today's exact `<div role="group" aria-label="Theme">…</div>` block — same `SEGMENTS`, same `useRef`, same `handleKeyDown`. No behavioral change to expanded mode.
3. When `collapsed === true`, return a single button:
   - `data-testid="theme-cycle-button"` (mandatory — used by Phase 3 query).
   - 36×36, `rounded-full`, `border border-soleur-border-default`, `bg-soleur-bg-surface-2`, `text-soleur-accent-gold-fg`, hover `box-shadow` matching the pill's active-segment ring (`ring-1 ring-inset ring-soleur-border-emphasized` equivalent). **Use Tailwind utility classes only — no inline `style={{ color: "var(--soleur-...)" }}`** (raw vars would trip the CSP regression test in `theme-csp-regression.test.tsx`).
   - Inner SVG mirrors the *current* mode's icon (Moon / Sun / Monitor — reuse the file's existing `MoonIcon` / `SunIcon` / `MonitorIcon` components).
   - On click: compute `next = SEGMENTS[(SEGMENTS.findIndex(s => s.value === theme) + 1) % SEGMENTS.length]`, then `setTheme(next.value)`.
   - `aria-label={"Theme: " + currentLabel}` (e.g., `Theme: Dark`). Native `<button>` semantics handle the rest. No `title` attribute (redundant with `aria-label` on desktop, useless on touch).

### Phase 2 — Layout move (`(dashboard)/layout.tsx`)

1. Insert immediately after the brand-row `</div>` (the `</div>` at line ~274, closing the `<div className="flex items-center justify-between …">` opened at line 250) and before the `<nav>`:

   ```tsx
   {/* Theme toggle — sidebar header. Pill in expanded state, single
       cycle button in collapsed state. Replaces the prior footer-block
       mount. See spec TR7. */}
   <div className={`border-b border-soleur-border-default ${collapsed ? "px-2 py-3" : "px-3 py-3"}`}>
     <ThemeToggle collapsed={collapsed} />
   </div>
   ```

   The new block carries its own `py-3`. Do **not** touch the brand-row `py-5` to "fix the spacing" — the brand-row's padding is its own concern, the toggle block's padding is its own.

2. Delete the old footer-block mount at lines ~323–333 (the `{!collapsed && (…)}` wrapper including the `<p>Theme</p>` label).

### Phase 3 — Tests (`theme-toggle.test.tsx`)

1. Update every existing `<ThemeToggle />` to `<ThemeToggle collapsed={false} />` (the prop is now required — without this, the file won't compile).
2. Add a `renderToggleCollapsed()` helper next to `renderToggle()` that mounts `<ThemeToggle collapsed />`.
3. Add `describe("collapsed mode")` with one test:

   > **cycle-advances-mode:** fresh `localStorage` (provider default = `system`). Render collapsed. Query the cycle button via `getByTestId("theme-cycle-button")`. Click → assert `localStorage.getItem("soleur:theme") === "dark"`. Click → assert `"light"`. Click → assert `"system"`. (Sequence: `system → dark → light → system` per `SEGMENTS` order.)

   No string-equality assertions on `aria-label`. The behavior under test is "click cycles the mode," not "the label says the right thing."

## Test Strategy

- `bun test apps/web-platform/test/components/theme-toggle.test.tsx` — primary unit coverage.
- `bun test apps/web-platform/test/dashboard-sidebar-collapse.test.tsx` AND `apps/web-platform/test/dashboard-layout-drawer-rail.test.tsx` — pre-existing layout tests. Verified at plan time: neither file uses `getAllByRole("button")`, `queryAllByRole("button")`, or any button-count assertion, so adding the cycle button to the collapsed-mode render does not change their assertion surface. Both files should pass without edits; if they break, the failure surfaces in their own selector queries — fix there, not in `layout.tsx`.
- `theme-csp-regression.test.tsx` and `theme-provider.test.tsx` — should remain untouched and green.
- Manual QA: load `/dashboard` in both themes, click each pill segment, then collapse the sidebar (`⌘B`) and confirm the cycle button walks `Dark → Light → System` (or whichever sequence — starting state depends on saved theme).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `theme-toggle.tsx` accepts a **required** `collapsed: boolean`; expanded-mode JSX is byte-for-byte equivalent to today.
- [ ] `(dashboard)/layout.tsx` diff against main shows exactly two hunks: one insertion between brand-row and `<nav>`, one deletion of the old footer block. Verified via `git diff main -- 'apps/web-platform/app/(dashboard)/layout.tsx'` (single-quote the path — bare parens are zsh glob qualifiers).
- [ ] **Brand-row `py-5` (line 250) is unchanged.** No spacing/padding tidies on any line outside the two prescribed hunks.
- [ ] Old footer-block `<p>Theme</p>` label and `<ThemeToggle />` mount are fully removed (no orphan label).
- [ ] Cycle button's color tokens are applied via Tailwind utility classes, not raw `var(--soleur-*)` inline styles (CSP regression test would fail otherwise).
- [ ] `data-testid="theme-cycle-button"` is present in collapsed-mode render.
- [ ] `theme-toggle.test.tsx` passes for both pill mode (existing tests, now passing `collapsed={false}` explicitly) and collapsed mode (new cycle-advance test).
- [ ] No changes to `--soleur-*` token values, `globals.css`, `theme-provider.tsx`, or theme regression test files.
- [ ] PR body uses `Closes #3316` and references the mock at `knowledge-base/product/design/web-platform/theme-toggle-mock.html`.

### Post-merge (operator)

- [ ] In production: open `/dashboard`, verify pill at top of sidebar in both themes; click each segment.
- [ ] In production: collapse sidebar (`⌘B`); verify cycle button replaces the pill at the same vertical position; click three times and confirm the cycle.

## Domain Review

**Domains relevant:** none.

Single-component visual redesign on an already-shipped capability. No new skill/agent/user-facing capability per `hr-new-skills-agents-or-user-facing` (this is iteration). No marketing/legal/finance/sales/support/ops surface.

**Brainstorm carry-forward:** brainstorm explicitly recorded "Assessed: none" with rationale. Carry-forward applied.

### Product/UX Gate

**Tier:** advisory (modifies an existing UI without adding a new page/flow/component file; no `components/**/*.tsx` create paths trigger mechanical BLOCKING).
**Decision:** auto-accepted — the interactive mock at `knowledge-base/product/design/web-platform/theme-toggle-mock.html` (real production tokens, both themes side-by-side, both expanded and collapsed states) was reviewed and approved by the user before this plan was invoked.
**Agents invoked:** none.
**Skipped specialists:** `ux-design-lead` (mock higher-fidelity than a wireframe; uses real tokens), `copywriter` (no copy added), `spec-flow-analyzer` (no new flow).
**Pencil available:** N/A.

## Risks

- **TR7 violation drift.** A reviewer or future agent may "tidy up" `layout.tsx` while in the file (rename a className, fix indentation, extract a helper). Anything beyond the two prescribed hunks is a TR7 violation. Enforced by AC: `git diff main` must show exactly two hunks AND brand-row `py-5` must remain unchanged.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with a non-empty reason — verified.
- When you run `git diff main -- 'apps/web-platform/app/(dashboard)/layout.tsx'` to check TR7 compliance, the parentheses MUST be wrapped in single-quotes — bare parentheses are zsh glob qualifiers and silently match nothing.
- `bun test` in this repo runs vitest under the hood for `apps/web-platform/test/**`. Do NOT switch to `bun:test` runtime — the existing test file uses `vitest`'s `vi`/`describe`/`it` API.
- Pill segment height (`h-8` = 32px) is below the 44px iOS touch-target guideline. This is a **pre-existing** condition inherited from the current production component and is **not in scope** for this redesign — flagged here only so a reviewer doesn't surface it as a regression. If touch sizing becomes a complaint, file a separate issue.
- Border convention: the sidebar's footer chrome historically uses `border-t` to delimit blocks (status link, docs link, sign-out separators). The new toggle block uses `border-b` because it's header chrome, not footer. This is a deliberate choice, not an inconsistency to "fix" — leave it.

## Out of Scope

- Avatar / account dropdown menu (alternate placement, would need its own brainstorm).
- Desktop topbar component (deferred until a second tenant — search, notifications — exists).
- Per-route theme overrides or theme scheduling.
- Token-level changes to either light or dark `--soleur-*` palette.
- Touch-target uplift for pill segments (see Sharp Edges).
