---
name: soleur-engineering-workflow-pr-comment-resolver
description: "Use this agent when you need to address comments on pull requests or code reviews by making the requested changes and reporting back on the resolution."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/engineering/workflow/pr-comment-resolver.md`, relative to the plugin root.
