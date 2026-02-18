---
name: community
description: "This skill should be used when managing community engagement across Discord and GitHub. It provides sub-commands for generating weekly digests, checking community health, posting updates, and welcoming new members. Triggers on \"community digest\", \"community health\", \"community metrics\", \"weekly digest\", \"community update\", \"/soleur:community\"."
---

# Community Management

Manage community engagement across Discord and GitHub. This skill routes to sub-commands for digests, health metrics, posting, and onboarding.

## Sub-commands

| Command | Description |
|---------|-------------|
| `/soleur:community digest` | Generate weekly community digest |
| `/soleur:community health` | Display community health metrics |
| `/soleur:community post <topic>` | Redirect to discord-content skill |
| `/soleur:community welcome` | Generate and post a welcome message |

If no sub-command is provided, display the table above and ask which sub-command to run.

---

## Phase 0: Prerequisites

<critical_sequence>

Before executing any sub-command, validate environment variables.

**Required for all sub-commands except `post`:**

```bash
if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
  echo "DISCORD_BOT_TOKEN is not set."
  echo ""
  echo "To configure:"
  echo "  1. Go to https://discord.com/developers/applications"
  echo "  2. Select your bot application > Bot > Copy token"
  echo "  3. export DISCORD_BOT_TOKEN=\"your-token-here\""
  echo ""
  echo "Bot permissions required: SERVER MEMBERS INTENT, MESSAGE CONTENT INTENT"
  # Stop execution
fi
```

```bash
if [[ -z "${DISCORD_GUILD_ID:-}" ]]; then
  echo "DISCORD_GUILD_ID is not set."
  echo ""
  echo "To configure:"
  echo "  1. Enable Developer Mode in Discord (Settings > Advanced)"
  echo "  2. Right-click your server name > Copy Server ID"
  echo "  3. export DISCORD_GUILD_ID=\"your-server-id\""
  # Stop execution
fi
```

**Required for sub-commands that post (digest, welcome):**

```bash
if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
  echo "DISCORD_WEBHOOK_URL is not set."
  echo ""
  echo "To configure:"
  echo "  1. Open Discord server > Server Settings > Integrations > Webhooks"
  echo "  2. Click 'New Webhook' and configure the target channel"
  echo "  3. Copy the webhook URL"
  echo "  4. export DISCORD_WEBHOOK_URL=\"https://discord.com/api/webhooks/...\""
  # Stop execution
fi
```

**Brand guide (required for digest Discord post and welcome):**

Check if `knowledge-base/overview/brand-guide.md` exists. If missing and the sub-command needs it (digest, welcome), warn:

> Brand guide not found. Digest Discord post and welcome messages will not have brand voice alignment. Run the brand-architect agent to create a brand guide.

Continue without brand guide (do not stop execution).

</critical_sequence>

---

## Sub-command: digest

Generate a weekly community digest from Discord and GitHub activity.

### Phase 1: Spawn Agent

<decision_gate>

Spawn the community-manager agent with the digest capability:

```
Task community-manager: "Generate a weekly community digest.

Working directory: [current working directory]
Script directory: plugins/soleur/skills/community/scripts/

Collect Discord messages and GitHub activity for the last 7 days.
Write digest to knowledge-base/community/YYYY-MM-DD-digest.md.
Post condensed version to Discord via webhook.

Environment:
  DISCORD_BOT_TOKEN: set
  DISCORD_GUILD_ID: [value]
  DISCORD_WEBHOOK_URL: set
  DISCORD_CHANNEL_IDS: [value or 'all channels']
"
```

</decision_gate>

### Phase 2: Report Results

After the agent completes, display:

```
Digest generated!

File: knowledge-base/community/YYYY-MM-DD-digest.md
Discord: Posted (HTTP 2xx) | Failed (see above for manual posting)

Highlights:
- [Top finding from digest]
- [Second finding]
```

---

## Sub-command: health

Display community health metrics inline.

### Phase 1: Spawn Agent

Spawn the community-manager agent with the health metrics capability:

```
Task community-manager: "Display community health metrics.

Working directory: [current working directory]
Script directory: plugins/soleur/skills/community/scripts/

Collect Discord guild info, members, and GitHub activity for the last 30 days.
Display metrics inline. Do not write any files."
```

### Phase 2: Display

The agent displays metrics directly. No additional formatting needed.

---

## Sub-command: post

Redirect to the discord-content skill.

<validation_gate>

This sub-command does not perform any action. Skills cannot invoke other skills programmatically.

Display:

> For posting content to Discord, use `/soleur:discord-content <topic>` directly.
> The discord-content skill handles brand voice validation, user approval, and webhook posting.

</validation_gate>

---

## Sub-command: welcome

Generate and post a welcome message for new community members.

### Phase 1: Brand Voice

Read the brand guide to align the welcome message:

1. Read `knowledge-base/overview/brand-guide.md` if it exists
2. Extract `## Voice` section for tone and language
3. Extract `## Channel Notes > ### Discord` section for Discord-specific guidelines

If no brand guide exists, use a neutral professional tone.

### Phase 2: Generate Message

Generate a welcome message that includes:

- Brief introduction to the project
- Key resources (docs site, getting started guide)
- How to get help (Discord channels, GitHub issues)
- Encouragement to share what they build

Keep under 2000 characters (Discord message limit).

### Phase 3: User Approval

<decision_gate>

Present the draft to the user with character count. Use the **AskUserQuestion tool**:

- **Accept** -- Post this welcome message to Discord
- **Edit** -- Provide feedback to revise (return to Phase 2)
- **Reject** -- Discard and exit

</decision_gate>

### Phase 4: Post

On acceptance, post via webhook:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"ESCAPED_CONTENT\"}" \
  "$DISCORD_WEBHOOK_URL"
```

JSON-escape all content before inserting into the payload.

**On success (HTTP 2xx):** "Welcome message posted to Discord."

**On failure:** Display the draft for manual posting. Do not retry.

---

## Important Guidelines

- All sub-commands require explicit user approval before posting to Discord
- The 2000-character Discord message limit is enforced during generation
- JSON-escape all content before webhook payloads
- If brand guide is missing, warn but continue (do not block execution)
- Environment variable validation happens once in Phase 0, not per sub-command
- Scripts are at `plugins/soleur/skills/community/scripts/` relative to repo root
