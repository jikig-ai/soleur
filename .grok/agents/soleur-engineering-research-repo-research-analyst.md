---
name: soleur-engineering-research-repo-research-analyst
description: "Use this agent when you need to research a repository's structure, documentation, and patterns -- architecture files, GitHub issues, contribution guidelines, and implementation patterns. Unlike soleur-engineering-research-git-history-analyzer (commit history), this agent examines repo structure, docs, issues, and templates."
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/research/repo-research-analyst.md.

In that file, a multi-segment `soleur:<domain>:<name>` id names an agent: spawn it with spawn_subagent using the id with its colons replaced by hyphens. A one-segment `soleur:<name>` names a skill: Read `${GROK_PLUGIN_ROOT}/skills/<name>/SKILL.md`.
