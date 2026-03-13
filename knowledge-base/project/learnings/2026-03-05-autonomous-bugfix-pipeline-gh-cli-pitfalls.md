---
title: "Autonomous bug-fix pipeline: gh CLI, workflow_run, and auto-revert pitfalls"
date: 2026-03-05
category: integration-issues
module: ci-cd
tags:
  - github-actions
  - gh-cli
  - workflow_run
  - auto-merge
  - auto-revert
  - bot-fix-pipeline
severity: medium
related_issues:
  - 377
  - 370
---

# Learning: Autonomous bug-fix pipeline gh CLI and workflow design pitfalls

## Problem

Building an end-to-end autonomous bug-fix pipeline (scheduled issue selection, agent fix, auto-merge gate, post-merge monitor with auto-revert) surfaced nine distinct pitfalls across gh CLI behavior, GitHub Actions `workflow_run` semantics, bot identity formats, and git race conditions.

## Solution

### 1. `gh pr list --head` does exact matching, not prefix matching

`gh pr list --head "bot-fix/"` returns nothing because `--head` expects an exact branch name, not a prefix. To find all PRs whose branch starts with `bot-fix/`, pipe through jq:

```bash
gh pr list --state open --json number,headRefName,createdAt \
  --jq '[.[] | select(.headRefName | startswith("bot-fix/"))] | sort_by(.createdAt) | last | .number // empty'
```

### 2. `workflow_dispatch` has no `workflow_run` context

A `workflow_dispatch` trigger does not populate `github.event.workflow_run.*`. If a workflow supports both `workflow_run` and `workflow_dispatch`, conditional fields like `conclusion` and `head_sha` must be resolved from inputs first, falling back to the event context:

```bash
SHA="${DISPATCH_SHA:-$RUN_SHA}"
CONCLUSION="${DISPATCH_CONCLUSION:-$RUN_CONCLUSION}"
```

### 3. Squashed commits use PR title, not branch commit messages

After squash-merge, the commit message on main is the PR title (e.g., `[bot-fix] Fix login timeout`), not the individual branch commit messages. Issue number extraction via `Fix #N` from the commit subject fails because the PR title does not include that pattern. Extract from the PR body instead:

```bash
PR_NUM=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${COMMIT_SHA}/pulls" \
  --jq '.[0].number // empty')
ISSUE_NUM=$(gh pr view "$PR_NUM" --json body --jq '.body' | grep -oP 'Ref #\K\d+' | head -1)
```

### 4. Validate SHA inputs against injection

`commit_sha` from `workflow_dispatch` inputs is user-supplied. Without validation, it can inject arbitrary arguments into `git log` or `git revert`. Enforce hex format:

```bash
if [[ ! "$SHA" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
  echo "::error::Invalid commit SHA format: $SHA"
  exit 1
fi
```

### 5. Verify PR author identity before auto-merge

The auto-merge gate must confirm the PR was created by a recognized bot identity, not by a human who happened to use the `bot-fix/` branch prefix. GitHub Apps use `app/<slug>` as their author login (e.g., `app/claude` for claude-code-action), NOT the `<name>[bot]` suffix convention used by GitHub Actions bots. Match all known formats explicitly:

```bash
PR_AUTHOR=$(gh pr view "$PR_NUM" --json author --jq '.author.login // empty')
ALLOWED=false
case "$PR_AUTHOR" in
  github-actions\[bot\]|*\[bot\]*|app/claude) ALLOWED=true ;;
esac
if [[ "$ALLOWED" != "true" ]]; then
  echo "::warning::PR #$PR_NUM author is '$PR_AUTHOR', not a recognized bot. Skipping auto-merge."
  exit 0
fi
```

When onboarding a new GitHub App, add its identity to the `case` pattern and to the CLA allowlist in `cla.yml`.

### 6. Mechanical priority check prevents privilege escalation

The agent labels the PR `bot-fix/auto-merge-eligible` based on its own assessment, but the workflow must independently verify the source issue is `priority/p3-low`. Without this, a mislabeled or compromised agent could auto-merge fixes for high-priority issues:

```bash
PRIORITY=$(gh issue view "$ISSUE_NUM" --json labels \
  --jq '[.labels[].name | select(startswith("priority/"))] | .[0] // "unknown"')
if [[ "$PRIORITY" != "priority/p3-low" ]]; then
  gh pr edit "$PR_NUM" --remove-label "bot-fix/auto-merge-eligible"
  gh pr edit "$PR_NUM" --add-label "bot-fix/review-required"
fi
```

### 7. Stale checkout race in auto-revert

The `workflow_run` trigger checks out main, but another commit may have landed between the bot-fix merge and the monitor run. Reverting HEAD without verification reverts the wrong commit. Fix: fetch latest main and verify HEAD matches the expected SHA before reverting:

```bash
git fetch origin main
git reset --hard origin/main
if [[ "$(git rev-parse HEAD)" != "$COMMIT_SHA" ]]; then
  echo "::warning::HEAD != expected bot-fix commit. Another push landed. Skipping revert."
  exit 0
fi
git revert --no-edit HEAD
```

### 8. Capture Discord webhook HTTP status

`curl` to a Discord webhook can fail silently (HTTP 429 rate limit, 401 expired URL). Capture the status code and warn on non-2xx, matching the pattern used in `version-bump-and-release.yml`:

```bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d "$PAYLOAD" "$DISCORD_WEBHOOK_URL")
if [[ "$HTTP_CODE" =~ ^2 ]]; then
  echo "Discord notification sent (HTTP $HTTP_CODE)"
else
  echo "::warning::Discord notification failed (HTTP $HTTP_CODE)"
fi
```

### 9. Every workflow step using `gh` CLI needs GH_TOKEN

The `gh` CLI requires `GH_TOKEN` or `GITHUB_TOKEN` in the environment to authenticate. A step that calls `gh pr view` without the token exits with code 4 (auth failure). If the step is not marked `continue-on-error: true`, this fails the entire workflow -- even for non-critical steps like Discord notifications. Always set `GH_TOKEN` in the `env:` block of every `run:` step that uses `gh`:

```yaml
env:
  GH_TOKEN: ${{ github.token }}
```

## Key Insight

When building autonomous CI pipelines that merge code without human review, every assumption the workflow makes about its inputs must be mechanically verified -- branch naming semantics, commit message format, PR authorship, issue priority labels, and git HEAD state. The gh CLI's `--head` flag, `workflow_run` context availability, and squash-merge message rewriting are all sources of silent behavioral divergence from what a developer would expect. Defense-in-depth means the workflow independently re-checks every condition the agent claims to have verified.

## Related

- `2026-02-21-github-actions-workflow-security-patterns.md` -- SHA pinning, input validation, exit code checking
- `2026-03-05-github-output-newline-injection-sanitization.md` -- GITHUB_OUTPUT sanitization in the same CI surface
- `2026-03-03-serialize-version-bumps-to-merge-time.md` -- workflow architecture precedent
- `.github/workflows/scheduled-bug-fixer.yml` -- auto-merge gate implementation
- `.github/workflows/post-merge-monitor.yml` -- auto-revert and issue lifecycle
- `plugins/soleur/skills/fix-issue/SKILL.md` -- Phase 5.5 eligibility check

## Tags
category: integration-issues
module: ci-cd
