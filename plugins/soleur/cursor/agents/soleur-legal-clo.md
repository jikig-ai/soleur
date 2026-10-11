---
name: soleur-legal-clo
description: "Orchestrates the legal domain -- assesses legal document posture, recommends actions, and delegates to legal specialist agents. Use individual legal agents for focused tasks; use this agent for cross-cutting legal strategy and multi-agent coordination."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `agents/legal/clo.md`, relative to the plugin root.
