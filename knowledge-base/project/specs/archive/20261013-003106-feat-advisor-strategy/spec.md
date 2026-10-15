# Spec: Context-Aware Agent Gating for Token Optimization

**Issue:** TBD (token optimization) | #2030 (advisor strategy, deferred)
**Branch:** feat-advisor-strategy
**Status:** Draft

## Problem Statement

Soleur is hitting Claude Code usage limits faster than expected. The root cause is cumulative agent sprawl: 60+ agents all use `model: inherit` (Opus), and pipelines like review (8-13 agents), brainstorm (up to 8 domain leaders), and resolve-parallel (unbounded) spawn maximum agents regardless of context.

## Goals

- **G1:** Reduce token consumption per session by gating agent spawning based on actual context
- **G2:** Maintain current quality levels — no model downgrades, no skipping agents that are relevant
- **G3:** Provide a user override mechanism when gating incorrectly skips a relevant agent

## Non-Goals

- Model downgrades (e.g., `model: sonnet` for routine agents) — explicitly ruled out by user
- Advisor strategy adoption at plugin level — technically impossible (Messages API constraint)
- Token usage instrumentation — separate concern, tracked as a prerequisite in #2030

## Functional Requirements

- **FR1:** Review skill gates agents based on file types changed in the PR diff
- **FR2:** Brainstorm skill gates domain leaders based on feature description keyword matching (already partially implemented in Phase 0.5)
- **FR3:** Work skill defaults to Tier C (sequential) unless plan has 3+ independent tasks
- **FR4:** User can force full pipeline via explicit flag or keyword (e.g., "deep review")

## Technical Requirements

- **TR1:** Gating rules must be deterministic (file-path patterns, not LLM judgment) to avoid unpredictable spawning
- **TR2:** Gating decisions must be logged/visible so the user knows which agents were skipped and why
- **TR3:** No changes to agent frontmatter or model selection policy
