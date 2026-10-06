---
name: soleur-engineering-review-data-integrity-guardian
description: "Use this agent when you need to review database migrations, data models, or any code that manipulates persistent data. Use soleur:engineering:review:data-migration-expert for ID mapping validation; use soleur:engineering:review:deployment-verification-agent for deploy checklists. Boundary vs gdpr-gate: see plugins/soleur/skills/review/SKILL.md §boundaries."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `agents/engineering/review/data-integrity-guardian.md`, relative to the plugin root.
