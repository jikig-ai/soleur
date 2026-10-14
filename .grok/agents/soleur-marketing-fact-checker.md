---
name: soleur-marketing-fact-checker
description: "Verifies factual claims, statistics, and attributed quotes in drafts by fetching cited URLs and confirming source support. Use soleur-marketing-copywriter for marketing copy; use content-writer for blog articles; use this agent for citation verification."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/fact-checker.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
