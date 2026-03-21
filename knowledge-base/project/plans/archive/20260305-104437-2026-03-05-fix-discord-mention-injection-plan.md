---
title: "fix: sanitize Discord mention patterns in release webhook"
type: fix
date: 2026-03-05
semver: patch
deepened: 2026-03-05
---

# fix: Sanitize Discord mention patterns in release webhook

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Test Scenarios, References)
**Research sources:** Discord API documentation, project learnings, constitution review

### Key Improvements

1. Clarified Discord's default webhook mention behavior -- webhooks only parse user mentions by default, not `@everyone`/`@here`, but `allowed_mentions: {parse: []}` is still needed to block user/role mentions and as defense-in-depth
2. Added the three valid `parse` array values (`"users"`, `"roles"`, `"everyone"`) from official API docs for implementer reference
3. Added verification step to test scenarios -- `jq` dry-run to validate JSON structure before relying on CI

## Overview

The Discord webhook notification in `version-bump-and-release.yml` includes unsanitized PR body content. A PR body containing `@everyone`, `@here`, or Discord mention syntax (`<@USER_ID>`, `<@&ROLE_ID>`) would trigger real mentions in the Discord channel when the release notification is posted.

## Problem Statement

In the "Post to Discord" step (`.github/workflows/version-bump-and-release.yml:239-278`), the release notes are extracted from the PR body via `cat "$RELEASE_NOTES_FILE"` and interpolated directly into the Discord webhook `content` field. The Discord API processes mention syntax in `content` by default, meaning an attacker (or careless contributor) with merge access could trigger `@everyone` or `@here` pings on the entire server.

**Attack chain:** Merge access + PR body containing mention syntax + webhook having mention permissions. The issue is rated P3 because this requires merge access, but the fix is trivial and eliminates the risk entirely.

**Root cause:** The `jq` payload construction at line 263 does not set the `allowed_mentions` field, so Discord uses its default mention-parsing behavior.

### Research Insight: Discord Webhook Default Behavior

Per Discord API docs (verified 2026-03-05): "In interactions and webhooks, only user mentions are parsed" by default. This means `@everyone` and `@here` are likely already suppressed for webhook messages without `allowed_mentions`. However, `<@USER_ID>` user mentions ARE parsed by default in webhooks, and `<@&ROLE_ID>` role mentions may also resolve depending on server configuration. The `allowed_mentions: {parse: []}` fix is still necessary to:

1. Block user mention parsing (which IS active by default on webhooks)
2. Guarantee `@everyone`/`@here` suppression regardless of future Discord API changes
3. Provide explicit, auditable intent in the payload

## Proposed Solution

Use Discord's `allowed_mentions` API field to disable all mention parsing at the API level, rather than relying on regex stripping. This is the defense-in-depth approach recommended by Discord's documentation.

### `.github/workflows/version-bump-and-release.yml` -- "Post to Discord" step

**Change the `jq` payload construction** (line 263-267) to include `allowed_mentions` with an empty `parse` array:

```yaml
          PAYLOAD=$(jq -n \
            --arg content "$MESSAGE" \
            --arg username "Sol" \
            --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
            '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
```

The `allowed_mentions.parse: []` setting tells Discord to render mention text literally (e.g., `@everyone` appears as plain text) without triggering any actual pings. This covers all mention types:

- `@everyone` and `@here` (mass mentions) -- `parse` value: `"everyone"`
- `<@USER_ID>` and `<@!USER_ID>` (user mentions) -- `parse` value: `"users"`
- `<@&ROLE_ID>` (role mentions) -- `parse` value: `"roles"`

### API Reference: AllowedMentions Object

The `allowed_mentions` object supports four fields (Discord API docs):

| Field | Type | Description |
|-------|------|-------------|
| `parse` | array of strings | Which mention categories to process: `"users"`, `"roles"`, `"everyone"` |
| `roles` | array of snowflakes | Specific role IDs to allow (max 100) |
| `users` | array of snowflakes | Specific user IDs to allow (max 100) |
| `replied_user` | boolean | Whether to ping the replied-to message author (default: false) |

