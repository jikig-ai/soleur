---
name: soleur-operations-service-automator
description: "Use this agent when you need to provision third-party services via API or MCP tools. Use soleur-operations-ops-provisioner for browser-based SaaS setup."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/operations/service-automator.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
