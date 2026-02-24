# Spec: Model Selection Policy

**Branch:** feat-model-policy
**Date:** 2026-02-24

## Problem Statement

Soleur has no documented model selection policy. One agent (`learnings-researcher`) uses `model: haiku` as a premature optimization, and the agent-native-architecture skill recommends tiered model selection in its reference docs. The project also lacks an explicit `effortLevel` setting.

## Goals

- G1: Standardize all agents on `model: inherit`
- G2: Document the model selection policy in AGENTS.md
- G3: Update agent-native-architecture references to recommend Opus 4.6
- G4: Add `effortLevel: high` to project settings

## Non-Goals

- Hardcoding `model: opus` on every agent (removes user cost control)
- Adding per-agent effort controls (not supported by Claude Code plugin spec)
- Changing the constitution

## Functional Requirements

- FR1: `learnings-researcher.md` uses `model: inherit`
- FR2: AGENTS.md contains a "Model Selection Policy" section with default, override rules, and effort guidance
- FR3: Agent Compliance Checklist includes `model: inherit` as the standard
- FR4: Agent-native-architecture reference docs recommend Opus 4.6 as default model tier
- FR5: `.claude/settings.json` includes `"effortLevel": "high"`

## Technical Requirements

- TR1: All 60 agents have `model: inherit` (verified via grep)
- TR2: No agent uses explicit model override without justification
- TR3: Plugin version bumped (PATCH)
