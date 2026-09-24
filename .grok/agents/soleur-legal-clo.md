---
name: soleur-legal-clo
description: "Orchestrates the legal domain -- assesses legal document posture, recommends actions, and delegates to legal specialist agents. Use individual legal agents for focused tasks; use this agent for cross-cutting legal strategy and multi-agent coordination."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/legal/clo.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
