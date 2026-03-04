# Tasks: fix gh issue list --jq --arg unsupported

## Phase 1: Core Fix

- [ ] 1.1 Update `scheduled-bug-fixer.yml` "Select issue" step to use `export` + `$ENV.OPEN_FIXES` instead of `--arg skip`
  - Add `export OPEN_FIXES` after the `OPEN_FIXES=$(gh pr list ...)` assignment (after line 70)
  - Remove `--arg skip "$OPEN_FIXES"` from the `--jq` flag (line 79)
  - Replace `$skip` with `$ENV.OPEN_FIXES` in the jq expression (line 80)
  - File: `.github/workflows/scheduled-bug-fixer.yml` lines 67-84

## Phase 2: Documentation

- [ ] 2.1 Update learnings document to reflect the corrected pattern
  - Fix the code example in section "3. Skip Issues With Open Bot-Fix PRs" to use `export OPEN_FIXES` + `$ENV.OPEN_FIXES`
  - Remove the `--arg skip` from the example
  - Add a note that `gh --jq` does not support jq flags like `--arg`; use `$ENV` instead
  - File: `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md` lines 37-46

## Phase 3: Verification

- [ ] 3.1 Run compound skill before commit
- [ ] 3.2 Edge cases already validated locally with jq binary (empty string, single number, comma-separated list all produce correct results)
