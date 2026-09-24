---
name: soleur-marketing-brand-architect
description: "Use this agent when you need to define or refine a brand identity. It guides an interactive workshop covering company identity, positioning, voice and tone, visual direction, and channel-specific guidelines. Outputs a structured brand guide document to knowledge-base/marketing/brand-guide.md."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/marketing/brand-architect.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
