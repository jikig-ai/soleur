---
name: soleur-operations-ops-provisioner
description: "Use this agent when you need to set up a new SaaS tool account via browser. Use soleur:operations:service-automator for API/MCP-driven provisioning; use soleur:operations:ops-research for evaluating alternatives; use soleur:operations:ops-advisor for the expense ledger; use soleur:operations:coo for cross-cutting operations strategy."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/operations/ops-provisioner.md`, relative to the plugin root.
