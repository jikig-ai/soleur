---
module: plan
date: 2026-05-11
problem_type: integration_issue
component: plan_skill
symptoms:
  - "Plan's Research Reconciliation asserts 'mitigation X does not apply because we don't have Y'"
  - "Claim is based on reading the layout/shell file only"
  - "The actual artifact Y lives in a sibling file (route page, child component) the plan didn't grep"
  - "Pattern-recognition reviewer catches it pre-merge by reading the FULL render tree"
root_cause: scope_too_narrow_in_research_reconciliation
severity: medium
tags: [planning, research-reconciliation, render-tree, multi-agent-review, false-negative]
synced_to: [plan]
related_pr: 3587
---

# Learning: Plan Research Reconciliation must grep the full render tree, not just the layout file

## Problem

PR #3587 (`feat-one-shot-kb-sidebar-transition`) applies the SettingsShell CSS-width-transition pattern to the Knowledge Base sidebar. The settings PR chain had five iterations, each adding one mitigation:

- #3573: unconditional transition class
- #3579: `mx-auto`-content anchor padding (collapsed-state `md:pl-[14.5rem]`)
- #3584: padding on always-on base classes
- #3585: padding on inner wrapper, not outer nav

The plan's "Research Insights" (Phase 2) explicitly asserted that the #3579 mitigation **does not apply** to KB:

> The KB doc viewer is NOT `mx-auto max-w-2xl`-wrapped — it renders the document directly inside the content well (file: `apps/web-platform/components/kb/kb-doc-shell.tsx:49-55`), so there is no horizontal-center re-flow to anchor against.

The plan's claim was **wrong**. The author only read `kb-doc-shell.tsx`, which is a thin wrapper. The actual centering happens one level deeper — in the route page:

```
apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx:77
  <div className="mx-auto max-w-3xl space-y-4">
apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx:153
  <div className="mx-auto max-w-3xl">
```

The route page renders INSIDE `KbDocShell` as `children`. The plan's grep stopped at the shell file boundary and missed the children. Without the anchor-padding mitigation, the rendered markdown / PDF content would drift ~15.5rem leftward during the 200ms transition (sidebar width 18rem − collapsed-state pl 2.5rem). This is exactly the bug #3579 was filed to fix on settings.

`soleur:engineering:review:pattern-recognition-specialist` caught the false-negative pre-merge by reading the route page. The fix was a one-line className change in `kb-doc-shell.tsx` — `pl-10` → `pl-10 md:pl-[18rem]` — but the plan would have shipped without it.

## Solution

When a plan's "Research Reconciliation" or "Research Insights" section asserts that a mitigation **does not apply** because the codebase lacks artifact Y (e.g., "no `mx-auto`", "no `useResizeObserver`", "no `onSubmit` handler"), grep the **full render tree** for Y:

```bash
# Wrong — stops at the shell file
grep -n "mx-auto" apps/web-platform/components/kb/kb-doc-shell.tsx

# Right — walks the route → layout → shell → children chain
grep -rn "mx-auto" apps/web-platform/app/\(dashboard\)/dashboard/kb/ \
                   apps/web-platform/components/kb/
```

The render tree is wider than the file you're editing. For a Next.js app the chain is typically:

1. `app/<route>/page.tsx` (renders the actual content)
2. `app/<route>/layout.tsx` (wraps siblings; KbLayout, dashboard layout)
3. `components/<feature>/<feature>-layout.tsx` (the layout shell — what most plans read)
4. `components/<feature>/<feature>-shell.tsx` / `-doc-shell.tsx` (presentation wrapper)
5. Route's `children` prop → resolves back to step 1

A plan that reads only step 3 or step 4 will miss the centering, ResizeObserver, fixed-width wrappers, or other geometric constraints that live in step 1 or step 5.

For a Rails / non-React stack the equivalent is: don't stop at the partial — walk up to the view template and the parent layout.

## Key Insight

A plan's assertion of "we don't have Y, therefore mitigation X is unneeded" is **falsifiable**. Treat it as a precondition that must be verified by grep, not asserted from a single file read. The cost of verification is one extra `grep -rn` against the route tree (≈2 seconds). The cost of shipping without the mitigation is a visible UX regression that another PR has to fix.

This is the planning-time analogue of multi-agent review's cross-artifact contract drift class (see `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`). In that learning, the reviewer agents missed the brand-guide drift because they only read the local file. Here, the plan author missed the route-page `mx-auto` because they only read the layout file. The defense is the same: when an artifact references or wraps another artifact, both must be inspected.

## Prevention

1. In `soleur:plan`'s Phase 1 (Research) and `soleur:deepen-plan`'s Research Reconciliation: when the plan asserts "Y is absent", the grep must include the route page and any children consumed via `children` props or slot props. A grep that returns zero hits in the layout file is insufficient evidence that Y is absent app-wide.
2. In multi-agent review at PR time (already working): `pattern-recognition-specialist` and `git-history-analyzer` independently re-verify load-bearing plan claims by reading the full render tree. PR #3587 confirmed this defense fired.
3. Sharp Edge candidate for `plugins/soleur/skills/plan/SKILL.md`: "When a plan claims a sibling-PR mitigation does not apply because the codebase lacks artifact Y, grep the full render tree (route page + layout + shell + components/<feature>/) for Y before merging the claim. A single-file read is insufficient evidence."

## Session Errors

- **Plan's Research Insights claimed `mx-auto` is absent from KB** — Recovery: Pattern-recognition reviewer caught it pre-merge; inline anchor-padding fix landed in c7e70258. Prevention: Plan skill should grep the route tree, not just the shell file, when asserting an artifact's absence.
- **Introduced mobile-pl regression via `md:pl-10`** — Recovery: Code-quality reviewer flagged the responsive-gate mismatch (chevron is unconditional, padding was md-only); fix changed to `pl-10 md:pl-[18rem]`. Prevention: When porting a class to `md:`-prefixed transitions, audit every responsive gate of every related element (chevron, button, sibling) — not just the one being animated.
- **Left `setKbCollapsed` in public hook interface after refactor** — Recovery: Architecture-strategist + code-quality-analyst both flagged the dead export; removed inline. Prevention: When refactoring a hook to remove a mutation pathway, grep external callers of any setter that lost its sole internal caller; drop unused exports in the same commit.
