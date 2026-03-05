# Tasks: fix-compound-fanout-exceeds-max-5

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/skills/compound/SKILL.md` to confirm current subagent count and line numbers
- [ ] 1.2 Read `knowledge-base/overview/constitution.md` to verify max-5 rule at line 148 and sequential-phase principle at line 201

## Phase 2: Core Implementation (single file: `plugins/soleur/skills/compound/SKILL.md`)

- [ ] 2.1 Remove `### 5. **Category Classifier** (Parallel)` section (lines 100-106)
- [ ] 2.2 Renumber `### 6. **Documentation Writer** (Parallel)` to `### 5.` and prepend the 3 Category Classifier bullets before existing bullets
  - Final merged section has 7 bullets: determines category, validates category against schema, suggests filename, assembles markdown, validates YAML, formats content, creates file
- [ ] 2.3 Renumber `### 7. **Optional: Specialized Agent Invocation**` to `### 6.`
- [ ] 2.4 Verify Phase 1.5 Deviation Analyst text (line 125) -- NO CHANGE NEEDED (becomes accurate post-fix)
- [ ] 2.5 Update Success Output block (lines 343-348): remove Category Classifier line, update Documentation Writer line to "Classified to performance-issues/, created complete markdown"

## Phase 3: Verification

- [ ] 3.1 Count `### N.` headers under `## Execution Strategy` to verify exactly 5 parallel subagents
- [ ] 3.2 Verify merged Documentation Writer section includes all 7 bullets (3 from Classifier + 4 original)
- [ ] 3.3 Verify Success Output shows exactly 5 Primary Subagent Results
- [ ] 3.4 Verify `### 6.` is Optional Specialized Agent Invocation (not Documentation Writer)
- [ ] 3.5 Grep compound-capture SKILL.md for any subagent names -- expect zero matches
- [ ] 3.6 Run markdownlint on `plugins/soleur/skills/compound/SKILL.md`
- [ ] 3.7 Run compound skill end-to-end to verify execution
