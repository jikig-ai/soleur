---
name: soleur-triage
description: "This skill should be used when triaging legacy local todo files in todos/. For GitHub issues, use soleur:support:ticket-triage agent."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/triage/SKILL.md`, relative to the plugin root.
