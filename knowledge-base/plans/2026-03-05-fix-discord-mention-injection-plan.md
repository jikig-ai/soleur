---
title: "fix: sanitize Discord mention patterns in release webhook"
type: fix
date: 2026-03-05
semver: patch
---

# fix: Sanitize Discord mention patterns in release webhook

## Overview

The Discord webhook notification in `version-bump-and-release.yml` includes unsanitized PR body content. A PR body containing `@everyone`, `@here`, or Discord mention syntax (`<@USER_ID>`, `<@&ROLE_ID>`) would trigger real mentions in the Discord channel when the release notification is posted.

## Problem Statement

In the "Post to Discord" step (`.github/workflows/version-bump-and-release.yml:239-278`), the release notes are extracted from the PR body via `cat "$RELEASE_NOTES_FILE"` and interpolated directly into the Discord webhook `content` field. The Discord API processes mention syntax in `content` by default, meaning an attacker (or careless contributor) with merge access could trigger `@everyone` or `@here` pings on the entire server.

**Attack chain:** Merge access + PR body containing mention syntax + webhook having mention permissions. The issue is rated P3 because this requires merge access, but the fix is trivial and eliminates the risk entirely.

**Root cause:** The `jq` payload construction at line 263 does not set the `allowed_mentions` field, so Discord uses its default behavior of parsing all mention types.

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

- `@everyone` and `@here` (mass mentions)
- `<@USER_ID>` and `<@!USER_ID>` (user mentions)
- `<@&ROLE_ID>` (role mentions)

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

- [ ] The `jq` payload in the "Post to Discord" step includes `allowed_mentions: {parse: []}` -- file: `.github/workflows/version-bump-and-release.yml`
- [ ] Release notes content is preserved verbatim (no sed stripping that alters text)
- [ ] Existing webhook fields (`content`, `username`, `avatar_url`) remain unchanged

## Test Scenarios

- Given a PR body containing `@everyone`, when the release workflow runs, then the Discord message displays `@everyone` as plain text without pinging anyone
- Given a PR body containing `<@123456789>` (user mention syntax), when the release workflow runs, then the Discord message displays the raw text without resolving or pinging the user
- Given a PR body containing `<@&987654321>` (role mention syntax), when the release workflow runs, then the Discord message displays the raw text without pinging the role
- Given a normal PR body with no mention syntax, when the release workflow runs, then the Discord notification behaves identically to current behavior

## Context

- GitHub Issue: #427
- Found during review of PR #420
- Bot fix was attempted but blocked by the `soleur:fix-issue` skill's infrastructure constraint (`.github/workflows/` is prohibited for automated fixes)
- Related learning: `knowledge-base/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` (webhook payload conventions)
- Related learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md` (CI security patterns)
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

- Discord API `allowed_mentions` documentation: https://discord.com/developers/docs/resources/webhook#execute-webhook-jsonform-params
- GitHub Issue: #427
- PR #420 (where the vulnerability was found)
- `.github/workflows/version-bump-and-release.yml:239-278` (the "Post to Discord" step)
