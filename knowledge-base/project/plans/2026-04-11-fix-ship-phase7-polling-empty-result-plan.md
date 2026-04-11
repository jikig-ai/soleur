---
title: "fix: ship Phase 7 release workflow polling gets stuck on empty parse result"
type: fix
date: 2026-04-11
---

# fix: ship Phase 7 release workflow polling gets stuck on empty parse result

## Enhancement Summary

**Deepened on:** 2026-04-11
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios, MVP)
**Research sources:** 6 institutional learnings, `gh` CLI `--jq` verification, SKILL.md Phase 7 full audit

### Key Improvements

1. Discovered a second polling location (item 3, Step 3 -- post-merge workflow validation) with the same missing max-iteration guard
2. Verified `gh run list --jq` returns `0` (not empty) for nonexistent commits -- confirming the `--jq` filter approach is safe
3. Added `--jq` filter for item 3 Step 3 to extract `status` directly instead of returning full JSON object
4. Added explicit `gh --jq` limitation awareness from learning `2026-03-04-gh-jq-does-not-support-arg-flag.md`

### New Considerations Discovered

- Item 3 Step 3 (`gh run list --workflow ... --jq '.[0]'`) returns a JSON object, forcing the agent to parse `status` from it -- same class of bug as the primary issue
- The `--jq` flag in `gh` CLI uses `gojq` (Go implementation), not system `jq` -- no external dependency needed, but `--arg` and `--argjson` are not supported
- Constitution mandates placing instructions at the step where they execute, not as deferred notes -- the max-iteration guard must be inline in the polling instruction, not a separate "NOTE" section

## Overview

The `/ship` Phase 7 release workflow verification polling gets stuck in an infinite loop when `gh run list` returns an empty array or the JSON parsing fails silently. The agent improvises Python3 inline parsing because the SKILL.md instructions do not provide explicit `--jq` filters for determining pending run count, and the result variable ends up empty (`""`) rather than `"0"`, so the loop exit condition never matches.

## Problem Statement

In PR #1935's ship session, Phase 7 Step 2 ran `gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion` which returns raw JSON without a `--jq` filter. The agent then attempted to count pending runs using an inline Python3 command:

```bash
PENDING=$(echo "$RUNS" | python3 -c "import json,sys; runs=json.load(sys.stdin); print(sum(1 for r in runs if r['status']!='completed'))")
```

This fails silently when:

