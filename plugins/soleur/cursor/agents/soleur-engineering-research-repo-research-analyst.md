---
name: soleur-engineering-research-repo-research-analyst
description: "Use this agent when you need to research a repository's structure, documentation, and patterns -- architecture files, GitHub issues, contribution guidelines, and implementation patterns. Unlike soleur:engineering:research:git-history-analyzer (commit history), this agent examines repo structure, docs, issues, and templates."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `agents/engineering/research/repo-research-analyst.md`, relative to the plugin root.
