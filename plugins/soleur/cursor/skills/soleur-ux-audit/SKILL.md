---
name: soleur-ux-audit
description: "This skill should be used when auditing live web-platform UI for decay. Screenshots bot routes, delegates to soleur:product:design:ux-design-lead audit mode, dedupes, files capped issues."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/ux-audit/SKILL.md`, relative to the plugin root.
