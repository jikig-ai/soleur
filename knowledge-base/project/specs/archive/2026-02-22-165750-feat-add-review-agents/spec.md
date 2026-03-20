# Spec: Add test-design-reviewer and code-quality-analyst to /soleur:review

**Issue:** #38
**Branch:** feat-add-review-agents
**Date:** 2026-02-10

## Problem Statement

The `test-design-reviewer` and `code-quality-analyst` agents exist in `plugins/soleur/agents/review/` but are not wired into the `/soleur:review` command. PR reviews miss test quality scoring and structured code smell analysis.

## Goals

- G1: Add `code-quality-analyst` to the always-on parallel agents block
- G2: Add `test-design-reviewer` to the conditional agents block (triggered by test files)
- G3: No changes to the findings synthesis pipeline

## Non-Goals

- Modifying the agent definitions themselves
- Adding these agents to the `/ship` workflow
- Changing how the synthesis pipeline processes findings

## Functional Requirements

- FR1: `code-quality-analyst` runs on every PR as parallel agent #10
- FR2: `test-design-reviewer` runs only when PR contains test files
- FR3: Test file detection covers common patterns: `*_test.rb`, `*_spec.rb`, `test_*.py`, `*.test.ts`, `*.test.js`, `*.spec.ts`, `*.spec.js`, `*_test.go`, `*_test.swift`, `*Tests.swift`, `__tests__/*`
- FR4: Both agents' findings flow into the existing todo-creation pipeline without modification

## Technical Requirements

- TR1: Only `plugins/soleur/commands/soleur/review.md` contains logic changes; version triad files updated mechanically per plugin policy
- TR2: Follow the existing numbered list format in `<parallel_tasks>` block
- TR3: Follow the existing format in `<conditional_agents>` block with "when to run" and "what it checks" sections

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/commands/soleur/review.md` | Add agent #10 to parallel block; add test-design-reviewer to conditional block |
