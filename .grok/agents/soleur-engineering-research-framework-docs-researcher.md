---
name: soleur-engineering-research-framework-docs-researcher
description: "Use this agent when you need to gather documentation and best practices for specific frameworks, libraries, or dependencies. Use soleur-engineering-research-best-practices-researcher for general industry best practices; use this agent for a specific library's docs and source."
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/research/framework-docs-researcher.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
