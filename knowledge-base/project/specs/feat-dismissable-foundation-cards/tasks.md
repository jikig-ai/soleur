---
title: Tasks — Progressive Task Surfacing
issue: 2413
branch: feat-dismissable-foundation-cards
plan: knowledge-base/project/plans/2026-04-16-feat-progressive-task-surfacing-plan.md
---

# Tasks

## Phase 1: Define Operational Tasks Data

- [ ] 1.1 Add `OPERATIONAL_TASKS` array to `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - 6 entries: pricing, competitive, launch, hiring, distribution, financial
  - Same shape as `FOUNDATION_PATHS` entries
- [ ] 1.2 Derive `operationalCards` from `kbFiles` map using `FOUNDATION_MIN_CONTENT_BYTES`
- [ ] 1.3 Combine into `allCards` array and derive `allTasksComplete`

## Phase 2: Update FoundationCards Component

- [ ] 2.1 Update `FoundationCards` in `apps/web-platform/components/dashboard/foundation-cards.tsx`
  - Split `cards` into `completed` and `active` internally
  - Render completed as compact chip `<a>` tags (checkmark + title, link to KB)
  - Render active in existing grid
  - Return null if no active cards and no completed chips

## Phase 3: Update Dashboard Page Rendering

- [ ] 3.1 Update empty-state view to pass `allCards` to `<FoundationCards>`
- [ ] 3.2 Update inbox view to pass `allCards` to `<FoundationCards>`
- [ ] 3.3 Replace `allFoundationsComplete` with `allTasksComplete` for section-hide logic
- [ ] 3.4 Remove `SUGGESTED_PROMPTS` block (operational tasks replace its purpose)

## Phase 4: Tests

- [ ] 4.1 Extend `apps/web-platform/test/foundation-cards.test.tsx`
  - Completed cards render as chips, not full cards
  - Clicking a chip navigates to KB path
  - Active grid shows only incomplete cards
- [ ] 4.2 Extend `apps/web-platform/test/command-center.test.tsx`
  - Operational tasks render alongside incomplete foundations
  - KB-existing operational tasks are skipped
  - All-complete state hides the section
  - Stub files (< 500 bytes) still show as incomplete
