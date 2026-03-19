# Tasks: Product/UX Gate for Engineering Workflows

**Plan:** `knowledge-base/plans/2026-03-19-feat-product-ux-gate-plan.md`
**Issue:** #671
**Branch:** feat-product-ux-gate

## Phase 1: Plan Skill — Phase 2.5 UI Detection Gate

### 1.1 Insert Phase 2.5 section in plan SKILL.md
- [x] Read `plugins/soleur/skills/plan/SKILL.md`
- [x] Insert new `### 2.5. Product/UX Gate` section after line 192 (end of Phase 2) and before Phase 3 (line 194)
- [x] Include semantic assessment prompt with three tiers (BLOCKING, ADVISORY, NONE)
- [x] Include BLOCKING flow: spec-flow-analyzer → CPO → ux-design-lead (conditional)
- [x] Include ADVISORY flow: pipeline auto-accept or interactive AskUserQuestion
- [x] Include NONE flow: write minimal `## UX Review` section, proceed silently
- [x] Define `## UX Review` heading contract (tier, decision, agents invoked, pencil available, findings)

### 1.2 Add conditional skip to Phase 3
- [x] Read Phase 3 SpecFlow section in plan SKILL.md
- [x] Add conditional: "If spec-flow-analyzer was invoked in Phase 2.5, skip this phase and proceed to Phase 4."

## Phase 2: Work Skill — Backstop Pre-Flight Check

### 2.1 Add check 7 to Phase 0.5 scope checks
- [x] Read `plugins/soleur/skills/work/SKILL.md`
- [x] Insert check 7 after existing check 6 (line 72) and before `**On FAIL:**` block (line 74)
- [x] Scan plan for `## UX Review` heading; if absent, grep for UI file patterns
- [x] WARN only (advisory, never blocking)

## Phase 3: Brainstorm Domain Config Enhancement

### 3.1 Broaden Product domain Assessment Question and Task Prompt
- [x] Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
- [x] Append UI creation signals to existing Product Assessment Question (line 10)
- [x] Update Product domain Task Prompt to include UI/UX analysis alongside product strategy
- [x] Verify new wording only triggers on NEW pages/flows, not modifications

## Phase 4: Constitution Annotation

### 4.1 Add enforcement annotation to line 122
- [x] Read `knowledge-base/project/constitution.md`
- [x] Add `[skill-enforced: plan Phase 2.5, work Phase 0.5]` prefix to line 122
