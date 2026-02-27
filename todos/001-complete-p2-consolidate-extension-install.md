---
status: pending
priority: p2
issue_id: "001"
tags: [code-review, quality]
dependencies: []
---

# Consolidate Extension Install Code Path

## Problem Statement
The extension install block in check_deps.sh has duplicated `"$IDE" --install-extension` calls -- once for `--auto` and once for interactive mode. The decline path shows `[skip]` then falls through to a re-check that exits 1, which is confusing for a hard dependency.

## Findings
- Lines 86-101: Two identical install commands separated by prompt logic
- `[skip]` tag used for a hard dependency (inconsistent with feature-video where `[skip]` = soft dep)
- Install command exit code not captured in either branch

## Proposed Solutions
1. Consolidate: prompt first (if not auto), exit 1 on decline, then single install + re-check
   - Pros: Removes duplication, clearer flow
   - Cons: Minor refactor
   - Effort: Small

## Acceptance Criteria
- [ ] Single `--install-extension` call in the script
- [ ] User decline exits 1 immediately with clear message
- [ ] Install failure captured before re-check
