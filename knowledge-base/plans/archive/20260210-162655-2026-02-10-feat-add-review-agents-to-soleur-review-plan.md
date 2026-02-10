---
title: "feat: Add test-design-reviewer and code-quality-analyst to /soleur:review"
type: feat
date: 2026-02-10
issue: 38
branch: feat-add-review-agents
version_bump: MINOR
---

# feat: Add test-design-reviewer and code-quality-analyst to /soleur:review

## Overview

Wire two existing but unused review agents into the `/soleur:review` command so PR reviews include test quality scoring and structured code smell analysis. [Updated 2026-02-10: incorporated plan review feedback]

## Problem Statement

The `test-design-reviewer` and `code-quality-analyst` agents exist in `plugins/soleur/agents/review/` but are not referenced by the `/soleur:review` command. PR reviews currently miss these two analysis dimensions.

## Proposed Solution

Add `code-quality-analyst` as always-on parallel agent #10 and `test-design-reviewer` as a conditional agent triggered when the PR contains test files. Single logic change to `plugins/soleur/commands/soleur/review.md`, plus mechanical version bump.

## Non-Goals

- Modifying the agent definition files themselves
- Adding these agents to the `/ship` workflow
- Changing the findings synthesis pipeline
- Adding other unused agents (e.g., `legacy-code-expert`)

## Implementation

### Change 1: Add code-quality-analyst to parallel block

**File:** `plugins/soleur/commands/soleur/review.md` (line 78)

Add after agent #9, before `</parallel_tasks>`:

```markdown
10. Task code-quality-analyst(PR content) - Detect code smells and produce refactoring roadmap
```

### Change 2: Add test-design-reviewer to conditional block

**File:** `plugins/soleur/commands/soleur/review.md` (after line 105)

Add a new conditional section after the migration agents block, before `</conditional_agents>`. Renumber migration agents to 11-12 for sequential numbering. Follow the existing migration agents pattern:

```markdown
**If PR contains test files:**

13. Task test-design-reviewer(PR content) - Score test quality against Farley's 8 properties

**When to run test review agent:**

- PR includes files matching `*_test.rb`, `*_spec.rb`
- PR includes files matching `test_*.py`, `*_test.py`
- PR includes files matching `*.test.ts`, `*.test.js`, `*.spec.ts`, `*.spec.js`
- PR includes files matching `*_test.go`
- PR includes files matching `*_test.swift`, `*Tests.swift`
- PR includes files in `__tests__/` or `spec/` or `test/` directories

**What this agent checks:**

- `test-design-reviewer`: Scores tests against Farley's 8 properties, produces a weighted Test Quality Score with letter grade and top 3 improvement recommendations
```

### Change 3: Version bump (MINOR)

Wiring previously unused agents into the review command adds new capabilities to `/soleur:review`. MINOR bump per AGENTS.md rules.

Version triad + external references updated mechanically per plugin policy.

## Acceptance Criteria

- [ ] `code-quality-analyst` appears as item #10 in the `<parallel_tasks>` block
- [ ] `test-design-reviewer` appears in the `<conditional_agents>` block with test file triggers
- [ ] Conditional agents renumbered sequentially (11-12 for migration, 13 for tests)
- [ ] Version triad updated (plugin.json, CHANGELOG.md, README.md)
- [ ] External version references synced (root README badge, bug report template)

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-10-add-review-agents-brainstorm.md`
- Spec: `knowledge-base/specs/feat-add-review-agents/spec.md`
- Issue: #38
- Agent definitions: `plugins/soleur/agents/review/test-design-reviewer.md`, `plugins/soleur/agents/review/code-quality-analyst.md`
- Modified file: `plugins/soleur/commands/soleur/review.md`
