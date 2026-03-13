# Spec: Hacker News Community Agent Extension

**Issue:** #140
**Branch:** feat/hn-presence
**Brainstorm:** [2026-03-13-hn-presence-brainstorm.md](../../brainstorms/2026-03-13-hn-presence-brainstorm.md)

## Problem Statement

The community agent monitors Discord, GitHub, X/Twitter, Bluesky, and LinkedIn but has no Hacker News visibility. HN is the primary developer community hub for dev tool credibility and adoption. Without HN monitoring, Soleur misses mentions, competitive signals, and trending discussions relevant to the ICP (technical solo founders).

## Goals

- G1: Add read-only HN monitoring to the community agent via Algolia API
- G2: Include HN data in automated daily community digests
- G3: Add HN-specific tone guidance to the brand guide for manual posting
- G4: Follow existing platform conventions (standalone shell script, no adapter refactor)

## Non-Goals

- Automated HN posting (no write API exists)
- Show HN launch preparation (separate initiative, requires karma building)
- Platform adapter refactor (#470 -- deferred)
- HN account creation or karma building automation
- Playwright-based browser posting

## Functional Requirements

- **FR1:** `hn-community.sh` shell script with subcommands:
  - `mentions [--query TERM]` -- Search HN Algolia API for mentions of a term (default: "soleur"). Return JSON with item ID, title, URL, points, comments, author, date.
  - `trending [--tags TAGS]` -- Fetch front-page stories matching domain keywords. Return JSON with top N items.
  - `thread ITEM_ID` -- Fetch a specific HN item and its comment tree. Return JSON with item details and nested comments.
- **FR2:** HN row in SKILL.md platform detection table. Always-enabled (no env vars). Detection: `curl -sf "https://hn.algolia.com/api/v1/items/1" > /dev/null`.
- **FR3:** HN data collection section in community-manager agent (Capability 1: Digest Generation). Calls `hn-community.sh mentions` and `hn-community.sh trending`.
- **FR4:** `## Hacker News Activity` optional section in digest heading contract. Shows mention count, notable threads, trending topics.
- **FR5:** HN data collection in `scheduled-community-monitor.yml` workflow. No secrets needed (public API).
- **FR6:** `### Hacker News` channel notes section in `knowledge-base/marketing/brand-guide.md`. Covers: understated technical tone, no marketing speak, show-don't-tell, no superlatives.

## Technical Requirements

- **TR1:** Script follows existing convention: `#!/usr/bin/env bash`, `set -euo pipefail`, `require_jq` dependency check, case-dispatched subcommands, JSON to stdout, errors to stderr.
- **TR2:** Apply shell API wrapper hardening patterns (5-layer defense from learnings): input validation, transport (curl stderr suppression), response parsing (JSON validation), error extraction, depth-limited retry (max 3 on 429/rate limit).
- **TR3:** No credentials/env vars required. HN Algolia API is public and unauthenticated.
- **TR4:** Respect Algolia rate limits. HN Algolia API has undocumented rate limits -- implement exponential backoff on 429 responses.

## Acceptance Criteria

- [ ] `hn-community.sh mentions` returns JSON with Soleur mentions from HN
- [ ] `hn-community.sh trending` returns JSON with front-page stories matching domain keywords
- [ ] `hn-community.sh thread <id>` returns JSON with item and comment tree
- [ ] Community SKILL.md platform detection table includes HN as always-enabled
- [ ] Community-manager agent digest flow includes HN data collection
- [ ] Digest heading contract includes `## Hacker News Activity`
- [ ] Scheduled workflow includes HN data collection step
- [ ] Brand guide has `### Hacker News` channel notes section
- [ ] All existing platform scripts and functionality remain unchanged
