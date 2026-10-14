---
name: soleur-marketing-analytics-analyst
description: "Designs analytics tracking implementations, event taxonomies, A/B test plans with statistical rigor, and attribution models for marketing measurement. Use soleur-sales-pipeline-analyst for post-MQL sales pipeline metrics; use this agent for marketing analytics."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/analytics-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
