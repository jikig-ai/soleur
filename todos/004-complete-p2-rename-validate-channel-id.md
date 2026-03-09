---
status: pending
priority: p2
issue_id: "477"
tags: [code-review, quality]
dependencies: []
---

# Rename validate_channel_id to validate_snowflake_id

## Problem Statement

`discord-community.sh` uses `validate_channel_id()` with a hardcoded label, while `discord-setup.sh` uses `validate_snowflake_id(id, label)` with a parameterized label. The inconsistency makes the codebase harder to reason about and prevents reuse.

## Findings

- `discord-community.sh:130-136` — `validate_channel_id()` hardcodes "channel_id" in error message
- `discord-setup.sh:137-144` — `validate_snowflake_id()` takes a label parameter
- Both do identical `^[0-9]+$` regex check
- Found by: pattern-recognition-specialist, code-quality-analyst

## Proposed Solutions

### Option A: Rename to validate_snowflake_id with label param (Recommended)
- **Pros:** Consistent naming, reusable for guild_id validation
- **Cons:** None
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `plugins/soleur/skills/community/scripts/discord-community.sh`
- **Lines:** 130-136 (function definition), 141 (call site)

## Acceptance Criteria

- [ ] `discord-community.sh` uses `validate_snowflake_id` with label parameter
- [ ] Call site passes "channel_id" as label
- [ ] Error message output unchanged
