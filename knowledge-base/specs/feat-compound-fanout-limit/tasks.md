# Tasks: fix-compound-fanout-exceeds-max-5

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/skills/compound/SKILL.md` to confirm current subagent count and line numbers
- [ ] 1.2 Read `knowledge-base/overview/constitution.md` to verify max-5 rule text at line 148

## Phase 2: Core Implementation

- [ ] 2.1 Merge Category Classifier into Documentation Writer in `plugins/soleur/skills/compound/SKILL.md`
  - [ ] 2.1.1 Remove `### 5. **Category Classifier** (Parallel)` section (lines 100-106)
  - [ ] 2.1.2 Renumber `### 6. **Documentation Writer** (Parallel)` to `### 5.`
  - [ ] 2.1.3 Add Category Classifier bullets to merged Documentation Writer: "Determines optimal category," "Validates category against schema," "Suggests filename based on slug"
- [ ] 2.2 Renumber `### 7. **Optional: Specialized Agent Invocation**` to `### 6.`
- [ ] 2.3 Update Phase 1.5 Deviation Analyst paragraph if it references subagent count
- [ ] 2.4 Update Success Output block to show 5 Primary Subagent Results (remove Category Classifier line, merge into Documentation Writer line)

## Phase 3: Testing

- [ ] 3.1 Count `### N.` headers under `## Execution Strategy` to verify exactly 5 parallel subagents
- [ ] 3.2 Verify merged Documentation Writer section includes all 6 former responsibilities (3 from Classifier + 3 original)
- [ ] 3.3 Verify Success Output shows exactly 5 Primary Subagent Results
- [ ] 3.4 Run markdownlint on `plugins/soleur/skills/compound/SKILL.md`
- [ ] 3.5 Run compound skill to verify end-to-end execution
