---
title: "feat: Progressive Task Surfacing — Dismissable Foundation Cards"
type: enhancement
date: 2026-04-16
issue: 2413
branch: feat-dismissable-foundation-cards
brainstorm: knowledge-base/project/brainstorms/2026-04-16-dismissable-foundation-cards-brainstorm.md
spec: knowledge-base/project/specs/feat-dismissable-foundation-cards/spec.md
---

# Progressive Task Surfacing — Dismissable Foundation Cards

## Overview

Completed foundation cards on the Command Center dashboard auto-collapse into compact
chips. Freed grid slots fill with KB-gap-aware operational tasks. The grid always shows
the founder's most relevant next actions.

**Scope:** Modify 3 existing files. No new API routes, no database changes, no new
component files. State is derived from the existing KB tree API response.

## Implementation Phases

### Phase 1: Define Operational Tasks Data

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

Add `OPERATIONAL_TASKS` array alongside existing `FOUNDATION_PATHS`, using the same
shape. Each entry maps to a KB file path and a domain leader.

```typescript
const OPERATIONAL_TASKS = [
  { id: "pricing", title: "Set pricing strategy", leaderId: "cmo", kbPath: "product/pricing-strategy.md", promptText: "Design a pricing strategy for my product — tiers, value metrics, and competitive positioning." },
  { id: "competitive", title: "Create competitive analysis", leaderId: "cpo", kbPath: "product/competitive-analysis.md", promptText: "Run a competitive analysis — identify key competitors, positioning gaps, and differentiation opportunities." },
  { id: "launch", title: "Plan marketing launch", leaderId: "cmo", kbPath: "marketing/launch-plan.md", promptText: "Create a marketing launch plan — channels, timeline, and messaging strategy." },
  { id: "hiring", title: "Define hiring plan", leaderId: "coo", kbPath: "operations/hiring-plan.md", promptText: "Build a hiring plan — roles needed, timeline, and budget." },
  { id: "distribution", title: "Build distribution strategy", leaderId: "cmo", kbPath: "marketing/distribution-strategy.md", promptText: "Design a distribution strategy — channels, partnerships, and growth loops." },
  { id: "financial", title: "Set up financial projections", leaderId: "cfo", kbPath: "finance/financial-projections.md", promptText: "Create financial projections — revenue model, burn rate, and runway forecast." },
];
```

**Derive done state** using the existing `kbFiles` map and `FOUNDATION_MIN_CONTENT_BYTES`
threshold (same pattern as foundation cards):

```typescript
const operationalCards: FoundationCard[] = OPERATIONAL_TASKS.map((t) => ({
  ...t,
  done: kbFiles.has(t.kbPath) && (kbFiles.get(t.kbPath)?.size ?? 0) >= FOUNDATION_MIN_CONTENT_BYTES,
}));
```

### Phase 2: Update FoundationCards Component

**File:** `apps/web-platform/components/dashboard/foundation-cards.tsx`

Extend the component to accept and render two sections:

1. **Completed chips** — compact `<a>` tags rendered above the grid for all cards where
   `done === true`. Each chip shows a green checkmark SVG + title, links to `/dashboard/kb/{kbPath}`.

2. **Active card grid** — the existing grid, but now receives only incomplete cards
   (both foundation and operational).

```typescript
interface FoundationCardsProps {
  cards: FoundationCard[];           // all cards (foundation + operational)
  getIconPath: (id: DomainLeaderId) => string | null;
  onIncompleteClick: (promptText: string) => void;
}
```

The component splits `cards` internally:

```typescript
const completed = cards.filter((c) => c.done);
const active = cards.filter((c) => !c.done);
```

Render completed chips as a flex-wrap row above the grid. Render active cards in the
existing `grid-cols-2 md:grid-cols-4` grid. If no active cards remain, render nothing
(the parent hides the section).

### Phase 3: Update Dashboard Page Rendering

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

Foundation cards currently render in **two places**: the empty-state view (no
conversations) and the inbox view (conversations exist). Both need the same update.

Changes:

1. Combine `foundationCards` + `operationalCards` into a single `allCards` array.
2. Derive `allTasksComplete = allCards.every((c) => c.done)` to replace
   `allFoundationsComplete` for the section-hide logic.
3. Pass `allCards` to `<FoundationCards>` instead of just `foundationCards`.
4. When `allTasksComplete`, hide the section entirely (preserve current behavior).

The `SUGGESTED_PROMPTS` block (shown when all foundations complete and no conversations)
is removed — operational tasks replace its purpose.

**Dropped after review:** Progress counter and dynamic header rename ("FOUNDATIONS" →
"UP NEXT") — chips already communicate progress visually, and the header adds state
without value.

### Phase 4: Tests

**Files:**

- `apps/web-platform/test/foundation-cards.test.tsx` — extend existing 6 tests
- `apps/web-platform/test/command-center.test.tsx` — extend existing 12 tests

New test cases:

- Completed cards render as chips (compact `<a>` tags with checkmark), not full cards
- Clicking a chip navigates to KB path
- Operational task cards render alongside incomplete foundation cards
- Operational tasks whose KB file exists (with sufficient size) are not shown
- Grid shows all incomplete cards (foundation + operational)
- When all cards (foundation + operational) are complete, section is hidden

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | Add `OPERATIONAL_TASKS`, combine with foundations, update render logic |
| `apps/web-platform/components/dashboard/foundation-cards.tsx` | Split into completed chips + active grid |
| `apps/web-platform/test/foundation-cards.test.tsx` | Add chip rendering and operational task tests |
| `apps/web-platform/test/command-center.test.tsx` | Add progressive surfacing integration tests |

## Acceptance Criteria

- [ ] Completed foundation cards render as compact chips (checkmark + title) above the active grid
- [ ] Chips link to `/dashboard/kb/{kbPath}`
- [ ] Incomplete foundations + incomplete operational tasks fill the active grid
- [ ] Operational tasks whose KB file exists (>= 500 bytes) are skipped
- [ ] Grid maintains `grid-cols-2 md:grid-cols-4` layout
- [ ] When all 10 cards are complete, the section is hidden
- [ ] First-run, provisioning, and error states remain unaffected
- [ ] Existing foundation card tests still pass

## Test Scenarios

1. **No foundations complete** — grid shows all 10 incomplete cards (4 foundation + 6 operational)
2. **Some foundations complete** — completed ones render as chips, rest in grid
3. **All foundations complete** — 4 chips + 6 operational task cards in grid
4. **Mix complete** — both foundation and operational chips, remaining in grid
5. **All complete** — section hidden entirely
6. **KB file exists but < 500 bytes** — card still shown as incomplete (stub detection)

## Domain Review

**Domains relevant:** Product

### Product (CPO)

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** Feature is well-scoped for L2 MVP. KB-gap-aware tasks align with CaaS thesis.
No new infrastructure needed. Dynamic AI-generated recommendations deferred to L4 North Star.

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed (brainstorm carry-forward)
**Agents invoked:** cpo (brainstorm phase)
**Skipped specialists:** none
**Pencil available:** N/A

The brainstorm explored visual treatment with ASCII mockups and the founder approved
"compact chips" layout. This modifies existing UI components (no new pages or flows).
No new component files — chips render within the existing `FoundationCards` component.
