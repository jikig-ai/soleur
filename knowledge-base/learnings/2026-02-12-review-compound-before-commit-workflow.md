---
module: soleur-plugin
date: 2026-02-12
problem_type: workflow-issue
component: brainstorm, compound, review
tags: [workflow, review, compound, commit-protocol, anti-sycophancy]
severity: medium
---

# Run Review and Compound Before Commit, Not After

## Problem

During the brainstorm improvement feature, we completed all implementation and version bumps, then almost committed without running code review or `/soleur:compound`. The Workflow Completion Protocol in AGENTS.md listed compound as step 1 but did not explicitly include code review, and the ordering was easy to skip in practice.

## Root Cause

1. **Review was implicit, not explicit**: The protocol assumed review would happen naturally. It didn't -- momentum toward "commit and PR" skipped it.
2. **Compound was listed but easy to forget**: Step 1 said "Run `/soleur:compound`" but nothing enforced it before step 2 ("Commit all artifacts").
3. **No gate between implementation and commit**: The workflow went straight from "done implementing" to "let me commit."

## Solution

Updated AGENTS.md Workflow Completion Protocol to explicitly gate review and compound before commit:

1. Run code review on changes (catch issues before they're committed)
2. Run `/soleur:compound` to capture learnings (ask user first)
3. Then commit, push, and PR

## Key Insight

**The commit is the gate, not the PR.** By the time you're creating a PR, you've already committed. Review and compound must happen before the commit, not after. This is the same principle as pre-commit hooks: catch problems at the earliest possible point.

## Secondary Learning: Anti-Sycophancy Split

When adding behavioral guidance (like anti-sycophancy), split by scope:
- **Skill-specific guidance** (e.g., "challenge assumptions in brainstorming") goes in the skill's SKILL.md
- **Project-wide guidance** (e.g., "don't flatter, challenge reasoning") goes in AGENTS.md

This prevents scoping behavioral directives too narrowly to one command when they apply everywhere.

## Related

- [parallel-plan-review-catches-overengineering.md](./2026-02-06-parallel-plan-review-catches-overengineering.md) - Same session pattern: 3 reviewers unanimously simplified an over-scoped plan
- [spec-workflow-implementation.md](./2026-02-06-spec-workflow-implementation.md) - "Human-in-the-loop v1, automate v2"
