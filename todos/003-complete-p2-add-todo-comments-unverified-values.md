---
status: pending
priority: p2
issue_id: "003"
tags: [code-review, quality]
dependencies: []
---

# Add TODO Comments for Unverified Detection Values

## Problem Statement
The `dpkg -s pencil` package name and `mdfind` bundle ID `dev.pencil.desktop` are assumptions from the plan, not verified against actual Pencil Desktop artifacts. They may be wrong.

## Proposed Solutions
1. Add inline TODO comments at both detection points noting the values need verification
   - Effort: Small

## Acceptance Criteria
- [ ] TODO comment above `dpkg -s pencil` noting package name needs verification
- [ ] TODO comment above `mdfind` noting bundle ID needs verification
