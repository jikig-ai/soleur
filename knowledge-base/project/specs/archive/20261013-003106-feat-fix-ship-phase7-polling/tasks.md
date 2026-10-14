# Tasks: fix ship Phase 7 polling empty result

## Status Legend

- [ ] Not started
- [x] Complete

## Phase 1: Setup

- [x] 1.1 Read current `plugins/soleur/skills/ship/SKILL.md` Phase 7 section (lines ~595-660)
- [x] 1.2 Verify the exact line numbers of item 2 Steps 2-3 and item 3 Step 3 blocks

## Phase 2: Core Implementation -- Primary Fix (item 2)

- [x] 2.1 Replace item 2 Step 2 `gh run list` command with `--jq` filter version
  - [x] 2.1.1 Add `--jq '[.[] | select(.status != "completed")] | length'` to the existing command
  - [x] 2.1.2 Add result validation instruction (empty/non-numeric check)
- [x] 2.2 Add empty-result fallback block after item 2 Step 2 command
  - [x] 2.2.1 Add total run count check: `gh run list ... --jq 'length'`
  - [x] 2.2.2 Add retry logic for "no runs registered yet" case (3 retries, 15s waits)
  - [x] 2.2.3 Add "no workflows triggered" skip condition after retries exhausted
- [x] 2.3 Add maximum poll iteration guard to item 2 Step 3
  - [x] 2.3.1 Add "Maximum 40 iterations (20 minutes)" instruction inline in Step 3
  - [x] 2.3.2 Add timeout reporting instruction with workflow names and IDs

## Phase 3: Secondary Fix (item 3)

- [x] 3.1 Replace item 3 Step 3 `--jq '.[0]'` with `--jq '.[0] | "\(.status) \(.conclusion)"'`
- [x] 3.2 Add maximum poll iteration guard to item 3 Step 3 (same 40 iterations / 20 minutes)
- [x] 3.3 Update "Poll until" instruction to match output format (`completed` prefix check)

## Phase 4: Verification

- [x] 4.1 Verify item 2 Step 3 existing `--jq` filter is unchanged (already correct)
- [x] 4.2 Verify no Python3 references exist in the file after changes
- [x] 4.3 Run `npx markdownlint-cli2 --fix` on modified SKILL.md
- [x] 4.4 Verify the modified section renders correctly (no broken markdown fences)
- [x] 4.5 Run full test suite to verify no regressions
