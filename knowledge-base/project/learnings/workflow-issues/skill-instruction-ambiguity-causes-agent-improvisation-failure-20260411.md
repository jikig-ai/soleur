---
module: System
date: 2026-04-11
problem_type: workflow_issue
component: tooling
symptoms:
  - "Ship Phase 7 polling stuck indefinitely with pending= (empty string)"
  - "Agent improvises Python3 inline JSON parsing when SKILL.md lacks --jq filter"
  - "Poll loop exit condition never matches because empty string != '0'"
root_cause: missing_workflow_step
resolution_type: documentation_update
severity: medium
tags: [ship, phase-7, polling, jq, gh-cli, infinite-loop, agent-improvisation]
---

# Troubleshooting: Skill instruction ambiguity causes agent improvisation failure

## Problem

The `/ship` Phase 7 release workflow verification polling got stuck in an infinite loop because the SKILL.md instructions provided a `gh run list` command without a `--jq` filter, forcing the agent to improvise JSON parsing with Python3. The improvised parsing failed silently on empty input, producing an empty string instead of `"0"`, so the loop exit condition never matched.

## Environment

- Module: System (ship skill, Phase 7)
- Affected Component: `plugins/soleur/skills/ship/SKILL.md` lines 602-650
- Date: 2026-04-11

## Symptoms

- Ship Phase 7 ran 8 polling iterations with `pending=` (empty) before timing out
- Agent used `python3 -c "import json,sys; ..."` to parse raw JSON from `gh run list`
- Python3 stderr was swallowed by the pipeline, masking the parse failure
- All workflows were actually completed, but the agent could not determine this

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt after analysis of the PR #1935 ship session logs.

## Session Errors

**Wrong path for setup-ralph-loop.sh**

- **Recovery:** Found correct path at `./plugins/soleur/scripts/setup-ralph-loop.sh`
- **Prevention:** The one-shot skill instructions specify the correct path; this was a one-time misread

**Write tool rejected /tmp file that hadn't been read**

- **Recovery:** Created file with bash, read it, then used Write tool
- **Prevention:** Standard tool constraint -- always read before writing, even for temp files

## Solution

Added explicit `--jq` filters to all Phase 7 polling commands in SKILL.md, plus defensive guards:

**Change 1 -- Item 2 Step 2 (release verification):**

```bash
# Before (broken -- raw JSON output, agent must parse):
gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion

# After (fixed -- produces single integer directly):
gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion --jq '[.[] | select(.status != "completed")] | length'
```

**Change 2 -- Empty-result fallback:**

Added a second query to distinguish "all completed" (total > 0, pending = 0) from "not yet registered" (total = 0), with 3 retries at 15-second intervals.

**Change 3 -- Max-iteration guards:**

Added "Maximum 40 iterations (20 minutes)" to both polling locations (item 2 Step 3 and item 3 Step 3).

**Change 4 -- Item 3 Step 3 (post-merge validation):**

```bash
# Before (broken -- returns full JSON object):
gh run list --workflow <workflow-filename> --limit 1 --json databaseId,status,conclusion --jq '.[0]'

# After (fixed -- returns formatted status string):
gh run list --workflow <workflow-filename> --limit 1 --json databaseId,status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"'
```

## Why This Works

1. **ROOT CAUSE:** SKILL.md instructions left output format ambiguous, forcing the agent to improvise parsing. Agent improvisation with external tools (Python3) is fragile because error handling is ad hoc.
2. **Why the fix works:** Explicit `--jq` filters produce scalar output (integers, formatted strings) that require no parsing. The agent compares the output directly, eliminating the class of failure where improvised parsing produces unexpected types.
3. **Defense-in-depth:** Max-iteration guards ensure that even if a future parsing issue arises, the loop terminates after 20 minutes with an actionable error message rather than hanging indefinitely.

## Prevention

- When writing skill instructions that include `gh` CLI commands, always include `--jq` filters to produce scalar output. Never rely on the agent to parse raw JSON.
- All polling loops in skill instructions must include explicit max-iteration guards inline at the step where polling occurs (per constitution: instructions execute at the step they describe).
- Use the `[.[] | select(...)] | length` pattern (with array wrapper) for counting -- bare `select` produces nothing on zero matches, but `[select(...)]` always produces an array.

## Related Issues

- See also: [2026-03-29-post-merge-release-workflow-verification.md](../2026-03-29-post-merge-release-workflow-verification.md) -- original motivation for Phase 7 release verification
- See also: [2026-03-04-gh-jq-does-not-support-arg-flag.md](../2026-03-04-gh-jq-does-not-support-arg-flag.md) -- `gh --jq` limitations
- See also: [2026-03-10-jq-generator-silent-data-loss.md](../2026-03-10-jq-generator-silent-data-loss.md) -- jq generator empty result behavior
- GitHub issue: #1946
- Review issue: #1964 (merge state poll also missing max-iteration guard)
