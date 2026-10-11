---
name: soleur-operations-coo
description: "Orchestrates the operations domain -- assesses operational posture, recommends actions, and delegates to specialist agents (soleur:operations:ops-advisor, soleur:operations:ops-research, soleur:operations:ops-provisioner). Use individual operations agents for focused tasks; use this agent for cross-cutting operations strategy and multi-agent coordination. Use soleur:finance:cfo for financial analysis and budgeting."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `agents/operations/coo.md`, relative to the plugin root.
