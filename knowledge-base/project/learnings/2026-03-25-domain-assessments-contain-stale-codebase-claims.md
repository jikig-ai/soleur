---
title: Domain Leader Assessments Contain Stale Codebase Claims
category: logic_error
module: brainstorm
severity: medium
problem_type: workflow_issue
date: 2026-03-25
---

# Learning: Domain Leader Assessments Contain Stale Codebase Claims

## Problem

During brainstorm for website conversion review (#1142), the CMO assessment asserted "No 'Pricing' link visible in the nav" and the CPO assessment echoed this. Both were wrong — Pricing had already been added to the nav in PR #1136 (merged the same day). This stale claim propagated through the brainstorm document, spec, and initial plan as a Phase 1 task that was already done.

## Root Cause

Domain leader agents (CMO, CPO) read site.json to build their assessment but may have run before the latest PR merged, or read cached/stale data. Their assessments are not re-verified against the live codebase before being incorporated into plans. The plan skill carries forward brainstorm domain assessments without re-validating factual claims.

## Solution

The plan review phase (DHH/Kieran/Simplicity reviewers) caught the issue. Kieran verified actual file contents against plan claims and flagged the discrepancy. The task was marked as already done.

## Key Insight

Domain leader assessments are strategic analyses, not codebase audits. They make factual claims about code state (file contents, nav structure, meta tags) that may be stale by the time they reach the plan. Always verify domain leader codebase claims with a grep/read before incorporating them as plan tasks. A wrong "this is broken" claim creates a no-op task; a wrong "this works" claim skips necessary work.

## Session Errors

1. **CMO stale nav claim** — Asserted Pricing not in nav when it was. Recovery: Kieran review caught it. Prevention: Plan skill should verify domain leader factual claims about file contents before creating tasks.
2. **Buttondown tag copy-paste regression** — Updated Phase 2.2 to `homepage-waitlist` but forgot acceptance criteria and test scenarios. Recovery: Kieran caught the inconsistency. Prevention: When updating a value in one plan section, grep the plan for all instances of the old value.
3. **No-op task from unverified assumption** — Phase 4.2 "remove terminal-first from vision page" but vision page doesn't contain that text. Recovery: Kieran grep verification. Prevention: Grep before adding a "remove X from file Y" task.
4. **Spec brand violation** — Wrote "open-source plugin" in spec FR3 while brand guide prohibits "plugin." Recovery: CPO caught it. Prevention: Copywriter/spec-writer must grep spec output against brand guide prohibited terms.
5. **Phantom path** — Referenced `docs/legal/` which doesn't exist. Recovery: Kieran flagged it. Prevention: Verify paths exist before referencing them in plans.
6. **Phase dependency cycle** — Phase 2 consumed JS changes defined in Phase 4. Recovery: Plan review caught it; simplified plan removed the abstraction entirely. Prevention: When a later phase defines shared infrastructure, move it before the consuming phase or eliminate the abstraction.

## Tags

category: logic_error
module: brainstorm, plan
