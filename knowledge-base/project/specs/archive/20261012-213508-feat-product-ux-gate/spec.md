# Spec: Product/UX Gate for Engineering Workflows

**Issue:** #671
**Branch:** feat-product-ux-gate
**Date:** 2026-03-19
**Brainstorm:** `knowledge-base/project/brainstorms/2026-03-19-product-ux-gate-brainstorm.md`

## Problem Statement

Engineering workflows (plan, work, one-shot) have no mechanism to detect user-facing work and trigger product/UX review. Constitution line 122 mandates this review but no skill enforces it. PR #637 shipped 5+ user-facing screens without any product or design agent involvement because the feature was framed as infrastructure.

## Goals

1. Detect user-facing work in engineering plans using semantic LLM assessment
2. Conditionally trigger product agent pipeline (SpecFlow → CPO → UX lead) for new user flows
3. Provide advisory notice for modifications to existing UI
4. Add backstop in work skill to catch plans that bypass brainstorm/plan gates
5. Broaden brainstorm domain routing to trigger Product domain on UI creation signals

## Non-Goals

- Creating a new ux-reviewer agent (separate feature)
- PreToolUse hook enforcement (semantic detection is not hook-compatible)
- Modifying agent definitions (gap is in orchestration, not agent capability)
- Blocking on minor UI changes (copy edits, style tweaks)

## Functional Requirements

- **FR1:** Plan skill Phase 2.5 evaluates the generated plan with a semantic assessment: "Does this plan create new user-facing pages, multi-step user flows, or significant UI components?"
- **FR2:** If assessment returns "new user flows" (blocking tier): run spec-flow-analyzer with UI-flow-aware prompt, then CPO for product advisory, then offer ux-design-lead if Pencil MCP is available
- **FR3:** If assessment returns "UI modifications" (advisory tier): display notice suggesting UX review, allow user to skip
- **FR4:** If assessment returns "no UI" or "infrastructure only": proceed without interruption
- **FR5:** Plan skill writes a `## UX Review` section to the plan file documenting the assessment result and any agent findings
- **FR6:** Work skill Phase 0.5 scans the plan file for `## UX Review` section; if absent and plan references UI file patterns, warn the user
- **FR7:** Brainstorm Product domain assessment question includes UI creation signals alongside business validation signals

## Technical Requirements

- **TR1:** Semantic assessment uses the same LLM evaluation pattern as brainstorm domain routing (no keyword matching)
- **TR2:** Agent pipeline runs sequentially (SpecFlow findings inform CPO assessment, CPO findings inform UX design brief)
- **TR3:** ux-design-lead invocation is conditional on Pencil MCP availability; if unavailable, log a notice and continue
- **TR4:** Work backstop is advisory-only (warning, not blocking) to avoid deadlocking plans that legitimately skip UX review
- **TR5:** All changes are to SKILL.md files and brainstorm-domain-config.md — no new files, scripts, or hooks

## Acceptance Criteria

- [ ] Plan for a feature described as "add signup and onboarding flow" triggers the blocking gate and runs SpecFlow + CPO
- [ ] Plan for a feature described as "fix button color on dashboard" triggers advisory notice only
- [ ] Plan for a feature described as "add Redis caching layer" does not trigger any gate
- [ ] Work skill warns when executing a plan with UI file references but no `## UX Review` section
- [ ] Brainstorm for "build a new dashboard page" triggers Product domain leader
- [ ] One-shot pipeline completes with UX review gate firing inside the plan subagent
