# Learning: jq parse errors abort scripts under set -euo pipefail

## Problem

Line 118 of `plugins/soleur/hooks/stop-hook.sh` passed raw stdin from the Claude Code hook API to `jq` without guarding against malformed input. Under `set -euo pipefail`, `jq` exits 5 on parse errors (e.g., truncated JSON, plaintext), aborting the entire stop hook. Since the stop hook runs on every session exit, a single malformed API response could trap the user's session — every exit attempt fails with the jq error.

This was the same class of vulnerability documented in `2026-03-18-stop-hook-toctou-race-fix.md` (missing `|| true` guards under `set -euo pipefail`) but applied to `jq` rather than `grep` or `awk`.

## Solution

Added `2>/dev/null || true` to the jq call, matching the defensive pattern already used 4 times in the same file:

```bash
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)
```

On failure, `LAST_OUTPUT` becomes empty string — a safe value that the stuck detection counter handles gracefully.

## Key Insight

`jq`'s `// ""` alternative operator handles missing keys but does NOT handle invalid JSON input. These are orthogonal failure modes: `// ""` is a jq-level default, while parse errors are process-level exits that `set -e` intercepts before jq's expression logic runs. When a script under `set -euo pipefail` passes external input to `jq`, the parse-error exit code must be explicitly absorbed with `|| true`.

Empirical testing showed empty stdin is safe (jq exits 0), so only malformed text/JSON triggers the vulnerability.

## Tags

category: runtime-errors
module: plugins/soleur/hooks/stop-hook.sh
