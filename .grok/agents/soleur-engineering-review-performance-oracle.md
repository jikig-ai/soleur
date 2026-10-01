---
name: soleur-engineering-review-performance-oracle
description: "Use this agent when you need to analyze code for performance issues, optimize algorithms, identify bottlenecks, or ensure scalability. This includes reviewing database queries, memory usage, caching strategies, and overall system performance. The agent should be invoked after implementing features or when performance concerns arise."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/performance-oracle.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
