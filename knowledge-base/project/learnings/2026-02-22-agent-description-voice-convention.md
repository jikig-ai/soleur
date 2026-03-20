---
title: Agent vs Skill description voice convention
date: 2026-02-22
category: conventions
tags: [agents, skills, descriptions, voice]
module: plugins/soleur
---

# Agent vs Skill Description Voice Convention

## Convention

- **Agents** use imperative form: `"Use this agent when..."`
- **Skills** use third person: `"This skill should be used when..."`

## Detection

Run this to find non-compliant agent descriptions:

```bash
grep -rn '^description:' plugins/soleur/agents/ | grep -v 'Use this agent'
```

## Context

Three agents were found using wrong voice forms during a `/soleur:sync` audit (2026-02-21). The patterns were:
- "This agent should be used when..." (passive, belongs in skills)
- "This agent performs..." (third person declarative)
- "This agent analyzes..." (third person declarative)

All three were corrected to "Use this agent when..." in #222.
