---
name: soleur-marketing-cmo
description: "Orchestrates the marketing domain -- assesses marketing posture, creates unified strategy, and delegates to specialist agents (brand, SEO, content, conversion, paid, pricing, retention). Use individual marketing agents for focused tasks; use this agent for cross-cutting marketing strategy and multi-agent coordination."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/cmo.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
