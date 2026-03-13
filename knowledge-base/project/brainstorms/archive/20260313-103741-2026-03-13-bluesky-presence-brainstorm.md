# Bluesky Presence Brainstorm

**Date:** 2026-03-13
**Issue:** #139 — Extend Community Agent with Bluesky Presence
**Participants:** CCO, CMO, repo-research-analyst, learnings-researcher

## What We're Building

Bluesky as the 4th supported platform in the community agent, with full parity to X/Twitter: digest generation, health metrics, content suggestions, mention engagement, and automated posting via social-distribute. Platform-native content (not cross-posted from X).

**Prerequisite:** Platform adapter interface refactor (#470) — Bluesky being platform #4 triggers the deferred refactor. Adapter ships first as a separate PR, then Bluesky lands on top of it.

## Why This Approach

- **Bluesky's audience directly overlaps our ICP** — developer-heavy early adopters match Soleur's "solo technical founders" target.
- **16.38 interactions/post avg** — highest engagement among emerging platforms (though this will decline as the platform scales).
- **Thread-style content gets 3x engagement** — aligns with the thread format already used for X content.
- **AT Protocol is free and open** — no API tier costs (unlike X's $100/mo upgrade tracked in #497), simpler auth (app password → JWT vs OAuth 1.0a HMAC-SHA1), generous rate limits (3,000 req/5min, ~1,666 creates/hour).
- **Sequential PR approach** avoids the overscoping problem that hit the X integration (42 tasks → cut to 19). Adapter refactor is isolated from Bluesky-specific work.

## Key Decisions

1. **Sequencing: Adapter first, then Bluesky.** PR 1 refactors shared shell patterns from Discord/X into a common adapter interface (#470). PR 2 adds Bluesky on top of the adapter (#139). Clean separation, smaller blast radius per PR.

2. **Full X/Twitter parity on day one.** All 4 community-manager capabilities: digest, health, content suggestions, mention engagement. Plus social-distribute and content-publisher integration.

3. **Handle strategy: Start with `@soleur.bsky.social`, upgrade to `@soleur.ai` custom domain later.** Claim the default handle immediately (blocking — no code works without it). Custom domain handle requires DNS TXT record verification, can be done as a follow-up.

4. **Platform-native content, not cross-posted.** Bluesky gets unique content tailored to its developer audience and thread culture. social-distribute generates a distinct Bluesky variant (300-char limit, reply-chain threads, byte-position facets for links/mentions).

5. **Keep current brainstorm routing.** CCO triages support brainstorms and delegates to community-manager when appropriate. No direct routing change needed — the existing assessment layer works correctly.

## AT Protocol API Surface (Verified Live)

| Capability | Endpoint / Detail |
|---|---|
| Auth | `com.atproto.server.createSession` — app password + handle → accessJwt + refreshJwt |
| Create post | `com.atproto.repo.createRecord` with collection `app.bsky.feed.post` |
| Threads | Reply chains via `reply.root` + `reply.parent` strong references (uri + cid) |
| Rich text | Byte-position facets for links and mentions |
| Images | `com.atproto.repo.uploadBlob` — max 1MB each, 4 per post |
| Rate limits | 3,000 req/5min (IP), 5,000 write points/hour (account), HTTP 429 on excess |
| Character limit | 300 graphemes |
| Cost | Free, no tiers |

## Learnings to Apply

From 12 documented institutional learnings (X/Twitter and Discord integrations):

1. **5-layer shell API wrapper defense from day one** — input validation, curl stderr suppression, JSON response validation, jq fallback chains, float-safe retry arithmetic. Do not ship and fix later.
2. **Depth-limited retry** — max 3 retries with explicit depth parameter (`local depth="${N:-0}"` with ceiling guard).
3. **Multi-platform publisher error propagation** — return 0 for credential-missing skips, return 1 for real failures, exit 2 for partial failure. Include fallback issue creation path.
4. **Secrets via env vars only** — `BSKY_HANDLE`, `BSKY_APP_PASSWORD`. Write `bsky-setup.sh` following `x-setup.sh` convention with `git rev-parse --show-toplevel` for `.env` path resolution.
5. **Content publisher channel mapping** — add `bluesky` to `channel_to_section()` in `content-publisher.sh`, define `## Bluesky` content section format.
6. **Scope heuristic** — if plan exceeds 3 new files or 2 new sub-commands, flag as potentially overscoped.

## Files to Create/Modify

### PR 1: Adapter Refactor (#470)
- Extract shared patterns from `discord-community.sh` and `x-community.sh`
- Standardize auth, request wrapping, retry logic, error propagation
- Scope TBD during planning

### PR 2: Bluesky Integration (#139)
| Action | File |
|---|---|
| Create | `plugins/soleur/skills/community/scripts/bsky-community.sh` |
| Create | `plugins/soleur/skills/community/scripts/bsky-setup.sh` |
| Modify | `plugins/soleur/agents/support/community-manager.md` |
| Modify | `plugins/soleur/skills/community/SKILL.md` |
| Modify | `knowledge-base/marketing/brand-guide.md` (add `### Bluesky` Channel Notes) |
| Modify | `plugins/soleur/docs/_data/site.json` (add `bluesky` URL) |
| Modify | `plugins/soleur/docs/pages/community.njk` (add Bluesky card) |
| Modify | `plugins/soleur/skills/social-distribute/SKILL.md` (add Bluesky variant) |
| Modify | `scripts/content-publisher.sh` (add `bsky` channel mapping) |

## Open Questions

1. **Adapter interface design** — What level of abstraction? Shared bash functions sourced by each platform script? Or a dispatcher pattern? Deferred to #470 planning.
2. **Custom domain handle timing** — When to switch from `@soleur.bsky.social` to `@soleur.ai`? Depends on DNS setup and brand priority.
3. **Bluesky-native content strategy** — What makes Bluesky content different from X beyond format? Developer-focused topics, AT Protocol commentary, open-source themes? Deferred to brand guide Channel Notes authoring.
4. **Engagement norms** — Bluesky community norms for automated replies differ from X. Monitor before engaging heavily.

## Capability Gaps

| What is Missing | Domain | Why Needed |
|---|---|---|
| Platform adapter interface | Engineering | Bluesky is platform #4, triggering the deferred #470 refactor. Without it, each new platform adds duplicated script scaffolding. |
| `bsky-community.sh` script | Engineering | AT Protocol API wrapper for post creation, feed reading, metrics. |
| `bsky-setup.sh` script | Engineering | Credential setup and session management for AT Protocol auth. |
| Brand guide `### Bluesky` channel notes | Marketing | Tone calibration for Bluesky engagement — developer audience, thread culture. |
| Bluesky variant in social-distribute | Marketing | Platform-native content generation (300-char, reply-chain threads). |
| Community skill SKILL.md missing | Engineering (pre-existing) | Technical debt from #470 — skill directory has scripts but incomplete SKILL.md. |
