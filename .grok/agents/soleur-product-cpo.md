---
name: soleur-product-cpo
description: "Orchestrates the product domain -- assesses product strategy, validates business models, and delegates to specialist agents (soleur-product-spec-flow-analyzer, soleur-product-design-ux-design-lead, soleur-product-business-validator, soleur-product-competitive-intelligence). Use individual product agents for focused tasks; use this agent for cross-cutting product strategy and multi-agent coordination."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/product/cpo.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
