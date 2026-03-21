---
title: "feat(community): add engage sub-command for X mention engagement"
type: feat
date: 2026-03-10
---

# feat(community): add engage sub-command for X mention engagement

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 8
**Research sources:** X API v2 live documentation, 8 institutional learnings, constitution.md, existing codebase patterns

### Key Improvements

1. OAuth 1.0a signing for query params must match `cmd_fetch_metrics` pattern exactly -- query params go into signature base string, then appended to URL separately
2. Mentions endpoint caps at 800 most recent posts and returns empty (not error) beyond volume limits -- handle gracefully
3. Retweets over 140 characters appear truncated; need `referenced_tweets.id` expansion to get full text of quote tweets mentioning the account
4. Since-id state file must use `chmod 600` before writing (token-env-var learning pattern)
5. Agent markdown must avoid `$()` in bash blocks (command-substitution learning) -- use prose placeholders instead

### Applied Learnings

- `2026-03-09-shell-api-wrapper-hardening-patterns.md` -- 5-layer defense for API wrappers
- `2026-03-09-external-api-scope-calibration.md` -- verify API capabilities before spec
- `2026-03-09-depth-limited-api-retry-pattern.md` -- retry depth limit (already in `x_request`)
- `2026-03-03-headless-mode-skill-bypass-convention.md` -- `--headless` flag stripping and forwarding
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- `${N:-}` guards for optional args
- `2026-02-18-token-env-var-not-cli-arg.md` -- secrets via env vars, curl stderr suppression
- `2026-02-12-brand-guide-contract-and-inline-validation.md` -- inline brand voice validation
- `2026-02-22-command-substitution-in-plugin-markdown.md` -- no `$()` in agent/skill markdown
- `2026-03-10-require-jq-startup-check-consistency.md` -- startup check parity across script family

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

### Research Insights: Architecture

**Best Practices:**

- The brand guide inline validation pattern (learning `2026-02-12`) is the correct approach: read `## Voice` and `## Channel Notes > ### X/Twitter` directly in the agent, do not create a separate brand-voice-reviewer agent
- Skill-to-agent invocation is the established pattern: SKILL.md spawns `community-manager` agent, which does the actual work. The skill handles platform detection and argument parsing only

**Edge Cases:**

- If `knowledge-base/overview/brand-guide.md` does not exist, the agent should still draft replies but warn that brand voice alignment is not available. Do not block engagement on brand guide absence.

### X API Details

**Endpoint:** `GET /2/users/{id}/mentions`

- **Authentication:** OAuth 1.0a User Context (already implemented in `x-community.sh`)
- **Pricing:** Pay-per-use credits (not available on legacy Free tier -- requires credit purchase). X API v2 uses a credit-based system where credits are deducted per request, with deduplication (same resource within 24h charged once).
- **Parameters used:** `max_results` (default 10, range 5-100), `since_id` (track last processed), `tweet.fields=author_id,created_at,conversation_id`, `expansions=author_id`, `user.fields=username,name`
- **Rate limits:** Credit-based; the command fetches once per invocation (not polling)
- **Response:** `{ data: [Tweet], includes: { users: [User] }, meta: { newest_id, oldest_id, result_count, next_token } }`
- **Volume cap:** 800 most recent mentions maximum. Requesting beyond returns empty results, not errors.

### Research Insights: X API

**Best Practices (from live X API docs):**

- Include `conversation_id` in `tweet.fields` to enable threaded reply context -- helps the agent understand whether a mention is part of an existing conversation or a standalone mention
- Use `since_id` for incremental fetching rather than `start_time` -- ID-based filtering is more precise and avoids timezone edge cases
- Retweets over 140 characters appear truncated in the response. Add `referenced_tweets.id` to `expansions` if full quote-tweet text is needed. For v1, skip this -- truncated text is sufficient for reply context.
- The `next_token` in `meta` enables pagination. For v1, do not paginate (single fetch of max 10). Pagination adds complexity without clear user value at this volume.
- Non-public metrics (impression_count, etc.) require author authentication and only work within 30 days. Do not request `non_public_metrics` -- use `public_metrics` only.

