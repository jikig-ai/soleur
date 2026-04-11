# Tasks: fix ship Phase 7 polling empty result

## Status Legend

- [ ] Not started
- [x] Complete

## Phase 1: Setup

- [ ] 1.1 Read current `plugins/soleur/skills/ship/SKILL.md` Phase 7 section (lines ~595-660)
- [ ] 1.2 Verify the exact line numbers of item 2 Steps 2-3 and item 3 Step 3 blocks

## Phase 2: Core Implementation -- Primary Fix (item 2)

- [ ] 2.1 Replace item 2 Step 2 `gh run list` command with `--jq` filter version
  - [ ] 2.1.1 Add `--jq '[.[] | select(.status != "completed")] | length'` to the existing command
  - [ ] 2.1.2 Add result validation instruction (empty/non-numeric check)
- [ ] 2.2 Add empty-result fallback block after item 2 Step 2 command
  - [ ] 2.2.1 Add total run count check: `gh run list ... --jq 'length'`
  - [ ] 2.2.2 Add retry logic for "no runs registered yet" case (3 retries, 15s waits)
  - [ ] 2.2.3 Add "no workflows triggered" skip condition after retries exhausted
- [ ] 2.3 Add maximum poll iteration guard to item 2 Step 3
  - [ ] 2.3.1 Add "Maximum 40 iterations (20 minutes)" instruction inline in Step 3
  - [ ] 2.3.2 Add timeout reporting instruction with workflow names and IDs

## Phase 3: Secondary Fix (item 3)

- [ ] 3.1 Replace item 3 Step 3 `--jq '.[0]'` with `--jq '.[0] | "\(.status) \(.conclusion)"'`
- [ ] 3.2 Add maximum poll iteration guard to item 3 Step 3 (same 40 iterations / 20 minutes)
- [ ] 3.3 Update "Poll until" instruction to match output format (`completed` prefix check)

## Phase 4: Verification

- [ ] 4.1 Verify item 2 Step 3 existing `--jq` filter is unchanged (already correct)
- [ ] 4.2 Verify no Python3 references exist in the file after changes
- [ ] 4.3 Run `npx markdownlint-cli2 --fix` on modified SKILL.md
- [ ] 4.4 Verify the modified section renders correctly (no broken markdown fences)
- [ ] 4.5 Run full test suite to verify no regressions
