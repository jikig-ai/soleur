# Spec: Domain Prerequisites

**Issue:** #251
**Date:** 2026-02-22
**Status:** Draft

## Problem Statement

The Soleur plugin cannot add new domains (like Support) because:
- Agent description token budget is at 2,497/2,500 words (3 words from ceiling)
- Brainstorm Phase 0.5 routing requires ~35 lines of edits per new domain (unmaintainable at 7+ domains)
- plugin.json description is stale (missing Sales domain)

## Goals

- G1: Recover 200+ words of token budget headroom by trimming agent descriptions
- G2: Reduce per-domain brainstorm routing footprint from ~35 lines to ~3 lines via table-driven config
- G3: Fix plugin.json description accuracy

## Non-Goals

- Adding the Support domain (deferred per business validation)
- Adding any new agents or domains
- Changing agent behavior (only descriptions change)
- Adding token budget CI enforcement (noted as future work)

## Functional Requirements

- FR1: All 54 agent descriptions remain accurate and clear after trimming
- FR2: Brainstorm Phase 0.5 domain routing produces identical behavior after refactor (same questions, same routing, same participation prompts)
- FR3: plugin.json description lists all 6 active domains
- FR4: Adding a future domain requires only table rows (no structural edits to brainstorm.md)

## Technical Requirements

- TR1: Agent description word count stays under 2,300 words (200+ word buffer)
- TR2: No changes to agent file names, paths, or directory structure
- TR3: Brainstorm refactor is backward-compatible -- existing domain routing works identically
- TR4: Docs site builds successfully after changes (`npx @11ty/eleventy --input=docs`)

## Acceptance Criteria

- [ ] `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` reports <= 2,300
- [ ] Brainstorm Phase 0.5 uses a config table, not per-domain inline blocks
- [ ] plugin.json description includes "sales"
- [ ] Docs site builds cleanly
- [ ] Version bump (PATCH -- no new components)
