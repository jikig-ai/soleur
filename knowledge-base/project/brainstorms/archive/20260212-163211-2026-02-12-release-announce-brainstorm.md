---
name: Release Announce Brainstorm
description: Automate release announcements to Discord and GitHub Releases
date: 2026-02-12
issue: "#59"
---

# Release Announce Brainstorm

## What We're Building

A new `/release-announce` skill that generates AI-powered release announcements and posts them to Discord (via webhook) and GitHub Releases (via `gh release create`). The skill integrates into the `/ship` workflow as a post-merge phase but can also run standalone.

## Why This Approach

- **Separate skill + ship integration (Approach B):** Keeps `/ship` focused on the release lifecycle while making announcements a composable, agent-discoverable capability. Aligns with the project vision of building standalone company functions.
- **Rejected alternatives:**
  - Extending `/ship` directly -- tightly couples announcement logic to release flow
  - GitHub Action on tag push -- less AI flexibility for content generation, harder to iterate

## Key Decisions

1. **Trigger:** Integrated into `/ship` as post-merge phase, also invocable standalone
2. **Channels:** Discord (webhook) + GitHub Releases (`gh release create`)
3. **Content:** AI-generated summaries from CHANGELOG.md -- punchy for Discord, detailed for GitHub Release
4. **Credentials:** `DISCORD_WEBHOOK_URL` environment variable
5. **No Twitter/X:** Dropped from scope to avoid OAuth complexity
6. **No external dependencies:** Building blocks already exist in the repo (changelog skill has Discord patterns, gh CLI handles releases)

## Scope

### In Scope

- New `release-announce` skill under `plugins/soleur/skills/`
- AI-generated announcement from CHANGELOG.md version section
- Discord posting via webhook (formatted embed, under 2000 chars)
- GitHub Release creation via `gh release create` with detailed notes
- Integration hook in `/ship` skill post-merge phase
- Graceful degradation if webhook URL is missing or post fails
- Version bump (MINOR: new skill)

### Out of Scope

- Twitter/X integration
- Slack integration
- Automated image/banner generation for releases
- Release scheduling or delayed posting
- Analytics/tracking of announcement engagement

## Open Questions

- Should the Discord message use a rich embed (with color, fields, footer) or plain text?
- Should the skill create git tags, or assume tags are already created by the release process?
- What's the Discord channel/server for announcements?
