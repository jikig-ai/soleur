---
name: soleur-pencil-setup
description: "This skill should be used when Pencil MCP tools are unavailable. Detects Pencil Desktop or a Pencil-extension IDE and registers the MCP server with Claude Code CLI."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/pencil-setup/SKILL.md`, relative to the plugin root.
