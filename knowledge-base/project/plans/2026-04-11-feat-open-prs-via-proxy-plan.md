---
title: "feat: open PRs via proxy (push to feature branches + create PR)"
type: feat
date: 2026-04-11
deepened: 2026-04-11
---

# feat: open PRs via proxy (push to feature branches + create PR)

## Enhancement Summary

**Deepened on:** 2026-04-11
**Sections enhanced:** 6
**Research sources:** git check-ref-format man page (10 rules), 5 project learnings (CWE-22 path traversal, CWE-59 symlink escape, canUseTool sandbox defense-in-depth, token revocation timing, CI/CD MCP tiered gating review), existing codebase patterns (isPathInWorkspace extraction, GITHUB_NAME_RE, tool-path-checker.ts)

### Key Improvements

1. Branch validation upgraded from incomplete regex to full git ref format compliance (10 rules)
2. Extracted validation into standalone `branch-validation.ts` module following the `sandbox.ts` security extraction pattern
3. Added credential helper TOCTOU race condition mitigation
4. Added test URL assertion pattern from CI/CD learning (mock URL verification prevents silent API path bugs)

### New Considerations Discovered

- The plan's original regex (`^[a-zA-Z0-9][a-zA-Z0-9._\/-]*[a-zA-Z0-9]$`) missed 6 of git's 10 ref format rules: `.lock` suffix, `@{` sequence, single `@`, backslash, component-level dot prefix, and control characters beyond the character class
- Credential helper writes have a TOCTOU window: between `writeFileSync` and `execFileSync`, another process could read the token. Mitigated by `mode: 0o700` + `randomCredentialPath()`, but worth documenting
- The `createPullRequest` function in `github-app.ts` uses its own `githubFetch` wrapper (not the centralized `github-api.ts` `githubApiPost`), creating a bypass of the DELETE guard. Low risk since PR creation is POST-only, but worth noting for future audit

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

### Task 1: Extract branch validation into standalone module (branch-validation.ts)

Following the project's established pattern of extracting security-critical logic into dependency-free modules (see `sandbox.ts` from CWE-22 fix, `error-sanitizer.ts` from CWE-209 fix, `tool-path-checker.ts`), create `apps/web-platform/server/branch-validation.ts` with zero heavy dependencies.

### Research Insights

**Git ref format rules (authoritative, from `git check-ref-format` man page):**

Git imposes 10 rules on reference names. Branch names live under `refs/heads/` but the agent provides just the branch component (without the `refs/heads/` prefix). Using `--allow-onelevel` mode:

