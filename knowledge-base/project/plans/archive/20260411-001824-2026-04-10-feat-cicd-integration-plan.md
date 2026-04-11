---
title: "feat: CI/CD integration — agents trigger deploys, run tests, open PRs"
type: feat
date: 2026-04-10
---

# CI/CD Integration for Cloud Platform Agents

## Overview

Cloud platform agents need to read CI status, trigger GitHub Actions workflows, and open PRs on the founder's connected repo. This closes the capability gap between the CLI plugin (full local toolchain) and the cloud platform (currently no CI/CD access).

**Critical simplification from research:** The brainstorm proposed a "server-side proxy" — implementation research revealed this already exists as the `soleur_platform` in-process MCP server (`agent-runner.ts:438-501`). The codebase already has a GitHub App (`github-app.ts`), installation token generation, a `create_pull_request` MCP tool, and a review gate system. We extend these existing patterns rather than building new infrastructure.

## Problem Statement

Cloud agents are sandboxed with `allowedDomains: []` (no outbound network). The existing MCP server provides a `create_pull_request` tool but no CI/CD capabilities. Agents cannot: read whether CI passed, trigger a test run, or view workflow logs. This makes the cloud platform strictly inferior for engineering workflows.

## Proposed Solution

Extend the existing `soleur_platform` MCP server with 4 new tool categories, gated by the existing `canUseTool` callback with tiered permission logic:

| Tool | GitHub API | Gate Tier | Issue |
|------|-----------|-----------|-------|
| `github_read_ci_status` | `GET /repos/{owner}/{repo}/actions/runs` | Auto-approve | #1927 |
| `github_read_workflow_logs` | `GET /repos/{owner}/{repo}/actions/runs/{id}/logs` | Auto-approve | #1927 |
| `github_list_workflows` | `GET /repos/{owner}/{repo}/actions/workflows` | Auto-approve | #1927 |
| `github_trigger_workflow` | `POST /repos/{owner}/{repo}/actions/workflows/{id}/dispatches` | Gated | #1928 |
| `github_push_branch` | Git push via credential helper | Gated | #1929 |
| `create_pull_request` (existing) | `POST /repos/{owner}/{repo}/pulls` | Gated (add gate) | #1929 |

No network sandbox changes needed — MCP tools execute server-side with the platform's own GitHub App token.

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────┐
│ Agent Subprocess (sandboxed, no network)         │
│                                                   │
│  Calls MCP tools:                                │
│    github_read_ci_status(...)                    │
│    github_trigger_workflow(...)                   │
│    github_push_branch(...)                       │
└──────────────┬────────────────────────────────────┘
               │ MCP protocol (stdio)
               ▼
┌─────────────────────────────────────────────────┐
│ soleur_platform MCP Server (in-process)          │
│                                                   │
│  canUseTool callback:                            │
│    read tools → auto-approve                     │
│    write tools → AskUserQuestion → review gate   │
│    destructive → reject                          │
│                                                   │
│  Token: generateInstallationToken(installationId)│
│  Audit: log every request                        │
└──────────────┬────────────────────────────────────┘
               │ HTTPS (server-side)
               ▼
┌─────────────────────────────────────────────────┐
│ GitHub API (api.github.com)                       │
└─────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **MCP tools, not HTTP proxy.** The agent calls MCP tools via stdio. The platform server executes GitHub API calls with its own token. The agent never gets network access or sees the token. This is functionally identical to a proxy but uses the existing MCP infrastructure.

2. **Extend existing GitHub App.** The Soleur GitHub App already exists with installation token generation (`github-app.ts:408-447`). We add permissions (`actions:write`, `checks:read`) to the app manifest. No new app registration needed.

3. **Tiered gating in `canUseTool`.** The existing `canUseTool` callback (`agent-runner.ts:600-633`) already gates `AskUserQuestion`. We add tool-name-based gating: read tools pass through, write tools trigger a review gate, destructive patterns are rejected.

4. **Reuse credential helper for git push.** `workspace.ts:139-145` already creates ephemeral credential helper scripts for `git clone`. The same pattern works for `git push` — write temp script, push, delete immediately.

5. **[Deferred] Scoped installation tokens.** ~~Scope tokens per operation.~~ Deferred per review — tokens are ephemeral (1hr), server-side only, and the agent never sees them. The architecture already neutralizes the threat. Revisit if a security audit demands it.

6. **Tools hardcode owner/repo from workspace metadata.** MCP tools do NOT accept `owner` or `repo` as parameters. They read the connected repo from the user's workspace record in Supabase. This prevents an agent from targeting arbitrary repos.