**Pitfalls:**

- The mentions endpoint returns tweets that **mention** the authenticated user, not tweets **by** the user. This is the correct behavior for engagement.
- Empty data arrays mean no mentions in the requested range -- return cleanly, do not treat as error.
- The `includes.users` array may not have a 1:1 mapping with mentions if the same user mentioned the account multiple times. Match by `author_id` field, not by array index.

### Ownership Boundary

- `community engage` = fetch mentions + draft replies + post replies (this feature)
- `social-distribute` = broadcast blog articles to multiple platforms (unchanged)
- `community digest/health` = read-only monitoring (unchanged)

## Technical Considerations

### 1. x-community.sh fetch-mentions command

Add a new `cmd_fetch_mentions` function to `plugins/soleur/skills/community/scripts/x-community.sh`.

**Input:** Optional `--max-results N` (default 10, validate range 5-100), optional `--since-id ID` (validate numeric).

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

### Research Insights: fetch-mentions Implementation

**OAuth 1.0a Signing Pattern (from existing `cmd_fetch_metrics`):**

The `cmd_fetch_metrics` function demonstrates the pattern for signing GET requests with query params:

1. Build query string params as individual `key=value` strings
2. Pass them to `oauth_sign` as additional arguments (after method and URL)
3. `oauth_sign` includes them in the signature base string alongside the OAuth params
4. Append the query string to the URL separately for the actual curl call

This is critical: query params must be in the signature but also in the URL. Double-check this by reading `cmd_fetch_metrics` as the reference implementation.

**Shell Hardening Checklist (from learning `2026-03-09-shell-api-wrapper-hardening-patterns.md`):**

| Layer | Defense | Implementation |
|-------|---------|----------------|
| Input | Validate `--max-results` is numeric 5-100, `--since-id` is numeric | `[[ "$val" =~ ^[0-9]+$ ]]` check at entry |
| Transport | curl stderr suppression | `2>/dev/null` on curl (already in `x_request`) |
| Response parsing | Validate JSON on 2xx | `jq . >/dev/null 2>&1` check (already in `x_request`) |
| Error extraction | jq fallback chain | `jq -r '... // "fallback"' 2>/dev/null \|\| echo "fallback"` |
| Retry arithmetic | Not applicable (no float retry_after from X API mentions) | N/A |

**`set -euo pipefail` Compliance (from learning `2026-03-03`):**

- Use `${1:-}` for optional positional args in the dispatch case statement
- Any grep in pipelines must append `|| true` to handle no-match case
- The since-id file read should use `cat ... 2>/dev/null || true` for missing file

**Startup Check Parity (from learning `2026-03-10`):**

The new `fetch-mentions` command goes through `main()` which already calls `require_jq`, `require_openssl`, and `require_credentials`. No additional startup checks needed -- the existing guards cover the new command path.

### 2. User ID Resolution

The mentions endpoint requires a numeric user ID, not a username. The `cmd_fetch_metrics` function already calls `GET /2/users/me` which returns the authenticated user's ID. Extract and cache this ID for the mentions call.

Add a helper function `get_authenticated_user_id` that calls `/2/users/me` and returns only the ID. This avoids duplicating the metrics call logic.

### Research Insights: User ID Resolution

**Implementation detail:** The `get_authenticated_user_id` function should:

1. Call `oauth_sign "GET" "${X_API}/2/users/me"` (no additional params needed for this endpoint)
2. Make the curl call with the signed Authorization header
3. Extract `.data.id` via jq
4. Print only the ID to stdout (no JSON wrapper)
5. Use the same error handling as `x_request` (401, 403, 429)

**Gotcha:** Do not cache the user ID in a variable across commands. Each invocation of `x-community.sh` is a fresh shell process. The helper function is called once per `fetch-mentions` invocation, which is acceptable (one extra API call per session).

### 3. Since-ID State File

To avoid re-processing mentions, store the `newest_id` from the last fetch in a state file:

- Path: `.soleur/x-engage-since-id` (relative to repo root, resolved via `git rev-parse --show-toplevel`)
- Format: plain text, single line containing the tweet ID
- Created on first run, updated after each successful engagement session
- Add `.soleur/` to `.gitignore` if not already present

