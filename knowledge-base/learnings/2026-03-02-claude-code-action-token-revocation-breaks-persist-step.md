# Learning: claude-code-action Post-Step Revokes Token Before Persist Step

## Problem

The `scheduled-competitive-analysis.yml` workflow has a persist step that pushes the competitive intelligence report to `main` after `claude-code-action` generates it. The push fails with:

```
remote: Invalid username or token. Password authentication is not supported for Git operations.
fatal: Authentication failed for 'https://github.com/jikig-ai/soleur.git/'
```

The `claude-code-action` post-step cleanup revokes the GitHub App installation token via `curl -X DELETE .../installation/token`. This runs **after** the action step completes but **before** subsequent workflow steps execute. The persist step inherits revoked credentials from `actions/checkout`.

## Solution

Move the `git push` into the Claude agent's prompt so it executes **during** the `claude-code-action` step, while the App installation token is still valid.

Two blockers prevent a separate post-action persist step:

1. **Token revocation** — `claude-code-action` revokes the App installation token in its post-step cleanup. Re-authenticating with `GITHUB_TOKEN` solves auth but hits blocker #2.
2. **Branch protection** — The CLA Required ruleset blocks direct pushes to main unless the actor has bypass privileges. `GITHUB_TOKEN` pushes as `github-actions[bot]`, which can't be added as a bypass actor via API (it's a platform-builtin, not an installed integration). The Claude App **can** be added as a bypass actor through the GitHub UI.

By pushing inside the agent, the push uses the Claude App's identity (which has bypass) and the token hasn't been revoked yet.

```yaml
prompt: |
  ... run the analysis ...
  After creating the issue, persist the report to main by running:
  1. git add knowledge-base/overview/competitive-intelligence.md
  2. git diff --cached --quiet (if exit 0, skip — unchanged)
  3. git commit -m "docs: update competitive intelligence report"
  4. git push origin main
```

## Key Insight

When `claude-code-action` needs to push generated files, the push must happen **inside the agent prompt** — not in a subsequent workflow step. Two independent issues prevent post-action pushes: (1) the action revokes its own token in cleanup, and (2) `github-actions[bot]` cannot be granted ruleset bypass via the GitHub API (only through the UI, and only for installed Apps).

The general pattern: any file persistence from `claude-code-action` should be part of the agent's instructions, not a separate shell step.

## Session Errors

1. CI workflow auth failure — persist step exit code 128 (the bug itself)
2. Misunderstood user intent — attempted local agent run instead of GitHub Actions dispatch
3. Background task output retrieval failed — TaskOutput and Read both missed the output file
4. Wrong plugin.json path — used `plugins/soleur/plugin.json` instead of `plugins/soleur/.claude-plugin/plugin.json`
5. Wrong agent file path — tried `competitive-intelligence/AGENT.md` instead of `competitive-intelligence.md`

## Related

- [GitHub Actions auto-push vs PR for bot content](2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md) — GITHUB_TOKEN cascade limitations
- [GitHub Actions auto-release permissions](integration-issues/github-actions-auto-release-permissions.md) — explicit `permissions: contents: write`
- [Multi-agent cascade orchestration checklist](2026-03-02-multi-agent-cascade-orchestration-checklist.md) — Task tool allowedTools requirement
- [Schedule skill CI plugin discovery](2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md) — claude-code-action plugin setup

## Tags

category: integration-issues
module: ci-workflows
severity: high
