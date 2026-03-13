---
title: "feat: Add Hacker News monitoring to community agent"
type: feat
date: 2026-03-13
---

# feat: Add Hacker News monitoring to community agent

## Overview

Add read-only Hacker News monitoring to the community agent via the HN Algolia API. A new `hn-community.sh` shell script provides mention tracking, trending story surfacing, and thread fetching. Integrated into the daily automated digest workflow for zero-touch monitoring. Brand guide updated with HN-specific channel notes.

## Problem Statement / Motivation

The community agent monitors Discord, GitHub, and X/Twitter but has no HN visibility. HN is the primary developer community hub for dev tool credibility and adoption. Without HN monitoring, Soleur misses mentions, competitive signals, and trending discussions relevant to the ICP (technical solo founders).

## Proposed Solution

Create `hn-community.sh` following the existing standalone script convention (no adapter refactor). Use `github-community.sh` as the structural template (always-enabled, no auth, simple error handling) with 429 retry from the discord/x pattern. Three subcommands: `mentions`, `trending`, `thread`.

**Key choices:**
- `mentions` uses `/search_by_date` (recency over relevance) searching both stories and comments
- `trending` returns all front-page stories — the LLM agent filters for domain relevance
- No `url_encode()` helper — use `curl --data-urlencode`
- No connectivity probe — let real API calls handle failures
- `BASH_SOURCE` guard for testability (matches x-community.sh)
- Validate numeric ITEM_ID, handle 429 retry, return valid JSON on zero results

## Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `plugins/soleur/skills/community/scripts/hn-community.sh` | **CREATE** | Shell script: mentions, trending, thread subcommands wrapping HN Algolia API |
| `plugins/soleur/skills/community/SKILL.md` | EDIT | Add HN to description, platform detection table, scripts list, platforms output, guidelines |
| `plugins/soleur/agents/support/community-manager.md` | EDIT | Add HN to description, body text, prerequisites, Capability 1 data collection + analysis, digest heading contract |
| `.github/workflows/scheduled-community-monitor.yml` | EDIT | Add HN data collection commands to prompt. No secrets needed. |
| `knowledge-base/marketing/brand-guide.md` | EDIT | Add `### Hacker News` channel notes (understated technical tone, examples) |

## Acceptance Criteria

- [ ] `hn-community.sh mentions` returns JSON with recent mentions (stories + comments, sorted by date, default 20 hits)
- [ ] `hn-community.sh mentions --query "claude code" --limit 5` overrides search term and limit
- [ ] `hn-community.sh trending` returns front-page stories as JSON
- [ ] `hn-community.sh thread <id>` returns item + comment tree with `hn_url` field
- [ ] `hn-community.sh thread abc` rejects non-numeric ID (exit 1)
- [ ] Zero results return valid JSON with empty arrays (exit 0)
- [ ] 429 responses trigger retry with backoff (max 3, exit 2 on exhaustion)
- [ ] SKILL.md platform detection table includes HN (always-enabled, no env vars)
- [ ] Community-manager digest flow collects HN data; contract table has `## Hacker News Activity`
- [ ] Scheduled workflow prompt includes HN data collection
- [ ] Brand guide has `### Hacker News` channel notes
- [ ] All existing platform scripts and functionality remain unchanged

## Dependencies & Risks

- **HN Algolia API availability.** Public, free, no SLA. If unreachable, HN data is simply absent from the digest.
- **Undocumented rate limits.** Mitigated by 429 retry and conservative defaults (20 results/call).

## References

- Script template: `plugins/soleur/skills/community/scripts/github-community.sh` (auth model) + `x-community.sh` (retry pattern, BASH_SOURCE guard)
- Spec: `knowledge-base/specs/feat-hn-presence/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-03-13-hn-presence-brainstorm.md`
- HN Algolia API: `https://hn.algolia.com/api`
- Issue: #140 | Draft PR: #597
