---
title: "fix: inline shell variable in gh issue list jq expression"
type: fix
date: 2026-03-04
---

# fix: inline shell variable in gh issue list jq expression

The scheduled bug-fixer workflow (`scheduled-bug-fixer.yml`) fails at the "Select issue" step because `gh issue list --jq` does not support jq flags like `--arg`. The `--arg skip "$OPEN_FIXES"` is parsed as unknown positional arguments to `gh issue list`, not forwarded to jq.

**Error from CI run [#22657970844](https://github.com/jikig-ai/soleur/actions/runs/22657970844/job/65671713661):**

```
unknown arguments ["skip" "" "\n ($skip | split(\",\") ..."]
```

## Acceptance Criteria

- [ ] The `Select issue` step in `scheduled-bug-fixer.yml` no longer uses `--arg` with `--jq`
- [ ] The `$OPEN_FIXES` shell variable is inlined directly into the jq expression string using shell variable expansion
- [ ] The jq filter logic (split, tonumber, IN exclusion) remains functionally identical
- [ ] The learnings doc `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md` is updated to reflect the correct pattern (no `--arg`)
- [ ] Workflow runs successfully on `workflow_dispatch` trigger (or at next scheduled run)

## Test Scenarios

- Given `OPEN_FIXES` is empty, when the jq filter runs, then no issues are excluded and the oldest qualifying bug is selected
- Given `OPEN_FIXES` is `"42,99"`, when the jq filter runs, then issues #42 and #99 are excluded from selection
- Given `OPEN_FIXES` contains a single number `"42"`, when the jq filter runs, then issue #42 is excluded
- Given no qualifying issues exist at any priority, when the step completes, then it prints "No qualifying issues found" and exits 0

## Context

### Root Cause

`gh` CLI's `--jq` flag (`-q`) accepts a single jq expression string. It does not support passing additional jq flags like `--arg`, `--argjson`, etc. These extra tokens are consumed by `gh`'s own argument parser, which rejects them as unknown arguments.

### Fix Approach

Replace the `--arg skip "$OPEN_FIXES"` pattern with direct shell variable interpolation inside the jq expression. Instead of:

```bash
--jq --arg skip "$OPEN_FIXES" '($skip | split(",") | ...'
```

Use:

```bash
--jq '("'"$OPEN_FIXES"'" | split(",") | ...'
```

This injects the shell variable value directly into the jq string literal via quote-unquote-quote (`'...' "..." '...'`). The jq expression receives the literal value where `$skip` was previously referenced.

### Files to Change

1. `.github/workflows/scheduled-bug-fixer.yml` (lines 79-84) -- replace `--arg` usage with inlined shell variable
2. `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md` (lines 40-46) -- update code example to match corrected pattern

## References

- Failed CI run: https://github.com/jikig-ai/soleur/actions/runs/22657970844/job/65671713661
- `gh` CLI `--jq` docs: accepts a single expression string, no extra jq flags
- Existing learning: `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md`
