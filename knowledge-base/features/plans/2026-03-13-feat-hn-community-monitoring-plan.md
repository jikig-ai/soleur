---
title: "feat: Add Hacker News monitoring to community agent"
type: feat
date: 2026-03-13
---

# feat: Add Hacker News monitoring to community agent

## Overview

Add read-only Hacker News monitoring to the community agent via the HN Algolia API. A new `hn-community.sh` shell script provides mention tracking, trending topic surfacing, and thread fetching. Integrated into the daily automated digest workflow for zero-touch monitoring. Brand guide updated with HN-specific channel notes.

## Problem Statement / Motivation

The community agent monitors Discord, GitHub, X/Twitter, Bluesky, and LinkedIn but has no HN visibility. HN is the primary developer community hub for dev tool credibility and adoption. Without HN monitoring, Soleur misses mentions, competitive signals, and trending discussions relevant to the ICP (technical solo founders).

## Proposed Solution

Create `hn-community.sh` following the existing standalone script convention (no adapter refactor). The HN Algolia API is read-only and public (no auth needed), making HN an always-enabled platform like GitHub. Three subcommands: `mentions`, `trending`, `thread`. Integrate into the community-manager agent digest flow and the scheduled GitHub Actions workflow.

### Design Decisions (from spec-flow analysis)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Search endpoint for `mentions` | `/search_by_date` with 7-day lookback | Monitoring needs recency, not all-time popularity. Daily digest must surface new mentions, not rehash old ones. |
| Search scope for `mentions` | Both stories and comments (`tags=(story,comment)`) | Comments are where most product mentions happen ("I use Soleur for X"). Story-only misses the majority. |
| Default result limits | `mentions`: 20, `trending`: 10 | Balances digest readability with coverage. Both accept `--limit N` to override. |
| Trending keyword filtering | Fetch all `front_page` stories, client-side jq filter against keyword list variable | Simplest approach. Keywords in a variable at top of script. Overridable via `--keywords`. |
| `--tags` parameter | Rename to `--keywords` | Avoids confusion with Algolia's `tags` filter system which has different semantics. |
| Thread depth | Pass through Algolia response verbatim, no truncation | `thread` is for on-demand investigation, not digests. YAGNI on depth limits. |
| Connectivity probe timeout | `curl --max-time 10` | Prevents a slow Algolia response from eating the 30-minute CI workflow timeout. |
| Minimum platform gate | Keep unchanged | HN+GitHub alone produce a thin digest. Existing gate ("at least Discord or X") remains. |
| `BASH_SOURCE` guard | Include | Costs nothing, enables future test harness integration. Follows x-community.sh pattern. |
| Input validation | URL-encode `--query`, validate numeric ITEM_ID, validate `--keywords` | Follows 5-layer hardening pattern (Layer 1: Input validation). |
| Null item detection | Check `title` + `author` both null → exit 1 | Algolia returns 200 with null fields for deleted/non-existent items. |
| Include `hn_url` field | Yes, compute from `objectID` | `https://news.ycombinator.com/item?id=<objectID>` — low effort, high value for digest links. |

## Technical Considerations

- **No credentials needed.** HN Algolia API is public. No env vars, no secrets, no setup script. Always-enabled like GitHub.
- **Rate limits are undocumented.** Implement standard 429 retry with exponential backoff (max 3 retries), matching the existing discord/x pattern.
- **Comment vs. story output schema diverges.** Comments lack `title`, `url`, `points`. Output JSON uses nullable fields: `title: null` for comments, `comment_text: null` for stories.
- **Algolia `nbHits` can be approximate.** When `exhaustiveNbHits` is false, display as "~N" in digests.
- **No shared libraries exist.** Script is fully self-contained, like all other platform scripts.

## Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `plugins/soleur/skills/community/scripts/hn-community.sh` | **CREATE** | Core shell script: 3 subcommands (mentions, trending, thread), 5-layer hardening, Algolia API wrapper |
| `plugins/soleur/skills/community/SKILL.md` | EDIT | Add HN to: description (line 3), platform detection table (line 27+), scripts list (line 39+), important guidelines (line 157+), platforms sub-command output (line 76+) |
| `plugins/soleur/agents/support/community-manager.md` | EDIT | Add HN to: description (line 3), prerequisites section (new "Hacker News" subsection), Capability 1 data collection (line 63+), digest heading contract table (line 159+), Capability 2 health metrics (line 192+) |
| `.github/workflows/scheduled-community-monitor.yml` | EDIT | Add HN data collection commands to the prompt (line 78+). No secrets needed. |
| `knowledge-base/marketing/brand-guide.md` | EDIT | Add `### Hacker News` channel notes after existing platform sections |

