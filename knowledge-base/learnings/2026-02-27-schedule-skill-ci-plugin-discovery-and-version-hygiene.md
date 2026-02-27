# Learning: CI Plugin Discovery and Version Hygiene for Schedule Skill

## Problem

Building `soleur:schedule` — a skill that generates GitHub Actions workflow files to run Soleur skills on cron schedules — revealed two classes of issues:

1. **CI plugin discovery**: `claude-code-action` does not auto-discover local plugins from a checked-out repo. There is no `--plugin` CLI flag and no local path support. Generated workflows could not find the Soleur plugin.
2. **Version collision**: Bumping to 3.4.0 without checking main caused a collision (main already had 3.4.0 from CLA PR #319). The version triad is now a quad with `marketplace.json`.

## Solution

### CI Plugin Discovery

Created `.claude-plugin/marketplace.json` at the repo root — a self-hosting marketplace manifest. Generated workflows use `plugin_marketplaces` and `plugins` inputs:

```yaml
plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'
plugins: 'soleur@soleur'
```

The marketplace file lives at the repo root (not under `plugins/soleur/`) because `claude-code-action` looks for `.claude-plugin/marketplace.json` at the root of the cloned repo.

### Version Collision

Always fetch and check main before bumping: `git fetch origin main && git log --oneline origin/main -3`. The version triad is now a **quad**: `plugin.json`, `CHANGELOG.md`, `README.md`, and `.claude-plugin/marketplace.json`. Updated AGENTS.md pre-commit checklist to include marketplace.json.

## Key Insights

1. **`claude-code-action` has no local plugin discovery** — Any workflow that needs Soleur must use marketplace-based installation. The marketplace file is repo infrastructure, not a plugin artifact.
2. **GitHub Actions `with:` values are NOT shell-expanded** — `$(date +%Y-%m-%d)` in a `prompt:` field is passed literally. Use natural language ("today's date in YYYY-MM-DD format") instead. Shell expansion only works in `run:` blocks.
3. **SHA pinning for annotated tags requires two-step resolution** — `gh api repos/OWNER/REPO/git/ref/tags/v1` returns the tag object SHA, not the commit SHA. Must dereference: `gh api repos/OWNER/REPO/git/tags/$SHA --jq '.object.sha'`.
4. **SKILL.md-driven skills need argument passthrough for agent callers** — Interactive AskUserQuestion prompts block programmatic invocation. Always add a `$ARGUMENTS` bypass path (e.g., `--name`, `--skill`, `--cron`, `--model` flags) so agents can call the skill non-interactively.
5. **Version bumps on parallel branches collide** — Always rebase onto main and verify the next available version before bumping.

## Session Errors

- Edit tool "file not read" errors when editing files not yet read in the session
- Version 3.4.0 collision with main (caught by pattern-recognition reviewer)
- Missing schedule row in README.md Workflow table (caught by pattern-recognition reviewer)
- `$(date)` literal in GitHub Actions `with:` block (caught by security-sentinel)
- CHANGELOG referenced wrong PR number (#312 issue vs #321 PR)

## Tags
category: integration-issues
module: schedule, marketplace, versioning
