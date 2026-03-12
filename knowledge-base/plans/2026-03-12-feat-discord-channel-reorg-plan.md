---
title: "feat: Discord channel reorganization -- releases and blog channels"
type: feat
date: 2026-03-12
semver: patch
---

# feat: Discord channel reorganization -- releases and blog channels

## Overview

Reorganize Discord channel structure by introducing two new channels and routing content to them:

1. **#releases** -- Dedicated channel for version release announcements (currently posted to #announcements)
2. **#blog** -- Dedicated channel for blog post distribution content (currently posted to the general webhook channel)

This requires new Discord webhooks per channel, new GitHub Actions secrets, and updating all workflows and scripts that post to Discord.

## Problem Statement / Motivation

Currently, all automated Discord content flows through a single `DISCORD_WEBHOOK_URL` secret that targets one channel (likely #announcements or #general). This creates two problems:

1. **Signal-to-noise** -- Release notifications, blog posts, case study content, failure alerts, and community digests all land in the same channel. Users who care about releases but not blog posts cannot selectively follow.
2. **Channel purpose clarity** -- Discord best practice is to give channels clear, single purposes. Mixing content types makes channels harder to scan and reduces engagement.

The user wants:
- **#releases** for version release announcements (currently in the `version-bump-and-release.yml` workflow's "Post to Discord" step)
- **#blog** for blog post distribution (currently in the `content-publisher.sh` Discord posting and the `social-distribute` skill)

## Proposed Solution

### New Secrets

Add two new GitHub repository secrets:

| Secret | Target Channel | Used By |
|--------|---------------|---------|
| `DISCORD_RELEASES_WEBHOOK_URL` | #releases | `version-bump-and-release.yml` |
| `DISCORD_BLOG_WEBHOOK_URL` | #blog | `content-publisher.sh`, `social-distribute` skill |

The existing `DISCORD_WEBHOOK_URL` remains as the **default/general** webhook for:
- CI failure notifications (all workflows)
- Community digest posting
- Bot-fix monitor notifications
- `discord-content` skill (general community posts)

### Channel Creation (Manual)

Discord channels and webhooks must be created manually in the Discord server admin panel -- there is no automated way to do this safely:

1. Create #releases channel in the server (under an appropriate category)
2. Create a webhook in #releases, save the URL as `DISCORD_RELEASES_WEBHOOK_URL` repo secret
3. Create #blog channel in the server
4. Create a webhook in #blog, save the URL as `DISCORD_BLOG_WEBHOOK_URL` repo secret

### Code Changes

#### 1. `version-bump-and-release.yml` -- Route releases to #releases

- Change the "Post to Discord" step to use `DISCORD_RELEASES_WEBHOOK_URL` instead of `DISCORD_WEBHOOK_URL`
- Add fallback: if `DISCORD_RELEASES_WEBHOOK_URL` is not set, fall back to `DISCORD_WEBHOOK_URL` (graceful degradation for environments without the new secret)

**File:** `.github/workflows/version-bump-and-release.yml` (lines 239-278)

#### 2. `content-publisher.sh` -- Route blog content to #blog

- Add support for `DISCORD_BLOG_WEBHOOK_URL` environment variable
- In `post_discord()`, prefer `DISCORD_BLOG_WEBHOOK_URL` over `DISCORD_WEBHOOK_URL`
- Add fallback: if `DISCORD_BLOG_WEBHOOK_URL` is not set, fall back to `DISCORD_WEBHOOK_URL`
- Update the `create_discord_fallback_issue()` function to mention the correct channel

**File:** `scripts/content-publisher.sh` (lines 126-153)

#### 3. `scheduled-content-publisher.yml` -- Pass new secret

- Add `DISCORD_BLOG_WEBHOOK_URL: ${{ secrets.DISCORD_BLOG_WEBHOOK_URL }}` to the "Publish content" step's env block

**File:** `.github/workflows/scheduled-content-publisher.yml` (line 60)

#### 4. `social-distribute` skill -- Reference new env var

- Update the Discord webhook prerequisite check to mention `DISCORD_BLOG_WEBHOOK_URL` as the preferred env var
- Update webhook posting instructions to prefer `DISCORD_BLOG_WEBHOOK_URL`

**File:** `plugins/soleur/skills/social-distribute/SKILL.md` (prerequisite section)

#### 5. `discord-content` skill -- No changes needed

The `discord-content` skill is for general community content, not releases or blog posts. It correctly uses `DISCORD_WEBHOOK_URL` for the default/general channel.

#### 6. `discord-setup.sh` -- Update `write-env` to include new vars

- Add `DISCORD_RELEASES_WEBHOOK_URL` and `DISCORD_BLOG_WEBHOOK_URL` as optional variables in the `cmd_write_env()` function
- Update usage docs to mention the new variables

**File:** `plugins/soleur/skills/community/scripts/discord-setup.sh` (lines 204-236)

#### 7. Documentation updates

- Update the learning at `knowledge-base/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` to reference the multi-webhook channel architecture
- Update `knowledge-base/overview/constitution.md` if any new conventions emerge (e.g., webhook naming pattern)

## Technical Considerations

### Webhook per channel architecture

Discord webhooks are channel-scoped -- each webhook posts to exactly one channel. The project already has this pattern (the learning doc mentions separate community and release webhooks). This change formalizes it with distinct secret names.

### Backward compatibility

All changes use fallback patterns: `${DISCORD_RELEASES_WEBHOOK_URL:-$DISCORD_WEBHOOK_URL}`. Environments that have not created the new secrets continue to work unchanged -- all content goes to the existing channel.

### Secret management

The new secrets (`DISCORD_RELEASES_WEBHOOK_URL`, `DISCORD_BLOG_WEBHOOK_URL`) are GitHub repository secrets set via Settings > Secrets > Actions. No `.env` file changes are needed for CI. Local development (via `discord-setup.sh write-env`) optionally supports the new variables.

### Identity consistency

All webhook payloads already include explicit `username: "Sol"` and `avatar_url` fields per constitution.md rule. This ensures consistent identity across all three webhooks/channels.

## Non-Goals

- Creating the Discord channels (manual admin task)
- Changing the structure of posted messages (format stays the same)
- Adding rich embeds or interactive components
- Reorganizing other channels (e.g., #general, #help)
- Creating a channel for CI failure notifications (they stay on the default webhook)

## Acceptance Criteria

- [ ] `version-bump-and-release.yml` posts release announcements to `DISCORD_RELEASES_WEBHOOK_URL` when set, falls back to `DISCORD_WEBHOOK_URL` when not set
- [ ] `content-publisher.sh` posts blog/case-study content to `DISCORD_BLOG_WEBHOOK_URL` when set, falls back to `DISCORD_WEBHOOK_URL` when not set
- [ ] `scheduled-content-publisher.yml` passes the new `DISCORD_BLOG_WEBHOOK_URL` secret to the publish step
- [ ] `social-distribute` skill documentation references `DISCORD_BLOG_WEBHOOK_URL`
- [ ] All existing CI workflows that use `DISCORD_WEBHOOK_URL` for failure notifications continue to work unchanged
- [ ] All webhook payloads continue to include `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields
- [ ] `discord-setup.sh write-env` supports the new optional webhook variables
- [ ] The fallback pattern is tested: workflows work correctly when only `DISCORD_WEBHOOK_URL` is set

## Test Scenarios

- Given `DISCORD_RELEASES_WEBHOOK_URL` is set, when a release is created, then the release announcement is posted to the releases webhook URL
- Given `DISCORD_RELEASES_WEBHOOK_URL` is NOT set but `DISCORD_WEBHOOK_URL` is, when a release is created, then the release announcement falls back to the default webhook URL
- Given `DISCORD_BLOG_WEBHOOK_URL` is set, when `content-publisher.sh` posts Discord content, then the content is posted to the blog webhook URL
- Given `DISCORD_BLOG_WEBHOOK_URL` is NOT set but `DISCORD_WEBHOOK_URL` is, when `content-publisher.sh` posts Discord content, then the content falls back to the default webhook URL
- Given neither `DISCORD_RELEASES_WEBHOOK_URL` nor `DISCORD_WEBHOOK_URL` is set, when a release is created, then the Discord step is skipped with a warning
- Given the new channels exist in Discord with webhooks configured, when all three webhook secrets are set, then releases go to #releases, blog posts go to #blog, and failure notifications go to the default channel

## Dependencies & Risks

### Dependencies

- Manual Discord admin action: create #releases and #blog channels plus webhooks
- GitHub repo admin action: add `DISCORD_RELEASES_WEBHOOK_URL` and `DISCORD_BLOG_WEBHOOK_URL` secrets

### Risks

- **Low risk**: Fallback pattern ensures no breakage if secrets are not yet configured
- **Low risk**: Webhook URL format is the same as existing -- no new API patterns

## Files to Modify

| File | Change |
|------|--------|
| `.github/workflows/version-bump-and-release.yml` | Use `DISCORD_RELEASES_WEBHOOK_URL` with fallback |
| `scripts/content-publisher.sh` | Use `DISCORD_BLOG_WEBHOOK_URL` with fallback |
| `.github/workflows/scheduled-content-publisher.yml` | Pass `DISCORD_BLOG_WEBHOOK_URL` secret |
| `plugins/soleur/skills/social-distribute/SKILL.md` | Reference `DISCORD_BLOG_WEBHOOK_URL` |
| `plugins/soleur/skills/community/scripts/discord-setup.sh` | Optional new vars in `write-env` |
| `knowledge-base/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` | Document multi-webhook pattern |
| `test/content-publisher.test.ts` | Add tests for new env var fallback logic |

## References

- `knowledge-base/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` -- Existing webhook identity patterns
- `knowledge-base/learnings/2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` -- Webhook payload security
- Constitution rule: "All Discord webhook payloads must include explicit `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields"