1. `gh run list` returns `[]` (empty array -- workflows haven't registered yet)
2. The JSON structure changes between calls (new runs appear mid-poll)
3. Python3 stderr is swallowed by the pipeline

When parsing fails, `$PENDING` is empty (`""`), not `"0"`. The loop condition `if [ "$PENDING" = "0" ]` never matches, so the poll runs indefinitely until the overall timeout kills it.

## Root Cause

The SKILL.md Phase 7 Step 2 gives a `gh run list` command **without** a `--jq` filter, forcing the agent to parse raw JSON output. The agent improvises with Python3 (which may not even be available on all systems), and that improvisation has no fallback for empty or malformed input.

Additionally, there is no explicit handling in the instructions for:

- Empty `gh run list` results (no workflows triggered yet)
- Maximum poll iteration limit
- Validation that the parsing step produced a usable value

### Research Insights

**Institutional learnings that apply:**

- **`2026-03-04-gh-jq-does-not-support-arg-flag.md`:** `gh --jq` is a thin wrapper over jq's `-r` flag, not a full jq CLI emulator. It does not support `--arg`, `--argjson`, or `--slurpfile`. The `--jq` filter must be a single self-contained expression. This is fine for our use case (`select` + `length`), but constrains future extensions.
- **`2026-03-10-jq-generator-silent-data-loss.md`:** jq generators that produce zero results cause the entire surrounding expression to emit nothing. Our `[.[] | select(...)] | length` pattern is safe because the array constructor `[...]` always produces an array (empty yields `[]`, and `[] | length` yields `0`). However, if someone later removes the array wrapper, `select` alone would produce nothing on zero matches.
- **`2026-03-18-stop-hook-jq-invalid-json-guard.md`:** `jq`'s `// ""` alternative operator handles missing keys but does NOT handle invalid JSON input. When using `gh --jq`, invalid JSON from a network error would cause a parse error. The `gh` CLI handles this internally (returning exit code 1), but the SKILL.md instructions should tell the agent to check exit codes.
- **`2026-03-29-post-merge-release-workflow-verification.md`:** Documents the original motivation for Phase 7 release verification. PR CI and release CI test different things -- a dependency change can pass PR CI while breaking release CI.

**Verified behavior:**

- `gh run list --commit <nonexistent-sha> --json databaseId,status --jq '[.[] | select(.status != "completed")] | length'` returns `0` (not empty string) -- confirmed via live test
- `echo '[]' | jq '[.[] | select(.status != "completed")] | length'` returns `0` -- confirmed via live test
- `echo '[{"status":"completed"},{"status":"in_progress"}]' | jq '[.[] | select(.status != "completed")] | length'` returns `1` -- confirmed via live test

## Proposed Solution

### Change 1: Add `--jq` filters to Phase 7 item 2 Step 2

Replace the raw JSON output command with a `--jq` filter that directly produces a count of pending runs:

**Before** (SKILL.md line ~605):

```bash
gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion
```

**After:**

```bash
gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion --jq '[.[] | select(.status != "completed")] | length'
```

This produces a single integer (e.g., `0`, `2`, `3`) directly, eliminating the need for external JSON parsing.

### Change 2: Add empty-result fallback to item 2 Step 2

Add explicit instructions for handling the case where `gh run list` returns an empty array (`[]`), which produces `0` from the `--jq` filter. The agent must distinguish between:

- "0 pending because all runs completed" (success -- proceed)
- "0 pending because no runs have registered yet" (wait and retry)

Add a two-phase approach:

1. First, check total run count: `gh run list --branch main --commit <merge-sha> --json databaseId --jq 'length'`
2. If total is `0` and fewer than 3 retries have been attempted, wait 15 seconds and re-query (workflows may not have registered yet)
3. If total is still `0` after 3 retries (45 seconds total), treat as "no workflows triggered" and skip verification

### Change 3: Add maximum poll iteration guard to item 2 Step 3

Add an explicit instruction that the poll loop must exit after a maximum number of iterations (e.g., 40 iterations at 30 seconds = 20 minutes), reporting a timeout rather than hanging indefinitely. This is defense-in-depth against any future parsing issue.

Per constitution ("Multi-step LLM prompts must place every instruction at the step where it executes"), the max-iteration guard must be inline in the Step 3 polling instruction, not a separate "NOTE" or "IMPORTANT" block elsewhere.

### Change 4: Add result validation instruction

Add an explicit instruction that after any parsing/filtering step, the agent must validate the result is a non-empty integer before using it in a comparison. If the result is empty or non-numeric, treat it as an error and re-query once before failing.

### Change 5: Fix item 3 Step 3 polling (secondary fix)

The post-merge workflow validation polling (item 3, Step 3, line ~642-650) has the same missing max-iteration guard and uses `--jq '.[0]'` which returns a full JSON object instead of extracting the `status` field directly.

**Before** (SKILL.md line ~645):

```bash
gh run list --workflow <workflow-filename> --limit 1 --json databaseId,status,conclusion --jq '.[0]'
```

**After:**

```bash
gh run list --workflow <workflow-filename> --limit 1 --json databaseId,status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"'
```

This matches the pattern already used in item 2 Step 3 (`gh run view <id> --json status,conclusion --jq '"\(.status) \(.conclusion)"'`), making the output format consistent across all polling locations.

Also add the same max-iteration guard (40 iterations / 20 minutes) to this polling loop.

## Technical Considerations

- **No Python3 dependency.** The `--jq` flag is built into `gh` CLI (uses Go's `gojq`), so it is always available. Python3 is not guaranteed on all systems.
- **Backward compatibility.** This changes SKILL.md instructions only -- no code changes, no CI changes, no infrastructure changes.
- **Agent interpretation.** The clearer the instructions, the less room for improvisation. Providing exact command templates with `--jq` filters eliminates the parsing ambiguity.
- **Step 3 already uses `--jq`.** The individual run polling in item 2 Step 3 (`gh run view <id> --json status,conclusion --jq ...`) already uses the correct pattern. Item 2 Step 2 and item 3 Step 3 are the outliers.
- **`gh --jq` limitations.** The `--jq` flag does not support `--arg` or `--argjson`. All filter expressions must be self-contained strings. The `select` + `length` pattern used here is within those constraints.
- **jq array safety.** The `[.[] | select(...)] | length` pattern is safe for empty arrays because the array constructor `[...]` always produces an array. An empty input yields `[]`, and `[] | length` yields `0`. Do not simplify to a bare `select` without the array wrapper.

### Edge Cases

- **Race condition: new workflow appears mid-poll.** Between Step 2 and Step 3, a new workflow run can register (e.g., a `workflow_run` trigger). The pending count from Step 2 becomes stale. This is acceptable because Step 3 polls individual runs by ID -- it will complete when all known runs complete, and any new runs will be caught on the next iteration of the overall polling loop.
- **`gh` CLI network timeout.** If `gh run list` hangs due to network issues, the Bash tool's 2-minute timeout will kill it. The agent should treat a timeout as a failed query and retry once.
- **Workflow with `status: queued` vs `status: in_progress`.** Both are non-`completed` statuses. The `select(.status != "completed")` filter correctly captures both.

## Acceptance Criteria

- [x] Phase 7 item 2 Step 2 `gh run list` command includes `--jq` filter that outputs pending run count as an integer
- [x] Phase 7 item 2 Step 2 includes explicit handling for empty results (0 total runs = workflows not yet registered)
- [x] Phase 7 item 2 Step 2 includes a retry mechanism for the "no runs registered yet" case (up to 3 retries with 15-second waits)
- [x] Phase 7 item 2 Step 3 polling includes a maximum iteration guard (exit after 40 iterations / 20 minutes)
- [x] Phase 7 includes result validation: empty or non-numeric parsing results trigger a re-query, not infinite loop
- [x] Phase 7 item 3 Step 3 `gh run list` command uses `--jq` filter that extracts status string directly (not full JSON object)
- [x] Phase 7 item 3 Step 3 polling includes a maximum iteration guard (exit after 40 iterations / 20 minutes)
- [x] No Python3 dependency in any Phase 7 instruction
- [x] markdownlint passes on the modified SKILL.md

## Test Scenarios

- Given a merge commit with 2 pending workflows, when Phase 7 item 2 Step 2 runs, then the `--jq` filter outputs `2` and polling continues
- Given a merge commit where `gh run list` returns `[]` (empty array), when Phase 7 item 2 Step 2 runs, then the `--jq` filter outputs `0`, the total-count check detects 0 total runs, and it retries up to 3 times before treating as "no workflows triggered"
- Given a merge commit with all workflows completed, when Phase 7 item 2 Step 2 runs, then the `--jq` filter outputs `0`, the total-count check shows runs exist, and it proceeds to conclusion checking
- Given a polling loop that has run 40 iterations without all runs completing, when the 41st iteration would start, then the loop exits with a timeout report instead of continuing indefinitely
- Given a `--jq` filter that returns empty string (e.g., `gh` CLI network error), when the result is validated, then the agent re-queries once before reporting an error
- Given a post-merge workflow validation poll (item 3 Step 3), when `gh run list --workflow` returns a completed run, then the `--jq` filter outputs `"completed success"` (not a JSON object)
- Given a post-merge workflow validation poll that has run 40 iterations, when the 41st iteration would start, then the loop exits with a timeout report

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- **Issue:** #1946
- **Evidence:** PR #1935 ship session exhibited 8 iterations with `pending=` (empty) before timeout
- **Related learning:** `knowledge-base/project/learnings/2026-03-29-post-merge-release-workflow-verification.md`
- **File to modify:** `plugins/soleur/skills/ship/SKILL.md` (lines ~600-660)

## MVP

### plugins/soleur/skills/ship/SKILL.md -- Primary fix: item 2 Steps 2-3

Replace the current Step 2 block (approximately lines 602-606) with:

```markdown
   **Step 2:** Wait 15 seconds for workflows to trigger, then count pending runs on the merge commit:

   ```bash
   gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion --jq '[.[] | select(.status != "completed")] | length'
   ```

   This outputs a single integer (the count of non-completed runs). If the output is empty or non-numeric, re-run the command once. If still invalid, report an error and abort.

   **Empty-result fallback:** If the pending count is `0`, verify that runs actually exist:

   ```bash
   gh run list --branch main --commit <merge-sha> --json databaseId --jq 'length'
   ```

- If total runs > 0 and pending = 0: all runs completed. Proceed to Step 4.
- If total runs = 0: workflows have not registered yet. Wait 15 seconds and re-query. Retry up to 3 times (45 seconds total). If still 0 after 3 retries, treat as "no workflows triggered" and skip verification (the PR only touched files outside all path filters).

```

Replace the current Step 3 block (approximately lines 608-614) with:

```markdown
   **Step 3:** For each run that is not yet `completed`, poll every 30 seconds:

   ```bash
   gh run view <id> --json status,conclusion --jq '"\(.status) \(.conclusion)"'
   ```

   Poll until all runs report `completed`. Maximum 40 iterations (20 minutes). If the maximum is reached, report: "Release verification timed out after 20 minutes. N runs still pending: [list workflow names and IDs]." Do NOT silently continue -- investigate the stalled workflows.

```

### plugins/soleur/skills/ship/SKILL.md -- Secondary fix: item 3 Step 3

Replace the current item 3 Step 3 block (approximately lines 642-650) with:

```markdown
   **Step 3:** Poll each triggered run until completion (check every 30 seconds):

   ```bash
   gh run list --workflow <workflow-filename> --limit 1 --json databaseId,status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"'
   ```

   Poll until output starts with `completed`. Maximum 40 iterations (20 minutes). If the maximum is reached, report: "Post-merge validation timed out after 20 minutes for workflow [name]." Do NOT silently continue. Then check `conclusion`:

- **success**: Report pass and continue
- **failure**: Report failure, fetch logs with `gh run view <id> --log | tail -50`, and present the error to the user. Do NOT silently proceed.

```

## References

- Issue: #1946
- PR that exposed the bug: #1935
- Learning: `knowledge-base/project/learnings/2026-03-29-post-merge-release-workflow-verification.md`
- Learning: `knowledge-base/project/learnings/2026-03-04-gh-jq-does-not-support-arg-flag.md`
- Learning: `knowledge-base/project/learnings/2026-03-10-jq-generator-silent-data-loss.md`
- Learning: `knowledge-base/project/learnings/2026-03-18-stop-hook-jq-invalid-json-guard.md`
- Learning: `knowledge-base/project/learnings/2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`
- Ship skill: `plugins/soleur/skills/ship/SKILL.md`
