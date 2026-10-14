---
title: "feat: Add programmatic no-post guards to x-community.sh and bsky-community.sh"
type: feat
date: 2026-03-15
semver: patch
deepened: 2026-03-15
---

# feat: Add programmatic no-post guards to x-community.sh and bsky-community.sh

## Enhancement Summary

**Deepened on:** 2026-03-15
**Sections enhanced:** 4 (Technical Considerations, Edge Cases, Test Scenarios, Proposed Solution)

### Key Improvements

1. Identified engage flow impact -- interactive `community engage` sub-command routes through `community-router.sh` to posting functions, requiring `*_ALLOW_POST=true` for legitimate local use
2. Verified content-publisher.sh call sites (lines 252 and 281) that would break without `X_ALLOW_POST=true` in the workflow
3. Discovered monitoring workflow does not pass Bluesky credentials at all -- `BSKY_ALLOW_POST` guard is purely preventive for future credential addition
4. Confirmed existing test infrastructure: `test/x-community.test.ts` exists (no post tests yet), no bsky test file exists

### Relevant Learnings Applied

- `2026-03-15-env-var-post-guard-defense-in-depth.md` -- Exact pattern to replicate (strict equality, `return 1`, guard placement before args)
- `2026-03-14-content-publisher-channel-extension-pattern.md` -- Content publisher touchpoints and channel dispatch pattern
- `2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md` -- `BASH_SOURCE` guard pattern for test harness sourcing

## Overview

