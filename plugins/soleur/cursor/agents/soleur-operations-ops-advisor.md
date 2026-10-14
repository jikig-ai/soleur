---
name: soleur-operations-ops-advisor
description: "Use this agent when you need to track operational expenses, manage domain registrations, or get hosting recommendations. Use soleur:operations:ops-research for live research and provider comparison; use soleur:operations:ops-provisioner for account setup; use soleur:finance:cfo for financial analysis and budgeting; use this agent for reading and updating the expense ledger."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/operations/ops-advisor.md`, relative to the plugin root.
