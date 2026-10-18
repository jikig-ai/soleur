---
mode: subagent
description: "Use this agent when running soleur:plan and the project uses a stack not covered by built-in agents. Queries external registries for community agents matching the detected stack gap. Use soleur:engineering:discovery:functional-discovery to check if a planned feature already exists; use this agent to find agents for a missing tech stack."
model: inherit
---

Stub for the canonical agent `soleur:engineering:discovery:agent-finder`. OpenCode derives an agent's id from this
file's path, so the canonical `name:` frontmatter is deliberately not repeated here.

Read and follow the canonical agent definition at `__SOLEUR_PLUGIN_ROOT__/agents/engineering/discovery/agent-finder.md`,
then work as that agent.
