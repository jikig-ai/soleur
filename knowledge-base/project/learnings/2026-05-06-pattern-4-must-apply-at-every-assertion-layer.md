# Learning: Pattern 4 (data-testid scoping) must apply at every assertion layer, not just the outermost

## Problem

In PR #3339 (remove redundant blinking amber dot from tool-use chips), the plan
explicitly cited learning `2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`
Pattern 4 — "prefer `data-testid` attribute hooks over Tailwind class selectors,
to survive class-name refactors" — and added `data-testid="tool-status-chip"`
to the chip wrapper to satisfy the lesson.

The new tests then asserted the dot-was-removed via:

```ts
const chip = getByTestId("tool-status-chip");
expect(chip.querySelector("span.animate-pulse")).toBeNull();
```

`test-design-reviewer` caught this in multi-agent review: the **outer** scoping
followed Pattern 4 correctly, but the **inner** assertion reverted to a Tailwind
class selector (`.animate-pulse`). That selector silently passes if the dot
returns wearing `motion-safe:animate-pulse`, a CSS-module class, or a `<div>`
instead of a `<span>` — exactly the regression class Pattern 4 exists to prevent.

## Solution

Restate the assertion structurally, not by class membership. The chip's
contract is "render the label, nothing else" — express that:

```ts
const chip = getByTestId("tool-status-chip");
expect(chip.children).toHaveLength(1);
expect(chip.children[0].textContent).toBe(label);
```

This catches ANY new child element being added to the chip, regardless of how
it's styled or what tag it uses.

## Key Insight

When a plan cites a "prefer X over Y" learning, audit every assertion in the
new tests — not just the entry-point selector. Pattern 4 (and similar
test-API-vs-implementation-detail rules) is layer-recursive: the entry-point
wins half the battle; the inner assertions decide the other half.

A reliable check at deepen-plan or work time: grep the planned test snippets
for `querySelector\("[a-z]+\.[a-z-]+"\)` (an element-with-class selector). Each
hit is a candidate for replacement with a structural assertion (`children.length`,
`textContent`, role/aria attribute) or a `data-*` hook.

## Tags
category: best-practices
module: testing
cross-ref: 2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md (Pattern 4 origin)
caught-by: multi-agent review (test-design-reviewer)
pr: 3339
