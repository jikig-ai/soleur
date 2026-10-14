---
name: soleur-engineering-review-code-quality-analyst
description: "Use this agent when you need a formal quality report with severity-scored findings and a prioritized refactoring roadmap. Use soleur-engineering-review-pattern-recognition-specialist for quick pattern checks; use this agent when you need a formal report to plan refactoring work."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/code-quality-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
