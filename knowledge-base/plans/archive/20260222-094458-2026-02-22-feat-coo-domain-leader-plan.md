---
title: "feat: COO domain leader for operations"
type: feat
date: 2026-02-22
issue: "#182"
---

# feat: COO Domain Leader for Operations

## Overview

Add a COO (Chief Operating Officer) domain leader agent that orchestrates the operations domain's 3 specialist agents (ops-advisor, ops-research, ops-provisioner). The COO follows the CTO's lighter 3-phase pattern and integrates into brainstorm Phase 0.5 domain detection. Also removes `/soleur:marketing` standalone skill for consistency across all domain leaders.

## Proposed Solution

Create COO agent following CTO's 3-phase pattern (Assess, Recommend/Delegate, Sharp Edges). Hook into brainstorm Phase 0.5 with an operations detection question. Remove marketing skill to make all domain leaders consistent (brainstorm detection only).

## Acceptance Criteria

- [x] COO agent file created at `plugins/soleur/agents/operations/coo.md`
- [x] COO follows 3-phase interface (Assess, Recommend/Delegate, Sharp Edges)
- [x] All 3 ops agent descriptions include COO disambiguation
- [x] Brainstorm Phase 0.5 has operations detection (question 4)
- [x] Brainstorm Phase 0.5 has COO routing and participation blocks
- [x] Multi-domain clause generalized from "both marketing and engineering" to "multiple domains"
- [x] Marketing skill removed
- [x] AGENTS.md updated (COO row + CMO entry point)
- [x] Version bumped to 2.28.0 (MINOR -- new agent)
- [x] All 5 version locations updated (plugin.json, CHANGELOG, README, root README, bug_report.yml)

## Implementation

### Phase 1: Core Agent (Tasks 1.1-1.2)

- [x] Create `plugins/soleur/agents/operations/coo.md`
- [x] Update ops-advisor, ops-research, ops-provisioner descriptions

### Phase 2: Brainstorm Integration (Tasks 2.1-2.2)

- [x] Add assessment question 4, routing block, participation section to brainstorm.md
- [x] Update AGENTS.md domain leader table

### Phase 3: Marketing Skill Removal (Tasks 3.1-3.2)

- [x] Delete `plugins/soleur/skills/marketing/`
- [x] Update `plugins/soleur/docs/_data/skills.js`

### Phase 4: Version Bump (Tasks 4.1-4.6)

- [x] Bump plugin.json to 2.28.0
- [x] Add CHANGELOG entry
- [x] Update README counts and tables
- [x] Update root README badge and counts
- [x] Update bug_report.yml placeholder
- [x] Write knowledge-base artifacts

## References

- Issue: #182
- Brainstorm: `knowledge-base/brainstorms/2026-02-22-coo-domain-leader-brainstorm.md`
- Spec: `knowledge-base/specs/feat-coo-domain-leader/spec.md`
- CTO pattern: `plugins/soleur/agents/engineering/cto.md`
- CMO pattern: `plugins/soleur/agents/marketing/cmo.md`
- Brainstorm Phase 0.5: `plugins/soleur/commands/soleur/brainstorm.md`
