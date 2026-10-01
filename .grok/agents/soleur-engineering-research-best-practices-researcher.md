---
name: soleur-engineering-research-best-practices-researcher
description: "Use this agent when you need to research external best practices, documentation, and examples for any technology or development practice. Use soleur-engineering-research-framework-docs-researcher for a specific library's API docs; use this agent for cross-source best practices research."
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/research/best-practices-researcher.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
