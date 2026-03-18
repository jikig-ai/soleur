# Hacker News Community Agent Extension

**Date:** 2026-03-13
**Issue:** #140
**Branch:** feat/hn-presence

## What We're Building

Read-only Hacker News monitoring via the community agent. A new `hn-community.sh` shell script using the HN Algolia API (`hn.algolia.com/api/v1/`) that provides mention tracking, trending topic surfacing, and thread fetching. Integrated into the daily automated digest workflow so HN data appears alongside Discord, GitHub, and X/Twitter without manual invocation.

No posting automation. HN has no write API -- all submissions and comments require browser-based login. The community agent monitors HN; the founder posts manually.

Additionally: HN-specific channel notes in the brand guide to prevent voice mismatch when the founder does post manually.

## Why This Approach

**HN API is read-only.** The Algolia-backed API provides search and item retrieval but no write endpoints. Building posting automation would require fragile browser scraping that breaks on UI changes -- the Reddit risk assessment learning (2026-03-12) confirms this pattern fails on anti-automation platforms.

**Monitor-only matches the codebase pattern.** The existing community agent already separates monitoring (digest, health) from posting (engage). HN slots into the monitoring side cleanly.

**Always-enabled like GitHub.** No credentials needed for the Algolia API. Platform detection is a simple connectivity check, not an env var gate. This is the simplest integration surface in the community skill.

**Scheduled workflow integration provides zero-touch value.** The daily community monitor workflow already runs at 08:00 UTC. Adding HN data to the digest means HN mentions surface automatically alongside other platform data.

## Key Decisions

1. **Monitor-only scope** -- No posting automation. Read-only Algolia API only. All HN posting remains manual. Rationale: no write API exists, and HN's anti-automation culture (per Reddit risk assessment learning) makes browser automation high-risk.

2. **Standalone script, no adapter refactor** -- Add `hn-community.sh` following the same convention as `discord-community.sh`, `github-community.sh`, `x-community.sh`. The adapter refactor (#470) is deferred. Rationale: YAGNI -- the current convention works for 5 platforms (Discord, GitHub, X, Bluesky, LinkedIn). Adding one more doesn't justify the refactor.

3. **Always-enabled platform** -- HN requires no credentials. Like GitHub (always enabled via `gh auth status`), HN is always enabled if the Algolia API is reachable. No env vars needed.

4. **Brand guide HN channel notes** -- Add `### Hacker News` section to brand-guide.md with HN-specific tone guidance. HN culture rewards understated, technical, show-don't-tell content -- the opposite of the current brand voice ("Bold. Forward-looking. Energizing."). The channel notes must exist before any manual posting.

5. **Three subcommands** -- `mentions` (search for "soleur" mentions), `trending` (front-page items in dev tools/AI/solo founder domain), `thread` (fetch a specific HN item + comments by ID).

6. **Digest heading: `## Hacker News Activity`** -- Added to the digest heading contract. Shows mention count, notable threads, trending topics in the Soleur domain.

## Open Questions

1. **Keyword list for trending** -- What keywords define "our domain" for the trending subcommand? Candidates: "claude code", "agentic coding", "solo founder", "company of one", "AI dev tools". Should be configurable, not hardcoded.

2. **Show HN timing** -- When is the right moment for a Show HN? CMO assessment says: only after (a) demo URL exists, (b) account has 50+ karma, (c) HN voice profile is tested. This is outside the current feature scope but worth tracking.

3. **Account creation** -- Personal (founder-attributed) vs. brand account? HN culture favors individuals. This is a manual decision, not an engineering one.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|------------|
| `hn-community.sh` monitoring script | Engineering | Shell script wrapping HN Algolia API for mention tracking, trending topics, and thread retrieval |
| Brand guide `### Hacker News` channel notes | Marketing | HN-specific tone guidance to prevent brand voice mismatch on manual posts |
| HN row in SKILL.md platform detection table | Engineering | Platform detection needs HN entry (always-enabled, no env vars) |
| HN section in community-manager agent | Engineering | Agent digest flow needs HN data collection commands |
| HN in scheduled workflow | Engineering | Daily automated monitoring workflow needs HN data alongside other platforms |
| `## Hacker News Activity` in digest contract | Engineering | Digest heading contract needs new optional section |
