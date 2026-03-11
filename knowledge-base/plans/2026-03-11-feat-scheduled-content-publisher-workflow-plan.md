---
title: "feat: scheduled content publisher workflow for case study distribution"
type: feat
date: 2026-03-11
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-11
**Sections enhanced:** 7 (Content Parsing, Thread Posting, Discord Webhook, Error Handling, Cron Timing, Issue Deduplication, Script Architecture)
**Research sources:** GitHub Actions docs, Discord webhook API docs, X API v2 docs, project learnings corpus (8 learnings applied), prior social distribution plan (#502)

### Key Improvements
1. Added concrete `extract_section` and `extract_tweets` implementations with edge case handling for content files missing platform sections
2. Added thread posting recovery pattern from proven #502 distribution plan -- partial thread creates a resume issue instead of silent failure
3. Added Discord webhook rate limit awareness (30 req/min, 5 req/2s) -- not a concern for single posts but documents the limit
4. Added issue deduplication via title-based search to prevent duplicate manual-platform issues on re-runs
5. Added `x-community.sh` sourcing pattern for CI -- the script lives in `plugins/soleur/skills/community/scripts/` which must be on PATH or called with full path
6. Added cron timing offset recommendation: use non-zero minutes (e.g., `:07`, `:37`) to avoid GitHub Actions top-of-hour congestion delays

### New Considerations Discovered
- Content files for studies 2 and 4 contain "Not scheduled for [platform] distribution" placeholder text in unused platform sections -- the extraction logic must handle this gracefully (detect and skip)
- `x-community.sh post-tweet` argument order matters: text first, then `--reply-to ID` -- reversed order triggers the "unknown option" error path
- The `openssl` dependency for OAuth 1.0a signing is pre-installed on `ubuntu-latest` runners -- no setup step needed
- GitHub public repos auto-disable cron schedules after 60 days of inactivity -- if the campaign ends and no commits follow, cron triggers stop silently

# feat: scheduled content publisher workflow for case study distribution

## Overview

Build a `scheduled-content-publisher.yml` GitHub Actions workflow that automates the 3-week case study distribution campaign (2026-03-12 to 2026-03-30). The workflow fires on 5 scheduled dates, posting pre-generated content to Discord (fully automated via webhook) and X/Twitter (fully automated via `x-community.sh post-tweet` with `--reply-to` chaining). For manual platforms (IndieHackers, Reddit, HN), it creates a GitHub issue with copy-paste-ready content tagged `action-required`.

**Parent issue:** #530
**Content source:** `knowledge-base/specs/feat-product-strategy/distribution-content/` (5 files, one per case study)
**Distribution plan:** `knowledge-base/specs/feat-product-strategy/distribution-plan.md`

## Problem Statement

The CMO distribution plan defines a 3-week campaign publishing 5 case studies across 5 platforms. Execution currently requires the CEO to manually trigger each posting session on the scheduled dates. This creates a reliability gap -- no one is enforcing the calendar.

## Proposed Solution

A single GitHub Actions workflow (`scheduled-content-publisher.yml`) with:

1. **5 cron triggers** matching the campaign schedule (14:00 UTC for Discord+X, offset times for manual platform issues)
2. **A date-to-content mapping** that selects the correct content file and platform set for each run
3. **Discord posting** via `curl` to the webhook URL (no LLM agent needed -- content is pre-written)
4. **X/Twitter posting** via `x-community.sh post-tweet` with `--reply-to` chaining for threads
5. **GitHub issue creation** for manual platforms (IndieHackers, Reddit, HN) with pre-written content and `action-required` label
6. **`workflow_dispatch`** trigger for manual re-runs with a `case_study` input selector

### Architecture: Shell Script, Not claude-code-action

The workflow does NOT use `claude-code-action`. All content is pre-written in the distribution-content files. The workflow is a deterministic shell script that:

1. Reads the correct content file based on today's date or the `workflow_dispatch` input
2. Extracts platform-specific sections using `sed`/`awk` between `## Discord`, `## X/Twitter Thread`, etc. markers
3. Posts to Discord via `curl` webhook
4. Posts to X via `x-community.sh post-tweet` with reply chaining
5. Creates GitHub issues for manual platforms via `gh issue create`

This avoids LLM billing per run, eliminates non-determinism, and keeps the workflow under 5 minutes.

## Technical Considerations

### Content File Parsing

Each content file has sections delimited by `## Discord`, `## X/Twitter Thread`, `## IndieHackers`, `## Reddit`, `## Hacker News`. The workflow must extract content between these markers reliably.

#### Research Insights: Robust Section Extraction

**Recommended `extract_section` implementation:**

```bash
# extract_section <file> <heading>
# Extracts text between "## <heading>" and the next "## " or EOF.
# Returns empty string if section not found.
extract_section() {
  local file="$1"
  local heading="$2"
  local content
  content=$(sed -n "/^## ${heading}$/,/^## /{/^## /!p}" "$file" | sed '/^$/d; s/^[[:space:]]*//')
  # Handle "Not scheduled" placeholder sections (studies 2, 4)
  if echo "$content" | grep -q "Not scheduled for"; then
    echo ""
    return 0
  fi
  echo "$content"
}
```

**Edge cases to handle:**
- Studies 2 and 4 have placeholder text (`"Not scheduled for [platform] distribution. Use Discord + X only."`) in unused platform sections -- detect and treat as empty
- The `## Hacker News` section is always the last section in the file -- the `sed` range pattern handles this correctly because it matches to the next `## ` or EOF
- Content between the file header (`# Title`, `**Blog post:**`, etc.) and `---` separator must be skipped -- start extraction only after the first `---` delimiter
- The `---` horizontal rule between sections must not be included in extracted content

**X/Twitter Thread tweet extraction:**

The X/Twitter section contains structured tweets with a consistent pattern:

```text
**Tweet 1 (Hook) -- NNN chars:**
<tweet text spanning one or more lines>

**Tweet 2 (Body) -- NNN chars:**
<tweet text spanning one or more lines>
```

```bash
# extract_tweets <file>
# Outputs one tweet per entry, null-separated for safe iteration.
# Each entry is the tweet text (label line stripped).
extract_tweets() {
  local file="$1"
  local x_section
  x_section=$(extract_section "$file" "X/Twitter Thread")
  if [[ -z "$x_section" ]]; then
    echo "Error: No X/Twitter Thread section found in $file" >&2
    return 1
  fi
  # Split on **Tweet N pattern, strip the label line, trim whitespace
  echo "$x_section" | awk '
    /^\*\*Tweet [0-9]/ { if (buf != "") print buf; buf=""; next }
    { if (buf != "") buf = buf "\n" $0; else buf = $0 }
    END { if (buf != "") print buf }
  ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
```

**Important:** `x-community.sh post-tweet` takes the tweet text as the first positional argument. The text must be properly quoted. Shell special characters in the content (backticks, dollar signs, exclamation marks) must not be interpreted -- use single-quoted heredocs or variable expansion with double quotes.

### Date-to-Content Mapping

The workflow needs a mapping from date to content file and platform set:

| Date | Content File | Platforms |
|------|-------------|-----------|
| 2026-03-12 | `01-legal-document-generation.md` | Discord, X, IH (issue for 3/13), Reddit (issue for 3/16), HN |
| 2026-03-17 | `02-operations-management.md` | Discord, X |
| 2026-03-19 | `03-competitive-intelligence.md` | Discord, X, IH (issue for 3/20), Reddit (issue for 3/23) |
| 2026-03-24 | `04-brand-guide-creation.md` | Discord, X |
| 2026-03-26 | `05-business-validation.md` | Discord, X, IH (issue for 3/27), Reddit (issue for 3/30), HN |

Implement as a bash `case` statement on the `workflow_dispatch` input:

```bash
CONTENT_DIR="knowledge-base/specs/feat-product-strategy/distribution-content"

case "$CASE_STUDY_NUM" in
  1) CONTENT_FILE="$CONTENT_DIR/01-legal-document-generation.md"
     CASE_NAME="Legal Document Generation"
     MANUAL_PLATFORMS="indiehackers,reddit,hackernews" ;;
  2) CONTENT_FILE="$CONTENT_DIR/02-operations-management.md"
     CASE_NAME="Operations Management"
     MANUAL_PLATFORMS="" ;;
  3) CONTENT_FILE="$CONTENT_DIR/03-competitive-intelligence.md"
     CASE_NAME="Competitive Intelligence"
     MANUAL_PLATFORMS="indiehackers,reddit" ;;
  4) CONTENT_FILE="$CONTENT_DIR/04-brand-guide-creation.md"
     CASE_NAME="Brand Guide Creation"
     MANUAL_PLATFORMS="" ;;
  5) CONTENT_FILE="$CONTENT_DIR/05-business-validation.md"
     CASE_NAME="Business Validation"
     MANUAL_PLATFORMS="indiehackers,reddit,hackernews" ;;
  *) echo "Error: Invalid case study number: $CASE_STUDY_NUM (expected 1-5)" >&2
     exit 1 ;;
esac

if [[ ! -f "$CONTENT_FILE" ]]; then
  echo "Error: Content file not found: $CONTENT_FILE" >&2
  echo "Ensure distribution-content/ has been merged from feat-product-strategy." >&2
  exit 1
fi
```

### X API 402 Risk

**Critical:** Per learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`, the X API may return HTTP 402 if the pay-per-use account has zero credits. The workflow must:

1. Detect 402 specifically (distinct from 401/403/429)
2. On 402: create a GitHub issue titled `[Content Publisher] X API credits depleted -- manual posting required` with the pre-written tweet text, tagged `action-required`
3. Continue with Discord posting (do not abort the entire run)

#### Research Insights: X API Error Handling

**From proven #502 distribution plan -- thread posting recovery pattern:**

```bash
post_x_thread() {
  local file="$1"
  local -a tweets=()
  local tweet

  # Read tweets into array
  while IFS= read -r tweet; do
    [[ -n "$tweet" ]] && tweets+=("$tweet")
  done < <(extract_tweets "$file")

  if [[ ${#tweets[@]} -eq 0 ]]; then
    echo "Warning: No tweets found in X/Twitter Thread section. Skipping X posting." >&2
    return 0
  fi

  # Check credentials before attempting
  if [[ -z "${X_API_KEY:-}" || -z "${X_API_SECRET:-}" || -z "${X_ACCESS_TOKEN:-}" || -z "${X_ACCESS_TOKEN_SECRET:-}" ]]; then
    echo "Warning: X API credentials not configured. Skipping X posting." >&2
    return 0
  fi

  # Post hook tweet
  local hook_result hook_id
  hook_result=$(bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet "${tweets[0]}" 2>&1) || {
    local exit_code=$?
    # Detect 402 specifically
    if echo "$hook_result" | grep -q "402"; then
      echo "X API returned 402 (Payment Required). Creating fallback issue." >&2
      create_x_fallback_issue "$file"
      return 0
    fi
    echo "Error posting hook tweet (exit $exit_code): $hook_result" >&2
    create_x_fallback_issue "$file"
    return 0  # Don't fail the workflow
  }
  hook_id=$(echo "$hook_result" | jq -r '.id')
  if [[ -z "$hook_id" || "$hook_id" == "null" ]]; then
    echo "Error: Failed to extract tweet ID from hook response." >&2
    create_x_fallback_issue "$file"
    return 0
  fi
  echo "[ok] Hook tweet posted: https://x.com/soleur_ai/status/$hook_id"

  # Chain body tweets
  local prev_id="$hook_id"
  local i
  for (( i = 1; i < ${#tweets[@]}; i++ )); do
    local reply_result reply_id
    reply_result=$(bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet "${tweets[$i]}" --reply-to "$prev_id" 2>&1) || {
      echo "Error posting tweet $((i+1))/${#tweets[@]}. Thread is partial." >&2
      echo "Resume from: --reply-to $prev_id" >&2
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))"
      return 0
    }
    reply_id=$(echo "$reply_result" | jq -r '.id')
    if [[ -z "$reply_id" || "$reply_id" == "null" ]]; then
      echo "Error: Failed to extract reply ID for tweet $((i+1)). Thread is partial." >&2
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))"
      return 0
    fi
    prev_id="$reply_id"
    echo "[ok] Tweet $((i+1))/${#tweets[@]} posted: https://x.com/soleur_ai/status/$reply_id"
  done

  echo "[ok] X thread posted successfully (${#tweets[@]} tweets)."
}
```

**Key patterns from research:**
- Each reply must reference the immediately preceding tweet's ID (not the hook tweet's ID) to maintain linear thread order
- All tweets in a thread share the same `conversation_id` (the hook tweet's ID) -- useful for later retrieval
- There is no batch/atomic thread endpoint -- each tweet is a separate API call
- `x-community.sh` already handles 429 rate limiting with exponential backoff (3 retries)
- The `openssl` dependency for OAuth 1.0a signing is pre-installed on `ubuntu-latest` runners

### Discord Webhook Payload

Per constitution: all Discord webhook payloads must include explicit `username`, `avatar_url`, and `allowed_mentions: {parse: []}`. Use `jq -n` to construct the payload with proper JSON escaping:

```bash
post_discord() {
  local content="$1"

  if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo "Warning: DISCORD_WEBHOOK_URL not set. Skipping Discord posting." >&2
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg content "$content" \
    --arg username "Sol" \
    --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
    '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL")

  if [[ "$http_code" =~ ^2 ]]; then
    echo "[ok] Discord message posted (HTTP $http_code)."
  else
    echo "Error: Discord webhook returned HTTP $http_code." >&2
    return 1
  fi
}
```

#### Research Insights: Discord Webhook Limits

**Rate limits (from Discord API docs):**
- 30 requests per minute per webhook URL; 5 requests per 2 seconds
- Not a concern for this workflow (single post per run)
- Failed requests count toward the rate limit -- do not retry in a tight loop

**Content limits:**
- Maximum content length: 2,000 characters
- All content files have been written to stay within this limit (verified during content generation)
- If content exceeds 2,000 chars, Discord returns 400 Bad Request -- the script should detect this and truncate with an ellipsis + link

**Webhook URL security:**
- Webhook URLs are stored as GitHub secrets, never committed
- If a webhook returns 404, the webhook has been deleted -- do not retry (per Discord docs, repeated 404 attempts result in temporary restrictions)
- The webhook URL format includes a token that grants post access -- treat it as an API key

### Cron Schedule

Per constitution: "New scheduled workflows should start with `workflow_dispatch` trigger only, adding cron after the pipeline is validated end-to-end."

**Phase 1 (this PR):** `workflow_dispatch` only, with a `case_study` input (1-5 selector).
**Phase 2 (after validation):** Add 5 cron entries.

#### Research Insights: Cron Timing

**Avoid top-of-hour schedules.** GitHub Actions cron can be delayed 5-15 minutes during periods of high load. High load times include the start of every hour. Use non-zero minutes to decrease the chance of delay:

```yaml
schedule:
  - cron: '7 14 12 3 *'   # Mar 12 14:07 UTC
  - cron: '7 14 17 3 *'   # Mar 17 14:07 UTC
  - cron: '7 14 19 3 *'   # Mar 19 14:07 UTC
  - cron: '7 14 24 3 *'   # Mar 24 14:07 UTC
  - cron: '7 14 26 3 *'   # Mar 26 14:07 UTC
```

**Public repo auto-disable:** GitHub automatically disables cron schedules in public repos after 60 days of inactivity. Since this is a 3-week campaign ending 2026-03-30, this is not a concern during the campaign. However, if the cron triggers are left in place after the campaign, they will auto-disable -- which is actually desirable behavior (no wasted runs on past dates).

**Cron with specific dates:** The cron expressions above use day-of-month + month fields. GitHub Actions will fire these only when both the month AND day match. After March 2026, these will never fire again (unless the workflow is re-triggered in March 2027), which is correct for a one-time campaign.

### Concurrency

```yaml
concurrency:
  group: scheduled-content-publisher
  cancel-in-progress: false
```

Prevent overlapping runs if a manual dispatch fires while a cron run is in progress.

### Permissions

```yaml
permissions:
  contents: read
  issues: write
```

Minimal permissions. `contents: read` for checkout + reading content files. `issues: write` for creating manual-platform issues and failure notifications. No `id-token: write` needed (no claude-code-action).

### Workflow Dispatch Input Validation

Per constitution: all `workflow_dispatch` inputs must be validated against a strict regex.

```yaml
inputs:
  case_study:
    description: 'Case study number (1-5)'
    required: true
    type: choice
    options:
      - '1'
      - '2'
      - '3'
      - '4'
      - '5'
```

Using `type: choice` eliminates the need for regex validation since GitHub constrains the value.

### Action SHA Pinning

Follow `scheduled-community-monitor.yml` pattern. Pin `actions/checkout` to the same SHA:

```yaml
uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
```

### Label Pre-creation

Per constitution: `gh issue create --label` fails if the label does not exist. The workflow must pre-create labels:

```bash
gh label create "action-required" \
  --description "Manual action needed from the CEO" \
  --color "D93F0B" 2>/dev/null || true
gh label create "content-publisher" \
  --description "Scheduled content publisher workflow" \
  --color "0E8A16" 2>/dev/null || true
```

### Timeout

Per constitution: scheduled workflows must set `timeout-minutes`. This workflow is deterministic shell (no LLM), so 10 minutes is generous.

### Content File Location

The content files are in `knowledge-base/specs/feat-product-strategy/distribution-content/`. This directory currently exists only in the `feat-product-strategy` worktree. Before this workflow can run, the content must be merged to main. The workflow should reference the files at this path and fail clearly if they are not found.

### Issue Deduplication

#### Research Insights: Preventing Duplicate Issues on Re-runs

If the workflow is re-run (manual dispatch after a partial failure), it must not create duplicate GitHub issues for manual platforms. Use title-based dedup with exact match:

```bash
create_manual_issue() {
  local title="$1"
  local body="$2"
  local labels="$3"

  # Check for existing issue with exact title match
  local existing
  existing=$(gh issue list --state open --search "in:title \"$title\"" --json number,title \
    --jq "[.[] | select(.title == \"$title\")] | .[0].number // empty")

  if [[ -n "$existing" ]]; then
    echo "Issue already exists: #$existing -- skipping duplicate creation." >&2
    return 0
  fi

  if gh issue create --title "$title" --label "$labels" --body "$body"; then
    echo "[ok] Issue created: $title"
  else
    echo "Error: Failed to create issue: $title" >&2
    return 1
  fi
}
```

Per learning `2026-02-21-github-actions-workflow-security-patterns.md`: use `--jq` with exact title comparison (`select(.title == ...)`) rather than substring matching, because substring matching could match unrelated issues (e.g., "Legal Document" matching "Legal Document Generation" and "Legal Document Review").

## Non-goals

- **No LLM agent** -- all content is pre-written; no claude-code-action needed
- **No content generation** -- the workflow posts existing content, it does not create new content
- **No engagement monitoring** -- that is handled by `scheduled-community-monitor.yml`
- **No Playwright web UI fallback for X** -- if the API fails, create an issue for manual posting instead
- **No multi-repository support** -- this workflow is specific to the Soleur case study campaign
- **No Discord embeds** -- plain `content` field only (matches discord-content skill v1 convention)
- **No automatic content truncation** -- content files are pre-validated to be under 2,000 chars for Discord

## Acceptance Criteria

- [ ] `workflow_dispatch` trigger with `case_study` choice input (1-5) works end-to-end
- [ ] Discord posts fire automatically via webhook with correct content, `username: Sol`, `avatar_url`, and `allowed_mentions: {parse: []}`
- [ ] X/Twitter threads post via `x-community.sh post-tweet` with `--reply-to` chaining (hook + body + final)
- [ ] GitHub issue created on publish days for manual platforms (IndieHackers, Reddit, HN) with pre-written content and `action-required` label
- [ ] On X API 402 error, workflow creates a fallback issue with tweet text instead of failing
- [ ] On Discord webhook failure, workflow logs the error and continues with other platforms
- [ ] Workflow logs confirm successful posting or surface errors clearly with `[ok]` prefix on success
- [ ] Content file not found produces a clear error message, not a silent failure
- [ ] `timeout-minutes: 10` set on the job
- [ ] Concurrency group prevents overlapping runs
- [ ] Labels pre-created before issue creation
- [ ] Action SHAs pinned (not tag references)
- [ ] Re-runs do not create duplicate manual-platform issues
- [ ] Partial X thread failure creates a resume issue with the last successful tweet ID

## Test Scenarios

- Given case study 1 is selected and Discord webhook is configured, when the workflow runs, then the Legal Document Generation Discord content is posted via webhook and X thread is posted with 4 chained tweets
- Given case study 2 is selected, when the workflow runs, then only Discord and X are posted (no manual platform issues created, since Operations Management has no IH/Reddit/HN distribution)
- Given case study 1 is selected and X API returns 402, when the workflow runs, then Discord posting succeeds and a GitHub issue is created with the pre-written tweet text for manual posting
- Given case study 1 is selected and the content file is missing, when the workflow runs, then the workflow exits with a clear error message referencing the expected path
- Given case study 1 is selected and Discord webhook URL is not configured, when the workflow runs, then Discord posting is skipped with a warning and X/manual platform steps proceed
- Given case study 1 is selected and the X thread partially fails after tweet 2, when the workflow runs, then tweets 1-2 are posted and a resume issue is created with the last tweet ID and remaining tweet text
- Given case study 1 was already dispatched and manual platform issues exist, when the workflow is re-run, then existing issues are detected and duplicates are not created
- Given the workflow is triggered via cron (Phase 2), when the date matches a scheduled post, then the correct content file and platform set are selected automatically

## Dependencies and Risks

### Prerequisites (must be done before first run)

1. **Content files on main:** The `distribution-content/` directory must be merged from `feat-product-strategy` to main
2. **GitHub secrets:** `DISCORD_WEBHOOK_URL`, `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` must be configured
3. **X API credits:** The X API pay-per-use account must have credits loaded (see learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`)
4. **Blog posts live:** All 5 case study blog posts must be deployed to soleur.ai
5. **`x-community.sh` on main:** The community scripts must be merged (already on main)

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| X API 402 (zero credits) | High | Medium | Fallback to issue creation with tweet text |
| Discord webhook URL rotated | Low | Medium | Workflow fails with clear error; re-configure secret |
| Content files not merged to main | High (blocking) | High | Document as prerequisite; fail clearly if missing |
| GitHub Actions cron drift (5-15 min) | Medium | Low | Acceptable for social media; non-zero minute offset reduces delay |
| X API rate limiting (429) | Low | Low | `x-community.sh` already handles retry with backoff (3 retries) |
| Partial X thread (2 of 4 tweets posted) | Low | Medium | Resume issue created with last tweet ID for manual continuation |
| Content exceeds Discord 2000-char limit | Low | Low | Pre-validated during content generation; 400 response logged clearly |
| Duplicate issues on re-run | Medium | Low | Title-based dedup before creation |
| Public repo cron auto-disable after 60 days | Low | None | Campaign ends in 3 weeks; auto-disable is desirable |

## Implementation Structure

### Files to Create

```text
.github/workflows/scheduled-content-publisher.yml   # The workflow
scripts/content-publisher.sh                          # Content extraction + posting logic
```

### `scripts/content-publisher.sh`

Separate the posting logic into a testable script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: content-publisher.sh <case-study-number>
# Environment: DISCORD_WEBHOOK_URL, X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET
# Exit codes:
#   0 - All platforms posted (or gracefully skipped)
#   1 - Fatal error (missing content file, invalid input)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTENT_DIR="$REPO_ROOT/knowledge-base/specs/feat-product-strategy/distribution-content"
X_SCRIPT="$REPO_ROOT/plugins/soleur/skills/community/scripts/x-community.sh"
AVATAR_URL="https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png"

# --- Content extraction ---

extract_section() {
  local file="$1"
  local heading="$2"
  local content
  content=$(sed -n "/^## ${heading}$/,/^## /{/^## /!p}" "$file" | sed '/^$/d; s/^[[:space:]]*//')
  # Handle "Not scheduled" placeholder sections (studies 2, 4)
  if echo "$content" | grep -q "Not scheduled for"; then
    echo ""
    return 0
  fi
  echo "$content"
}

extract_tweets() {
  local file="$1"
  local x_section
  x_section=$(extract_section "$file" "X/Twitter Thread")
  if [[ -z "$x_section" ]]; then
    echo "Error: No X/Twitter Thread section found in $file" >&2
    return 1
  fi
  echo "$x_section" | awk '
    /^\*\*Tweet [0-9]/ { if (buf != "") print buf; buf=""; next }
    { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if (buf != "") buf = buf "\n" $0; else buf = $0 }
    END { if (buf != "") print buf }
  '
}

# --- Content mapping ---

resolve_content() {
  local num="$1"
  case "$num" in
    1) CONTENT_FILE="$CONTENT_DIR/01-legal-document-generation.md"
       CASE_NAME="Legal Document Generation"
       MANUAL_PLATFORMS="indiehackers,reddit,hackernews" ;;
    2) CONTENT_FILE="$CONTENT_DIR/02-operations-management.md"
       CASE_NAME="Operations Management"
       MANUAL_PLATFORMS="" ;;
    3) CONTENT_FILE="$CONTENT_DIR/03-competitive-intelligence.md"
       CASE_NAME="Competitive Intelligence"
       MANUAL_PLATFORMS="indiehackers,reddit" ;;
    4) CONTENT_FILE="$CONTENT_DIR/04-brand-guide-creation.md"
       CASE_NAME="Brand Guide Creation"
       MANUAL_PLATFORMS="" ;;
    5) CONTENT_FILE="$CONTENT_DIR/05-business-validation.md"
       CASE_NAME="Business Validation"
       MANUAL_PLATFORMS="indiehackers,reddit,hackernews" ;;
    *) echo "Error: Invalid case study number: $num (expected 1-5)" >&2; exit 1 ;;
  esac
  if [[ ! -f "$CONTENT_FILE" ]]; then
    echo "Error: Content file not found: $CONTENT_FILE" >&2
    echo "Ensure distribution-content/ has been merged from feat-product-strategy." >&2
    exit 1
  fi
}

