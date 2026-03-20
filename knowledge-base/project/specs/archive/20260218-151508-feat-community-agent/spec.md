# Community Agent Spec

**Issue:** #96
**Date:** 2026-02-18
**Branch:** feat-community-agent
**Brainstorm:** `knowledge-base/brainstorms/2026-02-18-community-agent-brainstorm.md`

## Problem Statement

Soleur has community infrastructure (Discord webhook, release CI, brand voice guidelines) but no unified tool for managing community engagement. Users can post to Discord and announce releases, but cannot monitor community activity, generate digests, track contributors, or manage community health. Other projects using Soleur have no community management capability at all.

## Goals

1. Build a community manager agent that orchestrates community workflows across platforms
2. Build a community skill as the user-facing entry point for community operations
3. Enable Discord monitoring via bot token (read messages, reactions, members)
4. Generate weekly community digests (markdown + Discord post)
5. Design with platform-agnostic abstractions so GitHub Discussions and other platforms can be added later

## Non-Goals

- Docs site community page (separate follow-up issue)
- Discord bot hosting/persistent deployment (on-demand execution only)
- Moderation capabilities (read-only monitoring)
- Social media integrations (X/Bluesky) -- future expansion
- Real-time streaming/notifications

## Functional Requirements

- **FR1:** Community skill with sub-commands: `digest`, `post`, `health`, `welcome`
- **FR2:** Community manager agent that monitors Discord channels via bot API
- **FR3:** Weekly digest generation -- markdown file to `knowledge-base/community/` AND condensed Discord post
- **FR4:** Contributor identification and recognition from Discord + GitHub activity
- **FR5:** Community health metrics: member count, message volume, response times, unanswered questions
- **FR6:** Agent orchestrates existing skills: calls `discord-content` for posting, `release-announce` for releases

## Technical Requirements

- **TR1:** Discord Bot Token authentication via `DISCORD_BOT_TOKEN` env var
- **TR2:** Discord API access via shell scripts (curl) in `skills/community/scripts/`
- **TR3:** GitHub API access via `gh` CLI for PR/issue/discussion data
- **TR4:** Agent located at `agents/marketing/community-manager.md`
- **TR5:** Skill located at `skills/community/SKILL.md`
- **TR6:** Platform-agnostic design -- Discord-specific logic isolated in scripts, agent reasons about community concepts

## Architecture

```
User --> /soleur:community (skill)
              |
              +--> Simple actions (post, welcome) --> discord-content skill
              |
              +--> Complex workflows (digest, health) --> community-manager agent
                        |
                        +--> scripts/discord-api.sh (read Discord)
                        +--> scripts/github-community.sh (read GitHub)
                        +--> discord-content skill (post results)
                        +--> knowledge-base/community/ (write digests)
```

## Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `DISCORD_BOT_TOKEN` | Read access to Discord server | Yes |
| `DISCORD_WEBHOOK_URL` | Post to Discord (existing) | Yes |
| `DISCORD_GUILD_ID` | Discord server identifier | Yes |
| `DISCORD_CHANNEL_IDS` | Channels to monitor (comma-separated) | Optional |

## Open Questions

1. Rate limiting strategy for Discord API polling
2. Data retention window (7 days for digest? 30 for trends?)
3. Privacy handling for Discord usernames in digest files
4. GitHub Discussions support timeline (v1 or v2?)
