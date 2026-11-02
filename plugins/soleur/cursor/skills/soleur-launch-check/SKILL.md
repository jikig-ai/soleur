---
name: soleur-launch-check
description: "This skill should be used when checking an existing repository for production-readiness gaps and missing Soleur engineering practices."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/launch-check/SKILL.md`, relative to the plugin root.
