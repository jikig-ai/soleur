---
name: soleur-engineering-research-learnings-researcher
description: "Use this agent when you need to search institutional learnings in knowledge-base/project/learnings/ for relevant past solutions before implementing a new feature or fixing a problem. Unlike soleur-engineering-research-best-practices-researcher (external sources), this agent searches only internal learnings files."
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/research/learnings-researcher.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
