---
name: soleur-campaign-calendar
description: "This skill should be used when generating or refreshing the rolling campaign calendar. Scans knowledge-base/marketing/distribution-content/ markdown frontmatter, groups by status (overdue/upcoming/draft/published), writes a calendar view."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/campaign-calendar/SKILL.md`, relative to the plugin root.
