---
title: "Plausible Goals API Provisioning & Review-Driven Hardening"
date: 2026-03-13
category: integration-issues
tags: [plausible, analytics, goals-api, api-hardening, bash, curl, review-driven]
module: scripts
---

# Learning: Plausible Goals API Provisioning & Review-Driven Hardening

## Problem

A provisioning script for Plausible Analytics conversion goals (PUT /api/v1/sites/goals) was implemented with a 5-layer API hardening pattern but contained structural issues that only surfaced during multi-agent review: duplicated HTTP functions, scattered temp file cleanup, and missing input validation on the base URL and site ID.

## Solution

Refactored to a single `api_request()` function that accepts method, endpoint, and optional payload:

1. **DRY: Unified api_put/api_get into api_request()** -- method parameter drives PUT-specific headers; shared status handling eliminated ~50 lines of duplication
2. **Trap-based temp file cleanup** -- `trap 'rm -f "$response_file"' RETURN` replaces 7 scattered `rm -f` calls
3. **HTTPS validation** -- rejects non-HTTPS base URLs before any curl call transmits the Bearer token
4. **Site ID format validation** -- restricts to `[a-zA-Z0-9._-]+` preventing injection in URL construction
5. **umask 077** -- ensures temp files are owner-readable only
6. **provision_goal() simplified** -- 2 arguments instead of 3, with unknown goal_type producing explicit error

The Plausible Goals API uses PUT with upsert semantics (find-or-create), making the script safely idempotent.

## Session Errors

1. `soleur:plan_review` skill not available during planning phase (skipped, non-blocking)
2. `setup-ralph-loop.sh` wrong path on first attempt (fell back to correct path)
3. `shellcheck` not installed (fell back to `bash -n` syntax validation)
4. `worktree-manager.sh cleanup-merged` failed from bare repo root (`fatal: this operation must be run in a work tree`)

## Key Insight

Multi-agent review adds disproportionate value even on small scripts. Five review agents independently converged on the same primary finding (DRY violation), and the review phase produced more lines changed than the initial implementation. The review-to-implementation effort ratio was ~1:1, but the resulting script was 45 lines shorter and significantly more secure.

## Related

- Parent issue: #575 (Plausible analytics operationalization)
- This issue: #578 (configure Plausible dashboard goals)
- Related learning: `2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Related learning: `2026-03-13-shell-script-defensive-patterns.md`
- Sibling script: `scripts/weekly-analytics.sh`

## Tags

category: integration-issues
module: scripts
