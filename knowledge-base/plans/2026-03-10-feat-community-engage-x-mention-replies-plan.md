---
title: "feat(community): add engage sub-command for X mention engagement"
type: feat
date: 2026-03-10
---

# feat(community): add engage sub-command for X mention engagement

## Overview

Add an `engage` sub-command to the community skill that fetches recent X/Twitter mentions, drafts replies using brand guide tone, presents drafts for user approval, and posts approved replies. This is a human-in-the-loop engagement workflow -- no autonomous posting.

**Parent issue:** #127 (closed)
**This issue:** #469

## Problem Statement / Motivation

The community skill currently monitors X/Twitter (via `fetch-metrics`) and broadcasts content (via `social-distribute`), but there is no workflow for responding to mentions. Community engagement is bidirectional -- monitoring without response leaves mentions unanswered and misses relationship-building opportunities.

The `engage` sub-command closes the feedback loop: monitor mentions, draft brand-voice replies, get human approval, post.

## Proposed Solution

### Architecture

Extend the existing community skill with a new `engage` sub-command. This requires:

1. **New shell command** in `x-community.sh`: `fetch-mentions` -- wraps `GET /2/users/:id/mentions`
2. **New SKILL.md sub-command** section: `engage` -- orchestrates the fetch-draft-approve-post loop
3. **Community-manager agent update** -- add a "Capability 4: Mention Engagement" section

The flow:

```text
User runs: /soleur:community engage

1. Platform detection (X must be enabled)
2. Fetch authenticated user ID via GET /2/users/me
3. Fetch recent mentions via GET /2/users/:id/mentions
4. For each mention:
   a. Read brand-guide.md ## Voice and ## Channel Notes > ### X/Twitter
   b. Draft a reply (280-char limit, brand voice)
   c. Present: mention text + draft reply via AskUserQuestion
   d. User: Accept / Edit / Skip
   e. If accepted: post via x-community.sh post-tweet --reply-to <mention_id>
5. Summary: N mentions processed, M replies posted, K skipped
```

### X API Details

**Endpoint:** `GET /2/users/{id}/mentions`

- **Authentication:** OAuth 1.0a User Context (already implemented in `x-community.sh`)
- **Pricing:** Pay-per-use credits (not available on legacy Free tier -- requires credit purchase)
- **Parameters used:** `max_results` (default 10), `since_id` (track last processed), `tweet.fields=author_id,created_at,conversation_id`, `expansions=author_id`, `user.fields=username,name`
- **Rate limits:** Credit-based; the command fetches once per invocation (not polling)
- **Response:** `{ data: [Tweet], includes: { users: [User] }, meta: { newest_id, result_count } }`

### Ownership Boundary

- `community engage` = fetch mentions + draft replies + post replies (this feature)
- `social-distribute` = broadcast blog articles to multiple platforms (unchanged)
- `community digest/health` = read-only monitoring (unchanged)

## Technical Considerations

### 1. x-community.sh fetch-mentions command

Add a new `cmd_fetch_mentions` function to `plugins/soleur/skills/community/scripts/x-community.sh`.

**Input:** Optional `--max-results N` (default 10), optional `--since-id ID`.

**Implementation:** Reuse the existing `oauth_sign` function for OAuth 1.0a signing. The mentions endpoint requires query parameters to be included in the OAuth signature base string (same pattern as `cmd_fetch_metrics`).

**Output:** JSON to stdout matching the raw API response structure, filtered to essential fields:

```json
{
  "mentions": [
    {
      "id": "123",
      "text": "@soleur_ai how do I...",
      "author_username": "user123",
      "author_name": "User Name",
      "created_at": "2026-03-10T12:00:00Z",
      "conversation_id": "120"
    }
  ],
  "meta": {
    "newest_id": "123",
    "result_count": 5
  }
}
```

**Error handling:** Same patterns as existing commands -- 401/403/429 handling via `x_request`, jq fallback chain, curl stderr suppression. See learning `2026-03-09-shell-api-wrapper-hardening-patterns.md`.

### 2. User ID Resolution

The mentions endpoint requires a numeric user ID, not a username. The `cmd_fetch_metrics` function already calls `GET /2/users/me` which returns the authenticated user's ID. Extract and cache this ID for the mentions call.

Add a helper function `get_authenticated_user_id` that calls `/2/users/me` and returns only the ID. This avoids duplicating the metrics call logic.

### 3. Since-ID State File

To avoid re-processing mentions, store the `newest_id` from the last fetch in a state file:

- Path: `.soleur/x-engage-since-id` (relative to repo root, resolved via `git rev-parse --show-toplevel`)
- Format: plain text, single line containing the tweet ID
- Created on first run, updated after each successful engagement session
- Add `.soleur/` to `.gitignore` if not already present

This is optional for v1 -- the skill can run without it (processes last 10 mentions). But including it prevents duplicate engagement on repeated runs within the same day.

### 4. Brand Voice Draft Generation

The community-manager agent reads `knowledge-base/overview/brand-guide.md` sections:
- `## Voice` -- overall brand voice
- `## Channel Notes > ### X/Twitter` -- X-specific tone: "Declarative, concrete, no hedging"

The agent drafts replies within 280 characters, following the brand guide's instruction that "Every tweet should read like a statement, not a question."

### 5. Approval Flow

Constitution requires: "For user approval flows, present items one at a time with Accept, Skip, and Edit options."

Each mention is presented via AskUserQuestion:

```text
Mention from @user123 (2026-03-10 12:00):
"@soleur_ai how do I set up the community skill?"

Draft reply:
"The community skill detects platforms from env vars. Run /soleur:community platforms to see what's configured, then follow the setup instructions for each."

Options:
1. Accept -- post this reply
2. Edit -- modify the reply text
3. Skip -- move to next mention
```

If `--headless` is set, skip all mentions (no autonomous posting).

### 6. Security Considerations

- No new credentials required -- reuses existing X API credentials from env vars
- Reply text is user-approved before posting (no autonomous engagement)
- No raw mention content stored to files -- only the since-id state
- OAuth 1.0a signing already handles credential security
- curl stderr suppression already in place to prevent token leakage

## Non-Goals

- Autonomous/scheduled engagement (no cron, no headless posting)
- Sentiment analysis or filtering of mentions
- DM engagement (mentions only)
- Multi-account support
- Rate limit credit tracking or budget management
- Engagement analytics or reporting beyond the session summary

## Acceptance Criteria

- [ ] `x-community.sh fetch-mentions` returns recent mentions as JSON (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] `x-community.sh fetch-mentions --max-results 5` limits results
- [ ] `x-community.sh fetch-mentions --since-id <id>` returns only newer mentions
- [ ] `x-community.sh fetch-mentions` handles 401, 403, 429 errors with clear messages
- [ ] `/soleur:community engage` detects X platform and reports status
- [ ] `/soleur:community engage` fetches mentions and presents each with a draft reply
- [ ] Draft replies follow brand guide voice and respect 280-character limit
- [ ] User can Accept, Edit, or Skip each draft
- [ ] Accepted replies are posted via `x-community.sh post-tweet --reply-to`
- [ ] Session summary shows counts: processed, posted, skipped
- [ ] `--headless` mode skips all mentions without posting
- [ ] `--since-id` state file persists between sessions (`.soleur/x-engage-since-id`)
- [ ] community-manager agent documentation updated with Capability 4

## Test Scenarios

### Happy Path

- Given X credentials are configured and mentions exist, when running `community engage`, then mentions are fetched and presented one at a time with draft replies
- Given a draft reply is accepted, when the user selects Accept, then the reply is posted via `post-tweet --reply-to` and the since-id state is updated
- Given a draft reply is skipped, when the user selects Skip, then no reply is posted and the next mention is presented

### Error Handling

- Given X credentials are not configured, when running `community engage`, then the skill reports "X/Twitter not configured" and stops
- Given the X API returns 401, when fetching mentions, then the error message includes credential regeneration instructions
- Given the X API returns 429, when fetching mentions, then `x_request` retries up to 3 times with clamped backoff
- Given no mentions exist, when running `community engage`, then the skill reports "No recent mentions found" and exits cleanly

### Edge Cases

- Given `--headless` is passed, when running `community engage`, then all mentions are skipped (no posting)
- Given a since-id state file exists, when running `community engage`, then only mentions newer than the stored ID are fetched
- Given the since-id state file does not exist, when running `community engage`, then the last 10 mentions are fetched (default behavior)
- Given a mention text contains special characters (quotes, newlines, emoji), when drafting a reply, then the reply is properly JSON-escaped for the API call

### Shell Script Tests

- Given `x-community.sh fetch-mentions` is called without credentials, then it exits 1 with "Missing X API credentials"
- Given `x-community.sh fetch-mentions --max-results abc` is called, then it exits 1 with a usage error (non-numeric)
- Given the API returns malformed JSON, then `fetch-mentions` exits 1 with "malformed JSON" error

## Dependencies & Risks

### Dependencies

- X API paid tier access -- mentions endpoint requires credit purchase (not available on legacy Free tier). Learning `2026-03-09-external-api-scope-calibration.md` documents that Free tier is extremely limited.
- #127 merged -- community SKILL.md and x-community.sh exist (confirmed: already merged and closed)

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| X API credit cost higher than expected | Medium | Low | Default `max_results=10`, single fetch per session, no polling |
| Mentions endpoint deprecated or restructured | Low | High | Script returns clear API error; no silent failure |
| Rate limiting during reply posting | Low | Medium | `x_request` already handles 429 with retry |

## Semver Intent

`semver:minor` -- new sub-command (`engage`) in existing skill, new shell command (`fetch-mentions`).

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/community/scripts/x-community.sh` | Add `cmd_fetch_mentions`, `get_authenticated_user_id` functions |
| `plugins/soleur/skills/community/SKILL.md` | Add `engage` sub-command section, update sub-command menu |
| `plugins/soleur/agents/support/community-manager.md` | Add Capability 4: Mention Engagement |
| `.gitignore` | Add `.soleur/` if not present |
| `test/x-community.test.ts` | Tests for `fetch-mentions` command parsing and error handling |

## References

- `plugins/soleur/skills/community/SKILL.md` -- existing community skill structure
- `plugins/soleur/skills/community/scripts/x-community.sh` -- existing X API wrapper with OAuth 1.0a
- `plugins/soleur/agents/support/community-manager.md` -- existing community-manager agent
- `knowledge-base/overview/brand-guide.md` ## Channel Notes > ### X/Twitter -- brand voice for replies
- `knowledge-base/learnings/2026-03-09-external-api-scope-calibration.md` -- X API tier constraints
- `knowledge-base/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md` -- error handling patterns
- X API docs: `GET /2/users/{id}/mentions` -- https://docs.x.com/x-api/users/get-mentions
- Issue: #469
- Parent: #127 (closed)