Setting `parse: []` with no `roles`/`users` arrays suppresses all mention parsing entirely.

### Why `allowed_mentions` over sed stripping

The issue body suggests `sed 's/@everyone//g; s/@here//g'` but this approach has gaps:

1. **Incomplete coverage** -- Does not strip user mentions (`<@123456>`) or role mentions (`<@&789>`)
2. **Content destruction** -- Removing `@everyone` from legitimate text changes the meaning of the release notes
3. **Bypass risk** -- Unicode lookalikes or zero-width characters could evade regex stripping
4. **API-level enforcement** -- `allowed_mentions` is the official Discord mechanism for this exact problem; it preserves content while neutralizing mentions

## Non-goals

- Sanitizing the GitHub Release body (GitHub Releases don't support mention syntax)
- Adding mention sanitization to the triage workflow (it does not post to Discord webhooks)
- Changing webhook permissions on the Discord server (defense-in-depth, not instead-of)

## Acceptance Criteria

- [x] The `jq` payload in the "Post to Discord" step includes `allowed_mentions: {parse: []}` -- file: `.github/workflows/version-bump-and-release.yml`
- [x] Release notes content is preserved verbatim (no sed stripping that alters text)
- [x] Existing webhook fields (`content`, `username`, `avatar_url`) remain unchanged

## Test Scenarios

- Given a PR body containing `@everyone`, when the release workflow runs, then the Discord message displays `@everyone` as plain text without pinging anyone
- Given a PR body containing `<@123456789>` (user mention syntax), when the release workflow runs, then the Discord message displays the raw text without resolving or pinging the user
- Given a PR body containing `<@&987654321>` (role mention syntax), when the release workflow runs, then the Discord message displays the raw text without pinging the role
- Given a normal PR body with no mention syntax, when the release workflow runs, then the Discord notification behaves identically to current behavior

### Local Verification

Before merging, validate the JSON payload structure locally:

```bash
# Verify jq produces valid JSON with allowed_mentions
echo "Test @everyone body" | jq -n \
  --arg content "$(cat)" \
  --arg username "Sol" \
  --arg avatar_url "https://example.com/logo.png" \
  '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}'
# Expected: valid JSON with "allowed_mentions":{"parse":[]}
```

Full end-to-end verification requires a real webhook URL and is best done post-merge on the next release.

## Context

- GitHub Issue: #427
- Found during review of PR #420
- Bot fix was attempted but blocked by the `soleur:fix-issue` skill's infrastructure constraint (`.github/workflows/` is prohibited for automated fixes)
- Related learning: `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` (webhook payload conventions)
- Related learning: `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md` (CI security patterns)
- Constitution principle: "All Discord webhook payloads must include explicit `username` and `avatar_url` fields" (line 92) -- the existing code already follows this; this fix adds `allowed_mentions` as another required field

## MVP

### `.github/workflows/version-bump-and-release.yml`

Single-line change to the `jq` invocation in the "Post to Discord" step:

```yaml
          PAYLOAD=$(jq -n \
            --arg content "$MESSAGE" \
            --arg username "Sol" \
            --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
            '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
```

### `knowledge-base/overview/constitution.md`

Update the existing Discord webhook convention (line 92) to include `allowed_mentions`:

> All Discord webhook payloads must include explicit `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields rather than relying on webhook defaults -- webhook messages freeze author identity at post time; only delete+repost changes identity on existing messages; omitting `allowed_mentions` enables mention injection from unsanitized content

## References

- Discord API `allowed_mentions` object: <https://docs.discord.com/developers/resources/message#allowed-mentions-object>
- Discord API Execute Webhook: <https://docs.discord.com/developers/resources/webhook#execute-webhook>
- GitHub Issue: #427
- PR #420 (where the vulnerability was found)
- `.github/workflows/version-bump-and-release.yml:239-278` (the "Post to Discord" step)
- Learning: `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md`
- Learning: `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-03-fix-release-notes-pr-extraction.md`
