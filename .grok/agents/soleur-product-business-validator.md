---
name: soleur-product-business-validator
description: "Use this agent when you need to validate a business idea through structured market research, competitive analysis, and business model assessment. Use soleur-product-competitive-intelligence for ongoing competitor monitoring; use soleur-product-spec-flow-analyzer for spec gap analysis; use soleur-product-cpo for cross-cutting product strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/product/business-validator.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
