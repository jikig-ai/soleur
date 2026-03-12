---
status: pending
priority: p2
tags: [code-review, architecture, error-handling]
---

# Add early file-existence check for x-community.sh

## Problem Statement

The script references `x-community.sh` via `$X_SCRIPT` (line 24) but doesn't validate it exists at startup. If the community skill reorganizes, the script would fail mid-execution — after Discord has already posted but before X posting starts.

## Findings

- **Location:** `scripts/content-publisher.sh:24`
- **Flagged by:** architecture-strategist
- Cross-boundary dependency: repo-root script depends on plugin-internal script path

## Proposed Solutions

### Solution A: Add file-existence check in main() before platform posting
```bash
if [[ -n "${X_API_KEY:-}" ]] && [[ ! -f "$X_SCRIPT" ]]; then
  echo "Error: x-community.sh not found at $X_SCRIPT" >&2
  exit 1
fi
```

- **Effort:** Small
- **Risk:** Low

## Acceptance Criteria

- [ ] Script fails fast with clear error if x-community.sh is missing and X credentials are configured