Add `X_ALLOW_POST=true` and `BSKY_ALLOW_POST=true` environment variable guards to the posting functions in `x-community.sh` and `bsky-community.sh`, replicating the defense-in-depth pattern established in `linkedin-community.sh` (PR #623). This prevents autonomous posting by LLM agents during monitoring workflows, regardless of prompt instructions.

Closes #629.

## Problem Statement

Agent prompt instructions are soft guards -- they work when the agent cooperates and fail silently when it does not. Two posting functions currently lack programmatic barriers:

1. **`cmd_post_tweet()` in `x-community.sh`** -- Currently protected only by X API Free tier HTTP 403, which is an accidental guard that vanishes if the account is upgraded to a paid tier.
2. **`cmd_post()` in `bsky-community.sh`** -- Has zero safety guards. The monitoring workflow sets `BSKY_HANDLE` and `BSKY_APP_PASSWORD`, so an agent hallucinating a post command would succeed.

## Proposed Solution

Add an environment variable check as the first statement in each posting function, following the exact pattern from `linkedin-community.sh:cmd_post_content()`:

### x-community.sh -- `cmd_post_tweet()` (line 563)

```bash
cmd_post_tweet() {
  # Guard: require explicit opt-in to post.
  if [[ "${X_ALLOW_POST:-}" != "true" ]]; then
    echo "Error: X_ALLOW_POST is not set to 'true'." >&2
    echo "Set X_ALLOW_POST=true to enable posting." >&2
    return 1
  fi
  # ... existing implementation unchanged
```

`return 1` is correct here because x-community.sh has a `BASH_SOURCE` guard (line 639) that enables sourcing for test harnesses.

### bsky-community.sh -- `cmd_post()` (line 230)

```bash
cmd_post() {
  # Guard: require explicit opt-in to post.
  if [[ "${BSKY_ALLOW_POST:-}" != "true" ]]; then
    echo "Error: BSKY_ALLOW_POST is not set to 'true'." >&2
    echo "Set BSKY_ALLOW_POST=true to enable posting." >&2
    return 1
  fi
  # ... existing implementation unchanged
```

Note: `bsky-community.sh` currently lacks a `BASH_SOURCE` guard (line 412 uses bare `main "$@"`). The guard should be added for consistency with x-community.sh and linkedin-community.sh, and `return 1` should be used in the post guard for consistency. Without the `BASH_SOURCE` guard, `return 1` inside a function called from `main` would propagate up and cause exit 1 in direct execution mode (which is the desired behavior). If the script is later sourced for testing, `return 1` is also correct.

### Collateral changes

1. **Script header documentation** -- Add `X_ALLOW_POST` and `BSKY_ALLOW_POST` to the environment variable documentation blocks in each script's header comment.
2. **SKILL.md update** -- Add notes about the post guards to `plugins/soleur/skills/community/SKILL.md` (similar to the LinkedIn note added in #623).
3. **BASH_SOURCE guard for bsky-community.sh** -- Add the standard `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` guard for test harness consistency.
4. **Workflow verification** -- Confirm `scheduled-community-monitor.yml` does NOT set `X_ALLOW_POST` or `BSKY_ALLOW_POST`. Confirm `scheduled-content-publisher.yml` sets `X_ALLOW_POST=true` (it uses x-community.sh for posting via content-publisher.sh). Bluesky is not yet in the content publisher, so no workflow change needed for `BSKY_ALLOW_POST`.

### What NOT to change

- **`scheduled-community-monitor.yml`** -- Must NOT set any `*_ALLOW_POST` variable. This is the whole point: monitoring workflows cannot post.
- **`scheduled-content-publisher.yml` for Bluesky** -- `content-publisher.sh` has no Bluesky channel support yet. Adding `BSKY_ALLOW_POST=true` would be dead code.
- **`scheduled-content-publisher.yml` for X** -- The content publisher calls `x-community.sh post-tweet` via `content-publisher.sh`. This workflow MUST set `X_ALLOW_POST=true` in its env block, otherwise existing content publishing breaks. This is the one workflow change required.

## Technical Considerations

- **Strict string equality** (`!= "true"`) prevents accidental enabling via empty string, `"1"`, `"TRUE"`, or any other truthy-looking value.
- **`return 1` vs `exit 1`** -- `return 1` is preferred because it works correctly both when the script is executed directly (propagates exit code) and when sourced for testing (does not kill the test shell).
- **Guard placement** -- The check goes before argument parsing. No point validating arguments if posting is not allowed.

### Research Insights

**Engage flow impact:** The `community engage` sub-command in SKILL.md routes replies through `community-router.sh x post-tweet --reply-to <id>` (line 96) and `community-router.sh bsky post "<text>" --reply-to-uri ...` (line 119). The router dispatches to the underlying scripts, so the guard applies. Users running `engage` locally must set `X_ALLOW_POST=true` or `BSKY_ALLOW_POST=true` in their environment. This is intentional -- the guard creates a two-key system even for interactive flows, preventing accidental posting from misconfigured terminals.

**Monitoring workflow credential inventory:** `scheduled-community-monitor.yml` (lines 50-58) passes X credentials (`X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`) and LinkedIn credentials, but does NOT pass Bluesky credentials (`BSKY_HANDLE`, `BSKY_APP_PASSWORD`). The `BSKY_ALLOW_POST` guard is preventive -- it protects against future credential addition without a corresponding audit of the monitoring workflow's capabilities.

**Content-publisher caller analysis:** `scripts/content-publisher.sh` calls `x-community.sh post-tweet` at two locations: line 252 (hook tweet) and line 281 (reply thread tweets). Both call sites pass the result through `post_request` error handling. The `X_ALLOW_POST` guard fires before any of this, so `return 1` propagates cleanly as exit code 1, which content-publisher.sh already handles via its `|| { ... }` error pattern.

**Test infrastructure:** `test/x-community.test.ts` exists with `FAKE_CREDS_ENV` fixture but has no post-tweet tests. No `test/bsky-community.test.ts` exists. Post guard tests can be added as simple exec-and-check-exit-code tests without network access.

## Acceptance Criteria

- [x] `cmd_post_tweet()` in `x-community.sh` checks `X_ALLOW_POST` before any posting logic
- [x] `cmd_post()` in `bsky-community.sh` checks `BSKY_ALLOW_POST` before any posting logic
- [x] Both guards use strict string equality (`!= "true"`) with `${VAR:-}` default
- [x] Both guards use `return 1` (not `exit 1`)
- [x] Script header comments document the new env vars
- [x] `bsky-community.sh` has `BASH_SOURCE` guard added for test harness support
- [x] `scheduled-community-monitor.yml` does NOT set `X_ALLOW_POST` or `BSKY_ALLOW_POST`
- [x] `scheduled-content-publisher.yml` sets `X_ALLOW_POST=true` in the publish step's env block
- [x] SKILL.md updated with post guard notes for X and Bluesky
- [x] Guard messages reference the variable name so operators know how to enable posting

## Test Scenarios

- Given `X_ALLOW_POST` is unset, when `x-community.sh post-tweet "test"`, then exit code 1 with "X_ALLOW_POST is not set" message to stderr
- Given `X_ALLOW_POST=false`, when `x-community.sh post-tweet "test"`, then exit code 1 with guard message
- Given `X_ALLOW_POST=true` and valid credentials, when `x-community.sh post-tweet "test"`, then post proceeds normally
- Given `BSKY_ALLOW_POST` is unset, when `bsky-community.sh post "test"`, then exit code 1 with "BSKY_ALLOW_POST is not set" message to stderr
- Given `BSKY_ALLOW_POST=false`, when `bsky-community.sh post "test"`, then exit code 1 with guard message
- Given `BSKY_ALLOW_POST=true` and valid credentials, when `bsky-community.sh post "test"`, then post proceeds normally
- Given monitoring workflow runs (no `*_ALLOW_POST` in env), when agent calls posting commands, then posts are blocked regardless of prompt instructions
- Given content publisher workflow runs (has `X_ALLOW_POST=true`), when content-publisher.sh calls `x-community.sh post-tweet`, then post proceeds normally

## Edge Cases

| Scenario | Expected Behavior | Mitigation |
|----------|------------------|------------|
| Content-publisher.sh lacks `X_ALLOW_POST=true` | X posting silently fails in content publisher | Add `X_ALLOW_POST=true` to `scheduled-content-publisher.yml` env block |
| Bluesky added to content-publisher later | Posting would fail without `BSKY_ALLOW_POST=true` | Document with `TODO(#nnn)` for future content-publisher Bluesky support |
| `BASH_SOURCE` guard breaks existing bsky-community.sh callers | No breakage -- `main "$@"` still runs on direct execution | The guard is strictly additive; `if [[ BASH_SOURCE == $0 ]]; then main "$@"; fi` is equivalent to bare `main "$@"` when not sourced |
| User runs `community engage` without `*_ALLOW_POST=true` | Engage flow blocks at the post step after user approves a reply | Guard error message tells user exactly which variable to set; engage session can resume |
| `scheduled-campaign-calendar.yml` uses X posting | Not affected -- verified no post commands | Confirmed: workflow does not reference `x-community.sh` or `bsky-community.sh` |

## Non-goals

- Adding guards to read-only commands (fetch-metrics, fetch-mentions, etc.) -- these are safe for monitoring
- Adding Bluesky to the content-publisher workflow -- that is a separate feature
- Adding guards to discord-community.sh -- Discord webhook posting is a different pattern (no script-level post function)

## References

- LinkedIn guard PR: #623
- Pattern source: `plugins/soleur/skills/community/scripts/linkedin-community.sh:cmd_post_content()` (lines 225-229 in feat-linkedin-post-guard branch)
- Learning: `knowledge-base/project/learnings/2026-03-15-env-var-post-guard-defense-in-depth.md`
- Files to modify:
  - `plugins/soleur/skills/community/scripts/x-community.sh` (line 563: `cmd_post_tweet()`)
  - `plugins/soleur/skills/community/scripts/bsky-community.sh` (line 230: `cmd_post()`, line 412: add `BASH_SOURCE` guard)
  - `plugins/soleur/skills/community/SKILL.md` (add post guard notes)
  - `.github/workflows/scheduled-content-publisher.yml` (add `X_ALLOW_POST: "true"` to env block)
- Workflows to verify unchanged:
  - `.github/workflows/scheduled-community-monitor.yml` (must NOT have `*_ALLOW_POST`)
