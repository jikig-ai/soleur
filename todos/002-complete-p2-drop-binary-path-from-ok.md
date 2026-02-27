---
status: pending
priority: p2
issue_id: "002"
tags: [code-review, quality]
dependencies: []
---

# Drop Binary Path from Extension OK Messages

## Problem Statement
The `[ok] Pencil extension ($BINARY)` messages display full filesystem paths like `~/.cursor/extensions/highagency.pencildev-1.2.3/out/mcp-server-linux`. This is implementation noise in a preflight check.

## Proposed Solutions
1. Replace `($BINARY)` with just `[ok] Pencil extension`
   - Effort: Small

## Acceptance Criteria
- [ ] Status output shows `[ok] Pencil extension` without a path
