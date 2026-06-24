---
title: "Tasks — fix: tighten sidebar workspace-button → collapse-toggle gap"
plan: knowledge-base/project/plans/2026-06-24-fix-sidebar-workspace-button-gap-plan.md
branch: feat-one-shot-sidebar-workspace-button-gap
lane: single-domain
---

# Tasks

## Phase 0 — Preconditions

- [ ] 0.1 Confirm sole `pr-20` functional hit:
      `git grep -n "pr-20" apps/web-platform/components apps/web-platform/app`
      → only `workspace-context-band.tsx:105` (comment at `:95` updates with it).
- [ ] 0.2 Confirm toggle geometry: `grep -n "right-3 top-10" apps/web-platform/app/\(dashboard\)/layout.tsx`
      → `right-3` (12px) + `w-6` (24px) = 36px right footprint.
- [ ] 0.3 Read band test tripwires (no `pr-20` literal asserted today):
      `grep -n "min-h-\[64px\]\|pt-2\|pt-3\|pb-3" apps/web-platform/test/workspace-context-band.test.tsx`.

## Phase 1 — Core Implementation

- [ ] 1.1 `workspace-context-band.tsx:105`: change expanded pill-row wrapper
      `… px-3 pt-2 md:pr-20` → `… px-3 pt-2 md:pr-12`.
- [ ] 1.2 `workspace-context-band.tsx:95–100`: update the comment `md:pr-20` → `md:pr-12`
      with the 36px-footprint / 48px-clearance arithmetic.
- [ ] 1.3 Leave `org-switcher.tsx` and `layout.tsx` toggle position untouched
      (card is `w-full min-w-0` and fills reclaimed width automatically).

## Phase 2 — Testing

- [ ] 2.1 `test/workspace-context-band.test.tsx`: add tripwire — expanded pill wrapper
      `className` contains `md:pr-12`, not `md:pr-20`. Mirror the `md:min-h-[64px]`
      tripwire comment style (note e2e is source of truth).
- [ ] 2.2 `e2e/nav-states-shell.e2e.ts`: verify the expanded-rail no-overflow gate stays
      green; ADD a `«`-toggle ↔ `▾`-chevron horizontal non-intersection assertion in the
      `expanded multi-workspace` test IF one does not already exist
      (`chevronBox.x + chevronBox.width <= toggleBox.x`).

## Phase 3 — Verification

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-context-band.test.tsx` green.
- [ ] 3.3 Run `nav-states-shell` e2e per project Playwright invocation; overflow ≤ 1px +
      non-intersection pass.
- [ ] 3.4 Re-run open `code-review` overlap query before freezing (Plan §Open Code-Review Overlap).
- [ ] 3.5 Visual check `/dashboard` expanded multi-workspace: card fills rail, ~12px gap
      to `«`, chevron clear of toggle; collapsed rail unchanged.
