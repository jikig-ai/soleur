---
name: soleur-product-design-ux-design-lead
description: "Use this agent when you need to create visual designs in .pen files using Pencil MCP tools. Handles wireframes, high-fidelity screens, and component design. Use soleur-product-business-validator for pre-build idea validation; use soleur-product-cpo for cross-cutting product strategy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/product/design/ux-design-lead.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
