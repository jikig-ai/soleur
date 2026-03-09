# Tasks: fix discord-community.sh hardening

## Phase 1: discord-community.sh Fixes

### 1.1 Add curl stderr suppression and connection failure handler
- File: `plugins/soleur/skills/community/scripts/discord-community.sh`
- Function: `discord_request()` lines 71-74
- Add `2>/dev/null` to curl call
- Wrap in `if !` to catch connection failures with clear error message
- Reference: `discord-setup.sh:78` pattern

### 1.2 Add jq bash fallback in catch-all error handler
- File: `plugins/soleur/skills/community/scripts/discord-community.sh`
- Function: `discord_request()` line 107
- Append `|| echo "Unknown error"` after `2>/dev/null`
- Reference: `discord-setup.sh:113` pattern

### 1.3 Clamp retry_after to max 60s in 429 handler
- File: `plugins/soleur/skills/community/scripts/discord-community.sh`
- Function: `discord_request()` line 100
- After extracting retry_after, add: `if (( retry_after > 60 )); then retry_after=60; fi`

### 1.4 Add channel_id numeric validation to cmd_messages
- File: `plugins/soleur/skills/community/scripts/discord-community.sh`
- Function: `cmd_messages()` after line 117
- Add numeric regex check matching `DISCORD_GUILD_ID` validation pattern

## Phase 2: discord-setup.sh Fixes

### 2.1 Add JSON validation on 2xx responses
- File: `plugins/soleur/skills/community/scripts/discord-setup.sh`
- Function: `discord_request()` lines 88-89
- Add `jq .` validation before echoing body
- Reference: `discord-community.sh:82-86` pattern

### 2.2 Clamp retry_after to max 60s in 429 handler
- File: `plugins/soleur/skills/community/scripts/discord-setup.sh`
- Function: `discord_request()` lines 102-106
- After retry_after extraction and null check, add max clamp

### 2.3 Add channel_id/guild_id numeric validation
- File: `plugins/soleur/skills/community/scripts/discord-setup.sh`
- Functions: `cmd_list_channels()` line 154, `cmd_create_webhook()` line 162
- Add numeric regex check for ID parameters

## Phase 3: x-community.sh Fix

### 3.1 Clamp retry_after to max 60s in 429 handler
- File: `plugins/soleur/skills/community/scripts/x-community.sh`
- Function: `x_request()` line 227
- After extracting retry_after, add max clamp

## Phase 4: Verification

### 4.1 Manual verification of all changes
- Read each modified file end-to-end
- Confirm all five issue items are addressed
- Confirm no regressions in existing caller patterns
- Verify `set -euo pipefail` compatibility (no bare variables, grep fallbacks)