This is optional for v1 -- the skill can run without it (processes last 10 mentions). But including it prevents duplicate engagement on repeated runs within the same day.

### Research Insights: Since-ID State

**Best Practices:**

- Resolve repo root with `git rev-parse --show-toplevel` (same pattern as `x-setup.sh` after the path fix documented in learning `2026-03-09-x-provisioning-playwright-automation.md`)
- Create the `.soleur/` directory with `mkdir -p` before writing
- Set file permissions with `chmod 600` before writing content (learning `2026-02-18-token-env-var-not-cli-arg.md` -- while not a secret, applying secure defaults to local state files is good practice)
- Read with fallback: `cat "${repo_root}/.soleur/x-engage-since-id" 2>/dev/null || true` -- missing file is normal on first run

**State update timing:** Write the since-id ONLY after all mentions have been processed (not after each individual reply). If the session is interrupted mid-way, the next run will re-fetch and re-present already-processed mentions. This is safer than potentially skipping mentions that were fetched but not acted on.

**Edge case:** If the since-id file contains a non-numeric value (corruption), treat it as missing and fetch last 10 mentions. Validate with `[[ "$since_id" =~ ^[0-9]+$ ]]`.

### 4. Brand Voice Draft Generation

The community-manager agent reads `knowledge-base/overview/brand-guide.md` sections:

- `## Voice` -- overall brand voice
- `## Channel Notes > ### X/Twitter` -- X-specific tone: "Declarative, concrete, no hedging"

The agent drafts replies within 280 characters, following the brand guide's instruction that "Every tweet should read like a statement, not a question."

### Research Insights: Brand Voice

**From brand-guide.md `### X/Twitter` section:**

- Full brand voice: "Declarative, concrete, no hedging. Every tweet should read like a statement, not a question."
- Hook-first: "the first tweet must deliver a complete, compelling idea that works even if nobody clicks 'Show more.'"
- No "I just wrote about..." openers
- 280-character limit enforced per tweet during generation, not as a post-hoc trim

**Inline validation pattern (learning `2026-02-12`):**

- Read the brand guide headings directly in the agent context
- Validate the draft against `## Voice` do's/don'ts before presenting to user
- No separate brand-voice-reviewer agent needed -- inline validation is faster and simpler

**Draft quality guidelines:**

- Address the mention's question or statement directly
- Include a concrete actionable next step when applicable (e.g., "Run `/soleur:community platforms` to check your setup")
- Do not start with "Thanks for reaching out" or similar pleasantries -- brand voice is declarative
- Do not use hashtags in replies unless the original mention uses them
- Count characters before presenting to user -- reject and redraft if over 280

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

### Research Insights: Approval Flow

**Headless mode convention (learning `2026-03-03`):**

- Strip `--headless` from `$ARGUMENTS` before processing remaining args
- Forward `--headless` to any child Skill tool invocations
- In headless mode: skip all mentions with a summary message ("Skipped N mentions in headless mode -- engage requires interactive approval")
- Safety constraints (platform detection, credential validation) still run in headless mode

**Edit flow detail:**
When user selects "Edit", present a free-text input prompt. The agent should:

1. Accept the user's edited text
2. Validate it is within 280 characters
3. If over 280: report the character count and ask for a shorter version
4. If valid: proceed as if "Accept" was selected

**Skip-all option:**
After presenting the first mention, add a 4th option: "Skip all remaining -- end session". This prevents the user from having to Skip through many irrelevant mentions one by one.

### 6. Security Considerations

- No new credentials required -- reuses existing X API credentials from env vars
- Reply text is user-approved before posting (no autonomous engagement)
- No raw mention content stored to files -- only the since-id state
- OAuth 1.0a signing already handles credential security
- curl stderr suppression already in place to prevent token leakage

### Research Insights: Security

**From learning `2026-02-18-token-env-var-not-cli-arg.md`:**

- The since-id is not a secret, but the `.soleur/` directory could later hold other local state. Adding it to `.gitignore` prevents accidental commit of any future sensitive state.
- Never echo token values in error messages -- the existing `x_request` function already follows this pattern.

