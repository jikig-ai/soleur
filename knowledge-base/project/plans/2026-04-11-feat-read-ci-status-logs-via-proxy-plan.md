---
title: "feat: read CI status and logs via proxy"
type: feat
date: 2026-04-11
---

# Read CI Status and Logs via Proxy

## Enhancement Summary

**Deepened on:** 2026-04-11
**Sections enhanced:** 6
**Research sources:** Codebase analysis (ci-tools.ts, github-api.ts,
tool-tiers.ts, canusertool-tiered-gating.test.ts, agent-runner.ts),
knowledge-base learnings (5 relevant), GitHub API documentation

### Key Improvements

1. Identified missing auto-approve integration test in
   `canusertool-tiered-gating.test.ts` -- tests only cover gated tier,
   not auto-approve path for CI read tools
2. Identified missing GitHub API rate limit handling in
   `github-api.ts` -- no 429 retry, no `X-RateLimit-*` header
   monitoring
3. Validated gap analysis item 3.2 (legacy Status API) with project
   learning about Check Runs vs Commit Statuses being distinct GitHub
   primitives

### New Considerations Discovered

- `github-api.ts` has no retry logic for transient errors (429, 502,
  503) -- GitHub recommends exponential backoff
- No pagination handling for repos with many workflow runs (GitHub
  returns max 100 per page)
- The `per_page` cap at 30 in `readCiStatus` is conservative but
  appropriate for agent context windows

## Overview

