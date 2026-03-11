---
title: "feat: scheduled content publisher workflow for case study distribution"
type: feat
date: 2026-03-11
semver: patch
---

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

Each content file has sections delimited by `## Discord`, `## X/Twitter Thread`, `## IndieHackers`, `## Reddit`, `## Hacker News`. The workflow must extract content between these markers reliably. Use `sed -n '/^## Discord$/,/^## /{ /^## /!p; }' <file>` or equivalent.

The X/Twitter section contains structured tweets:

```text
**Tweet 1 (Hook) -- NNN chars:**
<tweet text>

**Tweet 2 (Body) -- NNN chars:**
<tweet text>
...
```

Parse individual tweets by splitting on the `**Tweet N` pattern, stripping the label line.

### Date-to-Content Mapping

The workflow needs a mapping from date to content file and platform set:

| Date | Content File | Platforms |
|------|-------------|-----------|
| 2026-03-12 | `01-legal-document-generation.md` | Discord, X, IH (issue for 3/13), Reddit (issue for 3/16), HN |
| 2026-03-17 | `02-operations-management.md` | Discord, X |
| 2026-03-19 | `03-competitive-intelligence.md` | Discord, X, IH (issue for 3/20), Reddit (issue for 3/23) |
| 2026-03-24 | `04-brand-guide-creation.md` | Discord, X |
| 2026-03-26 | `05-business-validation.md` | Discord, X, IH (issue for 3/27), Reddit (issue for 3/30), HN |

Implement as a bash `case` statement on the date string (`date +%Y-%m-%d`) or the `workflow_dispatch` input.

### X API 402 Risk

**Critical:** Per learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`, the X API may return HTTP 402 if the pay-per-use account has zero credits. The workflow must:

1. Detect 402 specifically (distinct from 401/403/429)
2. On 402: create a GitHub issue titled `[Content Publisher] X API credits depleted -- manual posting required` with the pre-written tweet text, tagged `action-required`
3. Continue with Discord posting (do not abort the entire run)

### Discord Webhook Payload

Per constitution: all Discord webhook payloads must include explicit `username`, `avatar_url`, and `allowed_mentions: {parse: []}`. Use `jq -n` to construct the payload with proper JSON escaping:

```bash
PAYLOAD=$(jq -n \
  --arg content "$DISCORD_CONTENT" \
  --arg username "Sol" \
  --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
  '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
```

### Cron Schedule

Per constitution: "New scheduled workflows should start with `workflow_dispatch` trigger only, adding cron after the pipeline is validated end-to-end."

**Phase 1 (this PR):** `workflow_dispatch` only, with a `case_study` input (1-5 selector).
**Phase 2 (after validation):** Add 5 cron entries:

```yaml
schedule:
  - cron: '0 14 12 3 *'  # Mar 12 14:00 UTC
  - cron: '0 14 17 3 *'  # Mar 17 14:00 UTC
  - cron: '0 14 19 3 *'  # Mar 19 14:00 UTC
  - cron: '0 14 24 3 *'  # Mar 24 14:00 UTC
  - cron: '0 14 26 3 *'  # Mar 26 14:00 UTC
```

Note: GitHub Actions cron does not guarantee exact timing (can be delayed 5-15 min). This is acceptable for social media posting.

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

## Non-goals

- **No LLM agent** -- all content is pre-written; no claude-code-action needed
- **No content generation** -- the workflow posts existing content, it does not create new content
- **No engagement monitoring** -- that is handled by `scheduled-community-monitor.yml`
- **No Playwright web UI fallback for X** -- if the API fails, create an issue for manual posting instead
- **No multi-repository support** -- this workflow is specific to the Soleur case study campaign

## Acceptance Criteria

- [ ] `workflow_dispatch` trigger with `case_study` choice input (1-5) works end-to-end
- [ ] Discord posts fire automatically via webhook with correct content, `username: Sol`, `avatar_url`, and `allowed_mentions: {parse: []}`
- [ ] X/Twitter threads post via `x-community.sh post-tweet` with `--reply-to` chaining (hook + body + final)
- [ ] GitHub issue created on publish days for manual platforms (IndieHackers, Reddit, HN) with pre-written content and `action-required` label
- [ ] On X API 402 error, workflow creates a fallback issue with tweet text instead of failing
- [ ] On Discord webhook failure, workflow logs the error and continues with other platforms
- [ ] Workflow logs confirm successful posting or surface errors clearly
- [ ] Content file not found produces a clear error message, not a silent failure
- [ ] `timeout-minutes` set on the job
- [ ] Concurrency group prevents overlapping runs
- [ ] Labels pre-created before issue creation
- [ ] Action SHAs pinned (not tag references)

## Test Scenarios

- Given case study 1 is selected and Discord webhook is configured, when the workflow runs, then the Legal Document Generation Discord content is posted via webhook and X thread is posted with 4 chained tweets
- Given case study 2 is selected, when the workflow runs, then only Discord and X are posted (no manual platform issues created, since Operations Management has no IH/Reddit/HN distribution)
- Given case study 1 is selected and X API returns 402, when the workflow runs, then Discord posting succeeds and a GitHub issue is created with the pre-written tweet text for manual posting
- Given case study 1 is selected and the content file is missing, when the workflow runs, then the workflow exits with a clear error message
- Given case study 1 is selected and Discord webhook URL is not configured, when the workflow runs, then Discord posting is skipped with a warning and X/manual platform steps proceed
- Given the workflow is triggered via cron (Phase 2), when the date matches a scheduled post, then the correct content file and platform set are selected automatically

## Dependencies and Risks

### Prerequisites (must be done before first run)

1. **Content files on main:** The `distribution-content/` directory must be merged from `feat-product-strategy` to main
2. **GitHub secrets:** `DISCORD_WEBHOOK_URL`, `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` must be configured
3. **X API credits:** The X API pay-per-use account must have credits loaded (see learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`)
4. **Blog posts live:** All 5 case study blog posts must be deployed to soleur.ai

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| X API 402 (zero credits) | High | Medium | Fallback to issue creation with tweet text |
| Discord webhook URL rotated | Low | Medium | Workflow fails with clear error; re-configure secret |
| Content files not merged to main | High (blocking) | High | Document as prerequisite; fail clearly if missing |
| GitHub Actions cron drift | Medium | Low | Acceptable for social media; manual dispatch as backup |
| X API rate limiting (429) | Low | Low | `x-community.sh` already handles retry with backoff |

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