**From learning `2026-03-09-shell-api-wrapper-hardening-patterns.md`:**

- The `cmd_fetch_mentions` function inherits all 5 hardening layers from `x_request` -- no additional security measures needed at the command level.
- Input validation on `--since-id` and `--max-results` prevents URL path injection (same pattern as snowflake ID validation in Discord scripts).

**Agent markdown security (learning `2026-02-22-command-substitution-in-plugin-markdown.md`):**

- The Capability 4 section in `community-manager.md` must NOT use `$()` in bash code blocks
- Use angle-bracket prose placeholders (e.g., `<user_id>`, `<since_id>`) with substitution instructions instead
- Or use separate bash blocks for each individual command

## Non-Goals

- Autonomous/scheduled engagement (no cron, no headless posting)
- Sentiment analysis or filtering of mentions
- DM engagement (mentions only)
- Multi-account support
- Rate limit credit tracking or budget management
- Engagement analytics or reporting beyond the session summary
- Pagination through more than one page of mentions (v1 fetches a single page)

## Acceptance Criteria

- [ ] `x-community.sh fetch-mentions` returns recent mentions as JSON (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] `x-community.sh fetch-mentions --max-results 5` limits results (validates range 5-100)
- [ ] `x-community.sh fetch-mentions --since-id <id>` returns only newer mentions (validates numeric)
- [ ] `x-community.sh fetch-mentions` handles 401, 403, 429 errors with clear messages
- [ ] `x-community.sh fetch-mentions` handles empty data (no mentions) cleanly
- [ ] `/soleur:community engage` detects X platform and reports status
- [ ] `/soleur:community engage` fetches mentions and presents each with a draft reply
- [ ] Draft replies follow brand guide voice and respect 280-character limit
- [ ] User can Accept, Edit, or Skip each draft
- [ ] "Skip all remaining" option available after first mention
- [ ] Accepted replies are posted via `x-community.sh post-tweet --reply-to`
- [ ] Session summary shows counts: processed, posted, skipped
- [ ] `--headless` mode skips all mentions without posting, with summary message
- [ ] `--since-id` state file persists between sessions (`.soleur/x-engage-since-id`)
- [ ] Since-id state file updated only after all mentions processed (not per-reply)
- [ ] community-manager agent documentation updated with Capability 4
- [ ] Agent markdown uses no `$()` command substitution in bash blocks

## Test Scenarios

### Happy Path

- Given X credentials are configured and mentions exist, when running `community engage`, then mentions are fetched and presented one at a time with draft replies
- Given a draft reply is accepted, when the user selects Accept, then the reply is posted via `post-tweet --reply-to` and the since-id state is updated after all mentions processed
- Given a draft reply is skipped, when the user selects Skip, then no reply is posted and the next mention is presented
- Given the user selects Edit, when they provide modified text within 280 characters, then the edited reply is posted

### Error Handling

- Given X credentials are not configured, when running `community engage`, then the skill reports "X/Twitter not configured" and stops
- Given the X API returns 401, when fetching mentions, then the error message includes credential regeneration instructions
- Given the X API returns 429, when fetching mentions, then `x_request` retries up to 3 times with clamped backoff
- Given no mentions exist, when running `community engage`, then the skill reports "No recent mentions found" and exits cleanly
- Given the brand guide does not exist, when drafting replies, then the agent warns about missing brand voice but proceeds with default professional tone

### Edge Cases

- Given `--headless` is passed, when running `community engage`, then all mentions are skipped with summary message (no posting)
- Given a since-id state file exists, when running `community engage`, then only mentions newer than the stored ID are fetched
- Given the since-id state file does not exist, when running `community engage`, then the last 10 mentions are fetched (default behavior)
- Given the since-id state file contains a non-numeric value, when running `community engage`, then it is treated as missing (fetch last 10)
- Given a mention text contains special characters (quotes, newlines, emoji), when drafting a reply, then the reply is properly JSON-escaped for the API call
- Given the same user mentions the account multiple times, when resolving author info from `includes.users`, then author matching uses `author_id` field (not array index)
- Given the user selects "Skip all remaining", when processing mentions, then all remaining are skipped and session summary is displayed
- Given an edit exceeds 280 characters, when the user submits it, then the character count is reported and re-edit is requested

