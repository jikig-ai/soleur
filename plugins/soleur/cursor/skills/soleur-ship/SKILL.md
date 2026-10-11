---
name: soleur-ship
description: "This skill should be used when preparing a feature for production deployment. Enforces the lifecycle checklist: commit artifacts, update docs, capture learnings, create PR. Version bumping happens in CI."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/ship/SKILL.md`, relative to the plugin root.
