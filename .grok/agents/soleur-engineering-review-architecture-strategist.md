---
name: soleur-engineering-review-architecture-strategist
description: "Use this agent when you need to analyze code changes from an architectural perspective, evaluate system design decisions, or ensure modifications align with established architectural patterns. Use soleur-engineering-design-ddd-architect for Domain-Driven Design modeling; use this agent for general architectural compliance review."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/architecture-strategist.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
