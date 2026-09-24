---
name: soleur-marketing-conversion-optimizer
description: "Analyzes and optimizes conversion surfaces -- landing pages, signup flows, onboarding sequences, forms, popups, and paywall/upgrade screens. Use soleur-sales-outbound-strategist for human-assisted outbound motions; use soleur-marketing-cmo for overall strategy; use this agent for product-led conversion surface optimization."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/conversion-optimizer.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
