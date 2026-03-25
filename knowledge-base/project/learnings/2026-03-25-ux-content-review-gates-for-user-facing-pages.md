---
date: 2026-03-25
category: integration-issues
module: plan-skill, work-skill
severity: high
tags: [workflow, ux-design, content-review, pricing-page, specialist-gates]
---

# Learning: UX and Content Review Gates Must Be Enforced for User-Facing Pages

## Problem

During the pricing page v2 redesign (#656), the workflow went directly from brainstorm/plan to implementation without involving the UX designer (wireframes) or copywriter (page content). The plan skill's Product/UX Gate was marked "reviewed (carried from brainstorm)" — but the brainstorm only assessed the *idea*, not the *page design*. Domain leader assessments (CMO recommended conversion-optimizer + copywriter, CPO recommended UX review) were captured as text but never enforced as prerequisites.

The result: an agent wrote HTML/CSS from brainstorm bullet points, producing a page with no design artifacts and no reviewed copy. The user caught this and flagged it as a process failure.

## Solution

1. Reverted the premature implementation
2. Launched copywriter agent to draft all page content (hero, hiring table, tier cards, FAQ, CTA)
3. Launched UX designer agent to create wireframes in Pencil (3+2 layout, section hierarchy)
4. Ran CMO review on both artifacts — caught 3 blockers (hiring table numbers, FAQ factual error, missing sections)
5. Only then implemented from approved copy + approved wireframes

The proper flow for copy-heavy user-facing pages: **Specialists produce artifacts first, then code implements from those artifacts.**

## Key Insight

Domain leader assessments that recommend specialists are not informational — they are prerequisites. "CMO recommends copywriter" means the copywriter must run before implementation, not that it would be nice if they did. The plan skill currently has no mechanism to enforce this. Filed as #1137.

The specialist sequence for user-facing pages:

1. Copywriter drafts content
2. UX designer creates wireframes
3. Domain leader (CMO) reviews both
4. Implementation works from approved artifacts

## Session Errors

**Workflow gap: skipped UX designer and copywriter** — Recovery: user caught it, reverted, restarted with specialists. Prevention: plan skill must enforce specialist prerequisites when Product/UX Gate is BLOCKING (#1137).

**git stash used in worktree** — Recovery: stash pop succeeded. Prevention: should have committed WIP first or used a separate git show command to check the base branch.

**Copywriter factual error on Claude costs** — Recovery: user corrected, CMO review caught it independently. Prevention: copywriter prompts should include explicit "verify with founder" flags on pricing/cost claims.

**Hiring table number mismatch between specialists** — Recovery: CMO provided market-defensible numbers. Prevention: when multiple specialists produce overlapping content (copywriter + UX designer both had hiring numbers), designate one as canonical and have the other reference it.

## Tags

category: integration-issues
module: plan-skill, work-skill, brainstorm-skill