7. **Protected branch patterns.** "main", "master", and the repo's default branch (fetched via API on workspace connection) are protected. Pattern matching: exact match against a hardcoded list plus the stored default branch. No regex configurability for P3 — keep it simple.

### Implementation Phases

#### Phase 1: Tiered Gating Infrastructure (#1926)

Extend `canUseTool` with tiered permission logic and audit logging. This is the foundation all other phases depend on.

**Files to modify:**

- `apps/web-platform/server/agent-runner.ts` — add tiered gating logic to `canUseTool`, add CI/CD MCP tool definitions inline

**Tasks:**

- [ ] 1.1 Add tiered gate logic to `canUseTool` via switch on tool name: `auto-approve` | `gated` | `blocked`
- [ ] 1.2 For `gated` tools: trigger `AskUserQuestion` with tool name, parameters, and a human-readable description of what the agent wants to do
- [ ] 1.3 For `blocked` patterns: reject with clear error message (e.g., "Force-push is not allowed from cloud agents")
- [ ] 1.4 Add inline structured audit logging in `canUseTool`: `console.log(JSON.stringify({ tool, tier, decision, sessionId, repo, ts: Date.now() }))`
- [ ] 1.5 Update GitHub App manifest to add `actions:write` and `checks:read` permissions (requires App settings page update)
- [ ] 1.6 Add graceful degradation for installations that have not yet approved the new permissions — detect 403 from GitHub, surface message to founder: "Your Soleur app installation needs updated permissions. Visit [install URL] to approve."
- [ ] 1.7 Write tests for tiered gating logic (unit tests for canUseTool, integration test for review gate flow)

**Blocked patterns (validated in tool handler, not string matching):**

- `github_push_branch`: tool handler validates branch name against protected list (`main`, `master`, stored default branch). Only `--force` and `--force-with-lease` are blocked — validated as explicit boolean parameters on the tool schema, not by string-matching CLI flags.
- Any `DELETE` method GitHub API calls rejected at the `github-api.ts` fetch wrapper level.

#### Phase 2: Read CI Status (#1927)

Add read-only MCP tools for CI visibility. First consumer of the gating infrastructure.

**Files to modify:**

- `apps/web-platform/server/agent-runner.ts` — add read tools inline
- `apps/web-platform/server/github-api.ts` (new) — thin GitHub API fetch wrapper using `generateInstallationToken()`

**Tasks:**

- [ ] 2.1 Create `github-api.ts`: thin wrapper around `fetch` using `generateInstallationToken()` for auth. Reject `DELETE` method calls at this layer.
- [ ] 2.2 Add `github_read_ci_status` tool: returns recent workflow runs with status (pass/fail/in-progress), commit SHA, branch, run URL, and workflow name/ID (eliminates need for separate `list_workflows` tool)
- [ ] 2.3 Add `github_read_workflow_logs` tool: returns run conclusion, failure annotations (from GitHub Check Annotations API), and the run URL. Does NOT download the full log zip — agents can request the founder check the URL for full logs. If annotations are empty, falls back to returning the last 100 lines of the most recent failed step via the jobs API.
- [ ] 2.4 Register tools with `auto-approve` gate tier in `canUseTool`
- [ ] 2.5 Add `allowedTools` entries for the new tools in agent-runner.ts
- [ ] 2.6 Write tests: mock GitHub API responses, verify token generation, verify annotation extraction

**Log strategy (simplified per review):** Prefer GitHub Check Annotations API (structured failure data, small payload) over raw log zip download. Fallback to last 100 lines of the failed step only if annotations are empty. This avoids downloading multi-MB zips while still giving agents actionable failure context.

#### Phase 3: Trigger Workflows (#1928)

Add gated workflow dispatch tool. Depends on Phase 1 (gating) and Phase 2 (status reading).

**Files to modify:**

- `apps/web-platform/server/agent-runner.ts` — add trigger tool inline
- `apps/web-platform/server/github-api.ts` — add dispatch method

**Tasks:**

- [ ] 3.1 Add `github_trigger_workflow` tool: accepts workflow ID and optional `inputs` object
- [ ] 3.2 Register with `gated` tier — `canUseTool` triggers review gate before execution
- [ ] 3.3 Review gate message: "Agent wants to trigger workflow **{name}** on branch **{ref}**. Allow?"
- [ ] 3.4 After dispatch, automatically poll `github_read_ci_status` and return the new run ID so the agent can track progress
- [ ] 3.5 Rate limit: max 10 workflow triggers per session (prevent runaway loops)
- [ ] 3.6 Write tests: verify gate fires, verify dispatch API call, verify rate limiting

