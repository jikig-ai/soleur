---
name: soleur-invoice
description: "This skill should be used when the founder wants to get paid through their own Stripe account: list who owes them, create and send an invoice behind a human-approval preview, or chase an overdue one. Test-mode only in v1."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/invoice/SKILL.md`, relative to the plugin root.
