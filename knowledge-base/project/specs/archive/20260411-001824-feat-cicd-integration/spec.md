# Feature: CI/CD Integration for Cloud Platform Agents

## Problem Statement

Cloud platform agents cannot interact with the founder's CI/CD pipeline. The CLI plugin has full local toolchain access (git push, gh CLI, test runners), but cloud agents are sandboxed with no outbound network and no GitHub credentials. This makes the cloud platform strictly inferior for engineering workflows.

## Goals

- Agents can read CI status, trigger workflows, and open PRs on the founder's connected repo
- All GitHub API access routes through a server-side proxy (agent never touches github.com directly)
- Tiered review gates enforced at the proxy layer (auto-approve reads, gate writes, block destructive actions)
- GitHub App provides per-repo authentication with short-lived, automatically rotating tokens
- Pattern generalizes to future service integrations (#1050)

## Non-Goals

- Self-hosted CI runner support (GitHub Actions only for P3)
- Cross-repo operations (agent can only access the connected workspace repo)
- Direct network access to github.com from agent sandbox
- GPG commit signing from cloud agents (defer — document limitation)
- Local test execution in workspace (already possible if deps installed; not a CI/CD feature)

## Functional Requirements

### FR1: GitHub App onboarding

Founder installs the Soleur GitHub App on their repo during project setup. The platform stores the installation ID and can generate short-lived installation tokens scoped to that repo.

### FR2: Read CI status and logs

Agent can view: workflow run status (pass/fail/in-progress), workflow run logs (truncated/summarized for context), check suite results, and commit status checks. All via proxy.

### FR3: Trigger GitHub Actions workflows

Agent can trigger `workflow_dispatch` events on existing workflows in the connected repo. Requires founder confirmation via review gate before the proxy forwards the request.

### FR4: Open pull requests

Agent can push to feature branches and open PRs on the connected repo. Requires founder confirmation via review gate. Force-push, push to main/master, and branch deletion are blocked unconditionally at the proxy.

## Technical Requirements

### TR1: Server-side proxy

All GitHub API calls from agent sessions route through a platform-side proxy. The proxy validates: (a) target repo matches the workspace's connected repo, (b) API endpoint is on the allowlist for the action's review gate tier, (c) request is within rate limits. The agent subprocess receives a proxy URL, not a GitHub token.

### TR2: GitHub App authentication

Register a Soleur GitHub App with permissions: `contents:write`, `actions:write`, `pull_requests:write`, `checks:read`. Installation tokens are short-lived (1 hour) and generated server-side. The agent never sees the app private key or long-lived credentials.

### TR3: Tiered review gates

| Tier | Actions | Enforcement |
|------|---------|-------------|
| Auto-approve | Read CI status, read logs, read workflow runs | Proxy passes through |
| Gate | Trigger workflows, push to feature branches, open PRs | Proxy holds until founder approves |
| Block | Force-push, push to main/master, delete branches, close issues | Proxy rejects unconditionally |

### TR4: Audit logging

All proxy requests are logged with: timestamp, agent session ID, action type, target repo, review gate tier, approval status, and response code. Enables post-hoc review of agent CI/CD activity.