**Key learning:** `workflow_dispatch` requires `actions:write` permission (learning: 2026-03-16). The GitHub App manifest update in Phase 1 covers this.

#### Phase 4: Open PRs (#1929)

Add gated branch push and enhance existing PR creation. Highest trust action.

**Files to modify:**

- `apps/web-platform/server/agent-runner.ts` — add push tool inline, gate existing PR tool
- `apps/web-platform/server/github-api.ts` — add PR creation method (or reuse existing)
- `apps/web-platform/server/workspace.ts` — extract credential helper into reusable function

**Tasks:**

- [ ] 4.1 Extract credential helper creation from `provisionWorkspaceWithRepo` (`workspace.ts:139-145`) into a reusable `withCredentialHelper(installationId, fn)` function
- [ ] 4.2 Add `github_push_branch` tool: pushes current workspace HEAD to a feature branch on the remote. Tool schema accepts `branch` (string) and `force` (boolean, default false). The handler rejects if `force` is true or if `branch` matches a protected pattern.
- [ ] 4.3 Validate branch name in handler: reject exact matches against `main`, `master`, and the stored default branch
- [ ] 4.4 Register `github_push_branch` with `gated` tier
- [ ] 4.5 Add review gate to existing `create_pull_request` tool (currently ungated)
- [ ] 4.6 Review gate message for push: "Agent wants to push to branch **{branch}** ({n} commits). Allow?"
- [ ] 4.7 Review gate message for PR: "Agent wants to open PR: **{title}** ({base} <- {head}). Allow?"
- [ ] 4.8 Set git commit author to `Soleur Agent <agent@soleur.ai>` (hardcoded)
- [ ] 4.9 Write tests: verify branch validation, verify credential helper cleanup, verify gate fires

**Key learnings:**

- Git push must use credential helper pattern, cleaned in `finally` block (learning: 2026-03-29)
- PRs created by GITHUB_TOKEN don't trigger workflows; App installation tokens do (learning: 2026-03-02)
- Never use `[skip ci]` on commits destined for PRs with required checks (learning: 2026-03-23)
- Validate all inputs mechanically — never trust agent self-assessment (learning: 2026-03-05)

## Alternative Approaches Considered

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| HTTP proxy between agent and GitHub | Clean separation, language-agnostic | New infrastructure to build, maintain, and secure. Duplicates MCP server pattern that already exists. | Rejected — MCP tools are functionally identical and already implemented |
| Direct network access (`allowedDomains: ["api.github.com"]`) | Simplest change | Exfiltration risk via gists, issue comments, cross-repo access. No request-level validation. | Rejected — violates security posture |
| User-provided PAT instead of GitHub App | Simplest auth | Over-scoped (all repos), user manages lifecycle, no rotation | Rejected — App model is already implemented |
| New GitHub App (separate from repo connection) | Clean permission separation | Founder installs two apps, more onboarding friction, duplicate token management | Rejected — extend existing app |

## Acceptance Criteria

### Functional Requirements

- [ ] Agent can list workflows on the connected repo
- [ ] Agent can read CI status (pass/fail/in-progress) for recent workflow runs
- [ ] Agent can read truncated workflow logs for failed jobs
- [ ] Agent can trigger a workflow_dispatch event after founder confirmation
- [ ] Agent can push commits to feature branches after founder confirmation
- [ ] Agent can open PRs after founder confirmation
- [ ] Force-push, push to main/master, and branch deletion are blocked unconditionally
- [ ] All MCP tool invocations are audit-logged

### Non-Functional Requirements

- [ ] Installation tokens are never exposed to the agent subprocess
- [ ] Credential helpers are ephemeral — created per-operation, deleted in `finally`
- [ ] Rate limit: max 10 workflow triggers per session
- [ ] Log truncation: max 200 lines per failed job returned to agent
- [ ] Review gate timeout: 5 minutes (existing pattern)

### Quality Gates

- [ ] Unit tests for tiered gating logic
- [ ] Unit tests for branch name validation and blocked patterns
- [ ] Integration tests for review gate flow (mock WebSocket)
- [ ] Security review: verify agent cannot access token, cannot bypass gate, cannot reach GitHub directly

## Test Scenarios

### Acceptance Tests