## Acceptance Criteria

### Happy Path

- [ ] `hn-community.sh mentions` returns JSON with recent Soleur mentions from HN (stories + comments, sorted by date)
- [ ] `hn-community.sh mentions --query "claude code"` searches for a custom term
- [ ] `hn-community.sh mentions --limit 5` limits results to 5 hits
- [ ] `hn-community.sh trending` returns JSON with front-page stories matching domain keywords
- [ ] `hn-community.sh trending --keywords "rust,golang"` overrides default keywords
- [ ] `hn-community.sh thread 12345` returns JSON with item and nested comment tree
- [ ] `hn-community.sh thread 12345` includes `hn_url` field with direct HN link
- [ ] Community SKILL.md platform detection table includes HN as always-enabled
- [ ] Community SKILL.md `platforms` sub-command output includes HN status line
- [ ] Community-manager agent digest flow collects HN data (mentions + trending)
- [ ] Digest heading contract includes `## Hacker News Activity` optional section
- [ ] Scheduled workflow prompt includes HN data collection step
- [ ] Brand guide has `### Hacker News` channel notes section with HN-specific tone guidance
- [ ] All existing platform scripts and functionality remain unchanged

### Error Handling

- [ ] 429 rate limit: retries with exponential backoff (max 3), exits 2 on exhaustion
- [ ] Network failure: clean error message to stderr, exits 1
- [ ] Invalid ITEM_ID (non-numeric): rejected before API call, exits 1
- [ ] Deleted/non-existent item: detected via null title+author, reports to stderr, exits 1
- [ ] Zero results: returns valid JSON with empty arrays (`{"hits":[],"count":0}`)
- [ ] Malformed JSON response: caught by jq validation, exits 1
- [ ] Algolia connectivity probe timeout: `--max-time 10`, HN silently disabled if unreachable
- [ ] `jq` not installed: `require_jq` exits 1 with install instructions

## Test Scenarios

- Given HN Algolia API is reachable, when `hn-community.sh mentions` is called, then JSON with recent mentions is returned sorted by date
- Given no mentions of "soleur" exist, when `hn-community.sh mentions` is called, then `{"hits":[],"count":0}` is returned with exit 0
- Given a valid HN item ID, when `hn-community.sh thread <id>` is called, then the item and its comment tree are returned as JSON
- Given an invalid (non-numeric) item ID, when `hn-community.sh thread abc` is called, then an error is printed to stderr and script exits 1
- Given the Algolia API returns 429, when any subcommand is called, then the script retries up to 3 times with backoff
- Given the Algolia API is unreachable, when platform detection runs, then HN is silently disabled and the digest proceeds without HN data
- Given jq is not installed, when any subcommand is called, then script exits 1 with install instructions

## Success Metrics

- HN mentions appear in daily automated digests alongside other platforms
- `hn-community.sh` follows all 5 hardening layers from shell API wrapper learnings
- Zero impact on existing platform scripts and agent behavior

## Dependencies & Risks

- **HN Algolia API availability.** Public, free, no SLA. If Algolia goes down, HN monitoring silently degrades. Low risk — Algolia has historically been reliable.
- **Undocumented rate limits.** The retry pattern handles this, but aggressive querying could trigger blocks. Mitigated by conservative defaults (20 results per call).
- **No write API means no engagement automation.** This is a non-goal per brainstorm, but worth noting: the community agent cannot reply to or upvote HN content.

## References & Research

### Internal References

- Spec: `knowledge-base/specs/feat-hn-presence/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-03-13-hn-presence-brainstorm.md`
- Script template: `plugins/soleur/skills/community/scripts/github-community.sh` (closest analog: always-enabled, no auth)
- Hardening patterns: `plugins/soleur/skills/community/scripts/x-community.sh` (5-layer defense, BASH_SOURCE guard)
- Shell API hardening learning: `knowledge-base/features/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Reddit risk assessment: `knowledge-base/features/learnings/2026-03-12-reddit-api-automation-risk-assessment.md`
- External API scope calibration: `knowledge-base/features/learnings/2026-03-09-external-api-scope-calibration.md`

### External References

- HN Algolia API: `https://hn.algolia.com/api`
- HN API (Firebase, items): `https://github.com/HackerNews/API`

### Related Work

- Issue: #140
- Draft PR: #597
- Platform adapter refactor (deferred): #470
- Community agent (original): #96
