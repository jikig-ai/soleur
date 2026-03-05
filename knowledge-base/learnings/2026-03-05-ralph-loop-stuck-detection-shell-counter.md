---
title: Stuck detection for Ralph Loop stop hook
date: 2026-03-05
category: implementation-patterns
tags: [ralph-loop, stuck-detection, bash-pipefail]
module: plugins/soleur/hooks
---

# Learning: Stuck detection for Ralph Loop stop hook

## Problem

The Ralph Loop stop hook had no stuck detection. When a completion promise was never emitted (e.g., after crash recovery where the original task was already done), the loop cycled indefinitely -- observed running 31+ iterations with no progress, burning tokens on empty or tool-use-only responses.

## Solution

Added stuck-detection logic to `plugins/soleur/hooks/stop-hook.sh`:

- Parse `stuck_count` and `stuck_threshold` from state file frontmatter
- Measure response length after stripping whitespace; responses < 20 chars are minimal
- Increment counter on minimal responses, reset to 0 on substantive ones
- Auto-terminate when counter >= threshold (default 3)
- Added `--stuck-threshold` flag to `setup-ralph-loop.sh` (0 disables detection)
- Applied `|| true` guards on grep for pipefail safety with pre-existing state files

Placement: after promise check (normal completions bypass counter), before iteration increment (stuck loops terminate without wasting another cycle). Combined sed pass updates both iteration and stuck_count in one disk write.

## Key Insight

`grep` under `set -euo pipefail` returns exit 1 on no match -- not just on error. When parsing pre-existing state files that lack newly-introduced frontmatter fields, grep for those fields fails with exit 1 and kills the script. The fix is `grep ... || true`, which is easy to forget because the failure is silent and only surfaces with state files created before the feature was added.

Secondary: tool-use-only responses produce empty LAST_OUTPUT (jq text extraction yields nothing when all content blocks are `tool_use`). This correctly counts as minimal -- the agent is calling tools but producing no user-visible progress.

## Tags

category: implementation-patterns
module: plugins/soleur/hooks
