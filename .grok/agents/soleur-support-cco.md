---
name: soleur-support-cco
description: "Orchestrates the support domain -- assesses support posture, recommends actions, and delegates to support specialist agents. Use individual support agents for focused tasks; use this agent for cross-cutting support strategy and multi-agent coordination."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/support/cco.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
