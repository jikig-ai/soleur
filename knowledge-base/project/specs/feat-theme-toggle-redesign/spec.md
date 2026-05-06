---
feature: theme-toggle-redesign
status: spec
branch: feat-theme-toggle-redesign
brainstorm: knowledge-base/project/brainstorms/2026-05-06-theme-toggle-redesign-brainstorm.md
mock: knowledge-base/product/design/web-platform/theme-toggle-mock.html
---

# Spec: Theme Toggle Redesign

## Problem Statement

The dashboard theme toggle (`apps/web-platform/components/theme/theme-toggle.tsx`) has two issues:

1. It is gated behind `!collapsed` in `app/(dashboard)/layout.tsx`, so users who keep the sidebar collapsed cannot reach it. This is the worst-case identified in the user-impact framing: "theme stuck / unreachable."
2. Its visual treatment (hard-square 3-segment strip with full-width borders) is heavier than the rest of the sidebar chrome and doesn't match the brand-guide pill/gold-accent aesthetic established in recent theme work (#3271 / #3308 / #3309 / #3312).

## Goals

- Make the theme toggle reachable in **both** expanded and collapsed sidebar states.
- Replace the hard-square segmented strip with a brand-aligned rounded pill.
- Move the toggle from the sidebar footer to the sidebar header so it sits with high-importance global controls (brand, collapse chevron) rather than after-thought links (status, docs, sign-out).
- Mock-first: ship a reviewable visual artifact before any component or layout code changes.

## Non-Goals

- Changing `--soleur-*` design token values for either theme.
- Altering theme persistence, SSR fallback, or `theme-provider.tsx` logic.
- Building a new desktop topbar component.
- Adding a 4th theme mode or removing existing modes (Dark / Light / System remain).
- Building a shadcn/Radix dropdown menu or avatar menu container.

## Functional Requirements

- **FR1.** Expanded sidebar (md:w-56): the toggle renders as a 3-segment rounded pill (Dark / Light / System), icon-only, anchored at the top of the sidebar, between the Soleur brand row and the navigation list, separated from nav by a 1px `--soleur-border-default` rule.
- **FR2.** Collapsed sidebar (md:w-14): the toggle renders as a single 36px circular icon button. Clicking it cycles Dark → Light → System → Dark. The icon reflects the *current* mode; a tooltip on hover surfaces the *next* mode.
- **FR3.** Active segment in pill mode uses `--soleur-bg-surface-1` background, `--soleur-accent-gold-fg` text/icon color, and a 1px ring/inset using `--soleur-border-emphasized` (the gold border token).
- **FR4.** Inactive segments use `--soleur-text-muted`, hover reveals `--soleur-text-secondary` (no background change).
- **FR5.** Mobile drawer opens with the sidebar in expanded form (not collapsed), so the pill is the rendered shape on mobile.
- **FR6.** Existing keyboard nav (Arrow-Left/Right/Home/End) is preserved in pill mode. Cycle button responds to Enter/Space.
- **FR7.** ARIA: pill keeps `role="group" aria-label="Theme"`; segments keep `aria-pressed` + `aria-label` per mode. Cycle button uses `aria-label="Theme: <current>; click for <next>"` so screen readers get the same info as the visual tooltip.

## Technical Requirements

- **TR1.** `ThemeToggle` accepts a `collapsed?: boolean` prop and renders the appropriate variant. No new module — same file.
- **TR2.** Layout mount point moves from the footer block (currently `app/(dashboard)/layout.tsx` lines ~323–333) to the sidebar header, immediately under the brand-row block (`app/(dashboard)/layout.tsx` ~lines 250–274). The `!collapsed` mount gate is removed.
- **TR3.** No new dependencies. Pure Tailwind + existing `--soleur-*` tokens. No Radix, no shadcn, no Headless UI.
- **TR4.** No changes to `theme-provider.tsx`, `globals.css` token values, `theme-csp-regression.test.tsx`, or `theme-provider.test.tsx`.
- **TR5.** `theme-toggle.test.tsx` is extended with: (a) collapsed-mode renders single button, (b) clicking cycle button calls `setTheme` with the next mode, (c) tooltip text matches expected pattern. Existing pill-mode tests remain green.
- **TR6.** SSR-safe: dual-mode rendering must not introduce a hydration mismatch. The collapsed-vs-expanded decision is server-known (driven by the same `collapsed` state that already drives sidebar width); icon for cycle button uses the same hydration-safe pattern as the existing `theme-provider`.
- **TR7. Minimal sidebar blast radius (user constraint, 2026-05-06).** When editing `app/(dashboard)/layout.tsx`, the only permitted mutations are:
  1. **Insert** the new `<ThemeToggle collapsed={collapsed} />` mount in the sidebar header (between brand-row and `<nav>`), wrapped in the new pill-wrap container.
  2. **Remove** the existing footer-block mount (lines ~323–333: the `{!collapsed && (<div>Theme...<ThemeToggle /></div>)}` block including its "THEME" label paragraph).

  Do **NOT** modify: the brand row, collapse-toggle button, mobile drawer top bar, mobile-close button, navigation items, `ConversationsRail` mount, footer email line, status link, docs link, sign-out button, or any class names / spacing / safe-area on the unrelated blocks. The diff against `layout.tsx` must consist of exactly one insertion block + one deletion block — no incidental edits, no opportunistic refactors.

  Verification: `git diff main -- apps/web-platform/app/\\(dashboard\\)/layout.tsx` should show only the two adjacent hunks above.

## Acceptance Criteria

- Mock at `knowledge-base/product/design/web-platform/theme-toggle-mock.html` opens cleanly in a modern browser; pill clicks update aria-pressed; collapsed cycle button rotates through 3 modes with correct icon swap and tooltip update.
- After integration: in expanded sidebar the toggle appears at the top; in collapsed sidebar a single gold-ringed icon button is visible at the same vertical position; both states reach all 3 modes via UI alone.
- `theme-toggle.test.tsx` passes for both pill and cycle modes.
- No visual regression on `/dashboard/settings`, `/dashboard/chat/*`, `/dashboard/kb/*` for either theme — the rest of the chrome is untouched.

## Out of Scope (deferred / explicit non-goals)

- Avatar menu / account dropdown (would be the alternate placement; not built today).
- Desktop topbar (separate scope, would unlock future search / notifications).
- Per-route theme preferences or theme scheduling.
