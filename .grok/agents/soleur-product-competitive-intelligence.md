---
name: soleur-product-competitive-intelligence
description: "Use this agent when you need recurring competitive landscape monitoring and market research reports. After producing the base report, it cascades to 4 specialist agents (soleur-marketing-growth-strategist, soleur-marketing-pricing-strategist, soleur-sales-deal-architect, soleur-marketing-programmatic-seo-specialist) to refresh downstream artifacts. Use soleur-product-business-validator for one-time idea validation; use this agent for ongoing competitor tracking."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/product/competitive-intelligence.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
