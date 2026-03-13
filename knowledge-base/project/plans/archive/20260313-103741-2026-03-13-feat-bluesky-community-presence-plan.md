---
title: "feat: Extend Community Agent with Bluesky Presence"
type: feat
date: 2026-03-13
---

# feat: Extend Community Agent with Bluesky Presence

## Overview

Add Bluesky as the 4th community platform with monitoring and engagement parity to X/Twitter. This includes an AT Protocol API wrapper (`bsky-community.sh`), credential setup (`bsky-setup.sh`), community-manager agent updates, community skill updates, and brand guide channel notes.

Follows the same ad-hoc platform script pattern as `x-community.sh` and `discord-community.sh`. No adapter interface prerequisite — #470 becomes a follow-up refactor once all 4 platform scripts exist and the real commonalities are visible.

[Updated 2026-03-13 — applied review feedback from DHH, simplicity, and Kieran reviewers. Dropped #470 prerequisite, deferred facets + social distribution + get-feed, collapsed 6 phases to 4, simplified session management.]

## Problem Statement / Motivation

Bluesky has the highest engagement among emerging platforms (16.38 interactions/post avg) with a developer-heavy early adopter audience that directly overlaps Soleur's ICP. The AT Protocol is free and open with simpler auth than X's OAuth 1.0a. No competing CaaS tools have established Bluesky presence — first-mover advantage is available.

## Proposed Solution

Follow the same platform integration pattern used for X/Twitter (#127). Build `bsky-community.sh` as an independent script following the existing ad-hoc pattern. AT Protocol auth is simpler (app password → JWT bearer token), so the script should be shorter than `x-community.sh` (~250 lines vs 577).

### Architecture

```
┌──────────────────────────────────────────────────────┐
│  community skill (SKILL.md)                          │
│  ├── platforms: detect BSKY_HANDLE + BSKY_APP_PASS   │
│  ├── engage --platform bluesky                       │
│  └── delegates to community-manager agent            │
├──────────────────────────────────────────────────────┤
│  community-manager agent                             │
│  ├── Capability 1: Digest (+ Bluesky metrics)        │
│  ├── Capability 2: Health (+ Bluesky stats)          │
│  └── Capability 4: Mention Engagement (+ Bluesky)    │
├──────────────────────────────────────────────────────┤
│  bsky-community.sh             bsky-setup.sh         │
│  ├── create-session            ├── write-env          │
│  ├── post [--reply-to ...]     └── verify             │
│  ├── get-metrics                                     │
│  └── get-notifications                               │
├──────────────────────────────────────────────────────┤
│  AT Protocol (bsky.social XRPC)                      │
└──────────────────────────────────────────────────────┘
```

### Implementation Phases

#### Phase 1: Account Setup and Credentials

- [ ] 1.1 Claim `@soleur.bsky.social` handle (manual — requires browser)
- [ ] 1.2 Generate app password via Bluesky settings
- [ ] 1.3 Create `bsky-setup.sh` (~80 lines, following `x-setup.sh` pattern)
  - `write-env`: append `BSKY_HANDLE` + `BSKY_APP_PASSWORD` to `.env` (using `git rev-parse --show-toplevel`, `chmod 600`)
  - `verify`: create session via `com.atproto.server.createSession`, fetch profile via `app.bsky.actor.getProfile`, confirm identity
  - Secrets via env vars only, never CLI args, suppress curl stderr
  - Dependencies: `curl`, `jq` only (no `openssl` — AT Protocol uses simple Bearer auth)
- [ ] 1.4 Add `BSKY_HANDLE`, `BSKY_APP_PASSWORD` to `.env.example` (if exists)

#### Phase 2: AT Protocol API Wrapper

- [ ] 2.1 Create `bsky-community.sh` (~250 lines, following `x-community.sh` pattern)
  - Header: usage docs, env var requirements, exit codes (0=success, 1=error, 2=rate-limit)
  - Dependency checks: `require_jq`, `require_curl`
  - Credential validation: `require_credentials` checking `BSKY_HANDLE` + `BSKY_APP_PASSWORD`
  - Session management: `create_session` — fresh session per invocation via `com.atproto.server.createSession`. No caching, no refresh logic. Each script invocation takes seconds; tokens last minutes.
  - `handle_response` function:
    - 2xx: validate JSON, echo body
    - 429: read `ratelimit-reset` header (Unix timestamp), compute sleep as `reset - now`, clamp to [1, 60]s, retry with depth limit (max 3). Note: Bluesky uses header-based rate limits, not body JSON like X.
    - 401: fail with credential error (no reauth — session is fresh)
    - Other: extract error from `{"error": "...", "message": "..."}` format, stderr + exit 1
  - `get_request` / `post_request` helpers with Bearer token auth
  - Commands:
    - `create-session`: test auth, output session JSON
    - `post <text> [--reply-to-uri URI --reply-to-cid CID --root-uri URI --root-cid CID]`: create post via `com.atproto.repo.createRecord`
      - Plain text only (no facets — URLs auto-link, mention facets deferred)
      - Validate post length using `wc -m` (codepoint count as grapheme approximation). Known gap: flag emoji and combining characters may differ. Let API reject true edge cases.
      - Returns `{"uri": "...", "cid": "..."}` for thread chaining
    - `get-metrics`: fetch profile via `app.bsky.actor.getProfile` (followers, following, posts counts)
    - `get-notifications [--limit N] [--cursor CURSOR]`: fetch notifications via `app.bsky.notification.listNotifications`, filter for `reason: "mention"`. Returns JSON with notifications array and cursor for pagination. More reliable than `searchPosts` — returns actual mentions, not text matches.

#### Phase 3: Agent + Skill Wiring

- [ ] 3.1 Update `community-manager.md` agent definition
  - Add `### Bluesky (optional)` prerequisites section: `BSKY_HANDLE`, `BSKY_APP_PASSWORD`
  - Add `bsky-community.sh` and `bsky-setup.sh` to Scripts list
  - Update Capability 1 (Digest): add Bluesky data collection via `bsky-community.sh get-metrics`
  - Update Capability 2 (Health): add Bluesky metrics display section (followers, following, posts)
  - Add Bluesky to Capability 4 (Mention Engagement):
    - Fetch mentions via `bsky-community.sh get-notifications`
    - Draft replies following brand guide `### Bluesky` channel notes
    - 300-char limit validation (not 280)
    - Post via `bsky-community.sh post --reply-to-uri ... --reply-to-cid ... --root-uri ... --root-cid ...`
    - Cursor state file: `.soleur/bsky-engage-cursor` (stores cursor string from `listNotifications` response)
    - Headless mode: skip all mentions with summary ("engage requires interactive approval"), same pattern as X
    - No free-tier fallback needed — AT Protocol is free, `listNotifications` has no access restrictions
  - Add `## Bluesky Metrics` to digest heading contract (optional heading)
  - Update description: "Reads Discord, GitHub, X/Twitter, and Bluesky data..."
- [ ] 3.2 Update `community/SKILL.md`
  - Add Bluesky row to Platform Detection table: `BSKY_HANDLE`, `BSKY_APP_PASSWORD`
  - Add `bsky-community.sh` and `bsky-setup.sh` to Scripts list (as proper markdown links)
  - Update `platforms` sub-command display to include Bluesky status
  - Update `engage` sub-command: add `--platform` flag. Without flag, prompt user which platform. With `--platform bluesky`, target Bluesky only. Backward-compatible: `engage` without flag still works (prompts).
  - Update description to mention Bluesky
  - Add setup instructions: "Run `bsky-setup.sh` to configure"

#### Phase 4: Brand Guide

- [ ] 4.1 Add `### Bluesky` section to `knowledge-base/marketing/brand-guide.md` under `## Channel Notes`
  - Developer-first audience, technical/builder tone
  - Thread format: reply chains for multi-part content
  - 300-char limit per post (graphemes)
  - AT Protocol / open-source credibility angle
  - Bluesky does not support hashtags as a native feature — do not use them
  - Engagement guardrails: Bluesky community is small and tightly knit, anti-bot sentiment is strong. Start with organic engagement, avoid aggressive automated posting patterns

## Deferred to Follow-Up Issues

| Item | Why Deferred | Follow-Up |
|---|---|---|
| Social distribution integration (social-distribute + content-publisher) | Zero followers on day one, no audience to distribute to. `post` command exists for when needed. | File issue |
| Rich text facets (byte-position link/mention rendering) | Hardest part of AT Protocol integration. URLs auto-link without facets. Mention facets require DID resolution. | File issue |
| `get-feed` command | Empty feed on new account. Not needed until content analysis is valuable. | Include in social distribution issue |
| Content Suggestions Bluesky signals (Capability 3) | No Bluesky data to analyze on a new account. Agent can naturally incorporate Bluesky data from digests/health once it flows. | Natural follow-up, no issue needed |
| Docs site updates (`site.json` URL, `community.njk` card) | Advisory-only via Platform Surface Check warnings. No functional value until profile is live with bio/avatar. | Include in social distribution issue |
| Custom domain handle (`@soleur.ai`) | Requires DNS verification, can switch later | Existing plan |
| Platform adapter interface (#470) | Premature abstraction — design after all 4 scripts exist | Already tracked |

## Acceptance Criteria

- [ ] `bsky-setup.sh write-env` writes credentials to `.env` securely
- [ ] `bsky-setup.sh verify` creates session and confirms profile identity
- [ ] `bsky-community.sh create-session` authenticates and returns session JSON
- [ ] `bsky-community.sh post "Hello from Soleur"` creates a Bluesky post
- [ ] `bsky-community.sh post` with 301+ characters exits 1 with limit error
- [ ] `bsky-community.sh get-metrics` returns follower/following/post counts
- [ ] `bsky-community.sh get-notifications` returns mention notifications with cursor
- [ ] `bsky-community.sh post --reply-to-uri ... --reply-to-cid ...` posts a reply with correct references
- [ ] `/soleur:community platforms` shows Bluesky status (enabled/not configured)
- [ ] `/soleur:community digest` includes Bluesky metrics section when configured
- [ ] `/soleur:community health` displays Bluesky stats when configured
- [ ] `/soleur:community engage --platform bluesky` processes mentions with approval flow
- [ ] Brand guide has `### Bluesky` channel notes

## Test Scenarios

- Given valid `BSKY_HANDLE` + `BSKY_APP_PASSWORD`, when `bsky-setup.sh verify` runs, then session is created and profile is fetched
- Given missing `BSKY_APP_PASSWORD`, when `bsky-community.sh post` runs, then exit 1 with error listing missing vars
- Given valid credentials, when `bsky-community.sh post` is called with 301+ characters, then exit 1 with "exceeds 300 character limit"
- Given rate limit (HTTP 429), when a request is made, then retry up to 3 times with clamped backoff from `ratelimit-reset` header
- Given Bluesky not configured, when `/soleur:community digest` runs, then Bluesky section is skipped (not error)
- Given Bluesky configured, when `/soleur:community health` runs, then Bluesky followers/following/posts are displayed
- Given `--headless` flag on engage, then skip all mentions with summary message
- Given a 3-post thread, when posting replies, then root uri+cid stay constant while parent uri+cid update each iteration

## Rollback Plan

All changes are additive. Rollback = remove new files (`bsky-community.sh`, `bsky-setup.sh`) + revert markdown edits to `community-manager.md`, `SKILL.md`, and `brand-guide.md`. No schema changes, no data migrations, no infrastructure changes.

## Dependencies & Risks

| Dependency | Risk | Mitigation |
|---|---|---|
| Bluesky account creation | Manual step, no API for headless account creation | Claim handle immediately, parallelize with code work |
| AT Protocol API stability | Less mature than X API | Verify endpoints live (done in brainstorm), pin to known working endpoints |
| Grapheme vs codepoint counting | `wc -m` counts codepoints, not graphemes. Edge case: flag emoji, combining chars | Use codepoint count as approximation, let API reject true edge cases. Document gap. |
| Rate limit header format | Bluesky uses `ratelimit-reset` header (Unix timestamp), not body JSON | Read header in `handle_response`, compute `sleep = reset - now` |

## References & Research

### Internal References

- `plugins/soleur/skills/community/scripts/x-community.sh` -- template for `bsky-community.sh`
- `plugins/soleur/skills/community/scripts/x-setup.sh` -- template for `bsky-setup.sh`
- `plugins/soleur/agents/support/community-manager.md` -- agent to update
- `plugins/soleur/skills/community/SKILL.md` -- skill to update
- `knowledge-base/marketing/brand-guide.md` -- add Bluesky channel notes

### Institutional Learnings Applied

- `2026-03-09-shell-api-wrapper-hardening-patterns.md` -- 5-layer defense adapted for AT Protocol
- `2026-03-09-depth-limited-api-retry-pattern.md` -- max 3 retries with depth guard
- `2026-02-18-token-env-var-not-cli-arg.md` -- secrets via env vars only
- `2026-03-09-external-api-scope-calibration.md` -- AT Protocol verified live before planning

### External References

- AT Protocol API: `https://docs.bsky.app/docs/get-started`
- Post creation: `https://docs.bsky.app/docs/advanced-guides/posts`
- Rate limits: `https://docs.bsky.app/docs/advanced-guides/rate-limits`

### Related Issues

- #139 -- this feature
- #470 -- platform adapter interface (follow-up refactor, no longer prerequisite)
- #127 -- X/Twitter integration (pattern reference, CLOSED)