# --- Content mapping ---
# Maps case study number to content file and platform set

# --- Content extraction ---
# extract_section <file> <heading>  -- extracts text between ## heading markers
# extract_tweets <file>             -- parses X/Twitter Thread section into individual tweets

# --- Discord posting ---
# post_discord <content>  -- POST to webhook with jq-constructed payload

# --- X/Twitter posting ---
# post_x_thread <file>  -- posts hook tweet, chains body tweets via --reply-to

# --- Manual platform issues ---
# create_manual_issue <case_study_name> <platforms_json> <file>  -- gh issue create with content

# --- Main ---
# Dispatch based on case study number
```

### `scheduled-content-publisher.yml`

```yaml
name: "Scheduled: Content Publisher"

on:
  workflow_dispatch:
    inputs:
      case_study:
        description: 'Case study number (1-5)'
        required: true
        type: choice
        options: ['1', '2', '3', '4', '5']

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
      - uses: actions/checkout@<pinned-sha>
      - name: Ensure labels exist
        # Pre-create action-required and content-publisher labels
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
        # Same pattern as scheduled-community-monitor.yml
```

## References

### Internal

- `scheduled-community-monitor.yml` -- cron/dispatch pattern, concurrency, permissions, Discord failure notification
- `plugins/soleur/skills/community/scripts/x-community.sh` -- X API v2 OAuth 1.0a posting with `--reply-to`
- `plugins/soleur/skills/discord-content/SKILL.md` -- Discord webhook posting pattern
- `knowledge-base/specs/feat-product-strategy/distribution-plan.md` -- campaign schedule and platform matrix
- `knowledge-base/specs/feat-product-strategy/distribution-content/*.md` -- pre-written content

### Learnings Applied

- `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- X API 402 risk and fallback strategy
- `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` -- `allowed_mentions: {parse: []}` requirement
- `2026-03-03-scheduled-bot-fix-workflow-patterns.md` -- label pre-creation, cascading patterns
- `2026-02-27-github-actions-sha-pinning-workflow.md` -- action SHA pinning
- `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` -- GITHUB_TOKEN cascade considerations
