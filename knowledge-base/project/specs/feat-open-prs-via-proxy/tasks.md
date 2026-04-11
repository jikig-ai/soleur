# Tasks: feat-open-prs-via-proxy

## Phase 1: Setup

- 1.1 Read existing implementation files on origin/main
  - 1.1.1 `apps/web-platform/server/push-branch.ts`
  - 1.1.2 `apps/web-platform/server/github-api.ts`
  - 1.1.3 `apps/web-platform/server/github-app.ts` (createPullRequest function)
  - 1.1.4 `apps/web-platform/server/tool-tiers.ts`
  - 1.1.5 `apps/web-platform/server/agent-runner.ts` (create_pull_request and github_push_branch tools)
  - 1.1.6 `apps/web-platform/test/push-branch.test.ts`
  - 1.1.7 `apps/web-platform/test/tool-tiers.test.ts`
  - 1.1.8 `apps/web-platform/test/canusertool-tiered-gating.test.ts`
- 1.2 Merge latest origin/main into feat-open-prs-via-proxy worktree
- 1.3 Install dependencies: `cd apps/web-platform && bun install`

## Phase 2: Core Implementation

### 2.1 Branch name format validation

- 2.1.1 Create shared `validateBranchFormat()` in `apps/web-platform/server/push-branch.ts`
  - Regex: alphanumeric start/end, allow `a-zA-Z0-9._/-` in middle
  - Reject `..`, `//`, `./`, leading/trailing `.` or `/`
  - Reject control characters, spaces, `~^:?*[\`
  - Max length guard (255 chars -- git ref limit)
- 2.1.2 Call `validateBranchFormat()` from `validateBranchName()` before the protected-branch check
- 2.1.3 Export `validateBranchFormat` for reuse in PR creation tool

### 2.2 PR creation input validation

- 2.2.1 Import `validateBranchFormat` in `apps/web-platform/server/agent-runner.ts`
- 2.2.2 In the `create_pull_request` tool handler, before calling `createPullRequest`:
  - Validate `args.head` with `validateBranchFormat()`
  - Validate `args.base` with `validateBranchFormat()`
  - Check `args.head !== args.base` (reject with descriptive error)
- 2.2.3 Add `args.base` to the protected-branch check (agent should not create PRs targeting protected branches as head -- though GitHub allows it, it's a safety guard)

## Phase 3: Testing

### 3.1 Branch name format validation tests

- 3.1.1 Add `describe("validateBranchFormat")` block to `push-branch.test.ts`
  - Test: rejects `..` in branch name
  - Test: rejects spaces
  - Test: rejects control characters
  - Test: rejects leading/trailing dot
  - Test: rejects `//`
  - Test: rejects single character
  - Test: allows `feat/my-branch`
  - Test: allows `fix-123`
  - Test: allows `feature.branch`
  - Test: rejects empty string
  - Test: rejects string over 255 chars

### 3.2 Happy-path push-branch tests

- 3.2.1 Mock `generateInstallationToken`, `execFileSync`, `writeFileSync`, `unlinkSync`
- 3.2.2 Test: successful push calls execFileSync with correct args (`["git", [..., "push", url, "HEAD:refs/heads/<branch>"]]`)
- 3.2.3 Test: credential helper file is created with correct permissions (0o700)
- 3.2.4 Test: credential helper file is deleted after successful push
- 3.2.5 Test: git config user.name/email set to Soleur Agent identity
- 3.2.6 Test: credential helper cleanup runs even when push fails (finally block)
- 3.2.7 Test: error message strips internal paths from stderr

### 3.3 createPullRequest unit tests

- 3.3.1 Create `apps/web-platform/test/create-pull-request.test.ts`
- 3.3.2 Mock `generateInstallationToken` and `githubFetch`
- 3.3.3 Test: successful creation returns number, htmlUrl, url
- 3.3.4 Test: 422 error with `errors[0].message` returns that specific message
- 3.3.5 Test: 422 error with only `message` field returns formatted error
- 3.3.6 Test: non-JSON error response returns generic error

### 3.4 PR creation validation tests

- 3.4.1 Add tests in `canusertool-tiered-gating.test.ts` or a new file for:
  - head === base rejection
  - Invalid branch format rejection for head
  - Invalid branch format rejection for base

### 3.5 Run full test suite

- 3.5.1 `cd apps/web-platform && bun test` -- verify all 86+ suites pass
- 3.5.2 `cd apps/web-platform && bunx tsc --noEmit` -- verify typecheck passes

## Phase 4: Housekeeping

### 4.1 Close slice issues

- 4.1.1 `gh issue close 1926 --comment "Implemented in PR #1925"`
- 4.1.2 `gh issue close 1927 --comment "Implemented in PR #1925"`
- 4.1.3 `gh issue close 1928 --comment "Implemented in PR #1925"`
- 4.1.4 `gh issue close 1929 --comment "Implemented in PR #1925 + hardening in PR #<this-pr>"`

### 4.2 Update roadmap

- 4.2.1 Edit `knowledge-base/product/roadmap.md`: change 3.10a-d status from "Not started" to "Done"
- 4.2.2 Edit 3.10 parent from "In progress" to "Done"
