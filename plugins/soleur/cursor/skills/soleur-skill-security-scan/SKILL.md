---
name: soleur-skill-security-scan
description: "This skill should be used when scanning Claude Code skills or agent files for advisory security risks: code-execution, prompt-injection, supply-chain, filesystem-boundary, telemetry. Emits LOW-RISK | REVIEW | HIGH-RISK."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/skill-security-scan/SKILL.md`, relative to the plugin root.