### Shell Script Tests

- Given `x-community.sh fetch-mentions` is called without credentials, then it exits 1 with "Missing X API credentials"
- Given `x-community.sh fetch-mentions --max-results abc` is called, then it exits 1 with a usage error (non-numeric)
- Given `x-community.sh fetch-mentions --max-results 200` is called, then it exits 1 with range error (max 100)
- Given the API returns malformed JSON, then `fetch-mentions` exits 1 with "malformed JSON" error
- Given the API returns `{ "data": [] }` (empty mentions), then output is `{"mentions":[],"meta":{"result_count":0}}`
- Given `--since-id 12345` is passed, then the API call includes `since_id=12345` in query params and OAuth signature

## Dependencies & Risks

### Dependencies

- X API paid tier access -- mentions endpoint requires credit purchase (not available on legacy Free tier). Learning `2026-03-09-external-api-scope-calibration.md` documents that Free tier is extremely limited. X API v2 now uses pay-per-use credits with a monthly cap of 2M post reads.
- #127 merged -- community SKILL.md and x-community.sh exist (confirmed: already merged and closed)

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| X API credit cost higher than expected | Medium | Low | Default `max_results=10`, single fetch per session, no polling, 24h deduplication |
| Mentions endpoint deprecated or restructured | Low | High | Script returns clear API error; no silent failure |
| Rate limiting during reply posting | Low | Medium | `x_request` already handles 429 with depth-limited retry (3 max) |
| Mentions include spam/bot accounts | Medium | Low | User reviews every reply before posting; Skip option is prominent |
| OAuth signature mismatch on new endpoint | Medium | Medium | Follow `cmd_fetch_metrics` pattern exactly for query param signing |

## Semver Intent

`semver:minor` -- new sub-command (`engage`) in existing skill, new shell command (`fetch-mentions`).

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/community/scripts/x-community.sh` | Add `cmd_fetch_mentions`, `get_authenticated_user_id` functions, update usage text |
| `plugins/soleur/skills/community/SKILL.md` | Add `engage` sub-command section, update sub-command menu |
| `plugins/soleur/agents/support/community-manager.md` | Add Capability 4: Mention Engagement (no `$()` in bash blocks) |
| `.gitignore` | Add `.soleur/` if not present |
| `test/x-community.test.ts` | Tests for `fetch-mentions` command parsing, validation, and error handling |

## References

- `plugins/soleur/skills/community/SKILL.md` -- existing community skill structure
- `plugins/soleur/skills/community/scripts/x-community.sh` -- existing X API wrapper with OAuth 1.0a (reference: `cmd_fetch_metrics` for query param signing pattern)
- `plugins/soleur/agents/support/community-manager.md` -- existing community-manager agent
- `knowledge-base/overview/brand-guide.md` `## Channel Notes > ### X/Twitter` -- brand voice for replies
- `knowledge-base/project/learnings/2026-03-09-external-api-scope-calibration.md` -- X API tier constraints
- `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md` -- 5-layer error handling
- `knowledge-base/project/learnings/2026-03-09-depth-limited-api-retry-pattern.md` -- retry depth limit
- `knowledge-base/project/learnings/2026-03-03-headless-mode-skill-bypass-convention.md` -- headless flag convention
- `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- strict mode guards
- `knowledge-base/project/learnings/2026-02-18-token-env-var-not-cli-arg.md` -- secret handling patterns
- `knowledge-base/project/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` -- inline brand validation
- `knowledge-base/project/learnings/2026-02-22-command-substitution-in-plugin-markdown.md` -- no `$()` in markdown
- `knowledge-base/project/learnings/2026-03-10-require-jq-startup-check-consistency.md` -- startup check parity
- X API docs: `GET /2/users/{id}/mentions` -- <https://docs.x.com/x-api/users/get-mentions>
- X API timelines integration guide -- <https://docs.x.com/x-api/posts/timelines/integrate>
- Issue: #469
- Parent: #127 (closed)
