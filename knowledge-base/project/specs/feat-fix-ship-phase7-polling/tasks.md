# Tasks: fix ship Phase 7 polling empty result

## Status Legend

- [ ] Not started
- [x] Complete

## Phase 1: Setup

- [ ] 1.1 Read current `plugins/soleur/skills/ship/SKILL.md` Phase 7 section (lines ~595-660)
- [ ] 1.2 Verify the exact line numbers of Step 2, Step 3, and Step 4 blocks

## Phase 2: Core Implementation

- [ ] 2.1 Replace Step 2 `gh run list` command with `--jq` filter version
  - [ ] 2.1.1 Add `--jq '[.[] | select(.status != "completed")] | length'` to the existing command
  - [ ] 2.1.2 Add result validation instruction (empty/non-numeric check)
- [ ] 2.2 Add empty-result fallback block after Step 2 command
  - [ ] 2.2.1 Add total run count check: `gh run list ... --jq 'length'`
  - [ ] 2.2.2 Add retry logic for "no runs registered yet" case (3 retries, 15s waits)
  - [ ] 2.2.3 Add "no workflows triggered" skip condition after retries exhausted
- [ ] 2.3 Add maximum poll iteration guard to Step 3
  - [ ] 2.3.1 Add "Maximum 40 iterations (20 minutes)" instruction
  - [ ] 2.3.2 Add timeout reporting instruction with workflow names and IDs
- [ ] 2.4 Verify Step 3 existing `--jq` filter is correct (it already uses `--jq`)
- [ ] 2.5 Verify no Python3 references exist in the file after changes

## Phase 3: Validation

- [ ] 3.1 Run `npx markdownlint-cli2 --fix` on modified SKILL.md
- [ ] 3.2 Verify the modified section renders correctly (no broken markdown fences)
- [ ] 3.3 Run full test suite to verify no regressions
