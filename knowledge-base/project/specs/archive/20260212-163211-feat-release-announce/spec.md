---
name: Release Announce Spec
description: Automate release announcements to Discord and GitHub Releases
date: 2026-02-12
issue: "#59"
status: draft
---

# Release Announce Spec

## Problem Statement

Release announcements are manual and inconsistent. After shipping a new version via `/ship`, there's no automated step to notify the community on Discord or create a GitHub Release. This means announcements are often forgotten or delayed.

## Goals

1. Automate posting release announcements to Discord and GitHub Releases
2. Generate engaging, AI-powered summaries from CHANGELOG.md content
3. Integrate seamlessly into the existing `/ship` workflow
4. Provide standalone invocation for ad-hoc announcements

## Non-Goals

- Twitter/X or Slack integration (future work)
- Automated image/banner generation
- Release scheduling or delayed posting
- Engagement analytics

## Functional Requirements

- **FR1:** Extract the current version's section from CHANGELOG.md
- **FR2:** Generate a channel-appropriate AI summary (punchy for Discord, detailed for GitHub Release)
- **FR3:** Post to Discord via webhook using `DISCORD_WEBHOOK_URL` environment variable
- **FR4:** Create GitHub Release via `gh release create` with version tag and generated notes
- **FR5:** Degrade gracefully if `DISCORD_WEBHOOK_URL` is unset (skip Discord, warn user)
- **FR6:** Degrade gracefully if posting fails (log error, continue workflow)
- **FR7:** Support standalone invocation via `/release-announce`
- **FR8:** Integrate as a post-merge phase in `/ship` skill

## Technical Requirements

- **TR1:** New skill at `plugins/soleur/skills/release-announce/SKILL.md`
- **TR2:** Discord messages must be under 2000 characters
- **TR3:** Use `gh release create` (already available in the project's toolchain)
- **TR4:** No new external dependencies or API keys beyond Discord webhook URL
- **TR5:** Follow plugin conventions: YAML frontmatter, third-person description, kebab-case naming

## Acceptance Criteria

- [ ] `/release-announce` skill exists and is discoverable by agents
- [ ] Running the skill generates Discord and GitHub Release content from CHANGELOG.md
- [ ] Discord webhook posts successfully when `DISCORD_WEBHOOK_URL` is set
- [ ] GitHub Release is created with the correct version tag and AI-generated notes
- [ ] Missing webhook URL produces a warning, not an error
- [ ] `/ship` skill invokes `/release-announce` in its post-merge phase
- [ ] Version bump (MINOR) applied: plugin.json, CHANGELOG.md, README.md
