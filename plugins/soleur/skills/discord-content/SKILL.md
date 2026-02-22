---
name: discord-content
description: "This skill should be used when creating and posting community content to Discord. It generates brand-consistent posts (project updates, tips, milestones, or custom topics), validates them against the brand guide, and posts via webhook after user approval. Triggers on \"post to Discord\", \"Discord update\", \"community post\", \"Discord announcement\", \"write Discord content\"."
---

# Discord Content

Create and post brand-consistent community content to Discord. Content is generated from a user-provided topic, validated against the brand guide, and posted via webhook after explicit user approval.

## Prerequisites

Before generating content, verify both prerequisites. If either fails, display the error message and stop.

### 1. Brand Guide

Check if `knowledge-base/overview/brand-guide.md` exists.

**If missing:**
> No brand guide found. Run the brand architect agent first to establish brand identity:
> `Use the brand-architect agent to define our brand.`

Stop execution.

### 2. Discord Webhook URL

Check if the `DISCORD_WEBHOOK_URL` environment variable is set.

**If missing:**
> `DISCORD_WEBHOOK_URL` is not set. To configure:
> 1. Open Discord server > Server Settings > Integrations > Webhooks
> 2. Click "New Webhook" and configure the target channel
> 3. Copy the webhook URL
> 4. Set the environment variable: `export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."`

Stop execution.

## Content Generation

### Phase 1: Topic Input

Ask the user: "What would you like to post about?"

Accept a freeform topic description. Optionally offer: "Summarize recent git activity?" -- if accepted, run `git log --oneline -20` to gather recent commits and PRs as source material.

### Phase 2: Generate Draft

Read the brand guide sections that inform content generation:

1. Read `## Voice` -- apply brand voice, tone, do's and don'ts
2. Read `## Channel Notes > ### Discord` -- apply Discord-specific guidelines (if the section exists)

Generate a draft post that:
- Addresses the user's topic
- Matches the brand voice from `## Voice`
- Follows Discord channel guidelines from `## Channel Notes`
- Stays within the 2000-character Discord message limit

### Phase 3: Inline Brand Voice Check

Before presenting the draft to the user, validate it against the brand guide:

1. Check the draft against the `### Do's and Don'ts` section
2. If any "Don't" patterns are found, revise the draft to remove them
3. If the draft exceeds 2000 characters, trim it while preserving key messages
4. Note any adjustments made

### Phase 4: User Approval

Present the final draft to the user with character count displayed. Use the **AskUserQuestion tool** with three options:

- **Accept** -- Post this content to Discord
- **Edit** -- Provide feedback to revise the draft (return to Phase 2 with feedback)
- **Reject** -- Discard the draft and exit

### Phase 5: Post to Discord

On acceptance, post the content via webhook:

First get the webhook URL with `printenv DISCORD_WEBHOOK_URL`, then use the literal URL:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"ESCAPED_CONTENT\", \"username\": \"Sol\", \"avatar_url\": \"AVATAR_URL\"}" \
  "<webhook-url>"
```

Replace `<webhook-url>` with the actual URL from `printenv`.

Set `avatar_url` to the hosted logo URL (e.g., the GitHub-hosted `logo-mark-512.png`). Webhook messages freeze author identity at post time -- these fields ensure consistent branding.

**Content must be properly JSON-escaped** before inserting into the payload. Escape double quotes, backslashes, and newlines.

**Payload format:** Plain `content` field only. No rich embeds in v1.

### Phase 6: Result

**On success (HTTP 2xx):**
> Posted to Discord successfully.

**On failure (HTTP 4xx/5xx):**
> Failed to post to Discord (HTTP [status_code]).
>
> Draft content (copy-paste manually):
> ```
> [full draft content]
> ```

Display the draft so the user can post it manually. Do not retry automatically.

## Important Guidelines

- All content requires explicit user approval before posting -- no auto-send
- The 2000-character limit is enforced during generation, not as a post-hoc check
- Content uses the plain `content` field, not Discord rich embeds
- JSON-escape all content before inserting into the webhook payload
- If the brand guide's `## Channel Notes > ### Discord` section is missing, generate content using only the `## Voice` section (no error)
- If the user selects "Edit", incorporate their feedback and regenerate -- do not present the same draft
- When posting via webhook, always include `username` and `avatar_url` fields to ensure consistent bot identity -- webhook messages freeze author identity at post time
