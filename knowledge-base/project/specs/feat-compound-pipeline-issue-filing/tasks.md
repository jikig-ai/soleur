# Tasks: fix(compound) route-to-definition pipeline issue filing

## Phase 1: Update compound/SKILL.md

- [ ] 1.1 Read `plugins/soleur/skills/compound/SKILL.md`
- [ ] 1.2 Locate the "Route Learning to Definition" section (around line 253-268)
- [ ] 1.3 Replace the headless mode instruction (line 263) from "auto-accept the LLM-proposed edit" to "file a GitHub issue with the proposed edit"
- [ ] 1.4 Verify the updated instruction includes: issue title format, body content requirements, milestone "Post-MVP / Later", and the skip condition for non-actionable edits

## Phase 2: Update compound-capture/SKILL.md

- [ ] 2.1 Read `plugins/soleur/skills/compound-capture/SKILL.md`
- [ ] 2.2 Add headless mode handling to Step 8.2 (Select Target) -- auto-select most relevant component without prompting
- [ ] 2.3 Add headless mode handling to Step 8.4 (Confirm) -- file GitHub issue instead of applying edit or prompting
  - [ ] 2.3.1 Include `gh issue create` command template with title, body, and milestone
  - [ ] 2.3.2 Include `synced_to` frontmatter update with issue number reference
  - [ ] 2.3.3 Ensure interactive mode behavior is explicitly preserved (Accept/Skip/Edit unchanged)

## Phase 3: Validation

- [ ] 3.1 Run `npx markdownlint-cli2 --fix` on both modified files
- [ ] 3.2 Verify no contradictions between compound/SKILL.md and compound-capture/SKILL.md headless instructions
- [ ] 3.3 Verify the `gh issue create` command includes `--milestone` (required by AGENTS.md guardrail)