- Given a connected repo with CI workflows, when agent calls `github_list_workflows`, then it returns workflow names and IDs without triggering a review gate
- Given a recent workflow run, when agent calls `github_read_ci_status`, then it returns status, commit SHA, branch, and URL
- Given a failed workflow run, when agent calls `github_read_workflow_logs`, then it returns truncated logs (last 200 lines per failed job)
- Given agent calls `github_trigger_workflow`, when founder approves in the review gate, then the workflow is dispatched and the agent receives the run ID
- Given agent calls `github_trigger_workflow`, when founder rejects in the review gate, then the dispatch does not happen and agent receives a rejection message
- Given agent calls `github_push_branch` targeting `main`, then the tool rejects immediately without triggering a review gate
- Given agent calls `github_push_branch` targeting `feat-x`, when founder approves, then commits are pushed and credential helper is cleaned up
- Given agent calls `create_pull_request`, when founder approves, then PR is created on the connected repo

### Edge Cases

- Given the GitHub App installation token is expired, when agent calls any CI tool, then a new token is generated automatically (existing caching in `generateInstallationToken`)
- Given the repo has no workflows, when agent calls `github_list_workflows`, then it returns an empty list (not an error)
- Given agent triggers 10 workflows in one session, when agent attempts an 11th, then it is rate-limited with a clear message
- Given founder disconnects during a review gate, when the 5-minute timeout expires, then the gate rejects and agent receives a timeout message
- Given a workflow log exceeds 1MB, when agent reads it, then only the last 200 lines per failed job are returned

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Three architecture decisions resolved: GitHub App auth, server-side proxy (now MCP tools), tiered review gates. Two ADRs recommended. Implementation complexity reduced significantly by reusing existing MCP server pattern.

### Product (CPO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Scope decomposed into 4 independent slices to mitigate risk. Key UX: review gate messages must be clear and actionable ("Agent wants to trigger workflow X" not "approve tool call"). No new user-facing pages — all interaction through existing conversation UI.

## Dependencies and Prerequisites

| Dependency | Status | Notes |
|------------|--------|-------|
| #1060 Project repo connection | CLOSED (2026-03-29) | Agents can clone founder's repo |
| #1044 Multi-turn continuity | CLOSED (2026-03-27) | Agents can iterate on CI failures |
| #1076 Secure token storage | CLOSED (2026-04-07) | BYOK encryption available (not needed for this — App tokens are server-side) |
| GitHub App manifest update | Required | Add `actions:write` and `checks:read` permissions |

## Risk Analysis and Mitigation

| Risk | Severity | Mitigation |
|------|----------|------------|
| Agent attempts to exfiltrate data via PR description or commit message | Medium | Proxy pattern (MCP tools) means agent never has direct GitHub API access. PR content is visible to founder via review gate. |
| GitHub App rate limits hit across multiple users | Low | Installation tokens have per-installation limits (5000 req/hr). Monitor via audit log. |
| Credential helper not cleaned up on crash | Medium | Use `finally` block (existing pattern). Add process exit handler as defense-in-depth. |
| Agent triggers expensive CI workflows repeatedly | Medium | Rate limit: 10 triggers per session. Founder approval required for each. |
| GPG-signed commit requirement blocks push | Low | Document as known limitation. Agent pushes with Soleur App identity, not founder identity. |

## References and Research

### Internal References

- MCP server creation: `agent-runner.ts:438-501`
- Installation token generation: `github-app.ts:408-447`
- canUseTool callback: `agent-runner.ts:600-633`
- Review gate flow: `review-gate.ts`
- Credential helper: `workspace.ts:139-145`
- Env allowlist: `agent-env.ts:12-28`
- Bash sandbox: `bash-sandbox.ts:13-34`

### Institutional Learnings

- Token revocation breaks persist step: `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`
- workflow_dispatch permissions: `2026-03-16-github-actions-workflow-dispatch-permissions.md`
- Autonomous pipeline pitfalls: `2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`
- canUseTool defense-in-depth: `2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- Review gate promise leak: `2026-03-20-review-gate-promise-leak-abort-timeout.md`
- Review gate selection validation: `2026-03-27-review-gate-selection-validation-web-platform.md`
- Repo connection implementation: `2026-03-29-repo-connection-implementation.md`

### Related Issues

- Parent: #1062
- Slice 1 (infra): #1926
- Slice 2 (read): #1927
- Slice 3 (trigger): #1928
- Slice 4 (PRs): #1929
- Domain leader stale data fix: #1930
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-10-cicd-integration-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cicd-integration/spec.md`
