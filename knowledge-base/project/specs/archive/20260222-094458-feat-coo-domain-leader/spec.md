---
title: COO Domain Leader for Operations
type: feat
date: 2026-02-22
issue: "#182"
---

# COO Domain Leader for Operations

## Problem Statement

The operations domain has 3 specialist agents (ops-advisor, ops-research, ops-provisioner) but no orchestrator to assess operational posture, prioritize actions, and delegate appropriately. Marketing (CMO) and Engineering (CTO) already have domain leaders.

## Goals

- G1: Create a COO agent that orchestrates the operations domain
- G2: Hook COO into brainstorm Phase 0.5 domain detection
- G3: Make all domain leader entry points consistent (brainstorm detection only)

## Non-Goals

- Enterprise-scale operations features (future work)
- Standalone `/soleur:operations` skill
- Full 4-phase domain leader interface (Review phase unnecessary for 3 agents)

## Functional Requirements

- FR1: COO agent with 3-phase interface (Assess, Recommend/Delegate, Sharp Edges)
- FR2: Assess phase reads ops data files (expenses.md, domains.md)
- FR3: Delegation table mapping each ops agent to its use case
- FR4: Operations detection question added to brainstorm Phase 0.5
- FR5: COO participation section in brainstorm domain leader participation
- FR6: All 3 ops agent descriptions updated with COO cross-reference

## Technical Requirements

- TR1: Follow CTO's 3-phase pattern (not CMO's 4-phase)
- TR2: Update Phase 0.5 multi-domain clause to be generic
- TR3: Remove marketing skill for consistency
- TR4: Update AGENTS.md domain leader table
- TR5: Version bump (MINOR -- new agent)
