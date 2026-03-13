# Spec: Extend Community Agent with X Presence

**Issue:** #127
**Branch:** feat-community-agent-x
**Brainstorm:** [2026-03-09-community-agent-x-brainstorm.md](../../brainstorms/2026-03-09-community-agent-x-brainstorm.md)

## Problem Statement

The community-manager agent is hardcoded to Discord + GitHub. It cannot monitor or engage on X/Twitter, which is one of the largest social platforms for reaching solo founders (#buildinpublic audience). Additionally, the community skill lacks a SKILL.md entry point, making it uninvocable. With 8 open platform extension issues, a platform-agnostic refactor is needed before adding X.

## Goals

1. Refactor community-manager into a platform-agnostic architecture using an adapter pattern
2. Add X/Twitter as the first non-Discord platform (Free tier API)
3. Enable monitoring (mentions, metrics, timeline) and engagement (draft replies) on X
4. Fix the community skill by creating SKILL.md with sub-commands
5. Maintain clear ownership boundary: community-manager = monitoring + engagement, social-distribute = broadcast

## Non-Goals

- Automated X content posting for blog distribution (social-distribute handles this)
- X API Basic/Pro tier features
- Implementing other platform integrations (#134-#140) — refactor enables them, but implementation is separate per issue
- X DM support
- Paid advertising on X
- Creating the X account itself (manual founder action, prerequisite)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Platform adapter interface: each platform script implements `fetch-mentions`, `fetch-metrics`, `post-reply`, `fetch-timeline` |
| FR2 | `x-community.sh` script implementing the adapter interface using X API v2 (Free tier) |
| FR3 | `x-setup.sh` script for X API credential validation (env vars: `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`) |
| FR4 | Refactored `discord-community.sh` conforming to the adapter interface (backwards-compatible) |
| FR5 | Community-manager agent updated to be platform-agnostic: capabilities accept a `--platform` flag or detect enabled platforms from env vars |
| FR6 | Unified digest format that presents multi-platform metrics under platform-specific sections |
| FR7 | Engagement capability: draft replies to X mentions with user approval before posting |
| FR8 | Community SKILL.md with sub-commands: `digest`, `health`, `engage`, `platforms` |
| FR9 | Rate limit tracking for X Free tier (50 tweets/month) with warnings at 80% and 100% usage |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | X API authentication via OAuth 1.0a (User Context) for Free tier |
| TR2 | All platform scripts use `curl` + `jq` + `openssl` — no additional installs beyond standard system tools |
| TR3 | Env var detection determines enabled platforms: `DISCORD_BOT_TOKEN` → Discord, `X_API_KEY` → X, GitHub always enabled via `gh` CLI |
| TR4 | Adapter scripts must exit non-zero with clear error messages on auth failure or rate limit |
| TR5 | Brand guide `## Channel Notes > ### X/Twitter` section consumed for engagement tone |
| TR6 | Engagement replies require user approval via AskUserQuestion pattern (same as discord-content) |
| TR7 | Existing Discord functionality must not regress — all current community-manager capabilities work unchanged |

## X API Access Notes

As of early 2026, X API has migrated to a **pay-per-use credit system**. Legacy tiers (Free/Basic/Pro) are being phased out. The Free tier is extremely limited (1 request per 24 hours on most endpoints). Meaningful API access (reading mentions, timelines, posting tweets) requires purchasing credits in the Developer Console. Scripts are designed to work with whatever access level is provisioned.

## Dependencies

- **Blocking:** X account registration (@soleur preferred) — manual founder action
- **Blocking:** X Developer Portal account + API key/credit provisioning — manual founder action
- **Non-blocking:** social-distribute skill update to note X account exists (separate follow-up)

## Success Criteria

- [ ] `x-community.sh fetch-mentions` returns recent mentions from X
- [ ] `x-community.sh fetch-metrics` returns follower count and engagement summary
- [ ] `discord-community.sh` still works unchanged through adapter interface
- [ ] Community digest includes both Discord and X sections when both are enabled
- [ ] `/soleur:community digest` invocable and functional
- [ ] `/soleur:community engage` drafts X reply with user approval gate
- [ ] Rate limit tracked and warning displayed at 80% of 50 tweets/month
