---
title: LinkedIn company page posts fail with HTTP 400 when LINKEDIN_ORG_ACCESS_TOKEN is unset
date: 2026-04-26
category: integration-issues
tags: [linkedin, content-publisher, credentials, api-errors]
issue: 2354
---

# Learning: LinkedIn org token fallback produces silent HTTP 400

## Problem

The content publisher failed to post to the LinkedIn Company Page for a scheduled blog post. The error was:

```
LinkedIn API returned HTTP 400 for /rest/posts: Organization permissions must be used when using organization as author
```

The fallback issue created by the publisher (GitHub issue 2354) required manual posting.

## Root Cause

In `plugins/soleur/skills/community/scripts/linkedin-community.sh`, `cmd_post_content` had a silent fallback:

```bash
# if set, otherwise fall back to LINKEDIN_ACCESS_TOKEN (which will likely 400).
if [[ "$author" == urn:li:organization:* ]] && [[ -n "${LINKEDIN_ORG_ACCESS_TOKEN:-}" ]]; then
  LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"
fi
```

When `LINKEDIN_ORG_ACCESS_TOKEN` was not configured in Doppler, the condition was false and the code silently fell through to using `LINKEDIN_ACCESS_TOKEN` (the personal token). LinkedIn's API requires the `w_organization_social` OAuth scope for organization posts — the personal token always produces HTTP 400 in this case. The comment even acknowledged "which will likely 400" but allowed the fallback anyway.

## Solution

Replace the silent fallback with an early-exit error when org author is used without `LINKEDIN_ORG_ACCESS_TOKEN`:

```bash
# Organization posts require w_organization_social scope -- use LINKEDIN_ORG_ACCESS_TOKEN.
if [[ "$author" == urn:li:organization:* ]]; then
  if [[ -z "${LINKEDIN_ORG_ACCESS_TOKEN:-}" ]]; then
    echo "Error: LINKEDIN_ORG_ACCESS_TOKEN is required for organization posts (w_organization_social scope)." >&2
    echo "Set LINKEDIN_ORG_ACCESS_TOKEN to a token with w_organization_social scope." >&2
    exit 1
  fi
  LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"
fi
```

This surfaces a clear, actionable error instead of letting a predictably-failing API call create a confusing 400 and trigger a fallback issue.

## Key Insight

**Silent fallbacks that "will likely fail" should fail early with clear errors instead.** A comment that says "which will likely 400" is a code smell — it means the author knew the fallback was broken but left it in. The right behavior is to fail loudly at configuration time, not at API call time with a cryptic error.

## Prevention

- When writing credential-selection logic for APIs with different OAuth scopes per operation, use guard-and-fail (early exit with clear message) rather than fallback-to-wrong-token.
- If `LINKEDIN_ORG_ACCESS_TOKEN` is missing from Doppler, the publisher now fails immediately with a clear error pointing to the missing secret — the operator knows exactly what to configure.

## Session Errors

1. Worktree creation first attempt exited 128 (`fatal: this operation must be run in a work tree`) during the `Updating main...` step — the bare repo cannot run fetch from a bare root. Retried immediately and succeeded. **Prevention:** This is a known bare-repo worktree manager issue; the script handles it gracefully on retry. No rule change needed.

## Files Changed

- `plugins/soleur/skills/community/scripts/linkedin-community.sh` — replaced silent fallback with early-exit guard for missing `LINKEDIN_ORG_ACCESS_TOKEN`
