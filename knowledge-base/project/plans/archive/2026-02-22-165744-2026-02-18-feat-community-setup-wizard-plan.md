---
title: "feat: Add setup sub-command to community skill"
type: feat
date: 2026-02-18
issue: "#129"
version_bump: PATCH
deepened: 2026-02-18
---

# feat: Add setup sub-command to community skill

## Enhancement Summary

**Deepened on:** 2026-02-18
**Agents used:** security-sentinel, Discord API researcher, plan reviewers (DHH, code-simplicity)

### Key Improvements
1. Token passed via env var (`DISCORD_BOT_TOKEN_INPUT`), never as CLI argument (prevents ps/history leakage)
2. .env written with chmod 600 permissions (owner-only)
3. Concrete curl patterns for all 6 Discord API operations

## Overview

Add a `/soleur:community setup` sub-command that automates Discord bot configuration. Opens the Discord Developer Portal for the user, guides them through bot creation, then automates guild discovery, webhook creation, and .env persistence via the Discord API.

## Problem Statement

The community skill requires three environment variables (DISCORD_BOT_TOKEN, DISCORD_GUILD_ID, DISCORD_WEBHOOK_URL) that users must configure manually. This involves navigating the Discord Developer Portal, enabling intents, generating OAuth2 URLs, and finding guild/channel IDs -- a tedious, error-prone process that blocks adoption.

## Proposed Solution

A bash script (`discord-setup.sh`) with thin sub-commands. The SKILL.md orchestrates user interaction (AskUserQuestion, agent-browser) and calls script sub-commands for API operations. Token is passed via `DISCORD_BOT_TOKEN_INPUT` environment variable, never as a CLI argument.

Flow:
1. Check if vars already exist -> prompt to reconfigure
2. Open Discord Developer Portal via agent-browser -> print instructions -> user pastes token
3. Validate token via API call (skip regex -- API is the source of truth)
4. Generate OAuth2 URL -> open via agent-browser -> user authorizes
5. Discover guilds -> user picks if multiple
6. List channels -> user picks
7. Create webhook
8. Write all three vars to .env (chmod 600)
9. Verify with guild-info -> strict pass/fail

## Technical Approach

### Files Modified

| File | Change |
|------|--------|
| `plugins/soleur/skills/community/SKILL.md` | Add `setup` sub-command section |
| `plugins/soleur/skills/community/scripts/discord-setup.sh` | New script: API operations |
| `plugins/soleur/agents/marketing/community-manager.md` | Add setup capability |

### discord-setup.sh Design

Sub-commands called by SKILL.md between user interaction points. Token via env var only.

```bash
#!/usr/bin/env bash
set -euo pipefail

# discord-setup.sh -- Discord bot setup API operations
#
# SECURITY: Token MUST be in DISCORD_BOT_TOKEN_INPUT env var.
# Never pass tokens as CLI arguments (visible in ps/history).
#
# Usage: discord-setup.sh <command> [args]
# Commands:
#   validate-token                  - Verify token via API, output app ID
#   discover-guilds                 - List guilds as JSON
#   list-channels <guild_id>        - List text channels as JSON
#   create-webhook <channel_id>     - Create webhook, output webhook URL
#   write-env <guild_id> <webhook>  - Write to .env with chmod 600
#   verify                          - Run guild-info check
```

**Why sub-commands:** The skill (SKILL.md) needs to interject AskUserQuestion prompts between API calls (guild selection, channel selection). A monolithic script cannot pause for AI-mediated user input. Sub-commands are the minimal API boundary.

**Security model:**
- Token in `DISCORD_BOT_TOKEN_INPUT` env var (not CLI arg -- invisible to `ps aux`)
- curl stderr suppressed during token operations (prevents debug leakage)
- .env created with umask 077 / chmod 600 (owner read/write only)
- Token never echoed in error messages

### SKILL.md Setup Flow

