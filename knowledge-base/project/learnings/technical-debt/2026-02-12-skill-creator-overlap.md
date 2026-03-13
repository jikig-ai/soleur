---
module: plugins/soleur
date: 2026-02-12
problem_type: best_practice
component: skills
tags: [skills, duplication, consolidation]
severity: low
---

# skill-creator and create-agent-skills Have Overlapping Purposes

## Context

Two skills exist with overlapping purposes:

- `skill-creator`: Triggers on "create a new skill", "build a skill", "package a skill"
- `create-agent-skills`: Triggers on "creating, writing, or refining Claude Code Skills"

Both deal with skill authoring, causing potential user confusion about which to invoke.

## Recommendation

Merge into a single `skill-creator` skill that covers both creating new skills and refining existing ones. The `create-agent-skills` name is less discoverable and redundant.
