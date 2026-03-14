# Tasks: fix skill discovery context compaction

Closes #618

## Phase 1: Setup and Diagnosis

- [ ] 1.1 Verify current baseline: run `bun test` to confirm all existing tests pass
- [ ] 1.2 Measure current cumulative description word count across all 58 skills (baseline: ~2,729 words)
- [ ] 1.3 Measure current cumulative description character count (baseline: ~19,960 chars)

## Phase 2: Create Verification Tooling

- [ ] 2.1 Create `plugins/soleur/scripts/verify-skills.sh` with skill validation logic (name match, description length, duplicates, word count)
- [ ] 2.2 Make script executable: `chmod +x plugins/soleur/scripts/verify-skills.sh`
- [ ] 2.3 Add cumulative description word budget test to `plugins/soleur/test/components.test.ts` (ceiling: 2,000 words)
- [ ] 2.4 Run `verify-skills.sh` to confirm it correctly reports current state (expect: over budget)

## Phase 3: Trim Skill Descriptions

- [ ] 3.1 Audit all 58 skill descriptions and categorize by trimming opportunity:
  - Remove trigger phrase lists (e.g., `Triggers on "ready to ship", ...`)
  - Shorten verbose restated descriptions
  - Preserve routing-critical keywords
  - Maintain third-person voice convention
- [ ] 3.2 Trim descriptions for skills in the "Content & Release" category (~21 skills)
- [ ] 3.3 Trim descriptions for skills in the "Development" category (~11 skills)
- [ ] 3.4 Trim descriptions for skills in the "Review & Planning" category (~7 skills)
- [ ] 3.5 Trim descriptions for skills in the "Workflow" category (~18 skills)
- [ ] 3.6 Verify cumulative word count is under 2,000 words

## Phase 4: Testing and Validation

- [ ] 4.1 Run `bun test` -- all existing tests plus new budget test must pass
- [ ] 4.2 Run `verify-skills.sh` -- must report `[ok] all skills verified`
- [ ] 4.3 Verify each trimmed description still starts with "This skill" (convention test)
- [ ] 4.4 Spot-check: invoke `soleur:work`, `soleur:compound`, `soleur:ship` via Skill tool to confirm they resolve

## Phase 5: Commit and Ship

- [ ] 5.1 Run `soleur:compound` to capture learnings
- [ ] 5.2 Commit all changes
- [ ] 5.3 Push and create PR (Closes #618)