# --- Discord posting ---

post_discord() {
  local content="$1"
  if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo "Warning: DISCORD_WEBHOOK_URL not set. Skipping Discord posting." >&2
    return 0
  fi
  local payload
  payload=$(jq -n \
    --arg content "$content" \
    --arg username "Sol" \
    --arg avatar_url "$AVATAR_URL" \
    '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL")
  if [[ "$http_code" =~ ^2 ]]; then
    echo "[ok] Discord message posted (HTTP $http_code)."
  else
    echo "Error: Discord webhook returned HTTP $http_code." >&2
    return 1
  fi
}

# --- X/Twitter posting ---

create_x_fallback_issue() {
  local file="$1"
  local x_content
  x_content=$(extract_section "$file" "X/Twitter Thread")
  local title="[Content Publisher] X API failed -- manual posting required for $CASE_NAME"
  local body
  body=$(printf '## Manual X/Twitter Posting Required\n\nThe scheduled content publisher could not post to X/Twitter for **%s**.\n\nPost this thread manually at https://x.com/compose/post:\n\n---\n\n%s' "$CASE_NAME" "$x_content")
  create_dedup_issue "$title" "$body" "action-required,content-publisher"
}

create_partial_thread_issue() {
  local file="$1"
  local last_tweet_id="$2"
  local resume_from="$3"
  local x_content
  x_content=$(extract_section "$file" "X/Twitter Thread")
  local title="[Content Publisher] Partial X thread -- resume for $CASE_NAME"
  local body
  body=$(printf '## Partial X Thread -- Resume Required\n\nThe thread for **%s** was partially posted. Resume from tweet %s.\n\n**Last successful tweet:** https://x.com/soleur_ai/status/%s\n**Resume with:** `--reply-to %s`\n\n---\n\n%s' "$CASE_NAME" "$resume_from" "$last_tweet_id" "$last_tweet_id" "$x_content")
  create_dedup_issue "$title" "$body" "action-required,content-publisher"
}

post_x_thread() {
  local file="$1"
  if [[ -z "${X_API_KEY:-}" || -z "${X_API_SECRET:-}" || -z "${X_ACCESS_TOKEN:-}" || -z "${X_ACCESS_TOKEN_SECRET:-}" ]]; then
    echo "Warning: X API credentials not configured. Skipping X posting." >&2
    return 0
  fi
  local -a tweets=()
  local tweet
  while IFS= read -r tweet; do
    [[ -n "$tweet" ]] && tweets+=("$tweet")
  done < <(extract_tweets "$file")
  if [[ ${#tweets[@]} -eq 0 ]]; then
    echo "Warning: No tweets found in X/Twitter Thread section. Skipping X posting." >&2
    return 0
  fi
  # Post hook tweet
  local hook_result hook_id
  hook_result=$(bash "$X_SCRIPT" post-tweet "${tweets[0]}" 2>&1) || {
    local exit_code=$?
    if echo "$hook_result" | grep -q "402"; then
      echo "X API returned 402 (Payment Required). Creating fallback issue." >&2
      create_x_fallback_issue "$file"
      return 0
    fi
    echo "Error posting hook tweet (exit $exit_code): $hook_result" >&2
    create_x_fallback_issue "$file"
    return 0
  }
  hook_id=$(echo "$hook_result" | jq -r '.id')
  if [[ -z "$hook_id" || "$hook_id" == "null" ]]; then
    echo "Error: Failed to extract tweet ID from hook response." >&2
    create_x_fallback_issue "$file"
    return 0
  fi
  echo "[ok] Hook tweet posted: https://x.com/soleur_ai/status/$hook_id"
  # Chain body tweets
  local prev_id="$hook_id"
  local i
  for (( i = 1; i < ${#tweets[@]}; i++ )); do
    local reply_result reply_id
    reply_result=$(bash "$X_SCRIPT" post-tweet "${tweets[$i]}" --reply-to "$prev_id" 2>&1) || {
      echo "Error posting tweet $((i+1))/${#tweets[@]}. Thread is partial." >&2
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))"
      return 0
    }
    reply_id=$(echo "$reply_result" | jq -r '.id')
    if [[ -z "$reply_id" || "$reply_id" == "null" ]]; then
      echo "Error: Failed to extract reply ID for tweet $((i+1))." >&2
      create_partial_thread_issue "$file" "$prev_id" "$((i+1))"
      return 0
    fi
    prev_id="$reply_id"
    echo "[ok] Tweet $((i+1))/${#tweets[@]} posted: https://x.com/soleur_ai/status/$reply_id"
  done
  echo "[ok] X thread posted successfully (${#tweets[@]} tweets)."
}

# --- Manual platform issues ---

create_dedup_issue() {
  local title="$1"
  local body="$2"
  local labels="$3"
  local existing
  existing=$(gh issue list --state open --search "in:title \"$title\"" --json number,title \
    --jq "[.[] | select(.title == \"$title\")] | .[0].number // empty")
  if [[ -n "$existing" ]]; then
    echo "Issue already exists: #$existing -- skipping." >&2
    return 0
  fi
  if gh issue create --title "$title" --label "$labels" --body "$body"; then
    echo "[ok] Issue created: $title"
  else
    echo "Error: Failed to create issue: $title" >&2
    return 1
  fi
}

create_manual_issues() {
  local file="$1"
  local platforms="$2"
  [[ -z "$platforms" ]] && return 0
  local IFS=','
  for platform in $platforms; do
    local section_name body_content title
    case "$platform" in
      indiehackers) section_name="IndieHackers" ;;
      reddit)       section_name="Reddit" ;;
      hackernews)   section_name="Hacker News" ;;
      *) echo "Warning: Unknown platform: $platform" >&2; continue ;;
    esac
    body_content=$(extract_section "$file" "$section_name")
    if [[ -z "$body_content" ]]; then
      echo "Warning: No $section_name content found. Skipping." >&2
      continue
    fi
    title="[Content Publisher] Post to $section_name: $CASE_NAME"
    local body
    body=$(printf '## Manual Posting Required: %s\n\n**Case study:** %s\n**Platform:** %s\n\nCopy-paste the content below:\n\n---\n\n%s' "$section_name" "$CASE_NAME" "$section_name" "$body_content")
    create_dedup_issue "$title" "$body" "action-required,content-publisher"
  done
}

# --- Main ---

main() {
  local case_study_num="${1:?Usage: content-publisher.sh <case-study-number>}"
  resolve_content "$case_study_num"
  echo "Publishing case study $case_study_num: $CASE_NAME"
  echo "Content file: $CONTENT_FILE"
  echo "Manual platforms: ${MANUAL_PLATFORMS:-none}"
  echo "---"

  # Discord
  local discord_content
  discord_content=$(extract_section "$CONTENT_FILE" "Discord")
  if [[ -n "$discord_content" ]]; then
    post_discord "$discord_content" || echo "Warning: Discord posting failed. Continuing." >&2
  else
    echo "Warning: No Discord content found. Skipping." >&2
  fi

  # X/Twitter
  post_x_thread "$CONTENT_FILE"

  # Manual platforms
  create_manual_issues "$CONTENT_FILE" "$MANUAL_PLATFORMS"

  echo "---"
  echo "[ok] Content publisher completed for: $CASE_NAME"
}

main "$@"
```

### `scheduled-content-publisher.yml`

```yaml
# Scheduled content publisher for the 3-week case study distribution campaign.
# Posts pre-generated content to Discord (webhook), X/Twitter (API), and
# creates GitHub issues for manual platforms (IndieHackers, Reddit, HN).
# Implements #530: scheduled content publisher workflow.
#
# Phase 1: workflow_dispatch only (validate end-to-end).
# Phase 2: add cron triggers after validation.
#
# Security: This workflow does NOT use untrusted event inputs in run: commands.
# The case_study input is a constrained choice (1-5) and is validated by
# the content-publisher.sh case statement before use.

name: "Scheduled: Content Publisher"

on:
  workflow_dispatch:
    inputs:
      case_study:
        description: 'Case study number (1-5)'
        required: true
        type: choice
        options:
          - '1'
          - '2'
          - '3'
          - '4'
          - '5'

concurrency:
  group: scheduled-content-publisher
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  publish:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout repository
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Ensure labels exist
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "action-required" \
            --description "Manual action needed from the CEO" \
            --color "D93F0B" 2>/dev/null || true
          gh label create "content-publisher" \
            --description "Scheduled content publisher workflow" \
            --color "0E8A16" 2>/dev/null || true

      - name: Publish content
        env:
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
          X_API_KEY: ${{ secrets.X_API_KEY }}
          X_API_SECRET: ${{ secrets.X_API_SECRET }}
          X_ACCESS_TOKEN: ${{ secrets.X_ACCESS_TOKEN }}
          X_ACCESS_TOKEN_SECRET: ${{ secrets.X_ACCESS_TOKEN_SECRET }}
          GH_TOKEN: ${{ github.token }}
        run: bash scripts/content-publisher.sh "${{ inputs.case_study }}"

      - name: Discord notification (failure)
        if: failure()
        env:
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
          REPO_URL: ${{ github.server_url }}/${{ github.repository }}
          RUN_ID: ${{ github.run_id }}
        run: |
          if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
            echo "DISCORD_WEBHOOK_URL not set, skipping failure notification"
            exit 0
          fi
          RUN_URL="${REPO_URL}/actions/runs/${RUN_ID}"
          MESSAGE=$(printf '**Content Publisher failed**\n\nCase study: %s\nWorkflow run: %s\n\nCheck logs for details.' \
            "${{ inputs.case_study }}" "$RUN_URL")
          PAYLOAD=$(jq -n \
            --arg content "$MESSAGE" \
            --arg username "Sol" \
            --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
            '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "$DISCORD_WEBHOOK_URL")
          if [[ "$HTTP_CODE" =~ ^2 ]]; then
            echo "Discord failure notification sent (HTTP $HTTP_CODE)"
          else
            echo "::warning::Discord failure notification failed (HTTP $HTTP_CODE)"
          fi
```

## References

### Internal

- `.github/workflows/scheduled-community-monitor.yml` -- cron/dispatch pattern, concurrency, permissions, Discord failure notification
- `plugins/soleur/skills/community/scripts/x-community.sh` -- X API v2 OAuth 1.0a posting with `--reply-to`
- `plugins/soleur/skills/discord-content/SKILL.md` -- Discord webhook posting pattern
- `knowledge-base/specs/feat-product-strategy/distribution-plan.md` -- campaign schedule and platform matrix
- `knowledge-base/specs/feat-product-strategy/distribution-content/*.md` -- pre-written content
- `knowledge-base/plans/2026-03-10-feat-post-blog-social-distribution-plan.md` -- prior social distribution plan with thread posting pattern

### Learnings Applied

- `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- X API 402 risk and fallback strategy
- `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` -- `allowed_mentions: {parse: []}` requirement
- `2026-03-03-scheduled-bot-fix-workflow-patterns.md` -- label pre-creation, cascading patterns
- `2026-02-27-github-actions-sha-pinning-workflow.md` -- action SHA pinning
- `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` -- GITHUB_TOKEN cascade considerations
- `2026-02-21-github-actions-workflow-security-patterns.md` -- input validation, exact title dedup
- `2026-03-05-github-output-newline-injection-sanitization.md` -- safe output writing patterns
- `2026-02-19-discord-bot-identity-and-webhook-behavior.md` -- webhook identity freezing, avatar URL

### External

- [GitHub Actions workflow syntax: scheduled events](https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions)
- [Discord webhook rate limits](https://birdie0.github.io/discord-webhooks-guide/other/rate_limits.html)
- [Discord webhooks complete guide](https://inventivehq.com/blog/discord-webhooks-guide)
