---
title: "Tasks: fix sibling installation ID org-match"
branch: feat-one-shot-sibling-install-org-match
lane: single-domain
---

# Tasks

## Phase 1: Fix the org-match filter

- [x] 1.1 Read `apps/web-platform/server/resolve-installation-id.ts`
- [ ] 1.2 Add `extractGitHubOwner(url: string): string | null` helper function
  - Extract owner from `https://github.com/<owner>/...` via regex
  - Return null for non-GitHub or malformed URLs
- [ ] 1.3 Update JSDoc comment to reflect org-level matching
- [ ] 1.4 Replace `.eq("repo_url", callerRepoUrl)` with `.like("repo_url", ...)` using extracted owner
  - If `extractGitHubOwner` returns null, skip the filter (safe default)

## Phase 2: Add unit tests

- [ ] 2.1 Create `apps/web-platform/test/resolve-installation-id.test.ts`
- [ ] 2.2 Test: returns own installation ID when present (no sibling lookup)
- [ ] 2.3 Test: resolves from sibling with same GitHub org
- [ ] 2.4 Test: does NOT resolve from sibling with different GitHub org
- [ ] 2.5 Test: returns null when no siblings exist
- [ ] 2.6 Test: returns null when caller has no repo_url
- [ ] 2.7 Test: handles non-GitHub URLs gracefully

## Phase 3: Test extractGitHubOwner edge cases

- [ ] 3.1 Test: `https://github.com/jikig-ai/soleur` -> `jikig-ai`
- [ ] 3.2 Test: `https://github.com/jikig-ai/chatte` -> `jikig-ai`
- [ ] 3.3 Test: `https://github.com/single` -> `null`
- [ ] 3.4 Test: `https://gitlab.com/jikig-ai/soleur` -> `null`
- [ ] 3.5 Test: empty/null input -> graceful null

## Phase 4: Verify

- [ ] 4.1 Run: `./node_modules/.bin/vitest run test/resolve-installation-id.test.ts`
- [ ] 4.2 Run: `./node_modules/.bin/vitest run` (full suite)
