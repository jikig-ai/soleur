---
title: "feat: server-side PR creation endpoint for agent-driven pull requests"
type: feat
date: 2026-04-06
semver: minor
---

# feat: server-side PR creation endpoint for agent-driven pull requests

## Overview

Soleur agents can clone, pull, and push to user repos via GitHub App installation tokens and ephemeral credential helpers. However, agents cannot create pull requests because: (1) the agent subprocess has no network access (sandbox: `allowedDomains: []`), (2) GitHub tokens are explicitly blocked from the agent environment (`agent-env.ts` allowlist), and (3) there is no custom tool or API endpoint for PR creation.

This plan adds a `create_pull_request` custom tool via the Agent SDK's in-process MCP server pattern (`createSdkMcpServer` + `tool` from `@anthropic-ai/claude-agent-sdk`). The tool handler runs server-side with full access to `generateInstallationToken`, calls the GitHub API (`POST /repos/{owner}/{repo}/pulls`), and returns the PR URL to the agent. No tokens leave the server process.

## Problem Statement / Motivation

- Agents push branches via `session-sync.ts` but have no way to open PRs
- The `/ship` skill and autonomous workflows (`one-shot`) need PR creation to complete the development cycle
- Exposing tokens to agents would violate the security model documented in `agent-env.ts` (CWE-526)
- A REST API route (like `/api/repo/create`) would require browser-side authentication (Supabase cookies) -- agents don't have browser sessions
- The Agent SDK's in-process MCP server runs within the server process, inheriting server credentials naturally

## Proposed Solution

### Architecture: In-Process MCP Server Tool

```
Agent (sandboxed)
    │
    ├── calls tool: mcp__soleur_platform__create_pull_request
    │
    └── Agent SDK routes to in-process MCP server handler
            │
            ├── Validates inputs (owner/repo, head, base, title)
            ├── Looks up github_installation_id from userId (closure)
            ├── Calls generateInstallationToken(installationId)
            ├── Calls GitHub API: POST /repos/{owner}/{repo}/pulls
            └── Returns { url, number, html_url } to agent
```

### Why MCP Server, Not REST API Route?

| Approach | Auth Model | Agent Can Call? | Token Safety |
|----------|-----------|-----------------|--------------|
| REST route (`/api/repo/pull-request`) | Supabase cookies (browser) | No -- agent has no browser session | Safe |
| canUseTool intercept | Custom tool name match | Yes, but fragile | Safe |
| **In-process MCP server** | Server-side closure (userId) | **Yes -- native tool** | **Safe** |

The MCP server pattern is the SDK-recommended approach for custom tools. The tool handler receives the agent's input as typed args and has access to server-side state via closure (userId, installationId). No new authentication mechanism needed.

## Technical Approach

### Implementation Phases

#### Phase 1: PR Creation Function in github-app.ts

Add a `createPullRequest` function to `apps/web-platform/server/github-app.ts`:

- Input: `installationId`, `owner`, `repo`, `head` (branch), `base` (default: `main`), `title`, `body` (optional)
- Uses `generateInstallationToken()` (existing, cached)
- Calls `POST /repos/{owner}/{repo}/pulls` via `githubFetch`
- Returns `{ url: string; number: number; htmlUrl: string }`
- Error handling: throws on error (consistent with `createRepo`); the MCP tool handler wraps in try/catch to return `isError` content

**File:** `apps/web-platform/server/github-app.ts`

#### Phase 2: Inline MCP Server in Agent Runner

Define the tool factory inline in `startAgentSession` within `agent-runner.ts` -- one tool does not warrant a separate module. Extract to `agent-tools.ts` only when a second tool is added.

The tool derives `owner`/`repo` server-side from the user's `repo_url` (already in the users table), so the agent only provides branch, title, and body. This eliminates mismatch risk (agent guessing a repo it can't access).

```typescript
// Inline in startAgentSession, after querying user data
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

// Parse owner/repo from repo_url (e.g., "https://github.com/owner/repo")
const repoUrl = new URL(user.repo_url);
const [, owner, repo] = repoUrl.pathname.split("/");

const createPr = tool(
  "create_pull_request",
  "Create a pull request on the user's connected GitHub repository",
  {
    head: z.string().describe("Branch containing changes"),
    base: z.string().default("main").describe("Target branch"),
    title: z.string().describe("PR title"),
    body: z.string().optional().describe("PR description (markdown)"),
  },
  async (args) => {
    try {
      const result = await createPullRequest(
        installationId, owner, repo,
        args.head, args.base, args.title, args.body,
      );
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error creating PR: ${(err as Error).message}` }],
        isError: true,
      };
    }
  },
);

