# Tasks: fix gh issue list --jq --arg unsupported

## Phase 1: Core Fix

- [ ] 1.1 Update `scheduled-bug-fixer.yml` "Select issue" step to inline `$OPEN_FIXES` directly into the jq expression string instead of using `--arg skip`
  - Replace `--jq --arg skip "$OPEN_FIXES" '($skip | split(",") ...'` with `--jq '("'"$OPEN_FIXES"'" | split(",") ...'`
  - Replace all `$skip` references inside the jq expression with the inlined string literal
  - File: `.github/workflows/scheduled-bug-fixer.yml` lines 79-84

## Phase 2: Documentation

- [ ] 2.1 Update learnings document to reflect the corrected pattern
  - Fix the code example in section "3. Skip Issues With Open Bot-Fix PRs" to remove `--arg` usage
  - Add a note that `gh --jq` does not support jq flags like `--arg`
  - File: `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md` lines 40-46

## Phase 3: Verification

- [ ] 3.1 Run compound skill before commit
- [ ] 3.2 Verify the jq expression handles edge cases: empty `OPEN_FIXES`, single number, comma-separated list
