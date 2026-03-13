# Feature: Bluesky Presence

## Problem Statement

Soleur has no presence on Bluesky, which has the highest engagement among emerging platforms (16.38 interactions/post avg) and a developer-heavy early adopter audience that directly overlaps our ICP. The community agent supports Discord, GitHub, and X/Twitter but has no Bluesky integration.

## Goals

- Add Bluesky as the 4th supported platform in the community agent with monitoring and engagement parity to X/Twitter
- Enable digest generation, health metrics, and mention engagement for Bluesky
- Claim `@soleur.bsky.social` handle and bootstrap profile
- Add brand guide channel notes for Bluesky-native voice

## Non-Goals

- Custom domain handle (`@soleur.ai`) — deferred to follow-up
- Platform adapter interface refactor (#470) — follow-up refactor once all 4 scripts exist
- Social distribution integration (social-distribute + content-publisher) — deferred until audience exists
- Rich text facets (byte-position link/mention rendering) — URLs auto-link without facets
- Changing brainstorm routing (CCO → community-manager delegation stays as-is)
- Instagram, TikTok, LinkedIn, Product Hunt, or Hacker News integrations
- Bluesky-specific features beyond X parity (e.g., custom feeds, labelers)
- Docs site updates (`site.json`, `community.njk`) — deferred until profile is live

## Functional Requirements

### FR1: Bluesky Account Setup

`bsky-setup.sh` stores credentials (`BSKY_HANDLE`, `BSKY_APP_PASSWORD`) in `.env` and verifies session creation via AT Protocol. Two commands: `write-env` and `verify`. Follows `x-setup.sh` conventions: `git rev-parse --show-toplevel` for `.env` path, `chmod 600`, no CLI arg secrets.

### FR2: Bluesky Community Script

`bsky-community.sh` provides AT Protocol API wrapper with commands: `create-session`, `post`, `get-metrics`, `get-notifications`. Single `post` command handles both new posts and replies via optional `--reply-to-uri/cid --root-uri/cid` flags. Plain text posts only (no facets). Codepoint-based length validation via `wc -m` as grapheme approximation. Fresh session per invocation (no token caching). Depth-limited retry (max 3) reading `ratelimit-reset` header.

### FR3: Community Agent Bluesky Support

community-manager agent includes Bluesky in 3 capabilities: digest generation, health metrics, and mention engagement. Content Suggestions deferred (no Bluesky data on new account). Platform detected via env var presence (`BSKY_HANDLE` + `BSKY_APP_PASSWORD`). Mentions fetched via `listNotifications` filtered by `reason: "mention"`. Cursor-based pagination with `.soleur/bsky-engage-cursor` state file.

### FR4: Community Skill Update

SKILL.md Platform Detection table includes Bluesky. `platforms` sub-command reports Bluesky status. `engage` sub-command adds `--platform` flag — prompts user to choose platform if flag not specified.

### FR5: Brand Guide

Brand guide includes `### Bluesky` Channel Notes (developer audience, thread culture, AT Protocol tone, anti-bot engagement guardrails).

## Technical Requirements

### TR1: AT Protocol Authentication

Fresh session per script invocation via `com.atproto.server.createSession`. No token caching or refresh logic — sessions last minutes, scripts run seconds. Store only app password in `.env`, not tokens. Dependencies: `curl` and `jq` only (no `openssl`).

### TR2: Error Handling

AT Protocol errors use `{"error": "ErrorName", "message": "..."}` format. Rate limits use `ratelimit-reset` header (Unix timestamp), not body JSON. Exit codes: 0=success, 1=error, 2=rate-limit-exhausted.

### TR3: Content Format

Plain text posts only (no facets). 300 grapheme limit validated via `wc -m` (codepoint approximation). Threads created via reply references using `--reply-to-uri/cid` and `--root-uri/cid` flags. Root references stay constant throughout a thread; parent references update per post.
