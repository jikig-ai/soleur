---
name: community
description: "This skill should be used when managing community engagement across Discord and GitHub. It provides sub-commands for generating weekly digests, checking community health, posting updates, and welcoming new members. Triggers on \"community digest\", \"community health\", \"community metrics\", \"weekly digest\", \"community update\", \"/soleur:community\"."
---

# Community Management

Manage community engagement across Discord and GitHub. This skill routes to sub-commands for digests, health metrics, posting, and onboarding.

## Sub-commands

| Command | Description |
|---------|-------------|
| `/soleur:community setup` | Configure Discord bot and write .env |
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
  echo "Run /soleur:community setup to configure Discord automatically."
  # Stop execution
fi
```

```bash
if [[ -z "${DISCORD_GUILD_ID:-}" ]]; then
  echo "DISCORD_GUILD_ID is not set."
  echo ""
  echo "Run /soleur:community setup to configure Discord automatically."
  # Stop execution
fi
```

**Required for sub-commands that post (digest, welcome):**

```bash
if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
  echo "DISCORD_WEBHOOK_URL is not set."
  echo ""
  echo "Run /soleur:community setup to configure Discord automatically."
  # Stop execution
fi
```

**Brand guide (required for digest Discord post and welcome):**

Check if `knowledge-base/overview/brand-guide.md` exists. If missing and the sub-command needs it (digest, welcome), warn:

> Brand guide not found. Digest Discord post and welcome messages will not have brand voice alignment. Run the brand-architect agent to create a brand guide.

Continue without brand guide (do not stop execution).

</critical_sequence>

---

## Sub-command: setup

Automate Discord bot configuration. Opens the Discord Developer Portal for the user, guides them through bot creation, then automates guild discovery, webhook creation, and .env persistence via the Discord API.

**This sub-command bypasses Phase 0 env var checks** -- it creates the env vars that Phase 0 validates.

Setup script: [discord-setup.sh](./scripts/discord-setup.sh)

### Phase 0: Check Existing Config

```bash
if [[ -n "${DISCORD_BOT_TOKEN:-}" ]] && [[ -n "${DISCORD_GUILD_ID:-}" ]] && [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
  # All three vars present
fi
```

If all three are set, use **AskUserQuestion**:

- **Reconfigure** -- Overwrite existing Discord configuration
- **Keep current** -- Exit setup, keep existing configuration

If "Keep current": exit. If any var is missing: proceed.

### Phase 1: Create Bot (browser + instructions)

1. Open the Discord Developer Portal in a headed browser:

```bash
agent-browser open "https://discord.com/developers/applications" --headed
```

2. Display instructions:

> **Create a Discord Bot Application:**
>
> 1. Click "New Application" -- name it (e.g., "soleur-community") -- click Create
> 2. Go to the **Bot** tab in the left sidebar
> 3. Click **Reset Token** -- copy the token that appears
> 4. Scroll down to **Privileged Gateway Intents**
> 5. Enable **SERVER MEMBERS INTENT** and **MESSAGE CONTENT INTENT**
> 6. Click **Save Changes**

3. Use **AskUserQuestion**: "Paste your bot token"

4. Validate the token securely:

```bash
DISCORD_BOT_TOKEN_INPUT="$token" plugins/soleur/skills/community/scripts/discord-setup.sh validate-token
```

- On success: capture app ID from stdout (first line)
- On failure: display "Invalid or expired token. Re-copy from the Bot tab in the portal." and re-prompt once with AskUserQuestion

### Phase 2: Invite Bot

1. Build the OAuth2 URL using the app ID from Phase 1:

```
https://discord.com/oauth2/authorize?client_id={APP_ID}&scope=bot&permissions=536939520
```

Permission 536939520 = View Channels + Send Messages + Read Message History + Manage Webhooks.

2. Navigate the browser to the OAuth2 URL:

```bash
agent-browser open "{OAUTH2_URL}" --headed
```

3. Display: "Select your server in the dropdown and click **Authorize**."

4. Use **AskUserQuestion**: "Continue after authorizing the bot"

### Phase 3: Configure

**Step 1: Discover guilds**

```bash
DISCORD_BOT_TOKEN_INPUT="$token" plugins/soleur/skills/community/scripts/discord-setup.sh discover-guilds
```

- If 0 guilds: "Bot is not in any servers. Complete the authorization step first." Exit.
- If 1 guild: auto-select, display the guild name
- If 2+ guilds: use **AskUserQuestion** with guild names as options

**Step 2: List channels**

```bash
DISCORD_BOT_TOKEN_INPUT="$token" plugins/soleur/skills/community/scripts/discord-setup.sh list-channels <guild_id>
```

Use **AskUserQuestion** with channel names (first 10 text channels) as options. Recommend `#general` or the first channel if no obvious default.

**Step 3: Create webhook**

```bash
DISCORD_BOT_TOKEN_INPUT="$token" plugins/soleur/skills/community/scripts/discord-setup.sh create-webhook <channel_id>
```

- On success (exit 0): capture webhook URL from stdout
- On exit code 2 (webhook limit): "This channel has too many webhooks. Pick a different channel." Return to Step 2.
- On exit code 1 (other error): display error and exit setup.

### Phase 4: Persist and Verify

**Step 1: Write .env**

```bash
DISCORD_BOT_TOKEN_INPUT="$token" plugins/soleur/skills/community/scripts/discord-setup.sh write-env <guild_id> <webhook_url>
```

**Step 2: Verify**

```bash
plugins/soleur/skills/community/scripts/discord-setup.sh verify
```

- On success: capture guild name (line 1) and member count (line 2) from stdout
- On failure: exit with error

**Step 3: Display summary**

```
Setup complete!

Guild: <name> (<count> members)
Channel: #<channel_name>
Webhook: soleur-community
Config: .env (3 variables written, permissions 600)

Next: Run /soleur:community health to see metrics.
```

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
  -d "{\"content\": \"ESCAPED_CONTENT\", \"username\": \"Sol\", \"avatar_url\": \"AVATAR_URL\"}" \
  "$DISCORD_WEBHOOK_URL"
```

Set `avatar_url` to the hosted logo URL (e.g., the GitHub-hosted `logo-mark-512.png`). Webhook messages freeze author identity at post time -- these fields ensure consistent branding.

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
- When posting via webhook, always include `username` and `avatar_url` fields to ensure consistent bot identity -- webhook messages freeze author identity at post time
