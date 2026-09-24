---
name: soleur-marketing-programmatic-seo-specialist
description: "Creates programmatic SEO strategies -- template design, data schemas, and page generation plans for comparison pages, alternatives pages, and other scalable content patterns. Use soleur-marketing-seo-aeo-analyst for technical SEO audits; use soleur-marketing-growth-strategist for keyword research; use this agent for template-driven page generation at scale."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/programmatic-seo-specialist.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
