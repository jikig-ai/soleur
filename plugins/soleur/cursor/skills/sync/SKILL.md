---
name: sync
description: "This skill analyzes the codebase and populates the knowledge-base with conventions, patterns, and technical debt"
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `commands/sync.md`, relative to the plugin root.