1. No slash-separated component can begin with `.` or end with `.lock`
2. Must contain at least one `/` (waived by `--allow-onelevel` -- agent branches can be single-component like `feat-x`)
3. Cannot contain `..` anywhere
4. Cannot contain ASCII control characters (bytes < 0x20 or 0x7F DEL), space, `~`, `^`, or `:`
5. Cannot contain `?`, `*`, or `[`
6. Cannot begin or end with `/`, no consecutive `//`
7. Cannot end with `.`
8. Cannot contain `@{`
9. Cannot be the single character `@`
10. Cannot contain `\`

**Implementation -- multi-check approach (not a single regex):**

A single regex cannot express all 10 rules (especially `.lock` suffix per component and `@{` sequence). Use a series of checks, each mapping to one git rule:

**File:** `apps/web-platform/server/branch-validation.ts`

```typescript
/**
 * Branch name validation following git check-ref-format rules.
 *
 * Extracted into a standalone module with zero heavy dependencies
 * (following sandbox.ts, error-sanitizer.ts extraction pattern)
 * for unit testability without mocking SDK/Supabase.
 *
 * See: git check-ref-format(1) man page for the 10 rules.
 */

const MAX_BRANCH_LENGTH = 255;

// ASCII control characters (0x00-0x1F, 0x7F) plus banned characters
const BANNED_CHARS_RE = /[\x00-\x1f\x7f ~^:?*[\]\\]/;

/**
 * Validate a branch name against git's ref format rules.
 * Uses --allow-onelevel semantics (single-component names like "feat-x" are valid).
 *
 * Throws with a descriptive message on the first rule violation.
 */
export function validateBranchFormat(branch: string): void {
  if (!branch || branch.length > MAX_BRANCH_LENGTH) {
    throw new Error(
      `Invalid branch name: ${!branch ? "empty" : "exceeds 255 characters"}`,
    );
  }

  // Rule 9: cannot be single character @
  if (branch === "@") {
    throw new Error("Invalid branch name '@'");
  }

  // Rule 6: cannot begin or end with /
  if (branch.startsWith("/") || branch.endsWith("/")) {
    throw new Error(
      `Invalid branch name '${branch.slice(0, 100)}': cannot begin or end with '/'`,
    );
  }

  // Rule 7: cannot end with .
  if (branch.endsWith(".")) {
    throw new Error(
      `Invalid branch name '${branch.slice(0, 100)}': cannot end with '.'`,
    );
  }

  // Rule 3: no .. anywhere
  if (branch.includes("..")) {
    throw new Error(
      `Invalid branch name '${branch.slice(0, 100)}': cannot contain '..'`,
    );
  }

  // Rule 6: no consecutive //
  if (branch.includes("//")) {
    throw new Error(
      `Invalid branch name '${branch.slice(0, 100)}': cannot contain '//'`,
    );
  }

  // Rule 8: no @{ sequence
  if (branch.includes("@{")) {
    throw new Error(
      `Invalid branch name '${branch.slice(0, 100)}': cannot contain '@{'"`,
    );
  }

  // Rule 4+5+10: no control chars, space, ~, ^, :, ?, *, [, \
  if (BANNED_CHARS_RE.test(branch)) {
    throw new Error(
      `Invalid branch name '${branch.slice(0, 100)}': contains forbidden characters`,
    );
  }

  // Rule 1: no component starts with . or ends with .lock
  const components = branch.split("/");
  for (const component of components) {
    if (component.startsWith(".")) {
      throw new Error(
        `Invalid branch name '${branch.slice(0, 100)}': component '${component}' starts with '.'`,
      );
    }
    if (component.endsWith(".lock")) {
      throw new Error(
        `Invalid branch name '${branch.slice(0, 100)}': component '${component}' ends with '.lock'`,
      );
    }
  }
}
```

### Research Insights: Security Extraction Pattern

From the CWE-22 path traversal learning: "Extracting security-critical logic into pure, dependency-free modules makes it unit-testable without mocking heavy dependencies like Anthropic SDK, Supabase, or WebSocket connections." The `branch-validation.ts` module follows this pattern exactly -- it imports only string utilities, making tests run in milliseconds.

From the canUseTool sandbox learning: "When auditing access control, trace the full call chain from the entry point (user request) to the enforcement point (sandbox check)." Applied here: the branch name flows from Zod schema -> tool handler -> `validateBranchFormat()` -> `validateBranchName()` (protected-branch check) -> `execFileSync` (git push). Validation at the first handler step ensures early rejection.

### Task 2: Integrate branch validation into push-branch and PR creation

**push-branch.ts changes:**

- Import `validateBranchFormat` from `branch-validation.ts`
- Call `validateBranchFormat(branch)` as the first step in `pushBranch()`, before the force-push check
- The existing `validateBranchName()` becomes step 2 (protected-branch check only)

**agent-runner.ts changes (create_pull_request tool handler):**

- Import `validateBranchFormat` from `branch-validation.ts`
- Before calling `createPullRequest()`:
  1. `validateBranchFormat(args.head)`
  2. `validateBranchFormat(args.base)`
  3. Check `args.head !== args.base` -- reject with "Head branch and base branch cannot be the same"

### Research Insights: Input Validation Ordering

From the tiered gating learning: the review gate fires in `canUseTool` before the tool handler executes. Validation in the tool handler runs after the founder approves. This means:

- The founder sees the raw branch names in the gate message (good -- they can spot suspicious names)
- Format validation catches malformed names before they hit `execFileSync` or the GitHub API
- The ordering is: Zod schema (type check) -> canUseTool (gate) -> tool handler (format validation) -> business logic (protected branch check) -> external call (git push / GitHub API)

### Task 3: Add comprehensive tests for branch-validation.ts

**File:** `apps/web-platform/test/branch-validation.test.ts` (new file)

Test each of the 10 git ref format rules individually, plus edge cases:

```typescript
describe("validateBranchFormat", () => {
  // Rule 1: component cannot start with . or end with .lock
  test("rejects branch with component starting with dot", () => { /* .hidden/branch */ });
  test("rejects branch with component ending in .lock", () => { /* feat/branch.lock */ });
  test("allows .lock in middle of component", () => { /* feat/branch.locksmith */ });

  // Rule 3: no ..
  test("rejects double dots", () => { /* feat..branch */ });

  // Rule 4: no control chars, space, ~, ^, :
  test("rejects space in branch name", () => { /* feat branch */ });
  test("rejects tilde", () => { /* feat~1 */ });
  test("rejects caret", () => { /* feat^2 */ });
  test("rejects colon", () => { /* feat:branch */ });
  test("rejects null byte", () => { /* feat\x00branch */ });
  test("rejects DEL character", () => { /* feat\x7Fbranch */ });

  // Rule 5: no ?, *, [
  test("rejects question mark", () => { /* feat? */ });
  test("rejects asterisk", () => { /* feat* */ });
  test("rejects open bracket", () => { /* feat[0] */ });

  // Rule 6: no leading/trailing /, no //
  test("rejects leading slash", () => { /* /feat */ });
  test("rejects trailing slash", () => { /* feat/ */ });
  test("rejects consecutive slashes", () => { /* feat//branch */ });

  // Rule 7: cannot end with .
  test("rejects trailing dot", () => { /* feat. */ });

  // Rule 8: no @{
  test("rejects @{ sequence", () => { /* feat@{0} */ });

  // Rule 9: cannot be @
  test("rejects single @", () => { /* @ */ });

  // Rule 10: no backslash
  test("rejects backslash", () => { /* feat\\branch */ });

  // Valid names
  test("allows simple branch", () => { /* feat-x */ });
  test("allows slashed branch", () => { /* feat/my-feature */ });
  test("allows dots in branch", () => { /* v1.0.0-rc */ });
  test("allows @ in branch (not sole char)", () => { /* user@branch */ });
  test("allows hyphens and underscores", () => { /* feat_my-branch */ });

  // Length limits
  test("rejects empty string", () => { /* "" */ });
  test("rejects branch over 255 chars", () => { /* "a".repeat(256) */ });
  test("allows branch at exactly 255 chars", () => { /* "a".repeat(255) */ });
});
```

### Task 4: Add happy-path tests for push-branch

The existing `push-branch.test.ts` only tests rejection cases. Add tests for the successful push path.

**File:** `apps/web-platform/test/push-branch.test.ts`

### Research Insights: Mock URL Assertion Pattern

From the CI/CD learning: "The pattern of 'write tests that mock API responses' can mask URL construction bugs because mocks return data for any URL. Adding URL assertions to test mocks would have caught this in the RED phase."

Applied here: when mocking `execFileSync` for the push test, assert the exact command array:

```typescript
test("successful push calls git with correct args", async () => {
  // Arrange: mock dependencies
  vi.mocked(generateInstallationToken).mockResolvedValue("ghs_test123");
  vi.mocked(execFileSync).mockReturnValue(Buffer.from(""));

  // Act
  await pushBranch({
    installationId: 12345,
    owner: "alice",
    repo: "my-repo",
    workspacePath: "/tmp/workspace",
    branch: "feat-new-feature",
    force: false,
  });

  // Assert: verify exact command (not just "some git command")
  const pushCall = vi.mocked(execFileSync).mock.calls.find(
    (call) => call[1]?.includes("push"),
  );
  expect(pushCall).toBeDefined();
  expect(pushCall![1]).toEqual(
    expect.arrayContaining([
      "push",
      "https://github.com/alice/my-repo.git",
      "HEAD:refs/heads/feat-new-feature",
    ]),
  );
});
```

**Credential helper lifecycle tests:**

```typescript
test("credential helper is cleaned up on success", async () => {
  vi.mocked(generateInstallationToken).mockResolvedValue("ghs_test");
  vi.mocked(execFileSync).mockReturnValue(Buffer.from(""));

  await pushBranch({ /* valid args */ });

  // writeFileSync called to create helper, unlinkSync to delete
  expect(writeFileSync).toHaveBeenCalledTimes(1);
  expect(unlinkSync).toHaveBeenCalledTimes(1);
});

test("credential helper is cleaned up even on push failure", async () => {
  vi.mocked(generateInstallationToken).mockResolvedValue("ghs_test");
  // First call = git config (succeeds), subsequent calls check for push
  vi.mocked(execFileSync).mockImplementation((_cmd, args) => {
    if (Array.isArray(args) && args.includes("push")) {
      throw new Error("push failed");
    }
    return Buffer.from("");
  });

  await expect(pushBranch({ /* valid args */ })).rejects.toThrow();
  expect(unlinkSync).toHaveBeenCalledTimes(1); // finally block runs
});
```

**Git author configuration test:**

```typescript
test("sets git author to Soleur Agent identity", async () => {
  vi.mocked(generateInstallationToken).mockResolvedValue("ghs_test");
  vi.mocked(execFileSync).mockReturnValue(Buffer.from(""));

  await pushBranch({ /* valid args */ });

  const configCalls = vi.mocked(execFileSync).mock.calls.filter(
    (call) => call[1]?.includes("config"),
  );
  expect(configCalls).toHaveLength(2);
  expect(configCalls[0]![1]).toContain("user.name");
  expect(configCalls[0]![1]).toContain("Soleur Agent");
  expect(configCalls[1]![1]).toContain("user.email");
  expect(configCalls[1]![1]).toContain("agent@soleur.ai");
});
```

### Task 5: Add tests for createPullRequest (github-app.ts)

No dedicated test exists for `createPullRequest`. Add unit tests.

**File:** `apps/web-platform/test/create-pull-request.test.ts` (new file)

### Research Insights: github-app.ts Uses Its Own Fetch Wrapper

The `createPullRequest` function uses `githubFetch` from `github-app.ts` (not `githubApiPost` from `github-api.ts`). This is because `github-app.ts` predates the `github-api.ts` extraction (which was created for CI tools). The two wrappers have different error handling: `github-api.ts` has the DELETE guard and 403 handling, while `github-app.ts` has more general error parsing.

This is not a bug (PR creation only uses POST, so the DELETE guard is irrelevant), but tests should mock `githubFetch` at the correct level:

```typescript
// Mock the module-internal githubFetch, not the centralized github-api.ts
vi.mock("../server/github-app", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/github-app")>();
  return {
    ...actual,
    // Override generateInstallationToken but keep createPullRequest using real logic
  };
});
```

Alternative: since `createPullRequest` calls `generateInstallationToken` and `githubFetch` (module-internal), mock at the `fetch` global level:

```typescript
const mockFetch = vi.fn();
global.fetch = mockFetch;

