---
name: soleur-admin-ip-refresh
description: "This skill should be used to refresh the prod SSH allowlist (Doppler ADMIN_IPS) after operator IP rotation. Detects drift, mutates Doppler with explicit ack."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/admin-ip-refresh/SKILL.md`, relative to the plugin root.
