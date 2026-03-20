# Learning: CI lint scripts that grep for inline patterns break when you extract to a shared script

## Problem
Extracted duplicated inline `gh api` calls from 9 workflow files into `scripts/post-bot-statuses.sh`. The architecture review agent discovered that `scripts/lint-bot-synthetic-statuses.sh` (merged to main separately in #842) greps for literal `context=cla-check` and `context=test` in workflow files. After the extraction, those strings only exist in the shared script, not the workflows — causing the lint to flag all 9 files as failures.

## Solution
Updated the lint script to accept either pattern:
- The inline `context=$ctx` grep (legacy/fallback)
- The `post-bot-statuses.sh` script call (new canonical pattern)

Added a test case (Test 8) for the shared script pattern to `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh`.

## Key Insight
When extracting duplicated code into a shared utility, always search for CI lint or validation scripts that grep for the inline pattern being removed. The lint and the code under lint are coupled by string matching — extracting the code breaks the lint even though behavior is preserved. Run `grep -r` for the exact strings being removed to find any downstream consumers before merging.

## Session Errors
1. Security hook blocked first batch of 9 workflow edits (informational PreToolUse hook fired as error, re-applied successfully on second attempt)
2. Ralph loop setup script path was wrong on first try (`skills/one-shot/scripts/` vs `scripts/`)

## Tags
category: integration-issues
module: ci-workflows
