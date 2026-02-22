# Domain Leader Pattern

**Issue:** #154
**Date:** 2026-02-20
**Status:** Draft

## Problem Statement

Soleur's workflow (brainstorm -> plan -> work -> review -> ship) is engineering-centric. Marketing has 12 specialist agents but no coordinator. Cross-domain features (e.g., product launches) require manual orchestration across domains. There is no pattern for domain-aware workflow participation.

## Goals

- G1: Define a reusable Domain Leader Interface that any domain can implement
- G2: Build a CMO agent that replaces `marketing-strategist` and orchestrates 11 marketing agents
- G3: Build a CTO agent that formalizes existing engineering orchestration
- G4: Add domain detection hooks to all 5 workflow commands (brainstorm, plan, work, review, ship)
- G5: Create a `/soleur:marketing` skill as standalone marketing entry point

## Non-Goals

- Leaders with blocking/veto authority (advisory only)
- Domain leaders for Legal, Operations, or Product (follow-up issues)
- Marketing agent subdirectory reorganization
- New marketing agents or skills beyond the CMO

## Functional Requirements

- FR1: Domain Leader Interface contract -- assess, recommend, delegate, review
- FR2: CMO agent replaces `marketing-strategist`, orchestrates 11 marketing specialists
- FR3: CTO agent wraps existing review/work orchestration patterns
- FR4: Domain detection in brainstorm command (replaces brand-only routing)
- FR5: Domain detection in plan command (adds domain tasks to plans)
- FR6: Domain detection in work command (leaders manage Agent Teams)
- FR7: Domain detection in review command (domain-specific review agents)
- FR8: Domain detection in ship command (domain readiness validation)
- FR9: `/soleur:marketing` skill with sub-commands for standalone marketing work
- FR10: Agent Teams integration for parallel specialist work

## Technical Requirements

- TR1: CMO agent description must be 1-3 sentences with disambiguation (token budget)
- TR2: Sharp-edges-only agent prompts (no general marketing knowledge)
- TR3: Brand routing in brainstorm must fold into CMO domain detection
- TR4: `marketing-strategist` agent must be removed (absorbed into CMO)
- TR5: Follow-up issues created for CLO, COO, CPO domain leaders
- TR6: Version bump (MINOR -- new agents + skill)

## Success Criteria

- SC1: User says "brainstorm a product launch" and CMO is automatically offered for marketing planning
- SC2: `/soleur:marketing audit` assesses brand, SEO, content, and community in parallel
- SC3: CTO + CMO can both participate in the same feature workflow
- SC4: Adding a future domain leader (e.g., CLO) follows the documented interface without modifying workflow commands
