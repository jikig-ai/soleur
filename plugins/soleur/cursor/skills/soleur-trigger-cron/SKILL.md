---
name: soleur-trigger-cron
description: "This skill should be used to fire an allowlisted cron manual-trigger on demand via POST /api/internal/trigger-cron, without SSH. Reads the secret read-only from Doppler, lists allowlisted events, supports optional event data and a dry-run."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/trigger-cron/SKILL.md`, relative to the plugin root.
