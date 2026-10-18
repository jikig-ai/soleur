---
mode: subagent
description: "Classifies and routes GitHub issues by severity and domain. Assigns priority (P1/P2/P3) and routes to the correct domain via gh CLI. Use the triage skill for triaging internal code review findings into the CLI todo system. For automated daily triage via GitHub Actions, see scheduled-daily-triage.yml."
model: inherit
---

Stub for the canonical agent `soleur:support:ticket-triage`. OpenCode derives an agent's id from this
file's path, so the canonical `name:` frontmatter is deliberately not repeated here.

Read and follow the canonical agent definition at `__SOLEUR_PLUGIN_ROOT__/agents/support/ticket-triage.md`,
then work as that agent.