Add read-only GitHub API endpoints to the platform MCP server so agents
can query CI workflow run status and read workflow logs for the connected
repository. This is slice 2 of 4 in the CI/CD integration (#1062).

**Critical finding:** PR #1925 (merged 2026-04-10) already implemented
the full CI/CD integration across all 4 slices in a single PR. The
`ci-tools.ts`, `github-api.ts`, `tool-tiers.ts`, test files, and
`agent-runner.ts` tool registrations all exist on main. This branch
diverged from main before that merge and needs to merge main to receive
the implementation.

## Problem Statement

Cloud platform agents are sandboxed with `allowedDomains: []` and cannot
read CI status from GitHub. The CLI plugin has full access to `gh` CLI
and local toolchain, but cloud agents have no CI visibility. This forces
founders to manually relay CI results to agents, breaking the autonomous
engineering workflow.

## Existing Implementation (on main)

PR #1925 delivered the following files relevant to slice 2:

| File | Purpose |
|------|---------|
| `apps/web-platform/server/ci-tools.ts` | `readCiStatus()` and `readWorkflowLogs()` handler functions |
| `apps/web-platform/server/github-api.ts` | Thin GitHub API fetch wrapper with `generateInstallationToken()` auth |
| `apps/web-platform/server/tool-tiers.ts` | Tier map: both CI tools mapped to `auto-approve` |
| `apps/web-platform/server/agent-runner.ts` | MCP tool registration, `canUseTool` tiered gating logic |
| `apps/web-platform/test/ci-tools.test.ts` | Unit tests for `readCiStatus` and `readWorkflowLogs` (306 lines) |
| `apps/web-platform/test/github-api.test.ts` | Unit tests for `githubApiGet`, `githubApiGetText`, `githubApiPost` (180 lines) |
| `apps/web-platform/test/tool-tiers.test.ts` | Unit tests for tier classification (97 lines) |
| `apps/web-platform/test/canusertool-tiered-gating.test.ts` | Integration tests for `canUseTool` tiered gating (357 lines) |

### Architecture

```text
Agent Subprocess (sandboxed, no network)
  |
  | MCP protocol (stdio)
  v
soleur_platform MCP Server (in-process, agent-runner.ts)
  |
  | canUseTool: auto-approve for read tools
  | Token: generateInstallationToken(installationId)
  v
GitHub API (api.github.com)
```

### Research Insights: Architecture

**GitHub API Rate Limits for App Installations:**

- GitHub App installation tokens get 5,000 requests/hour for
  repositories on paid plans, 1,000 for free plans
- The `/actions/runs` endpoint counts against the installation token
  rate limit
- The `/actions/jobs/{id}/logs` endpoint returns plain text and can be
  large (multi-MB for verbose builds) -- the 100-line truncation in
  `fetchFallbackLog()` is essential for agent context management
- Check run annotations are paginated (30 per page by default) -- the
  current implementation fetches only the first page, which is
  sufficient for most CI runs but could miss annotations in repos with
  many check steps

**Security Boundary Validation:**

The architecture is sound. The agent subprocess has `allowedDomains: []`
(no outbound network), so it physically cannot bypass the MCP tool layer
to reach GitHub directly. The installation token never enters the agent
process. The `DELETE` method block in `github-api.ts` prevents
accidental destructive operations even if a future tool were to
construct a delete path.

### Key Design Decisions (from parent plan)

1. **MCP tools, not HTTP proxy.** Agent calls MCP tools via stdio; the
   platform server executes GitHub API calls with its own token. Agent
   never gets network access or sees the token.

2. **Owner/repo hardcoded from workspace metadata.** MCP tools do NOT
   accept `owner` or `repo` as parameters. They read the connected repo
   from the workspace record. Prevents targeting arbitrary repos.

3. **Log strategy: annotations first, fallback to tail.** Prefer GitHub
   Check Annotations API (structured failure data, small payload). Fall
   back to last 100 lines of the first failed step only if annotations
   are empty. Avoids multi-MB log zip downloads.

4. **DELETE rejected at fetch wrapper layer.** `github-api.ts` rejects
   DELETE method calls unconditionally as defense-in-depth.

## Proposed Solution

Merge main into this feature branch to receive the existing
implementation, then verify all acceptance criteria are met. Add
missing auto-approve integration test for completeness.

### Implementation Phases

#### Phase 1: Merge and Verify

- [ ] 1.1 Merge `origin/main` into this branch to receive CI/CD
  implementation from PR #1925
- [ ] 1.2 Run existing test suite to verify all tests pass:
  `cd apps/web-platform && bun test ci-tools github-api tool-tiers canusertool-tiered-gating`
- [ ] 1.3 Verify TypeScript compilation: `cd apps/web-platform && npx tsc --noEmit`

#### Phase 2: Acceptance Criteria Verification

Map each acceptance criterion to its implementation evidence:

- [ ] 2.1 **AC1: Agent can read workflow run status** --
  `readCiStatus()` in `ci-tools.ts` calls
  `GET /repos/{owner}/{repo}/actions/runs` and returns `CiRunSummary[]`
  with id, name, branch, sha, status, conclusion, url, workflowId.
  Verified by `ci-tools.test.ts` "returns workflow runs with status"
  test.

- [ ] 2.2 **AC2: Agent can read check suite results** --
  `readWorkflowLogs()` in `ci-tools.ts` fetches check runs via
  `GET /repos/{owner}/{repo}/commits/{sha}/check-runs` and extracts
  annotations. Verified by `ci-tools.test.ts` "returns annotations"
  test.

- [ ] 2.3 **AC3: Agent can read workflow run logs (with truncation)** --
  `readWorkflowLogs()` falls back to `fetchFallbackLog()` which returns
  last 100 lines of the first failed step via
  `GET /repos/{owner}/{repo}/actions/jobs/{id}/logs`. Verified by
  `ci-tools.test.ts` "falls back to last 100 lines" test.

- [ ] 2.4 **AC4: All reads are auto-approved at the proxy layer** --
  `tool-tiers.ts` maps both
  `mcp__soleur_platform__github_read_ci_status` and
  `mcp__soleur_platform__github_read_workflow_logs` to `auto-approve`.
  `canUseTool` in `agent-runner.ts` passes through auto-approve tools
  with audit log. Verified by `tool-tiers.test.ts`.

- [ ] 2.5 **AC5: Proxy rejects reads targeting repos other than the
  connected workspace** -- MCP tool definitions in `agent-runner.ts`
  hardcode `owner` and `repo` from workspace metadata (captured at line
  565 and 590). The tool schema exposes only `branch` and `per_page`
  (for read_ci_status) and `run_id` (for read_workflow_logs). Agent
  cannot specify a different repository.

#### Phase 3: Test Gap Remediation

- [ ] 3.1 **Add auto-approve integration test to
  `canusertool-tiered-gating.test.ts`.** The existing tests only cover
  the `gated` tier path (create_pull_request). The `auto-approve` path
  for `github_read_ci_status` and `github_read_workflow_logs` is tested
  at the unit level in `tool-tiers.test.ts` but not in the integration
  test that exercises the full `canUseTool` callback. Add tests:

  ```typescript
  // apps/web-platform/test/canusertool-tiered-gating.test.ts
  test("github_read_ci_status auto-approved without review gate", async () => {
    const result = await canUseTool(
      "mcp__soleur_platform__github_read_ci_status",
      { branch: "main", per_page: 10 },
    );
    expect(result.behavior).toBe("allow");
    // Verify NO review gate was triggered (no sendToClient call)
  });

  test("github_read_workflow_logs auto-approved without review gate", async () => {
    const result = await canUseTool(
      "mcp__soleur_platform__github_read_workflow_logs",
      { run_id: 12345 },
    );
    expect(result.behavior).toBe("allow");
  });
  ```

#### Phase 4: Gap Analysis

Potential gaps to investigate:

- [ ] 4.1 **Check suite vs check run semantics.** AC2 says "check suite
  results" but the implementation reads check runs
  (`/commits/{sha}/check-runs`), not check suites
  (`/repos/{owner}/{repo}/check-suites/{id}`). Check runs are the
  individual items within a check suite and provide more granular data.
  The spec (FR2) says "check suite results" which is satisfied by
  reading the individual check runs that compose suites. No gap -- check
  runs are strictly more useful than check suites for CI failure
  analysis.

- [ ] 4.2 **Commit status checks.** The issue description mentions
  "commit statuses" but neither the spec nor the implementation includes
  the legacy Status API
  (`GET /repos/{owner}/{repo}/commits/{ref}/status`). The modern Check
  Runs API supersedes this. Only repos using legacy CI integrations
  (Travis CI, etc.) would need the Status API. Acceptable gap for P3 --
  GitHub Actions uses Check Runs exclusively. If needed later, adding a
  third tool is trivial.

  **Validated by learning:** `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md`
  confirms Commit Statuses (Status API) and Check Runs (Checks API) are
  fundamentally different GitHub primitives. GitHub Actions creates
  Check Runs, not Commit Statuses. Repos on GitHub Actions exclusively
  use Check Runs, so the legacy Status API is not needed.

- [ ] 4.3 **GitHub App permissions.** The archived tasks.md shows task
  1.5 "Update GitHub App manifest to add `actions:write` and
  `checks:read` permissions" as unchecked. This is a manual step
  (GitHub App settings page). Verify the app manifest has correct
  permissions, or document the graceful degradation path (403 handling
  in `github-api.ts`).

  **Graceful degradation is implemented:** `github-api.ts:handleErrorResponse`
  catches 403 with the message: "Your Soleur GitHub App installation may
  need updated permissions. Visit your GitHub App installation settings
  to approve new permissions." This covers the case where the App
  permissions have not been updated yet.

### Research Insights: Edge Cases

**GitHub API Error Handling:**

- `github-api.ts` has no retry logic for transient errors (HTTP 429,
  502, 503). GitHub recommends exponential backoff with jitter for 429
  responses. For P3, the error propagates to the agent which receives a
  user-facing error message. Acceptable for now -- agents can retry the
  MCP tool call manually. A future improvement would add automatic
  retry with exponential backoff in `github-api.ts`.

- The `X-RateLimit-Remaining` header is not monitored. For multi-user
  platforms sharing a GitHub App, a proactive rate limit check before
  each request would prevent hitting the limit. Defer to post-P3 --
  the App's 5,000 req/hr limit is generous for read-only CI queries.

**Pagination:**

- `readCiStatus()` uses `per_page` (capped at 30) without pagination.
  This means only the 30 most recent runs are returned. For the agent
  use case, this is appropriate -- agents need recent CI status, not
  historical runs. If a repo has more than 30 active workflows, some
  older runs will not appear, but the most recent ones (which are what
  matters for CI status checks) will always be included.

- Check run annotations are fetched without pagination (first page
  only, default 30 per page). For most CI runs, this is sufficient.
  Repos with many check steps (e.g., matrix builds with 50+ jobs)
  could have annotations on later pages that are missed. Acceptable
  for P3 -- the first page captures the most critical failures.

**Org vs User Installation:**

- Learning `2026-04-06-github-app-org-repo-creation-endpoint-routing.md`
  documents that org installation tokens have different identity
  semantics. For read-only endpoints (`/repos/{owner}/{repo}/actions/runs`),
  this is not an issue -- the endpoint is the same regardless of
  installation type. The difference only matters for user-scoped
  endpoints like `/user/repos`. No action needed for CI read tools.

## Acceptance Criteria

- [ ] Agent can read workflow run status for the connected repo
- [ ] Agent can read check suite results
- [ ] Agent can read workflow run logs (with truncation for large
  outputs)
- [ ] All reads are auto-approved at the proxy layer
- [ ] Proxy rejects reads targeting repos other than the connected
  workspace
- [ ] All existing tests pass after merge
- [ ] Auto-approve integration test added for CI read tools

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Pure infrastructure extension within the existing MCP
server architecture. The implementation follows established patterns
(MCP tool registration, `canUseTool` gating, `generateInstallationToken`
auth). No new architectural decisions -- all decisions were made in the
parent brainstorm (#1062) and applied in PR #1925. The tiered gating
system, audit logging, and owner/repo hardcoding provide adequate
security boundaries. No cross-domain implications.

## Test Scenarios

### Unit Tests (already exist)

- Given a connected repo, when agent calls `github_read_ci_status`,
  then it returns recent workflow runs with status, SHA, branch, URL,
  and workflow name/ID
- Given a branch filter, when agent calls `github_read_ci_status` with
  `branch: "main"`, then only runs for that branch are returned
- Given a workflow run with check annotations, when agent calls
  `github_read_workflow_logs`, then annotations are returned with path,
  line, level, and message
- Given a workflow run with no annotations but a failed step, when
  agent calls `github_read_workflow_logs`, then last 100 lines of the
  failed step are returned
- Given a read tool invocation, when `canUseTool` evaluates it, then
  the tool is auto-approved with audit log
- Given a GitHub API 403 response, when `githubApiGet` processes it,
  then a descriptive permission upgrade message is thrown

### New Tests (to add in Phase 3)

- Given `github_read_ci_status` tool name, when `canUseTool` processes
  it in the full agent-runner integration test, then behavior is
  `allow` with no review gate triggered
- Given `github_read_workflow_logs` tool name, when `canUseTool`
  processes it, then behavior is `allow` with no review gate triggered
- Given an auto-approved tool, when `canUseTool` processes it, then a
  structured audit log is emitted with `tier: "auto-approve"` and
  `decision: "auto-approved"`

### Research Insights: Test Patterns

**Existing test pattern to follow:** `canusertool-tiered-gating.test.ts`
boots a session, extracts the `canUseTool` callback from the mock SDK
`query()` call, and tests it directly. The auto-approve tests should
follow this same pattern but assert that `sendToClient` was NOT called
(no review gate) and that the return value is `{ behavior: "allow" }`.

**Mock setup already covers the CI tools:** The test file mocks
`ci-tools` and `trigger-workflow` imports. The `platformToolNames`
array includes the CI read tools. The only missing piece is test cases
that exercise the auto-approve branch in `canUseTool`.

### Acceptance Verification (manual)

- Given the test suite, when `bun test ci-tools github-api tool-tiers canusertool-tiered-gating` runs, then all tests pass
- Given TypeScript compilation, when `npx tsc --noEmit` runs, then no type errors

## References

- Parent issue: #1062
- Slice 1 (infrastructure): #1926
- Implementation PR: #1925
- Archived spec: `knowledge-base/project/specs/archive/20260411-001824-feat-cicd-integration/spec.md`
- Archived plan: `knowledge-base/project/plans/archive/20260411-001824-2026-04-10-feat-cicd-integration-plan.md`
- Archived brainstorm: `knowledge-base/project/brainstorms/archive/20260411-001824-2026-04-10-cicd-integration-brainstorm.md`

### Relevant Learnings Applied

- `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md` --
  Validates that Check Runs and Commit Statuses are distinct primitives;
  confirms legacy Status API omission is acceptable
- `2026-04-06-github-app-org-repo-creation-endpoint-routing.md` --
  Confirms org vs user installation tokens affect user-scoped endpoints
  only, not read-only repo endpoints used by CI tools
- `2026-03-30-review-agent-rate-limit-fallback.md` -- Pattern for
  handling API rate limits (relevant to future github-api.ts retry
  logic)
- `2026-02-18-token-env-var-not-cli-arg.md` -- Confirms tokens must
  never be passed as CLI args (already enforced: agent never sees
  token)
