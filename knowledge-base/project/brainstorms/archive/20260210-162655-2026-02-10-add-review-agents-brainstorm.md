# Brainstorm: Add test-design-reviewer and code-quality-analyst to /soleur:review

**Date:** 2026-02-10
**Issue:** #38
**Branch:** feat-add-review-agents
**Status:** Complete

## What We're Building

Wire two existing but unused review agents into the `/soleur:review` command:

1. **code-quality-analyst** -- Structured code smell detection using Fowler's methodology. Produces severity-scored findings with a refactoring roadmap. Added to the **always-on parallel block** since code smells apply to any PR.

2. **test-design-reviewer** -- Scores test quality against Dave Farley's 8 properties. Added to the **conditional agents block**, triggered only when the PR contains test files.

## Why This Approach

- Both agents already exist in `plugins/soleur/agents/review/` but aren't referenced by the review command.
- The parallel block's synthesis pipeline is generic -- it collects from "all parallel agents" and feeds into todo creation. No downstream changes needed.
- Making test-design-reviewer conditional avoids wasting a round-trip on PRs with no test files.
- code-quality-analyst is always-on because every PR with code can benefit from smell detection.

## Key Decisions

1. **code-quality-analyst: always-on parallel** -- Added as item 10 in the parallel block alongside the existing 9 agents.
2. **test-design-reviewer: conditional** -- Added to the `<conditional_agents>` block with trigger criteria for test file patterns (e.g., `*_test.rb`, `*_spec.rb`, `test_*.py`, `*.test.ts`, `*.spec.ts`).
3. **No downstream changes** -- The findings synthesis pipeline (Section 5) already handles any agent's output generically.
4. **Single file change** -- Only `plugins/soleur/commands/soleur/review.md` needs modification.

## Open Questions

None -- scope is well-defined.
