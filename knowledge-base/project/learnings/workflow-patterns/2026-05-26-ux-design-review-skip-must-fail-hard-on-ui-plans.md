---
title: "UX design review skip must FAIL HARD when plan has UI file patterns"
date: 2026-05-26
category: workflow-patterns
tags: [ux-review, plan-phase, specialist-gate, ui-components]
severity: medium
source_pr: 4508
source_issue: 4232
---

# Learning: UX design review skip must FAIL HARD when plan has UI file patterns

## Problem

PR-B of BYOK delegations (#4232) shipped 5 new user-facing UI components (DelegationToggle, DelegationFundedPane, DelegationBanner, DelegationAcceptanceModal, DelegationErrorCard) without UX design lead review or wireframes. The plan's Domain Review section listed `ux-design-lead` in `Skipped specialists` with justification "Pencil MCP availability unknown — deferred to deepen-plan." Phase 0.5's specialist review check (step 9) passed because the skip was documented — the check only verifies specialists are accounted for (in `Agents invoked` or `Skipped specialists`), not that skipping is appropriate given the plan's file scope.

## Root Cause

The Phase 0.5 specialist review check treats "documented skip" and "documented invocation" as equivalent for the pass/fail gate. When a plan has UI file patterns (`.tsx`, `.jsx`, `page.tsx`, `layout.tsx`, `components/`) AND `ux-design-lead` is in `Skipped specialists`, the check passes — the specialist is "accounted for." But a documented skip of UX review on a plan with 5 new UI surfaces is a process gap, not a process compliance.

## Solution

The specialist review check (Phase 0.5 step 9) should distinguish between:
- **Non-UI plans:** `ux-design-lead` skip is fine (infrastructure, legal-only, backend-only).
- **UI plans:** `ux-design-lead` skip should FAIL HARD in pipeline mode, requiring either (a) the specialist is invoked, or (b) the operator explicitly overrides with a justification that names the specific UI surfaces being shipped without review.

Proposed rule: When the plan's `## Files to Create` or `## Files to Edit` contains files matching `components/**/*.tsx` or `app/**/*.tsx` AND `ux-design-lead` is in `Skipped specialists`, Phase 0.5 step 9 must FAIL with: "Plan adds N UI components but UX design lead was skipped. Either invoke the specialist or provide an explicit override with named surfaces."

## Key Insight

"Documented skip" is not the same as "appropriate skip." The check should be context-sensitive: skipping UX review on a CLI tool is fine; skipping it on 5 new customer-facing components is a process gap regardless of documentation quality.

## Session Errors

1. **CWD drift after `cd apps/web-platform`** — Bash CWD persisted from a prior command, causing `cd apps/web-platform` to fail. **Recovery:** Used absolute paths. **Prevention:** Always use absolute paths in Bash commands; never rely on relative paths after a prior `cd`.

2. **Closed-issue collision gate false positive on contextual #4318** — One-shot's Step 0a.5 aborted on `#4318` which the user explicitly marked as "closed" (contextual citation, not a work target). `FILE_PATH_TARGET=false` because bare repo has no working tree files. **Recovery:** Recognized the known false-positive pattern, scrubbed closed refs, continued. **Prevention:** `/soleur:go` should scrub closed `#N` refs from args before invoking one-shot (the sharp edge note already documents this — the invoker should implement it).

3. **UX design review gap** — 5 new UI components shipped without wireframes or UX review despite the plan's Domain Review section acknowledging the gap. **Recovery:** User flagged post-implementation. **Prevention:** Phase 0.5 step 9 should FAIL HARD when plan has UI patterns and ux-design-lead is skipped (see Solution above).

## Tags
category: workflow-patterns
module: soleur:work, soleur:plan
