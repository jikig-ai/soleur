---
status: pending
priority: p2
issue_id: "477"
tags: [code-review, security]
dependencies: []
---

# Add validate_snowflake_id to cmd_write_env in discord-setup.sh

## Problem Statement

Fix 5 added `validate_snowflake_id` calls to `cmd_list_channels` and `cmd_create_webhook`, but `cmd_write_env` also accepts a `guild_id` parameter that is written directly to `.env` without validation. This is a gap in the PR's own stated goal of adding ID validation.

## Findings

- `discord-setup.sh:208` — `cmd_write_env` takes `guild_id` without validation
- `guild_id` is written to `.env` file which is later `source`d
- `validate_snowflake_id` already exists in the same file
- Found by: security-sentinel

## Proposed Solutions

### Option A: Add validate_snowflake_id call (Recommended)
- **Pros:** Completes Fix 5 coverage, prevents injection
- **Cons:** None
- **Effort:** Small (one line)
- **Risk:** Low

## Technical Details

- **Affected files:** `plugins/soleur/skills/community/scripts/discord-setup.sh`
- **Lines:** `cmd_write_env` function, after parameter extraction

## Acceptance Criteria

- [ ] `cmd_write_env` calls `validate_snowflake_id "$guild_id" "guild_id"` before writing to .env
