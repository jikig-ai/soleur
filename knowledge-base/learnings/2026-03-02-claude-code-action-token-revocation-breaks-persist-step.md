# Learning: claude-code-action Post-Step Revokes Token Before Persist Step

## Problem

The `scheduled-competitive-analysis.yml` workflow has a persist step that pushes the competitive intelligence report to `main` after `claude-code-action` generates it. The push fails with:

```
remote: Invalid username or token. Password authentication is not supported for Git operations.
fatal: Authentication failed for 'https://github.com/jikig-ai/soleur.git/'
```

The `claude-code-action` post-step cleanup revokes the GitHub App installation token via `curl -X DELETE .../installation/token`. This runs **after** the action step completes but **before** subsequent workflow steps execute. The persist step inherits revoked credentials from `actions/checkout`.

## Solution

Re-authenticate in the persist step using `${{ github.token }}` (GITHUB_TOKEN), which is scoped to the job and survives third-party action cleanup:

```yaml
- name: Persist competitive intelligence report
  env:
    GH_TOKEN: ${{ github.token }}
    REPO: ${{ github.repository }}
  run: |
    git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
    # ... git add, commit, push as before
```

Pass both values via `env:` to avoid expression injection in `run:` blocks.

## Key Insight

Any GitHub Actions workflow step that runs **after** `claude-code-action` (or similar actions that manage their own installation tokens) cannot rely on `actions/checkout` credentials. Always re-authenticate with `${{ github.token }}` via `git remote set-url` before any git push in post-action steps.

This applies to any workflow that: (1) uses `claude-code-action` to generate files, then (2) has a separate step to commit/push those files.

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
