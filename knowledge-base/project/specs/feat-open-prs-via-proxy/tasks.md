# Tasks: feat-open-prs-via-proxy

## Phase 1: Setup

- 1.1 Read existing implementation files on origin/main
  - 1.1.1 `apps/web-platform/server/push-branch.ts`
  - 1.1.2 `apps/web-platform/server/github-api.ts`
  - 1.1.3 `apps/web-platform/server/github-app.ts` (createPullRequest function, lines 596-660)
  - 1.1.4 `apps/web-platform/server/tool-tiers.ts`
  - 1.1.5 `apps/web-platform/server/agent-runner.ts` (create_pull_request tool ~line 525, github_push_branch tool ~line 655)
  - 1.1.6 `apps/web-platform/test/push-branch.test.ts`
  - 1.1.7 `apps/web-platform/test/tool-tiers.test.ts`
  - 1.1.8 `apps/web-platform/test/canusertool-tiered-gating.test.ts`
- 1.2 Merge latest origin/main into feat-open-prs-via-proxy worktree
- 1.3 Install dependencies: `cd apps/web-platform && bun install`

## Phase 2: Core Implementation

### 2.1 Extract branch validation module

- 2.1.1 Create `apps/web-platform/server/branch-validation.ts` (standalone, zero heavy dependencies)
  - Export `validateBranchFormat(branch: string): void`
  - Implement all 10 git ref format rules (from `git check-ref-format` man page):
    - Rule 1: no component starts with `.` or ends with `.lock`
    - Rule 3: no `..` anywhere
    - Rule 4: no ASCII control chars (< 0x20 or 0x7F), space, `~`, `^`, `:`
    - Rule 5: no `?`, `*`, `[`
    - Rule 6: no leading/trailing `/`, no `//`
    - Rule 7: cannot end with `.`
    - Rule 8: no `@{` sequence
    - Rule 9: cannot be single character `@`
    - Rule 10: no `\`
  - Max length guard (255 chars)
  - Empty string guard
  - Each rule throws with a descriptive, rule-specific error message
  - Truncate branch name to 100 chars in error messages (prevent log flooding)

### 2.2 Integrate into push-branch.ts

- 2.2.1 Import `validateBranchFormat` from `./branch-validation`
- 2.2.2 Call `validateBranchFormat(branch)` as first step in `pushBranch()`, before force-push check
- 2.2.3 Keep existing `validateBranchName()` as step 2 (protected-branch check remains separate)

### 2.3 Integrate into agent-runner.ts (create_pull_request tool)

- 2.3.1 Import `validateBranchFormat` from `./branch-validation`
- 2.3.2 In the `create_pull_request` tool handler, before calling `createPullRequest()`:
  - `validateBranchFormat(args.head)`
  - `validateBranchFormat(args.base)`
  - Check `args.head !== args.base` (reject with "Head branch and base branch cannot be the same")

## Phase 3: Testing (TDD -- write tests before implementation where practical)

### 3.1 Branch validation tests (RED first)

- 3.1.1 Create `apps/web-platform/test/branch-validation.test.ts`
- 3.1.2 Write tests for all 10 git ref format rules:
  - Rule 1: rejects `.hidden/branch`, rejects `feat/branch.lock`, allows `feat/branch.locksmith`
  - Rule 3: rejects `feat..branch`
  - Rule 4: rejects space, `~`, `^`, `:`, null byte (0x00), DEL (0x7F)
  - Rule 5: rejects `?`, `*`, `[`
  - Rule 6: rejects `/feat`, `feat/`, `feat//branch`
  - Rule 7: rejects `feat.`
  - Rule 8: rejects `feat@{0}`
  - Rule 9: rejects `@`
  - Rule 10: rejects `feat\branch`
- 3.1.3 Write tests for valid names: `feat-x`, `feat/my-feature`, `v1.0.0-rc`, `user@branch`, `feat_my-branch`
- 3.1.4 Write edge case tests: empty string, 255 chars (pass), 256 chars (fail)
- 3.1.5 Verify tests fail (RED phase)
- 3.1.6 Implement `branch-validation.ts` (GREEN phase)
- 3.1.7 Verify all tests pass

### 3.2 Happy-path push-branch tests

- 3.2.1 Mock `generateInstallationToken`, `execFileSync`, `writeFileSync`, `unlinkSync` in `push-branch.test.ts`
- 3.2.2 Test: successful push calls execFileSync with correct args -- **assert the exact URL and refspec** (`"https://github.com/alice/my-repo.git"`, `"HEAD:refs/heads/feat-new-feature"`)
- 3.2.3 Test: credential helper file created with `mode: 0o700`
- 3.2.4 Test: credential helper deleted after successful push (unlinkSync called)
- 3.2.5 Test: git config user.name set to "Soleur Agent", user.email to "<agent@soleur.ai>"
- 3.2.6 Test: credential helper cleanup runs even when push fails (finally block -- unlinkSync still called)
- 3.2.7 Test: error message strips internal paths from stderr (no `/tmp/` or `/workspaces/` in thrown error)

### 3.3 createPullRequest unit tests

- 3.3.1 Create `apps/web-platform/test/create-pull-request.test.ts`
- 3.3.2 Mock `generateInstallationToken` and global `fetch` (since github-app.ts uses its own `githubFetch` wrapping `fetch`)
- 3.3.3 Test: successful creation returns `{ number, htmlUrl, url }` -- **assert fetch URL** is `https://api.github.com/repos/alice/repo/pulls`
- 3.3.4 Test: 422 error with `errors[0].message` returns that specific message
- 3.3.5 Test: 422 error with only `message` field returns "GitHub create PR failed: 422 - {message}"
- 3.3.6 Test: non-JSON error response returns generic "GitHub create PR failed: {status}" error

### 3.4 PR creation validation tests

- 3.4.1 Add tests for head === base rejection (in the tool handler, not createPullRequest itself)
- 3.4.2 Add tests for invalid branch format rejection for head
- 3.4.3 Add tests for invalid branch format rejection for base

### 3.5 Run full test suite

- 3.5.1 `cd apps/web-platform && bun test` -- verify all 86+ suites pass
- 3.5.2 `cd apps/web-platform && bunx tsc --noEmit` -- verify typecheck passes

## Phase 4: Housekeeping

### 4.1 Close slice issues

- 4.1.1 `gh issue close 1926 --comment "Implemented in PR #1925"`
- 4.1.2 `gh issue close 1927 --comment "Implemented in PR #1925"`
- 4.1.3 `gh issue close 1928 --comment "Implemented in PR #1925"`
- 4.1.4 `gh issue close 1929 --comment "Implemented in PR #1925 + hardening in this PR"`

### 4.2 Update roadmap

- 4.2.1 Edit `knowledge-base/product/roadmap.md`: change 3.10a-d status from "Not started" to "Done"
- 4.2.2 Edit 3.10 parent from "In progress" to "Done"
