# Learning: Insights-driven workflow improvements from usage analytics

## Problem

Claude Code Insights report (100 sessions, 9 days, 459 commits) identified recurring friction patterns:

- Markdown lint errors (MD032/MD038) blocked commits in 5+ sessions
- QA/review phases skipped when dev server wasn't running
- Playwright MCP crashed from Chrome singleton user-data-dir locks
- Stale bare-repo files read after merging PRs
- Dependencies missing at app level (only installed at root)
- Reviewer recommendations followed blindly (Phase 5.5 removed despite being defense-in-depth)

## Solution

Encoded insights as enforceable AGENTS.md rules rather than just documenting them:

1. Added "Code Quality" section: markdownlint before commit, table edit verification, app-level dependency checks, Playwright lock detection, dependency validation before push
2. Added "Review & Feedback" section: read from merged branch not bare repo, never skip QA, confirm before removing plan phases, pre-ship checklist gate
3. Created `/soleur:postmerge` skill to enforce post-merge verification (CI on main, production health, file freshness, browser checks)
4. Configured project-level `.mcp.json` with isolated Chrome profile (`--user-data-dir /tmp/claude-playwright-profile`) to prevent singleton lock crashes

## Key Insight

Usage analytics (like /insights) are a feedback loop for workflow hardening. The pattern is: analytics surface recurring friction -> encode as AGENTS.md rules or skill phases -> friction eliminated in future sessions. Rules beat documentation, hooks beat rules, skills beat ad-hoc instructions.

## Session Errors

1. **Edited AGENTS.md on bare repo instead of worktree** -- Began making changes before creating a worktree. The bare repo has no working tree so the edit didn't persist in git, but it violated the "never edit files in main repo when worktree is active" rule. Recovery: created worktree and re-applied edits there. Prevention: The existing worktree-write-guard.sh hook should have caught this -- investigate why it didn't fire for the Edit tool on the bare repo.

2. **Created directory on bare repo** -- `mkdir -p plugins/soleur/skills/postmerge/` was run on the bare repo root. Recovery: removed with `rmdir` and recreated in the worktree. Prevention: Same worktree-write-guard issue as above.

3. **Invalid settings.json field** -- Attempted to add `mcpServers` key to `.claude/settings.json`, which failed schema validation. MCP servers belong in `.mcp.json`, not settings. Recovery: Created `.mcp.json` instead and added `enabledMcpjsonServers` to settings. Prevention: Check schema before editing settings files, or use `claude mcp add` CLI command.

## Tags

category: workflow
module: insights, agents-md, skills
