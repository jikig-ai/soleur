---
title: Discord Bot Identity and Webhook Behavior
category: integration-issues
tags:
  - discord-automation
  - bot-configuration
  - community-management
  - brand-consistency
  - webhook-api
module: community
symptoms:
  - Bot avatar too low resolution (32x32) with clipped borders
  - Bot user identity separate from webhook identity
  - Webhook messages freeze author identity at post time
  - Multiple webhooks with inconsistent identities
date: 2026-02-19
---

# Learning: Discord Bot Identity and Webhook Behavior

## Problem

During Discord community setup, several identity-related issues surfaced:

1. **Low-res avatar** -- The 32x32 favicon was used as the bot avatar. Discord needs 512x512 minimum, and its circular crop clipped the gold ring border.
2. **Bot vs webhook identity separation** -- Updating the bot user's name/avatar via `PATCH /users/@me` did not update webhook-posted messages. These are separate identity records in Discord.
3. **Frozen message identity** -- Updating a webhook's default name/avatar does not retroactively change previously posted messages. The author identity is frozen at post time.
4. **Multiple webhooks, inconsistent identity** -- The community webhook (#general) and release webhook (#announcements) had different names and avatars.

## Solution

### Avatar sizing
Generate a 512x512 PNG with padding inside the gold ring so Discord's circular crop doesn't clip borders. Saved as `plugins/soleur/docs/images/logo-mark-512.png`.

### Update both bot AND webhook
Bot user and webhook identities must be updated separately:

```bash
# Bot user
curl -X PATCH https://discord.com/api/v10/users/@me \
  -H "Authorization: Bot $TOKEN" \
  -d '{"username": "Sol", "avatar": "data:image/png;base64,..."}'

# Webhook (no auth header needed, token is in URL)
curl -X PATCH https://discord.com/api/webhooks/{id}/{token} \
  -d '{"name": "Sol", "avatar": "data:image/png;base64,..."}'
```

### Content edits vs identity changes
- **Content only**: `PATCH /webhooks/{id}/{token}/messages/{msg_id}` -- identity unchanged
- **Identity change**: Must `DELETE` then re-`POST` the message

### Consistent identity across webhooks
Use bot token with Manage Webhooks permission to list and update all guild webhooks:

```bash
curl -H "Authorization: Bot $TOKEN" \
  https://discord.com/api/v10/guilds/{guild_id}/webhooks
```

Then PATCH each with the same name and avatar.

## Key Insight

Discord treats bot users and webhooks as independent identity systems. Webhook messages snapshot the author identity at post time. The only way to fix stale identity on existing messages is delete + repost. All webhook payloads should include explicit `username` and `avatar_url` fields rather than relying on webhook defaults.

## Related

- `knowledge-base/learnings/2026-02-18-token-env-var-not-cli-arg.md` -- token security
- `knowledge-base/learnings/implementation-patterns/2026-02-12-ci-for-notifications-and-infrastructure-setup.md` -- CI webhook patterns
- `knowledge-base/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` -- brand guide contract
- GitHub Issue #142 -- brand assets directory research
