---
title: "Tasks: fix sibling installation ID org-match"
branch: feat-one-shot-sibling-install-org-match
lane: single-domain
---

# Tasks

## Phase 1: Fix the org-match filter

- [x] 1.1 Read `apps/web-platform/server/resolve-installation-id.ts`
- [ ] 1.2 Add **exported** `extractGitHubOwner(url: string): string | null` helper function
  - Extract owner from `https://github.com/<owner>/...` via regex
  - Return null for non-GitHub or malformed URLs
  - Must be exported for direct unit testing
- [ ] 1.3 Update JSDoc comment to reflect org-level matching via `.ilike()`
- [ ] 1.4 Replace `.eq("repo_url", callerRepoUrl)` with `.ilike("repo_url", ...)` using extracted owner
  - Use `.ilike()` (case-insensitive) NOT `.like()` -- `normalizeRepoUrl` preserves path case
  - If `extractGitHubOwner` returns null, skip the filter (safe default)

## Phase 2: Add unit tests

- [ ] 2.1 Create `apps/web-platform/test/resolve-installation-id.test.ts`
- [ ] 2.2 Test: returns own installation ID when present (no sibling lookup)
- [ ] 2.3 Test: resolves from sibling with same GitHub org
- [ ] 2.4 Test: resolves from sibling with same org but different case (`.ilike()` case-insensitive match)
- [ ] 2.5 Test: does NOT resolve from sibling with different GitHub org
- [ ] 2.6 Test: returns null when no siblings exist
- [ ] 2.7 Test: returns null when caller has no repo_url
- [ ] 2.8 Test: handles non-GitHub URLs gracefully

## Phase 3: Test extractGitHubOwner edge cases

- [ ] 3.1 Test: `https://github.com/jikig-ai/soleur` -> `jikig-ai`
- [ ] 3.2 Test: `https://github.com/jikig-ai/chatte` -> `jikig-ai`
- [ ] 3.3 Test: `https://github.com/single` -> `null`
- [ ] 3.4 Test: `https://gitlab.com/jikig-ai/soleur` -> `null`
- [ ] 3.5 Test: empty/null input -> graceful null

## Phase 4: Verify

- [ ] 4.1 Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/resolve-installation-id.test.ts`
- [ ] 4.2 Run: `cd apps/web-platform && ./node_modules/.bin/vitest run` (full suite)
- [ ] 4.3 Verify: `grep -n 'ilike' apps/web-platform/server/resolve-installation-id.ts` returns at least 1 match
- [ ] 4.4 Verify: `grep -c 'eq("repo_url"' apps/web-platform/server/resolve-installation-id.ts` returns 0
- [ ] 4.5 Verify: `grep -n 'export.*extractGitHubOwner' apps/web-platform/server/resolve-installation-id.ts` returns 1 match
