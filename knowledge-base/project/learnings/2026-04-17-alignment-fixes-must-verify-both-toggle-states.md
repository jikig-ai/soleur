---
name: alignment fixes must verify both toggle states
description: When fixing alignment of a toggleable UI control (chevron, accordion, collapse button), verify alignment holds in BOTH states -- a fix for one state can leave the other misaligned.
type: ui-bug
tags: [ui, layout, tailwind, nav, toggle, alignment]
---

# Learning: Alignment fixes on toggleable UI must verify both states

## Problem

PR #2494 (`fix(settings-nav): align expand chevron with main nav chevron`) aligned the
**collapsed-state** expand chevron (`>`) on `/dashboard/settings/*` with the main nav
header chevron. The fix adopted the KB layout precedent: absolute-positioned button at
`top-5` inside the content wrapper. The PR body confirmed alignment with screenshots.

The user then reported a follow-up issue: "when the Team Settings Page nav bar is not
collapsed the `<` is not aligned with the Main Nav Bar One." The **expanded-state**
collapse chevron (`<`) inside the settings `<nav>` was still ~18 px below the main nav
chevron, even after PR #2494.

Root cause: PR #2494 only touched the collapsed-state code path (the absolute-positioned
button in the content area). The expanded-state `<nav>` wrapper still carried its
original `py-10` (40 px top padding), while the main nav header used `py-5` (20 px). The
two code paths render at different times (mutually exclusive by `settingsCollapsed`
state), so fixing one did not reveal that the other needed the same fix.

## Solution

Follow-up PR: single-token Tailwind change -- `py-10` → `py-5` on the expanded-state
branch of the conditional `className` in `apps/web-platform/components/settings/settings-shell.tsx`.
Added two vitest assertions to lock in the alignment contract for both states.

The collapsed-state path from PR #2494 was untouched -- it was already correct for its
state.

## Key Insight

**A toggleable UI control has TWO rendering states, and each state's alignment with the
reference element must be verified independently.** A fix for the collapsed state does
not carry over to the expanded state (and vice versa) because the two branches of the
conditional `className` render different DOM structures with different parent geometry.

### The gap that made PR #2494 incomplete

PR #2494's alignment contract tests asserted on the collapsed-state expand button:

- `absolute left-2 top-5 z-10 h-6 w-6` classes present
- `h-4 w-4` svg
- `hidden md:flex` responsive behavior
- Exactly one expand button after collapsing

These tests are correct for the collapsed state. None of them say anything about the
**expanded-state** collapse button -- the DOM element that was still misaligned. The
test suite was complete for one state and silent about the other.

### Generalizable rule

When fixing the alignment of any UI control that has a toggleable state (collapse/expand,
accordion, drawer, disclosure widget, tab visibility), the alignment contract MUST be
asserted in **both states**, not just the one that surfaced the bug.

Applied to future plans: when `/soleur:plan` receives an alignment bug report for a
toggleable control, the research phase must check the other toggle state's geometry
before writing the plan. If the other state is also misaligned (or would become
misaligned after the fix), fold both into the same PR.

## Session Errors

- **Tried to Write session-state.md without reading it first.** Write tool correctly
  blocked per `hr-always-read-a-file-before-editing-it`. Recovery: ran `mkdir -p`, `ls`
  (which surfaced pre-existing content from the plan subagent), Read the file, then Write
  succeeded. **Prevention:** Already hook-enforced and skill-enforced; no new workflow
  change needed.
- **Plan+deepen subagent produced a new filename (`...-expanded-chevron-alignment-plan.md`)
  but the pre-existing session-state.md still pointed at the pre-deepen filename
  (`...-chevron-alignment-plan.md`).** Caught because the subagent's return contract
  named the new path explicitly. Recovery: manually overwrote session-state.md with the
  correct plan path. **Prevention:** The one-shot subagent contract already enforces this
  via the explicit `### Plan File` section in the return format; the mismatch here was
  pre-existing state from a prior session that the subagent didn't clean up. Low-impact
  and caught inline -- no workflow change warranted.

## Related

- PR #2494 -- `fix(settings-nav): align expand chevron with main nav chevron`
  (collapsed-state fix).
- PR #2504 -- expanded-state counterpart (this learning's source).
- `apps/web-platform/components/settings/settings-shell.tsx` -- both chevron code paths.
- `apps/web-platform/test/settings-sidebar-collapse.test.tsx` -- now covers alignment
  contract for both states.
