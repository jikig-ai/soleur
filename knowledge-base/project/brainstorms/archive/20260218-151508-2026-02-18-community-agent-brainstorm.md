# Community Agent Brainstorm

**Date:** 2026-02-18
**Issue:** #96
**Status:** Complete

## What We're Building

A community management capability for Soleur with two components:

1. **Community Manager Agent** (`agents/marketing/community-manager.md`) -- the reasoning brain that orchestrates community workflows: monitoring Discord via bot token, analyzing engagement patterns, generating weekly digests, and identifying contributors.

2. **Community Skill** (`skills/community/SKILL.md`) -- the user-facing entry point (`/soleur:community`) that provides sub-commands for common community operations and routes complex workflows to the agent.

The agent uses existing skills as building blocks: `discord-content` for posting, `release-announce` for releases. It adds monitoring (read Discord via bot API), synthesis (weekly digests), and strategy (content suggestions based on community activity).

This is designed to be reusable by any project using Soleur, not just Soleur's own community.

## Why This Approach

**Orchestrator pattern over replacement:** Existing skills (`discord-content`, `release-announce`) stay as sharp, single-purpose tools. The agent adds the higher-level intelligence -- when to post, what to digest, who to recognize. No duplication, no breaking changes.

**Agent + Skill combo over agent-only or skill-only:**
- Skill gives users a discoverable entry point (`/soleur:community digest`)
- Agent provides multi-step reasoning for complex workflows (analyzing a week of Discord data)
- Both are independently reusable -- other agents can call community-manager, users can invoke the skill directly

**Bot token for Discord monitoring:** Webhooks are write-only. Reading messages, reactions, and member activity requires a Discord bot token. This is the standard approach and unlocks the full monitoring capability.

**Multi-platform with abstractions:** Discord is the first implementation, but the design supports GitHub Discussions and social media adapters. Platform-specific logic stays in shell scripts; the agent reasons about community concepts (engagement, sentiment, contributors) not platform details.

## Key Decisions

1. **Architecture:** Agent + Skill combo. Agent = reasoning, Skill = user entry point + API scripts.
2. **Relationship to existing skills:** Orchestrator. discord-content and release-announce stay independent. Community agent calls them when needed.
3. **Discord access:** Bot token approach (env var `DISCORD_BOT_TOKEN`). Enables read access to messages, reactions, members.
4. **Digest output:** Both -- markdown file to `knowledge-base/community/` AND condensed Discord post. Full version for reference, summary for the channel.
5. **Platform scope:** Discord-first with platform-agnostic abstractions. GitHub Discussions is the natural second platform.
6. **Agent location:** `agents/marketing/community-manager.md` -- community management is a marketing function.
7. **Skill location:** `skills/community/SKILL.md` -- flat at root per Soleur convention.

## Capability Breakdown

### Community Skill Sub-commands

- `/soleur:community digest` -- Generate weekly community digest (spawns agent for analysis)
- `/soleur:community post <topic>` -- Craft and post a community update (uses discord-content skill)
- `/soleur:community health` -- Show community health metrics (member count, active discussions, response times)
- `/soleur:community welcome` -- Generate onboarding message for new members

### Community Agent Capabilities

- **Monitor:** Read Discord channels, track message volume, identify trending topics, flag unanswered questions
- **Analyze:** Identify top contributors, track engagement patterns over time, surface common questions/pain points
- **Synthesize:** Generate weekly digest (markdown + Discord post), create contributor recognition posts
- **Strategize:** Suggest content based on community activity, recommend engagement actions

### Shell Scripts (in `skills/community/scripts/`)

- `discord-api.sh` -- Discord Bot API wrapper (read messages, reactions, members)
- `github-community.sh` -- GitHub API wrapper (discussions, issue activity, PR contributions)
- `digest-template.sh` -- Digest markdown template generation

## Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `DISCORD_BOT_TOKEN` | Read access to Discord server | Yes (for monitoring) |
| `DISCORD_WEBHOOK_URL` | Post to Discord (existing) | Yes (for posting) |
| `DISCORD_GUILD_ID` | Discord server identifier | Yes |
| `DISCORD_CHANNEL_IDS` | Comma-separated channel IDs to monitor | Optional (defaults to all) |

## Open Questions

1. **Rate limiting:** Discord API has rate limits. How aggressively should monitoring poll? Daily batch vs. real-time?
2. **Data retention:** How much Discord history should we analyze? Last 7 days for digest? Last 30 for trends?
3. **Privacy:** Should we store Discord usernames in digest files? Or anonymize to "N contributors"?
4. **GitHub Discussions timeline:** When should GitHub Discussions support be added? V1 or V2?

## What's NOT in Scope

- Docs site community page (separate follow-up issue)
- Discord bot hosting/deployment (agent runs on-demand, not as a persistent bot)
- Moderation capabilities (read-only monitoring, no message deletion/banning)
- Social media integrations (X/Bluesky -- future expansion)
- Real-time notifications (batch analysis, not streaming)
