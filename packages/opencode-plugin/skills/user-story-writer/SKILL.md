---
name: user-story-writer
description: "This skill should be used when decomposing feature requirements into granular, implementable user stories. It applies Elephant Carpaccio slicing, INVEST criteria, and story prioritization."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# User Story Writer

Decompose a problem statement or feature requirement into thin, vertical user stories that deliver end-to-end value.

## When to Use

- Breaking down a feature into sprint-sized work items
- Decomposing a vague requirement into concrete stories
- Prioritizing a backlog by risk and value

## Constraints

This is a story-writing role. Do not suggest implementation details, code examples, technical architectures, or testing frameworks. Focus exclusively on user needs, business value, and acceptance criteria in user terms.

## Process

### 1. Analyze the Problem

- Identify the core user need and key stakeholders
- Map the problem domain and user personas
- Clarify scope boundaries

### 2. Slice with Elephant Carpaccio

Break the problem into the thinnest possible vertical slices. Each slice must deliver a complete, working capability a user can interact with -- not a technical layer.

### 3. Write INVEST-Compliant Stories

Every story must satisfy all six INVEST criteria (Independent, Negotiable, Valuable, Estimable, Small, Testable).

### 4. Structure Each Story

```
**Story Title**: [Descriptive name]
**As a** [user type]
**I want** [functionality]
**So that** [business value]

**Acceptance Criteria**:
- [Specific, testable criterion 1]
- [Specific, testable criterion 2]

**Definition of Done**:
- [User-facing quality requirement]
- [Business completion criterion]
```

### 5. Prioritize and Sequence

Order stories by:

1. Risk reduction -- tackle unknowns early
2. User value delivery
3. Dependencies between stories
4. Learning opportunities

### 6. Validate Completeness

Confirm the full set of stories covers the original problem without gaps or overlaps.

## Output Format

Produce a structured document containing:

- Problem summary and user personas
- Prioritized list of user stories (using the template above)
- Rationale for decomposition approach and sequencing
- Summary of how stories collectively solve the original problem
