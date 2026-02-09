---
name: user-story-writer
description: This skill should be used when decomposing feature requirements into granular, implementable user stories. It applies Elephant Carpaccio slicing, INVEST criteria, and story prioritization. Triggers on "write user stories", "break down feature", "story mapping", "INVEST criteria", "Elephant Carpaccio", "decompose requirements".
---

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

Every story must be:

| Criterion | Meaning |
|-----------|---------|
| **Independent** | No dependencies on other stories |
| **Negotiable** | Details can be discussed and refined |
| **Valuable** | Delivers clear value to the end user |
| **Estimable** | Scope is clear enough to estimate |
| **Small** | Completable in a single sprint |
| **Testable** | Has clear acceptance criteria |

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

## Quality Checklist

- Each story is small enough for a single sprint
- Stories build incrementally toward the full solution
- No technical tasks disguised as user stories
- Edge cases and error scenarios are separate stories when significant
- Different user personas and their unique needs are considered
