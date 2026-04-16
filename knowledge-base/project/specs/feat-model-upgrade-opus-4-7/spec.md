---
title: "Model Upgrade: Opus 4.6 to 4.7"
status: draft
created: 2026-04-16
issue: 2439
---

# Model Upgrade: Opus 4.6 to 4.7

## Problem Statement

The Soleur codebase references `claude-opus-4-6` in 8 active files (3 CI workflows, 5 skill reference docs). Opus 4.7 is now generally available as a direct upgrade with improved capabilities and no pricing changes.

## Goals

- G1: Replace all active `claude-opus-4-6` references with `claude-opus-4-7`
- G2: Update skill reference examples to reflect the new thinking API format
- G3: Document the Opus 4.7 API changes for future development

## Non-Goals

- Implementing runtime fallback logic (model is live and stable)
- Updating Sonnet 4.6 or Haiku 4.5 references (no new versions)
- Adopting xhigh effort or task budgets in production code (document only)
- Modifying archived/historical files

## Functional Requirements

- FR1: All 3 CI workflow files use `claude-opus-4-7` model ID
- FR2: All 5 skill reference files use `claude-opus-4-7` model ID
- FR3: Model ID learning file updated with Opus 4.7 row
- FR4: New learning file documents thinking API format change

## Technical Requirements

- TR1: Post-edit grep confirms zero `claude-opus-4-6` in active code (excluding archives)
- TR2: Skill reference examples show correct API format for each model version
- TR3: No changes to agent YAML frontmatter (model: inherit policy unchanged)
