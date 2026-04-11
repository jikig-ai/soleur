---
title: "CI/CD MCP tool implementation: tiered gating and multi-agent review findings"
date: 2026-04-10
category: integration-issues
tags:
  - mcp-tools
  - canUseTool
  - tiered-gating
  - github-api
  - review-agents
module: web-platform/server
symptoms:
  - "GitHub API endpoint mismatch: workflow run ID used where commit SHA expected"
  - "Audit logging bypassed structured logger"
  - "Credential helper used double quotes (shell injection defense-in-depth gap)"
---

# Learning: CI/CD MCP Tool Tiered Gating and Review Findings

## Problem

Implementing 5 MCP tools for cloud platform agents to interact with GitHub CI/CD (read status, read logs, trigger workflows, push branches, open PRs). The key architectural challenge was extending the existing `canUseTool` callback with tiered permission logic while maintaining the security invariant that agents never see GitHub tokens.

## Solution

Extracted tiered gating into `tool-tiers.ts` (following the `tool-path-checker.ts` pattern), created `github-api.ts` as a centralized fetch wrapper, and split tool handlers into `ci-tools.ts`, `trigger-workflow.ts`, and `push-branch.ts`. The multi-agent review (5 agents in parallel) caught several issues before merge:

1. **Wrong API endpoint**: `readWorkflowLogs` used `/commits/${runId}/check-runs` but this endpoint expects a commit SHA, not a workflow run ID. Fix: fetch the run first to get `head_sha`, then query check-runs for that SHA.

2. **Audit logging via `console.log`**: The tiered gating code used `console.log(JSON.stringify({...}))` instead of the project's pino-based structured logger. This bypassed log levels, filtering, and redaction. Fix: switched to `log.info({ sec: true, tool, tier, decision, repo }, "Platform tool gated")`.

3. **`fetchFallbackLog` bypassed `github-api.ts`**: Used a dynamic import of `generateInstallationToken` and raw `fetch()` to get plain-text job logs, bypassing the centralized wrapper's error handling and DELETE guard. Fix: added `githubApiGetText()` to `github-api.ts`.

4. **Missing `defaultBranch` in push tool**: The push tool validated against `main`/`master` but not the repo's actual default branch. Fix: fetch default branch via GitHub API at session start and pass to `pushBranch`.

5. **Credential helper shell quoting**: Used double quotes around token in the credential helper script. While GitHub tokens are safe for shell interpolation today, single quotes provide defense-in-depth against future format changes.

## Key Insight

Multi-agent parallel review (5 specialized agents) is highly effective for catching cross-cutting concerns that single-focus implementation misses. The `readWorkflowLogs` API path bug was caught by 3 independent agents (performance, architecture, security) — each from a different angle (correctness, abstraction consistency, silent failure mode). The pattern of "write tests that mock API responses" can mask URL construction bugs because mocks return data for any URL. Adding URL assertions to test mocks (e.g., `expect(mockFetch.mock.calls[1][0]).toContain("/commits/abc123/check-runs")`) would have caught this in the RED phase.

## Prevention

- When writing tests that mock HTTP APIs, always assert the URL being called — not just the shape of the response. This catches path construction bugs that mocks silently swallow.
- When adding a new centralized wrapper (like `github-api.ts`), immediately check for call paths that bypass it. Dynamic imports of lower-level functions are a code smell indicating the wrapper's API surface is incomplete.
- Use the structured logger for all audit-relevant logging from the start. `console.log` in a pino codebase is always a mistake.

## Session Errors

Session errors: none detected.

## References

- Spec: `knowledge-base/project/specs/feat-cicd-integration/spec.md`
- Plan: `knowledge-base/project/plans/2026-04-10-feat-cicd-integration-plan.md`
- Related: `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- Issues: #1926, #1927, #1928, #1929
