---
title: "fix: cmd_fetch_metrics bypasses x_request() hardening"
type: fix
date: 2026-03-12
status: already-fixed
semver: patch
---

# fix(community): cmd_fetch_metrics bypasses x_request() hardening

Closes #478

## Overview

Issue #478 reported that `cmd_fetch_metrics` in `x-community.sh` manually constructed its own curl call instead of using the shared `get_request()` / `handle_response()` pipeline. This meant it lacked retry logic for 429 responses, JSON validation on 2xx responses, and the `retry_after` clamping (1-60s range) added in PR #477.

## Status: Already Fixed

**This issue was resolved by PR #500** (commit `dcd8f7e`, merged 2026-03-10), titled "refactor(community): unify get_request and x_request response handling (#492)".

### Evidence

**Before fix** (at PR #477 state, commit `bcf6bb7`), `cmd_fetch_metrics` (lines 253-298):

- Manually called `oauth_sign()` and `curl` directly
- Used a bare `case` block for HTTP status handling
- Had no retry logic for 429 (hard-exited with `exit 2`)
- Had no JSON validation on 2xx responses
- Had no `retry_after` clamping

**After fix** (current `main`, lines 354-365):

- Calls `get_request "/2/users/me" "user.fields=public_metrics,description,created_at"`
- `get_request()` handles OAuth signing with query parameters included in the signature
- Delegates to `handle_response()` which provides:
  - 429 retry logic with depth-limited retries (up to 3 attempts)
  - JSON validation via `jq .` on all 2xx responses
  - `retry_after` clamping to [1, 60] range (from PR #477)

### How the fix was implemented

PR #500 introduced `get_request()` (lines 287-333) which:

1. Accepts `endpoint`, `query_params`, and `depth` arguments
2. Splits `query_params` on `&` and passes them as varargs to `oauth_sign()` for correct OAuth signature computation
3. Appends `query_params` as a query string to the request URL
4. Delegates response handling to the shared `handle_response()` function

This is exactly the approach proposed in Issue #478: "Extend `x_request()` to support query parameters for OAuth signing, then rewrite `cmd_fetch_metrics` to use `x_request()`."

## Acceptance Criteria

- [x] `cmd_fetch_metrics` uses `get_request()` instead of manual curl
- [x] Query parameters are included in OAuth signature computation
- [x] 429 responses trigger retry logic with depth limiting
- [x] 2xx responses are validated as JSON before output
- [x] `retry_after` values are clamped to [1, 60] range

## Test Scenarios

- Given a 429 response from `/2/users/me`, when `cmd_fetch_metrics` is called, then it retries up to 3 times with clamped `retry_after` delay
- Given a 2xx response with malformed JSON, when `cmd_fetch_metrics` is called, then it exits with an error about malformed JSON
- Given a 401 response, when `cmd_fetch_metrics` is called, then it prints credential regeneration instructions

## Recommended Action

Close Issue #478 as already fixed. The bot comment from 2026-03-11 correctly identified this.

## References

- Issue: #478
- Fix PR: #500 (commit `dcd8f7e`)
- Origin PR: #477 (commit `bcf6bb7`) -- where the issue was originally found
- File: `plugins/soleur/skills/community/scripts/x-community.sh`
