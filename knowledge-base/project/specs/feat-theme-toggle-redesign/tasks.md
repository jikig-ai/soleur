---
feature: theme-toggle-redesign
status: ready
branch: feat-theme-toggle-redesign
issue: 3316
pr: 3315
plan: knowledge-base/project/plans/2026-05-06-feat-theme-toggle-redesign-plan.md
spec: knowledge-base/project/specs/feat-theme-toggle-redesign/spec.md
mock: knowledge-base/product/design/web-platform/theme-toggle-mock.html
---

# Tasks: Theme Toggle Redesign

Derived from the plan. Constraint TR7 governs the entire layout edit — see plan §Acceptance Criteria.

## Phase 1 — Component (`apps/web-platform/components/theme/theme-toggle.tsx`)

- [x] **1.1** Change function signature to `export function ThemeToggle({ collapsed }: { collapsed: boolean })`. Required prop, no default.
- [x] **1.2** Wrap today's existing 3-segment JSX in `if (collapsed === false)` early-return. No changes to `SEGMENTS`, `useRef`, `handleKeyDown`, classNames, or aria attributes inside the pill block.
- [x] **1.3** Add the collapsed-mode return below: a single `<button>` with:
  - [x] `data-testid="theme-cycle-button"` (mandatory)
  - [x] 36×36, `rounded-full`, Tailwind utility classes only (`border-soleur-border-default`, `bg-soleur-bg-surface-2`, `text-soleur-accent-gold-fg`, focus-visible ring matching the pill's active treatment)
  - [x] No inline `style={{ color: "var(--soleur-...)" }}` (CSP regression risk)
  - [x] Inner SVG = current mode's icon (reuse existing `MoonIcon`/`SunIcon`/`MonitorIcon`)
  - [x] `aria-label={"Theme: " + currentLabel}` (e.g., `Theme: Dark`); no `title` attribute
- [x] **1.4** Click handler computes next mode via `SEGMENTS[(SEGMENTS.findIndex(s => s.value === theme) + 1) % SEGMENTS.length]` and calls `setTheme(next.value)`.

## Phase 2 — Layout (`apps/web-platform/app/(dashboard)/layout.tsx`)

- [x] **2.1** Insert the new toggle wrapper between brand-row `</div>` (line ~274) and `<nav>` (line ~277):

  ```tsx
  {/* Theme toggle — sidebar header. Pill in expanded state, single
      cycle button in collapsed state. Replaces the prior footer-block
      mount. See spec TR7. */}
  <div className={`border-b border-soleur-border-default ${collapsed ? "px-2 py-3" : "px-3 py-3"}`}>
    <ThemeToggle collapsed={collapsed} />
  </div>
  ```

- [x] **2.2** Delete the existing footer-block mount (lines ~323–333) including its `<p>Theme</p>` label.
- [x] **2.3** **Do NOT touch** brand-row `py-5` on line ~250 (the temptation to "tidy spacing" must be resisted — TR7 violation).
- [x] **2.4** Verify with `git diff main -- 'apps/web-platform/app/(dashboard)/layout.tsx'` (single-quote the path). Output must be exactly two hunks: one insertion near the brand row, one deletion in the footer area. Anything else = TR7 violation; revert.

## Phase 3 — Tests (`apps/web-platform/test/components/theme-toggle.test.tsx`)

- [x] **3.1** Update every existing `<ThemeToggle />` to `<ThemeToggle collapsed={false} />` (required prop or compile fails).
- [x] **3.2** Add a `renderToggleCollapsed()` helper next to the existing `renderToggle()`.
- [x] **3.3** Add a `describe("collapsed mode")` block with one test:
  - [x] **cycle-advances-mode:** fresh `localStorage` (provider default = `system`). Render collapsed. Query button via `getByTestId("theme-cycle-button")`. Click → assert `localStorage.getItem("soleur:theme") === "dark"`. Click → `"light"`. Click → `"system"`. (Sequence: `system → dark → light → system` per `SEGMENTS` order.)

## Phase 4 — Verification

- [x] **4.1** `bun test apps/web-platform/test/components/theme-toggle.test.tsx` — all green.
- [x] **4.2** `bun test apps/web-platform/test/dashboard-sidebar-collapse.test.tsx` — all green (no edits expected; verified at plan time no button-count assertions exist).
- [x] **4.3** `bun test apps/web-platform/test/dashboard-layout-drawer-rail.test.tsx` — all green (same).
- [x] **4.4** `bun test apps/web-platform/test/theme-csp-regression.test.tsx` — all green (no token-style changes should reach it; if it fails, raw `var(--soleur-*)` slipped into Phase 1).
- [x] **4.5** `bun test apps/web-platform/test/theme-provider.test.tsx` — all green (provider untouched).
- [ ] **4.6** Manual QA in browser: load `/dashboard` in dark and light, click each pill segment, then `⌘B` to collapse and click the cycle button three times. Both work; theme persists across reloads.

## Phase 5 — Ship

- [ ] **5.1** Run `skill: soleur:compound` (per AGENTS.md `wg-before-every-commit-run-compound-skill`).
- [ ] **5.2** Commit with `Closes #3316` in the body (not title).
- [ ] **5.3** Reference the mock (`knowledge-base/product/design/web-platform/theme-toggle-mock.html`) in the PR body.
- [ ] **5.4** Mark PR ready, queue auto-merge: `gh pr merge 3315 --squash --auto`.
- [ ] **5.5** Post-merge: verify production behavior per Acceptance Criteria → Post-merge.

## Definition of Done

- All checkboxes above are checked.
- `git diff main -- 'apps/web-platform/app/(dashboard)/layout.tsx'` shows exactly two hunks.
- All five test files in Phase 4 are green.
- PR is merged and post-merge production checks pass.
