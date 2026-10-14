---
name: soleur-marketing-copywriter
description: "Writes and edits marketing copy -- landing pages, email sequences, cold outreach, social content, and copy editing. Use the content-writer skill for blog articles; use soleur-sales-outbound-strategist for cadence strategy and audience targeting; use soleur-marketing-fact-checker for citation verification; use this agent for landing pages, emails, and short-form copy."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/copywriter.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
