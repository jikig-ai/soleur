---
title: LinkedIn organization posts require separate LINKEDIN_ORG_ACCESS_TOKEN
date: 2026-04-09
category: integration-issues
tags: [linkedin, oauth, content-publisher, api]
issue: "1755"
---

# Learning: LinkedIn org posts require separate LINKEDIN_ORG_ACCESS_TOKEN

## Problem

LinkedIn Company Page posts failed with HTTP 400:

```
Error: LinkedIn API returned HTTP 400 for /rest/posts: Organization permissions must be used when using organization as author
```

The content publisher was using the personal `LINKEDIN_ACCESS_TOKEN` for both personal and company page posts.

## Root Cause

LinkedIn's REST API enforces scope-based token routing:
- Personal posts (`urn:li:person:*`) → token with `w_member_social` scope
- Organization posts (`urn:li:organization:*`) → token with `w_organization_social` scope

The `cmd_post_content` function in `linkedin-community.sh` did not distinguish between the two author types. It always used `LINKEDIN_ACCESS_TOKEN`, which was obtained via personal OAuth and lacked `w_organization_social` scope.

## Solution

Added `LINKEDIN_ORG_ACCESS_TOKEN` as a separate env var. In `cmd_post_content`, after resolving the author URN:

```bash
# Organization posts require w_organization_social scope -- use LINKEDIN_ORG_ACCESS_TOKEN
# if set, otherwise fall back to LINKEDIN_ACCESS_TOKEN (which will likely 400).
if [[ "$author" == urn:li:organization:* ]] && [[ -n "${LINKEDIN_ORG_ACCESS_TOKEN:-}" ]]; then
  LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"
fi
```

## Key Insight

LinkedIn OAuth tokens are scope-bound per product. A personal "Sign In with LinkedIn" token cannot post as an organization even if that person is an org admin. A separate token obtained via the "Community Management API" or "Marketing Developer Platform" with `w_organization_social` scope is required. Always maintain separate tokens for personal vs. organization posting.

## Session Errors

1. **worktree-manager.sh `--yes create` failed with exit 128** — "fatal: this operation must be run in a work tree". The script calls `git pull` which is invalid from a bare repo root. Recovery: use `git worktree add` directly. Prevention: the worktree manager should detect bare-repo context and skip the `git pull` step.

2. **`bun test` crashes with floating point error/segfault** (bun 1.3.6, Linux x64). No test baseline could be established. Filed as tracking issue #1796. Prevention: upgrade bun or switch test runner if crash persists.

## Tags

category: integration-issues
module: content-publisher, linkedin-community
