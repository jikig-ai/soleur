# Tasks: Architecture Principles Register

## Phase 1: Create the Principles Register

- [x] 1.1 Create `knowledge-base/engineering/architecture/` directory
- [x] 1.2 Create `principles-register.md` with ~12 architecture-only principles in flat table format
- [x] 1.3 Verify each canonical source link resolves to the correct AGENTS.md/constitution.md section
- [x] 1.4 Verify related NFR IDs match entries in `nfr-reference.md`

## Phase 2: Architecture Skill — `principle list` Sub-command

- [x] 2.1 Add `architecture principle list` to sub-command table in SKILL.md
- [x] 2.2 Add `## Sub-command: principle list` section with steps (read register, display table)
- [x] 2.3 Verify cumulative skill description word count does not increase

## Phase 3: ADR Template and `create` Sub-command Update

- [x] 3.1 Add `## Principle Alignment` section to ADR template body after `## NFR Impacts` and before `## Diagram`
- [x] 3.2 Add format examples showing Aligned/Deviation/N/A usage
- [x] 3.3 Update `create` sub-command step 6 to gather Principle Alignment alongside NFR Impacts

## Phase 4: Extend `assess` Sub-command

- [x] 4.1 Add principles register read step after NFR register read
- [x] 4.2 Add principle alignment assessment step after NFR assessment
- [x] 4.3 Add principle alignment output section to assess output format
- [x] 4.4 Update "Offer to create an ADR" step to mention pre-filled principle alignment

## Phase 5: Architecture-Strategist Agent Update

- [x] 5.1 Add principles register reading to "Your evaluation must verify" list
- [x] 5.2 Add "Principle Alignment" as sub-item under "3. Compliance Check" in structured output
- [x] 5.3 Verify agent description word count unchanged (body changes only)

## Verification

- [x] 6.1 Run `npx markdownlint-cli2 --fix` on all changed files
- [x] 6.2 Run `grep -h 'description:' plugins/soleur/skills/*/SKILL.md | wc -w` — must not exceed current (1,892)
- [x] 6.3 Run `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` — must stay under 2,500
