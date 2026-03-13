# Tasks: feat-hn-presence

## Phase 1: Core Script

- [ ] 1.1 Create `plugins/soleur/skills/community/scripts/hn-community.sh`
  - [ ] 1.1.1 File header (shebang, usage, output/error contract)
  - [ ] 1.1.2 `set -euo pipefail` and `HN_ALGOLIA_API="https://hn.algolia.com/api/v1"` constant
  - [ ] 1.1.3 `require_jq()` dependency check (match discord pattern)
  - [ ] 1.1.4 `hn_request()` API helper with 429 retry (depth-limited, max 3, exponential backoff, curl stderr suppression, `--max-time 30`, JSON validation via jq)
  - [ ] 1.1.5 `url_encode()` helper for query parameter encoding
  - [ ] 1.1.6 `cmd_mentions()` — `/search_by_date?query=<term>&tags=(story,comment)&numericFilters=created_at_i>SEVEN_DAYS_AGO&hitsPerPage=<limit>`. Default query: "soleur", default limit: 20. Parse `--query TERM`, `--limit N`, `--days N` flags. Output JSON with: `hits[]` containing `objectID`, `title` (nullable), `url` (nullable), `points` (nullable), `num_comments` (nullable), `author`, `created_at`, `comment_text` (nullable), `story_title` (nullable), `hn_url` (computed). Top-level `count` and `exhaustive` fields.
  - [ ] 1.1.7 `cmd_trending()` — Fetch `tags=front_page` stories, client-side jq filter against `DEFAULT_KEYWORDS` variable. Parse `--keywords CSV`, `--limit N` flags. Default keywords: `"claude code,agentic,solo founder,company of one,AI dev tools,claude code plugin"`. Default limit: 10. Output JSON with matched stories.
  - [ ] 1.1.8 `cmd_thread()` — Fetch `/items/<ITEM_ID>`. Validate ITEM_ID is numeric. Check for null title+author (deleted/non-existent → stderr error, exit 1). Pass through Algolia response with added `hn_url` field.
  - [ ] 1.1.9 `main()` with case dispatch, `require_jq` call, usage on empty command, unknown command error
  - [ ] 1.1.10 `BASH_SOURCE` guard for testability
  - [ ] 1.1.11 `chmod +x` the script

## Phase 2: Agent & Skill Integration

- [ ] 2.1 Edit `plugins/soleur/skills/community/SKILL.md`
  - [ ] 2.1.1 Update description frontmatter to include "Hacker News"
  - [ ] 2.1.2 Add HN row to Platform Detection table (always-enabled, detection: `curl -sf --max-time 10 "$HN_ALGOLIA_API/items/1" > /dev/null`)
  - [ ] 2.1.3 Add `hn-community.sh` to Scripts list with markdown link
  - [ ] 2.1.4 Add HN line to `platforms` sub-command output format
  - [ ] 2.1.5 Add "All Hacker News API calls go through `hn-community.sh`" to Important Guidelines
- [ ] 2.2 Edit `plugins/soleur/agents/support/community-manager.md`
  - [ ] 2.2.1 Update description frontmatter to include "Hacker News"
  - [ ] 2.2.2 Add `### Hacker News (always enabled)` prerequisites subsection (no env vars, always available if Algolia reachable)
  - [ ] 2.2.3 Add HN data collection to Capability 1 Step 1 (Collect Data): `hn-community.sh mentions` and `hn-community.sh trending`
  - [ ] 2.2.4 Add `## Hacker News Activity` row to Digest File Contract table (optional, purpose: "HN mention count, notable threads, trending domain topics")
  - [ ] 2.2.5 Add HN to Capability 2 Step 1 (Health Metrics data collection): `hn-community.sh mentions --limit 5`
  - [ ] 2.2.6 Add HN section to Capability 2 Step 2 (Health Metrics display format)
  - [ ] 2.2.7 Add `hn-community.sh` to Scripts list
  - [ ] 2.2.8 Add HN guideline to Important Guidelines section

## Phase 3: Workflow Integration

- [ ] 3.1 Edit `.github/workflows/scheduled-community-monitor.yml`
  - [ ] 3.1.1 Add HN data collection commands to the prompt section (after GitHub, before step 3): `hn-community.sh mentions` and `hn-community.sh trending`. No env/secrets needed.
  - [ ] 3.1.2 Add "If hn-community.sh fails, log the error and continue" to error handling instruction

## Phase 4: Brand Guide

- [ ] 4.1 Edit `knowledge-base/marketing/brand-guide.md`
  - [ ] 4.1.1 Add `### Hacker News` channel notes after existing platform sections. Content: understated technical tone, no marketing speak, no superlatives, show-don't-tell, factual specifics over bold claims, technical depth over broad statements, no emojis, no hashtags. Two examples (story submission title, comment reply).

## Phase 5: Commit & Verify

- [ ] 5.1 Run `hn-community.sh mentions` and verify JSON output
- [ ] 5.2 Run `hn-community.sh trending` and verify JSON output
- [ ] 5.3 Run `hn-community.sh thread <known-id>` and verify JSON output
- [ ] 5.4 Run `hn-community.sh` with no args and verify usage output
- [ ] 5.5 Verify SKILL.md platform detection reports HN as enabled
- [ ] 5.6 Compound and commit
