# Learning: GitHub Actions auto-push vs PR for bot-generated content

## Problem

We needed a GitHub Action to persist an agent-generated file (`competitive-intelligence.md`) back to the repository after each scheduled run. The initial plan used `gh pr merge --squash --auto` to create and auto-merge a PR — respecting the team's PR-based workflow convention.

## Solution

Direct push to main instead of PR-based flow. The workflow adds a shell step that commits and pushes directly after the Claude agent finishes.

Three blockers made the PR approach unworkable:

1. **`allow_auto_merge` is OFF** — `gh pr merge --squash --auto` fails immediately with "auto-merge is not allowed for this repository"
2. **GITHUB_TOKEN cascade limitation** — PRs created by `GITHUB_TOKEN` don't trigger other workflows (`pull_request`, `pull_request_target` events are suppressed). CI and CLA checks never run, so required status checks never pass, and auto-merge waits forever.
3. **No branch protection blocks regular pushes** — the repo's rulesets only prevent force-push and branch deletion on main. Regular `git push origin main` is allowed.

## Key Insight

When a GitHub Action needs to write bot-generated content back to the repo, always check these three things before designing the merge strategy:

1. `gh api repos/{owner}/{repo} --jq '.allow_auto_merge'` — is auto-merge enabled?
2. What required status checks exist? Will they run on bot PRs? (GITHUB_TOKEN cascade says no)
3. What rulesets/branch protection actually block direct pushes? (Often less than you'd assume)

For fully-overwritten, bot-generated content (no meaningful merge possible), direct push is almost always simpler and more reliable than the PR dance. Save PRs for human-authored changes where review adds value.

## Also Learned

- `[skip ci]` in commit messages is ignored for `pull_request`-triggered workflows — only affects `push` triggers
- `git commit` fails silently if `git add` staged nothing (identical content). Always guard with `git diff --cached --quiet` before committing.
- `github-actions[bot]` email is `41898282+github-actions[bot]@users.noreply.github.com` — must be configured explicitly in CI runners.
- SpecFlow analysis (spec-flow-analyzer agent) caught the auto-merge blocker before any code was written — validating its value for CI/workflow features.

## Tags

category: integration-issues
module: github-actions, ci
