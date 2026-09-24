---
name: soleur-marketing-seo-aeo-analyst
description: "Use this agent when you need to analyze Eleventy documentation sites for SEO and AEO (AI Engine Optimization) opportunities. Use soleur-marketing-growth-strategist for content strategy and keyword research; use soleur-marketing-programmatic-seo-specialist for scalable page generation; use this agent for technical SEO audits."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/seo-aeo-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
