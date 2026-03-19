# Tasks: Expand Plan Phase 2.5 Domain Detection

## Phase 1: Brainstorm Domain Persistence (FR6)

- [ ] 1.1 Read `plugins/soleur/skills/brainstorm/SKILL.md` Phase 3.5 (lines 178-191)
- [ ] 1.2 Add `## Domain Assessments` section instructions to Phase 3.5 capture
  - [ ] 1.2.1 One-line `**Assessed:**` field listing all 8 domains
  - [ ] 1.2.2 Per-domain subsections with `**Summary:**` for relevant domains only
  - [ ] 1.2.3 Conditional: only write section if domain leaders participated in Phase 0.5

## Phase 2: Replace Phase 2.5 with Domain Review Gate (FR1-FR5, TR3, TR5)

- [ ] 2.1 Read `plugins/soleur/skills/plan/SKILL.md` Phase 2.5 (lines 194-244)
- [ ] 2.2 Rename section header: `### 2.5. Product/UX Gate` → `### 2.5. Domain Review Gate`
- [ ] 2.3 Implement Step 1 — Domain Sweep
  - [ ] 2.3.1 Brainstorm carry-forward check: parse `## Domain Assessments` from brainstorm doc
  - [ ] 2.3.2 Fresh assessment fallback: read `brainstorm-domain-config.md`, single-pass LLM assessment of all 8 domains
  - [ ] 2.3.3 Spawn domain leaders as blocking Tasks for relevant non-Product domains (parallel)
  - [ ] 2.3.4 Error handling: partial findings with `Status: error` on leader failure
- [ ] 2.4 Preserve Step 2 — Product/UX Gate
  - [ ] 2.4.1 Retain BLOCKING/ADVISORY/NONE classification
  - [ ] 2.4.2 Retain spec-flow-analyzer → CPO → ux-design-lead pipeline
  - [ ] 2.4.3 Step 2 only fires if Product domain flagged relevant in sweep
  - [ ] 2.4.4 Retain self-referential exclusion for orchestration-only plans
- [ ] 2.5 Define `## Domain Review` heading contract (minimal: Domains relevant + per-domain Status/Assessment + Product/UX Gate subsection)
- [ ] 2.6 Update `plugins/soleur/skills/work/SKILL.md` line 73: accept `## Domain Review` OR `## UX Review` (backward-compatible)
- [ ] 2.7 Update `knowledge-base/project/constitution.md` line 122 with all-domain enforcement text
- [ ] 2.8 Verify no other active SKILL.md files reference `## UX Review`: `grep -r '## UX Review' plugins/soleur/skills/`

## Phase 3: Validation

- [ ] 3.1 Test: plan with new third-party service → legal + ops detected
- [ ] 3.2 Test: backend-only plan → `## Domain Review` with "none"
- [ ] 3.3 Test: brainstorm → plan carry-forward of `## Domain Assessments`
- [ ] 3.4 Test: one-shot pipeline with 3+ domains → domain review gate fires, observe context behavior (TR4)
- [ ] 3.5 Test: existing plan with `## UX Review` heading passes work skill backstop
- [ ] 3.6 Final grep: no `## UX Review` in active skill files (except backward-compat in work SKILL.md)
