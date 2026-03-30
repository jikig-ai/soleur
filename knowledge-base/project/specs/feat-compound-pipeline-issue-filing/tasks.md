# Tasks: fix(compound) route-to-definition pipeline issue filing

## Phase 1: Update compound/SKILL.md

- [ ] 1.1 Read `plugins/soleur/skills/compound/SKILL.md`
- [ ] 1.2 Locate the "Route Learning to Definition" section (line 263)
- [ ] 1.3 Replace the headless mode instruction from "auto-accept the LLM-proposed edit" to "file a GitHub issue with the proposed edit"
  - [ ] 1.3.1 Use angle-bracket placeholders (not shell variables) per constitution "Never" rule
  - [ ] 1.3.2 Include `--milestone "Post-MVP / Later"` in the `gh issue create` instruction
  - [ ] 1.3.3 Include skip condition for non-actionable edits (empty or target file missing)
  - [ ] 1.3.4 Do NOT use stop-like language -- say "proceed to the decision menu"

## Phase 2: Update compound-capture/SKILL.md

- [ ] 2.1 Read `plugins/soleur/skills/compound-capture/SKILL.md`
- [ ] 2.2 Add headless mode handling to Step 8.2 (Select Target) after line 295
  - [ ] 2.2.1 Auto-select most relevant component using LLM judgment when multiple detected
  - [ ] 2.2.2 Use single component if only one detected
- [ ] 2.3 Replace Step 8.4 (Confirm) content (lines 320-332) with headless/interactive split
  - [ ] 2.3.1 Headless: write body to `/tmp/compound-rtd-body.md`, then `gh issue create --body-file`
  - [ ] 2.3.2 Headless: include graceful degradation on `gh issue create` failure (log error, continue)
  - [ ] 2.3.3 Headless: update `synced_to` frontmatter with `<definition-name>-issue-<number>`
  - [ ] 2.3.4 Interactive: preserve existing Accept/Skip/Edit via AskUserQuestion (unchanged)
  - [ ] 2.3.5 Interactive: preserve existing `synced_to` frontmatter update logic

## Phase 3: Validation

- [ ] 3.1 Run `npx markdownlint-cli2 --fix` on both modified SKILL.md files
- [ ] 3.2 Re-read both files after editing to verify headless/interactive branches are correct
- [ ] 3.3 Verify `gh issue create` includes `--milestone` (Guard 5 in guardrails.sh blocks without it)
- [ ] 3.4 Verify no shell variable expansion (`${VAR}`, `$()`) in SKILL.md instructions
- [ ] 3.5 Verify no stop-like language ("done", "complete", "return") after issue creation step
