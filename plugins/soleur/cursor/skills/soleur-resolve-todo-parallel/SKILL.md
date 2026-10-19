---
name: soleur-resolve-todo-parallel
description: "This skill should be used when resolving all pending CLI todos from the todos/ directory using parallel processing. It reads pending todos, plans resolution order with dependency analysis, and spawns parallel agents."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/resolve-todo-parallel/SKILL.md`, relative to the plugin root.
