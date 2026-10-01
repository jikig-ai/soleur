---
name: soleur-engineering-review-pattern-recognition-specialist
description: "Use this agent when you need to analyze code for design patterns, anti-patterns, naming conventions, and code duplication. This agent excels at identifying architectural patterns, detecting code smells, and ensuring consistency across the codebase."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/pattern-recognition-specialist.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
