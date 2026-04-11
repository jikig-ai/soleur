---
title: "feat: open PRs via proxy (push to feature branches + create PR)"
type: feat
date: 2026-04-11
---

# feat: open PRs via proxy (push to feature branches + create PR)

## Overview

Slice 4 of the CI/CD integration (#1062). Agents running on the cloud platform can push commits to feature branches and open pull requests on the founder's connected GitHub repository. All operations route through the server-side proxy -- the agent never touches GitHub tokens directly.

**Current status:** The core implementation merged in PR #1925 (commit 71199708). All 5 acceptance criteria are met in the merged code. This plan focuses on **hardening gaps** identified during post-merge review, closing open issues, and updating stale roadmap entries.

## Problem Statement / Motivation

PR #1925 shipped all 4 CI/CD slices in a single PR. While the acceptance criteria are met, the post-merge review identified several defense-in-depth gaps and missing test coverage that should be addressed before the issue is closed:

1. Branch name format validation is absent (only protected-branch checks exist)
2. Happy-path integration tests are missing for push-branch and PR creation
3. Issues #1926-#1929 are still open despite the code being merged
4. Roadmap entries 3.10a-d show "Not started" despite completion

## Proposed Solution

### Task 1: Add branch name format validation (push-branch.ts)

Add a regex-based branch name validator in `validateBranchName()` that rejects:

- Names containing `..` (path traversal)
- Names starting or ending with `.` or `/`
- Names containing control characters, spaces, `~`, `^`, `:`, `?`, `*`, `[`, `\`
- Names matching git's own ref validation rules (see `git check-ref-format`)

**File:** `apps/web-platform/server/push-branch.ts`

```typescript
// Add after PROTECTED_BRANCHES constant
const VALID_BRANCH_RE = /^[a-zA-Z0-9][a-zA-Z0-9._\/-]*[a-zA-Z0-9]$/;
const INVALID_BRANCH_PATTERNS = [/\.\./, /\/\//, /\.\//];

// In validateBranchName, before the protected-branch check:
if (!VALID_BRANCH_RE.test(branch) || INVALID_BRANCH_PATTERNS.some(p => p.test(branch))) {
  throw new Error(
    `Invalid branch name '${branch.slice(0, 100)}'. ` +
    "Branch names must start and end with alphanumeric characters " +
    "and cannot contain '..' or special characters.",
  );
}
```

### Task 2: Add branch name validation to PR creation (agent-runner.ts)

The `create_pull_request` tool's `head` and `base` parameters accept arbitrary strings. Add:

- Same format validation as push-branch for both `head` and `base`
- Check that `head !== base` (produces confusing GitHub API error otherwise)

**File:** `apps/web-platform/server/agent-runner.ts` (in the `createPr` tool handler, before calling `createPullRequest`)

### Task 3: Add happy-path tests for push-branch

The existing `push-branch.test.ts` only tests rejection cases. Add tests for:

- Successful push: mock `generateInstallationToken`, `execFileSync`, `writeFileSync`, `unlinkSync` -- verify credential helper is created, push command is correct, and cleanup runs
- Credential helper cleanup on error: mock `execFileSync` to throw, verify `unlinkSync` still runs
- Invalid branch name format: test the new regex validation
- Git author is set before push

**File:** `apps/web-platform/test/push-branch.test.ts`

### Task 4: Add tests for createPullRequest (github-app.ts)

No dedicated test exists for `createPullRequest`. Add unit tests for:

- Successful PR creation: mock `githubFetch`, verify request payload
- Error response parsing: mock 422 response, verify error message extraction
- Structured error extraction: verify `errors[0].message` is preferred over `message`

**File:** `apps/web-platform/test/create-pull-request.test.ts` (new file)

### Task 5: Close issues and update roadmap

After hardening work is complete:

1. Close #1926, #1927, #1928, #1929 (all implemented in PR #1925)
2. Update `knowledge-base/product/roadmap.md`: change 3.10a-d from "Not started" to "Done"
3. Update 3.10 parent from "In progress" to "Done"

## Acceptance Criteria

- [ ] Branch name format validation rejects `..`, control chars, spaces, and invalid git ref characters in push-branch
- [ ] PR creation tool validates head/base format and rejects head === base
- [ ] Happy-path push-branch tests cover credential helper lifecycle (create, use, cleanup)
- [ ] Happy-path push-branch tests verify git author configuration
- [ ] Credential helper cleanup test verifies cleanup runs even on push failure
- [ ] createPullRequest unit tests cover success, error parsing, and structured error extraction
- [ ] All existing tests pass (86 suites)
- [ ] Issues #1926-#1929 closed
- [ ] Roadmap entries 3.10a-d updated to "Done"

## Test Scenarios

- Given a branch name containing `..`, when agent calls `github_push_branch`, then the tool rejects with a descriptive error before touching git
- Given a branch name with spaces, when agent calls `github_push_branch`, then the tool rejects with format validation error
- Given a single-character branch name, when agent calls `github_push_branch`, then the tool rejects (too short for the regex)
- Given head === base in `create_pull_request`, when agent calls the tool, then it returns an error without calling the GitHub API
- Given a successful push, when `pushBranch` completes, then the credential helper file is deleted
- Given a failed push (execFileSync throws), when `pushBranch` catches the error, then the credential helper file is still deleted
- Given a 422 response from GitHub PR API with `errors[0].message`, when `createPullRequest` parses it, then it returns that specific message (not the generic status)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a hardening pass on already-merged infrastructure code. No architectural changes -- adding input validation and test coverage. Low risk, high value for defense-in-depth. The branch name validation follows the same pattern as the existing `GITHUB_NAME_RE` validation for owner/repo names in agent-runner.ts.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Rely on git/GitHub API to reject invalid refs | Zero code change | Errors are confusing, no audit trail, defense-in-depth gap | Rejected |
| Use `git check-ref-format --branch` subprocess | Authoritative validation | Requires spawning a process, adds latency | Rejected -- regex is faster and sufficient |
| Add Zod refinement on branch schema | Validation at schema level | Harder to share between push and PR tools | Rejected -- shared function is more maintainable |
| Shared `validateBranchFormat()` utility | Reusable across push and PR tools, unit testable | One more import | **Chosen** |

## Implementation Notes

- The `execFileSync` usage in push-branch.ts uses array args (not shell string), so branch names cannot cause command injection. The format validation is defense-in-depth, not a security-critical fix.
- The `create_pull_request` tool already goes through the review gate (gated tier), so the founder sees the branch names before approval. The validation catches errors earlier with better messages.
- Branch name regex should allow `/` for `feat/foo` style branches but reject `//` (empty path component).

## References

- Parent issue: [#1062](https://github.com/jikig-ai/soleur/issues/1062)
- Implementation PR: [#1925](https://github.com/jikig-ai/soleur/pulls/1925)
- Slice issues: #1926, #1927, #1928, #1929
- Spec (archived): `knowledge-base/project/specs/archive/20260411-001824-feat-cicd-integration/spec.md`
- Learning: `knowledge-base/project/learnings/2026-04-10-cicd-mcp-tool-tiered-gating-review-findings.md`
- Git ref format rules: `git check-ref-format` man page
