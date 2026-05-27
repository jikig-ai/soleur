---
title: "GitHub App installation sibling lookup must match on org, not exact repo_url"
category: integration-issues
module: web-platform/server/resolve-installation-id
tags: [github-app, supabase, multi-user, installation-id, sync]
date: 2026-05-28
---

# Learning: GitHub App installation sibling lookup must match on org, not exact repo_url

## Problem

After PR #4546 added a workspace-sibling fallback for resolving `github_installation_id` when a user's own row has NULL, the security review added an exact `repo_url` match filter (`.eq("repo_url", callerRepoUrl)`) to prevent cross-repo token leakage. This broke the fallback for the production case where two users in the same workspace are connected to different repos under the same GitHub org.

Production state:
- `ops@example.com`: `repo_url = "https://github.com/acme/repo-a"`, `github_installation_id = NULL`
- `admin@example.com`: `repo_url = "https://github.com/acme/repo-b"`, `github_installation_id = "122213433"`

The sibling lookup failed because `soleur != chatte`, even though installation `122213433` covers both repos in the `jikig-ai` org.

## Solution

Replace `.eq("repo_url", callerRepoUrl)` with `.ilike("repo_url", "https://github.com/${owner}/%")` where `owner` is extracted from the caller's URL via a regex helper (`extractGitHubOwner`). Use `.ilike()` (case-insensitive) because `normalizeRepoUrl` preserves path case — two users could store `jikig-ai` vs `Jikig-AI`.

## Key Insight

GitHub App installations are org-level, not repo-level. When scoping sibling lookups for installation IDs, match on the GitHub org (owner) extracted from the URL, not on the exact `repo_url`. The `workspace_members` join already prevents cross-workspace leakage, so the org-level match adds no new attack surface while correctly handling multi-repo orgs.

Secondary insight: always verify security-review tightenings against the actual production data shape. The exact-match filter was a reasonable security precaution in isolation but broke the real-world case it was designed to fix.

## Tags

category: integration-issues
module: web-platform/server/resolve-installation-id
