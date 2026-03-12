---
title: "fix: cmd_fetch_metrics bypasses x_request() hardening"
type: fix
date: 2026-03-12
status: already-fixed
deepened: 2026-03-12
semver: patch
---

# fix(community): cmd_fetch_metrics bypasses x_request() hardening

Closes #478

## Enhancement Summary

**Deepened on:** 2026-03-12
**Sections enhanced:** 3 (Evidence, Test Scenarios, Recommended Action)
**Research performed:** Source code audit of current `x-community.sh`, test suite review, git history tracing

### Key Findings
1. Issue #478 was already fixed by PR #500 (merged 2026-03-10) -- no implementation work needed
2. Test coverage gap: `handle_response` 429 retry path has no automated test (only 2xx, 401, 403, 5xx are tested)
3. Test coverage gap: `get_request()` and `cmd_fetch_metrics` have no dedicated tests -- only integration-level tests for `fetch-mentions` exist

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

### Verification Audit

**Code path audit** (2026-03-12): Traced the full call chain to confirm all three hardening properties propagate correctly:

| Property | Function | Line(s) | Status |
|---|---|---|---|
| 429 retry with depth limit | `handle_response()` | 211-227 | Verified: sleeps `retry_after`, invokes `retry_cmd` |
| JSON validation on 2xx | `handle_response()` | 178-184 | Verified: `jq .` validates before echoing |
| `retry_after` clamping [1,60] | `handle_response()` | 214-223 | Verified: `printf %.0f` + arithmetic clamp |
| Query params in OAuth sig | `get_request()` | 301-308 | Verified: splits on `&`, passes to `oauth_sign()` |
| Depth exhaustion guard | `get_request()` | 292-295 | Verified: exits 2 at depth >= 3 |

**Other commands also use `get_request()`**: `cmd_fetch_mentions` (line 424), `cmd_fetch_timeline` (line 496), and `resolve_user_id` (line 338) all route through the same hardened path. The unification is complete.

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

### Test Coverage Analysis

**Existing test coverage** in `test/x-community.test.ts` and `test/helpers/test-handle-response.sh`:

| Test Area | Covered | Notes |
|---|---|---|
| `handle_response` 2xx valid JSON | Yes | Lines 250-262 |
| `handle_response` 2xx malformed JSON | Yes | Lines 264-274 |
| `handle_response` 401 | Yes | Lines 277-289 |
| `handle_response` 403 (3 variants) | Yes | Lines 292-331 |
| `handle_response` 5xx default | Yes | Lines 334-359 |
| `handle_response` 429 retry | **No** | Retry invokes `retry_cmd` which requires mocking `sleep` |
| `get_request()` query param splitting | **No** | Would require mocking curl and OAuth |
| `cmd_fetch_metrics` end-to-end | **No** | Would require mocking X API responses |
| `x_request` rename verification | Yes | Lines 366-376 |

**Gaps worth tracking:** The 429 retry path and `get_request()` query param OAuth signing are untested. These are the exact properties Issue #478 was concerned about. Consider filing a separate issue to add 429 retry tests (likely using the existing `test-handle-response.sh` harness with a counter script as `retry_cmd`).

## Recommended Action

1. **Close Issue #478** as already fixed by PR #500. The bot comment from 2026-03-11 correctly identified this.
2. **Consider filing a follow-up issue** for 429 retry test coverage -- the hardening exists in code but has no automated regression test.

## Non-goals

- Re-implementing any part of the fix (it is complete and correct)
- Changing `handle_response()`, `get_request()`, or `cmd_fetch_metrics()` behavior
- Adding tests in this branch (test gaps are a separate concern from the bug fix)

## References

- Issue: #478
- Fix PR: #500 (commit `dcd8f7e`)
- Origin PR: #477 (commit `bcf6bb7`) -- where the issue was originally found
- File: `plugins/soleur/skills/community/scripts/x-community.sh`
- Test file: `test/x-community.test.ts`
- Test helper: `test/helpers/test-handle-response.sh`
