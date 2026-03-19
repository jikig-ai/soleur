# Tasks: Product/UX Gate for Engineering Workflows

**Plan:** `knowledge-base/plans/2026-03-19-feat-product-ux-gate-plan.md`
**Issue:** #671
**Branch:** feat-product-ux-gate

## Phase 1: Plan Skill — Phase 2.5 UI Detection Gate

### 1.1 Insert Phase 2.5 section in plan SKILL.md
- [ ] Read `plugins/soleur/skills/plan/SKILL.md`
- [ ] Insert new `### 2.5. Product/UX Gate` section after line 192 (end of Phase 2) and before Phase 3 (line 194)
- [ ] Include semantic assessment prompt with three tiers (BLOCKING, ADVISORY, NONE)
- [ ] Include BLOCKING flow: spec-flow-analyzer → CPO → ux-design-lead (conditional)
- [ ] Include ADVISORY flow: pipeline auto-accept or interactive AskUserQuestion
- [ ] Include NONE flow: write minimal `## UX Review` section, proceed silently
- [ ] Define `## UX Review` heading contract (tier, decision, agents invoked, pencil available, findings)

### 1.2 Add conditional skip to Phase 3
- [ ] Read Phase 3 SpecFlow section in plan SKILL.md
- [ ] Add conditional: "If spec-flow-analyzer was invoked in Phase 2.5, skip this phase and proceed to Phase 4."

## Phase 2: Work Skill — Backstop Pre-Flight Check

### 2.1 Add check 7 to Phase 0.5 scope checks
- [ ] Read `plugins/soleur/skills/work/SKILL.md`
- [ ] Insert check 7 after existing check 6 (line 72) and before `**On FAIL:**` block (line 74)
- [ ] Scan plan for `## UX Review` heading; if absent, grep for UI file patterns
- [ ] WARN only (advisory, never blocking)

## Phase 3: Brainstorm Domain Config Enhancement

### 3.1 Broaden Product domain Assessment Question and Task Prompt
- [ ] Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
- [ ] Append UI creation signals to existing Product Assessment Question (line 10)
- [ ] Update Product domain Task Prompt to include UI/UX analysis alongside product strategy
- [ ] Verify new wording only triggers on NEW pages/flows, not modifications

## Phase 4: Constitution Annotation

### 4.1 Add enforcement annotation to line 122
- [ ] Read `knowledge-base/project/constitution.md`
- [ ] Add `[skill-enforced: plan Phase 2.5, work Phase 0.5]` prefix to line 122