```
## Sub-command: setup

### Phase 0: Check Existing Config

Check if DISCORD_BOT_TOKEN, DISCORD_GUILD_ID, and DISCORD_WEBHOOK_URL are all set.
- If all three present: AskUserQuestion "Discord is already configured. Reconfigure?"
  - If No: exit
- If missing any: proceed

### Phase 1: Create Bot (agent-browser + instructions)

1. Open https://discord.com/developers/applications via agent-browser (headed mode)
2. Print instructions:
   - Click "New Application" -> name it -> Create
   - Go to Bot tab -> Reset Token -> copy token
   - Enable SERVER MEMBERS INTENT and MESSAGE CONTENT INTENT -> Save
3. AskUserQuestion: "Paste your bot token"
4. Validate securely:
   DISCORD_BOT_TOKEN_INPUT="$token" discord-setup.sh validate-token
   - If fails: "Invalid or expired token. Re-copy from portal." Re-prompt once.
5. Extract app ID from validate-token output

### Phase 2: Invite Bot

1. Generate OAuth2 URL: https://discord.com/oauth2/authorize?client_id={APP_ID}&scope=bot&permissions=536939520
2. Navigate agent-browser to OAuth2 URL
3. Print: "Select your server and click 'Authorize'"
4. AskUserQuestion: "Continue after authorizing"

### Phase 3: Configure

1. DISCORD_BOT_TOKEN_INPUT="$token" discord-setup.sh discover-guilds
   - If 0: "Bot not in any servers. Complete the invite step first." Exit.
   - If 1: auto-select
   - If 2+: AskUserQuestion with guild names
2. DISCORD_BOT_TOKEN_INPUT="$token" discord-setup.sh list-channels <guild_id>
   - AskUserQuestion with channel names (first 10 text channels)
3. DISCORD_BOT_TOKEN_INPUT="$token" discord-setup.sh create-webhook <channel_id>
   - If 400 (limit reached): suggest different channel, re-prompt

### Phase 4: Persist & Verify

1. DISCORD_BOT_TOKEN_INPUT="$token" discord-setup.sh write-env <guild_id> <webhook_url>
2. discord-setup.sh verify
   - If success: display guild name, member count
   - If failure: exit 1 with error
3. Display summary:
   Setup complete!
   Guild: <name> (<count> members)
   Channel: #<name>
   Webhook: soleur-community
   Config: .env (3 variables written, permissions 600)
   Next: Run /soleur:community health to see metrics.
```

### API Endpoint Reference

| Command | Endpoint | Method | Auth |
|---------|----------|--------|------|
| validate-token | `/users/@me` + `/oauth2/applications/@me` | GET | Bot token |
| discover-guilds | `/users/@me/guilds?with_counts=true` | GET | Bot token |
| list-channels | `/guilds/{id}/channels` | GET | Bot token |
| create-webhook | `/channels/{id}/webhooks` | POST | Bot token |

## Non-Goals

- Automating clicks inside Discord Developer Portal (too fragile)
- Supporting multiple Discord servers simultaneously
- Custom permission integer selection
- Webhook reuse detection (just create new -- webhooks are free)
- Token format regex (API validates for free)
- CI/CD integration (local-only)
- Secret management integration (pass, 1Password -- future)

## Acceptance Criteria

- [ ] `setup` sub-command appears in community skill sub-command table
- [ ] Running setup with no env vars walks through full wizard
- [ ] Running setup with existing vars prompts for reconfiguration
- [ ] Bot token passed via env var, never as CLI argument
- [ ] Bot token validated via Discord API before proceeding
- [ ] Guild auto-discovered from bot token
- [ ] Channel selection presented via AskUserQuestion
- [ ] Webhook created with name "soleur-community"
- [ ] All three vars written to .env with chmod 600
- [ ] Verification runs guild-info with strict pass/fail

## Test Scenarios

- Given no env vars, when running setup, then full wizard executes
- Given all three vars set, when running setup, then reconfiguration prompt appears
- Given expired bot token, when API check runs, then clear error with re-prompt (no token in message)
- Given bot not in any guilds, when discovery runs, then error about incomplete invite
- Given bot in multiple guilds, when discovery runs, then selection prompt
- Given channel at webhook limit, when create fails, then suggest different channel
- Given successful setup, when verify runs, then guild name and member count displayed
- Given .env written, when checking permissions, then file is chmod 600

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Token in CLI args | Pass via DISCORD_BOT_TOKEN_INPUT env var |
| Token in debug output | Suppress curl stderr during sensitive operations |
| .env world-readable | Create with umask 077, chmod 600 |
| Portal UI changes | Instructions are text-based, not selector-dependent |
| agent-browser not installed | Print URL as fallback, user opens manually |
| Rate limiting | discord_request pattern handles 429 with retry |

## References

- Discord API v10: https://discord.com/developers/docs
- Permissions integer 536939520 = VIEW_CHANNEL (1<<10) + SEND_MESSAGES (1<<11) + READ_MESSAGE_HISTORY (1<<16) + MANAGE_WEBHOOKS (1<<29)
- Existing: `plugins/soleur/skills/community/scripts/discord-community.sh`
- Learning: `knowledge-base/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md`
- Learning: `knowledge-base/learnings/implementation-patterns/2026-02-18-skill-cannot-invoke-skill.md`
- Issue: #129
