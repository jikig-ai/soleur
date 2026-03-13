# Feature: Bluesky Presence

## Problem Statement

Soleur has no presence on Bluesky, which has the highest engagement among emerging platforms (16.38 interactions/post avg) and a developer-heavy early adopter audience that directly overlaps our ICP. The community agent supports Discord, GitHub, and X/Twitter but has no Bluesky integration.

## Goals

- Add Bluesky as the 4th supported platform in the community agent with full X/Twitter parity
- Enable digest generation, health metrics, content suggestions, and mention engagement for Bluesky
- Add Bluesky as a publishing target in social-distribute and content-publisher
- Generate platform-native content (not cross-posted from X)
- Claim `@soleur.bsky.social` handle and bootstrap profile

## Non-Goals

- Custom domain handle (`@soleur.ai`) — deferred to follow-up
- Platform adapter interface refactor — handled separately in #470 (prerequisite)
- Changing brainstorm routing (CCO → community-manager delegation stays as-is)
- Instagram, TikTok, LinkedIn, Product Hunt, or Hacker News integrations
- Bluesky-specific features beyond X parity (e.g., custom feeds, labelers)

## Functional Requirements

### FR1: Bluesky Account Setup

`bsky-setup.sh` validates and stores credentials (`BSKY_HANDLE`, `BSKY_APP_PASSWORD`) in `.env`. Verifies session creation via AT Protocol. Follows `x-setup.sh` conventions: `git rev-parse --show-toplevel` for `.env` path, `chmod 600`, no CLI arg secrets.

### FR2: Bluesky Community Script

`bsky-community.sh` provides AT Protocol API wrapper with commands: `post`, `get-feed`, `get-metrics`, `get-mentions`, `reply`. Implements 5-layer defense (input validation, curl stderr suppression, JSON validation, jq fallback chains, float-safe retry). Depth-limited retry (max 3).

### FR3: Community Agent Bluesky Support

community-manager agent includes Bluesky in all 4 capabilities: digest generation, health metrics, content suggestions, and mention engagement. Platform detected via env var presence (`BSKY_HANDLE` + `BSKY_APP_PASSWORD`).

### FR4: Community Skill Update

SKILL.md Platform Detection table includes Bluesky. `platforms` sub-command reports Bluesky status. `engage` sub-command supports Bluesky mentions alongside X/Twitter.

### FR5: Social Distribution

social-distribute skill generates a Bluesky-native content variant (300-char grapheme limit, reply-chain thread format, byte-position facets). content-publisher.sh `channel_to_section()` maps `bluesky` channel.

### FR6: Brand Guide and Docs Site

Brand guide includes `### Bluesky` Channel Notes (developer audience, thread culture, AT Protocol tone). `site.json` includes `bluesky` URL. `community.njk` includes Bluesky card.

## Technical Requirements

### TR1: AT Protocol Authentication

Session management via `com.atproto.server.createSession`. Access tokens expire in minutes; refresh before expiry. Store only app password in `.env`, not tokens.

### TR2: Error Propagation

Multi-platform publisher returns 0 for credential-missing skips, 1 for real failures, exit 2 for partial failure. Fallback issue creation path for Bluesky failures.

### TR3: Content Format

Bluesky posts use rich text with byte-position facets for links and mentions. Threads created via reply references (root + parent strong references with uri + cid). 300 grapheme limit per post.

### TR4: Prerequisite

Platform adapter interface (#470) must be merged before this work begins. Bluesky scripts implement the adapter interface rather than the ad-hoc pattern.
