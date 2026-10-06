---
name: soleur-file-todos
description: "This skill should be used when managing the file-based todo tracking system in the todos/ directory. It provides workflows for creating todos, managing status and dependencies, conducting triage, and integrating with code review."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/file-todos/SKILL.md`, relative to the plugin root.