const toolServer = createSdkMcpServer({
  name: "soleur_platform",
  version: "1.0.0",
  tools: [createPr],
});
```

#### Phase 3: Wire Into Agent Runner

Modify `startAgentSession` in `apps/web-platform/server/agent-runner.ts`:

1. **Add `github_installation_id` and `repo_url` to the existing select query** -- the current query selects `workspace_path, repo_status` only; add the two new columns
2. If `installationId` and `repo_url` exist, create the MCP server inline (Phase 2 code)
3. Pass to `query()` options:
   - `mcpServers: { soleur_platform: toolServer }`
   - Add `"mcp__soleur_platform__create_pull_request"` to the `allowedTools` array (SDK requires explicit listing for in-process MCP tools)
4. **Handle canUseTool deny-by-default** -- the current canUseTool callback denies unrecognized tools. Add a check for `mcp__` prefixed tools: `if (toolName.startsWith("mcp__")) return { behavior: "allow" }` before the deny-by-default fallback. This covers the current tool and future MCP tools without per-tool enumeration.

When `installationId` is null (no GitHub App installed), skip the MCP server -- the tool simply won't be available, which is correct behavior.

**File:** `apps/web-platform/server/agent-runner.ts`

#### Phase 4: Tests

Write tests covering:

1. **`createPullRequest` unit tests** (`apps/web-platform/test/github-app-pr.test.ts`):
   - Happy path: returns URL and PR number
   - 422 error: branch not found or no diff between branches
   - 422 error: PR already exists for same head/base
   - 404 error: repo not found or no access
   - Token generation failure propagation

2. **Agent tool integration tests** (`apps/web-platform/test/agent-runner-tools.test.ts`):
   - Verify `mcpServers` is passed to `query()` when `installationId` exists
   - Verify `mcpServers` is omitted when `installationId` is null
   - Verify tool handler wraps errors in `isError` content (not crash)
   - Verify `canUseTool` allows `mcp__` prefixed tools (not blocked by deny-by-default)

## Non-Goals

- **PR merge/update/close** -- out of scope for this issue; tracked separately
- **PR review (request reviewers, add labels)** -- future enhancement
- **Cross-repo PRs (forks)** -- not needed for MVP; agents work on the user's own repos
- **Browser UI for PR creation** -- agents invoke the tool directly; no UI needed
- **Branch creation workflow** -- agents are responsible for creating and pushing branches before calling `create_pull_request`; this tool assumes the branch already exists on the remote (session-sync handles the push)
- **Rate limiting PR creation** -- the existing session-level rate limiter (`sessionThrottle`) constrains total agent activity; per-tool rate limiting is deferred unless abuse is observed

## Acceptance Criteria

### Functional Requirements

- [ ] Agent can invoke `mcp__soleur_platform__create_pull_request` tool during a session
- [ ] Tool creates a PR on the user's connected GitHub repo using the installation token
- [ ] Tool returns the PR URL, number, and HTML URL to the agent
- [ ] Tool returns a structured error (not crash) when the branch doesn't exist or has no diff
- [ ] Tool is only available when the user has a GitHub App installation (`installationId` is not null)
- [ ] No GitHub tokens are exposed to the agent subprocess environment

### Non-Functional Requirements

- [ ] Token generation uses existing cache in `github-app.ts` (no extra API calls for warm cache)
- [ ] Tool handler validates all inputs via Zod schema before calling GitHub API
- [ ] PR body is optional (GitHub defaults to empty)
- [ ] Owner/repo derived server-side from `repo_url` -- agent does not provide these
- [ ] Error messages from GitHub API are sanitized before returning to agent (no internal paths or tokens)
- [ ] `canUseTool` allows `mcp__` prefixed tools (not blocked by deny-by-default fallback)

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given an agent session with a connected repo, when the agent calls `create_pull_request` with valid branch/title, then a PR is created and the URL is returned
- Given an agent session with a connected repo, when the agent calls `create_pull_request` with a non-existent branch, then a structured error is returned (not a crash)
- Given an agent session with a connected repo, when the agent calls `create_pull_request` with identical head and base branches, then a 422 error is returned indicating no diff
- Given an agent session WITHOUT a connected repo, when the tool list is inspected, then `mcp__soleur_platform__create_pull_request` is NOT available
- Given an agent session with a connected repo, when the GitHub API returns 404, then the error is returned with sanitized message

### Edge Cases

- Given a PR already exists for the same head/base combination, when `create_pull_request` is called, then GitHub returns 422 -- the tool surfaces this as a user-friendly error
- Given the installation token is expired, when `create_pull_request` is called, then `generateInstallationToken` refreshes it transparently (existing cache logic)

## Technical Considerations

### Security

- **Token isolation**: Installation tokens stay in the server process. The MCP server handler runs in-process, not in the sandboxed agent subprocess.
- **Input validation**: Zod schema validates all inputs. Owner/repo names are validated against GitHub's naming rules (alphanumeric, hyphens, dots, underscores).
- **Error sanitization**: GitHub API error bodies may contain internal details; sanitize before returning to agent (strip URLs, paths, tokens).
- **Installation scope**: The installation token is scoped to repos the user authorized via the GitHub App -- no privilege escalation possible.

### Performance

- No additional network round-trips for warm token cache (5-minute safety margin already exists)
- In-process MCP server adds zero latency vs. a subprocess MCP server
- Single GitHub API call per PR creation

### Dependencies

- `@anthropic-ai/claude-agent-sdk` v0.2.80 (already installed) -- provides `tool`, `createSdkMcpServer`
- `zod` -- verify in `apps/web-platform/package.json` at implementation time; the SDK likely brings it as a peer/transitive dependency but confirm before relying on it

### canUseTool Interaction

The current `canUseTool` callback in `agent-runner.ts` has a deny-by-default fallback for unrecognized tools (lines ~502-506). In-process MCP server tools may or may not route through `canUseTool` -- the SDK documentation does not explicitly clarify this. The plan adds a defensive `mcp__` prefix check before the deny-by-default block to prevent runtime failures. This must be tested during implementation: if MCP tools bypass `canUseTool` entirely, the check is a harmless no-op.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| REST route + internal auth token | Rejected | Requires inventing a new auth mechanism for agent-to-server calls; agents have no network access |
| canUseTool intercept on custom tool name | Rejected | Works but is an ad-hoc pattern; SDK's MCP server is the designed extensibility point |
| Expose `GITHUB_TOKEN` to agent env | Rejected | Violates CWE-526 isolation; agent could use token for unintended operations |
| WebSocket message type for PR creation | Rejected | Agents don't have direct WS access; would require routing through the entire WS handler |
| **In-process MCP server** | **Chosen** | SDK-recommended pattern; type-safe; server-side handler with closure access; no new auth |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a pure backend infrastructure feature extending the existing GitHub App integration. No new services, no new user-facing pages, no legal/marketing/ops implications. The CTO assessment: architecturally sound -- follows the credential helper philosophy (ephemeral, scoped tokens; server-side only) and uses the SDK's designed extensibility mechanism. The in-process MCP server is strictly better than ad-hoc canUseTool interception for custom tools.

## References & Research

### Internal References

- `apps/web-platform/server/github-app.ts` -- existing token generation, repo CRUD
- `apps/web-platform/server/agent-env.ts` -- env isolation allowlist
- `apps/web-platform/server/agent-runner.ts:356-509` -- `query()` options, canUseTool hooks
- `apps/web-platform/server/session-sync.ts` -- push/pull pattern with credential helpers
- `knowledge-base/project/learnings/2026-03-29-repo-connection-implementation.md` -- credential helper philosophy
- GitHub issue: [#1648](https://github.com/jikig-ai/soleur/issues/1648)

### External References

- [Claude Agent SDK: Custom Tools](https://platform.claude.com/docs/en/agent-sdk/custom-tools) -- `createSdkMcpServer`, `tool` API
- [GitHub REST API: Create a pull request](https://docs.github.com/en/rest/pulls/pulls#create-a-pull-request) -- `POST /repos/{owner}/{repo}/pulls`
