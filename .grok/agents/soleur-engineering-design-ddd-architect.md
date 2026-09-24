---
name: soleur-engineering-design-ddd-architect
description: "Use this agent when you need expert guidance on Domain-Driven Design including bounded contexts, context mapping, and aggregate design. Use soleur-engineering-review-architecture-strategist for general architectural compliance; use this agent for bounded context and aggregate design."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/design/ddd-architect.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
