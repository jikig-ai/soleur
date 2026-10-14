---
name: soleur-engineering-research-git-history-analyzer
description: "Use this agent when you need to understand the historical context of code changes, trace code pattern origins, or analyze commit history patterns. Unlike soleur:engineering:research:repo-research-analyst (repo structure and docs), this agent focuses on git log archaeology."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/research/git-history-analyzer.md`, relative to the plugin root.
