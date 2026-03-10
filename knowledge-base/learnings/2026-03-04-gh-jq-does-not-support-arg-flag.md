---
synced_to: [schedule]
---

# Learning: gh --jq does not support jq flags like --arg

## Problem

When piping environment variables into `gh` CLI's `--jq` filter, the intuitive syntax fails:

```bash
gh issue list --jq --arg skip "$OPEN_FIXES" '[.[] | select(.number | IN($skip_nums[]))]'
```

Error: `gh` CLI parses `--arg skip "$OPEN_FIXES"` as unknown positional arguments to `gh issue list`, not as jq flags. The `--jq` flag accepts only a single jq expression string; it does not pass-through additional jq CLI flags.

## Solution

Use `export` to make the variable available to jq's `$ENV` object:

```bash
export OPEN_FIXES="123,456,789"
gh issue list --jq '[.[] | select(.number | IN(($ENV.OPEN_FIXES | split(",") | map(tonumber? // empty))[]))]'
```

This keeps the jq expression in single quotes (preventing shell injection) while leveraging jq's standard `$ENV` mechanism to access environment variables.

## Key Insight

`gh --jq` is a thin wrapper over jq's `-r` (raw output) flag, not a full jq CLI emulator. It does not support jq's argument-passing syntax (`--arg`, `--argjson`, `--slurpfile`). For dynamic data, rely on environment variables via `$ENV`, not jq CLI flags.

## Tags

category: workflow-patterns
module: scheduled-bug-fixer
gotcha: gh-cli-limitations