test("successful PR creation returns number and URL", async () => {
  vi.mocked(generateInstallationToken).mockResolvedValue("ghs_test");
  mockFetch.mockResolvedValue(new Response(
    JSON.stringify({ number: 42, html_url: "https://github.com/a/b/pull/42", url: "https://api.github.com/repos/a/b/pulls/42" }),
    { status: 201 },
  ));

  const result = await createPullRequest(12345, "alice", "repo", "feat-x", "main", "My PR", "desc");

  expect(result.number).toBe(42);
  expect(result.htmlUrl).toContain("/pull/42");

  // URL assertion (from CI/CD learning: always assert the URL being called)
  const fetchUrl = mockFetch.mock.calls[0][0];
  expect(fetchUrl).toBe("https://api.github.com/repos/alice/repo/pulls");
});

test("422 error with errors[0].message returns specific message", async () => {
  vi.mocked(generateInstallationToken).mockResolvedValue("ghs_test");
  mockFetch.mockResolvedValue(new Response(
    JSON.stringify({
      message: "Validation Failed",
      errors: [{ message: "A pull request already exists for alice:feat-x" }],
    }),
    { status: 422 },
  ));

  await expect(
    createPullRequest(12345, "alice", "repo", "feat-x", "main", "My PR"),
  ).rejects.toThrow("A pull request already exists");
});
```

### Task 6: Close issues and update roadmap

After hardening work is complete:

1. Close #1926, #1927, #1928, #1929 (all implemented in PR #1925)
2. Update `knowledge-base/product/roadmap.md`: change 3.10a-d from "Not started" to "Done"
3. Update 3.10 parent from "In progress" to "Done"

## Acceptance Criteria

- [ ] `branch-validation.ts` extracted as standalone module with zero heavy dependencies
- [ ] `validateBranchFormat()` enforces all 10 git ref format rules
- [ ] push-branch.ts calls `validateBranchFormat()` before protected-branch check
- [ ] PR creation tool validates head/base format and rejects head === base
- [ ] `branch-validation.test.ts` covers all 10 rules plus edge cases (empty, length, valid names)
- [ ] Happy-path push-branch tests cover credential helper lifecycle (create, use, cleanup)
- [ ] Happy-path push-branch tests verify git author configuration
- [ ] Credential helper cleanup test verifies cleanup runs even on push failure
- [ ] createPullRequest unit tests cover success, error parsing, and structured error extraction
- [ ] All test mocks assert the exact URL/command being called (not just response shape)
- [ ] All existing tests pass (86 suites)
- [ ] Issues #1926-#1929 closed
- [ ] Roadmap entries 3.10a-d updated to "Done"

## Test Scenarios

- Given a branch name containing `..`, when agent calls `github_push_branch`, then the tool rejects with "cannot contain '..'" before touching git
- Given a branch name with spaces, when agent calls `github_push_branch`, then the tool rejects with "contains forbidden characters"
- Given a branch name ending in `.lock`, when agent calls `github_push_branch`, then the tool rejects with "ends with '.lock'"
- Given a branch component starting with `.`, when agent calls `github_push_branch`, then the tool rejects with "starts with '.'"
- Given a branch name containing `@{`, when agent calls `github_push_branch`, then the tool rejects with "cannot contain '@{'"
- Given the single character `@` as branch name, when agent calls `github_push_branch`, then the tool rejects
- Given a branch name with backslash, when agent calls `github_push_branch`, then the tool rejects with "forbidden characters"
- Given a branch name over 255 characters, when agent calls `github_push_branch`, then the tool rejects with "exceeds 255 characters"
- Given head === base in `create_pull_request`, when agent calls the tool, then it returns "Head branch and base branch cannot be the same" without calling the GitHub API
- Given a successful push, when `pushBranch` completes, then the credential helper file is deleted (unlinkSync called)
- Given a failed push (execFileSync throws), when `pushBranch` catches the error, then the credential helper file is still deleted (finally block)
- Given a successful push, when `pushBranch` runs, then git config user.name is set to "Soleur Agent" and user.email to "<agent@soleur.ai>"
- Given a 422 response from GitHub PR API with `errors[0].message`, when `createPullRequest` parses it, then it returns that specific message (not the generic "422" status)
- Given a 422 response with only `message` field, when `createPullRequest` parses it, then it returns "GitHub create PR failed: 422 - {message}"

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a hardening pass on already-merged infrastructure code. No architectural changes -- adding input validation and test coverage. Low risk, high value for defense-in-depth. The branch name validation follows the same pattern as the existing `GITHUB_NAME_RE` validation for owner/repo names in agent-runner.ts. The extraction into `branch-validation.ts` follows the established pattern from `sandbox.ts` (CWE-22 fix) and `tool-path-checker.ts`.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Rely on git/GitHub API to reject invalid refs | Zero code change | Errors are confusing, no audit trail, defense-in-depth gap | Rejected |
| Use `git check-ref-format --branch` subprocess | Authoritative validation | Requires spawning a process for every push/PR, adds ~50ms latency per call | Rejected -- pure function is faster and sufficient |
| Add Zod refinement on branch schema | Validation at schema level, single source of truth | Harder to share between push and PR tools, Zod refinements don't produce descriptive per-rule errors | Rejected -- shared function with rule-specific errors is more maintainable |
| Single regex for all rules | Compact, single check | Cannot express component-level rules (`.lock` suffix, `.` prefix) or `@{` sequence in one pattern without catastrophic backtracking | Rejected -- series of checks is clearer and O(n) |
| Shared `validateBranchFormat()` in standalone module | Reusable, unit testable with zero mocking, follows security extraction pattern | One more file | **Chosen** |

## Implementation Notes

- The `execFileSync` usage in push-branch.ts uses array args (not shell string), so branch names cannot cause command injection. The format validation is defense-in-depth, not a security-critical fix.
- The `create_pull_request` tool already goes through the review gate (gated tier), so the founder sees the raw branch names before approval. The validation catches errors earlier with better messages.
- Branch name regex should allow `/` for `feat/foo` style branches but reject `//` (empty path component).
- The credential helper at `randomCredentialPath()` uses `os.tmpdir()` + UUID, making path collisions negligible. The `mode: 0o700` prevents other users from reading the token file. The TOCTOU window between writeFileSync and execFileSync is mitigated by these measures but cannot be fully eliminated without switching to file descriptor passing (over-engineering for this context).
- `createPullRequest` in `github-app.ts` uses a different fetch wrapper than `github-api.ts`. This is an artifact of the incremental implementation (github-app.ts predates github-api.ts). Not worth consolidating in this hardening pass -- the DELETE guard in `github-api.ts` is irrelevant for POST-only PR creation.

## Relevant Learnings Applied

| Learning | How It Applied |
|----------|---------------|
| CWE-22 path traversal (sandbox.ts) | Extraction pattern: standalone module with zero heavy dependencies for unit testability |
| canUseTool sandbox defense-in-depth | Traced full call chain from Zod schema to git push; validated no layer short-circuits |
| CI/CD MCP tiered gating review | Mock URL assertion pattern: always verify the URL/command being called, not just the response shape |
| Token revocation timing | Confirmed push happens inside agent session (token still valid); credential helper cleanup in finally block |
| GitHub output injection sanitization | Branch name validation prevents injection of special characters that could be misinterpreted in log output or audit records |

## References

- Parent issue: [#1062](https://github.com/jikig-ai/soleur/issues/1062)
- Implementation PR: [#1925](https://github.com/jikig-ai/soleur/pulls/1925)
- Slice issues: #1926, #1927, #1928, #1929
- Spec (archived): `knowledge-base/project/specs/archive/20260411-001824-feat-cicd-integration/spec.md`
- Learning: `knowledge-base/project/learnings/2026-04-10-cicd-mcp-tool-tiered-gating-review-findings.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md`
- Learning: `knowledge-base/project/learnings/2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`
- Git ref format rules: `git check-ref-format(1)` man page, 10 rules for valid reference names
