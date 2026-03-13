# Spec: Domain Leader Capability Gap Detection

**Issue:** #234
**Date:** 2026-02-22
**Brainstorm:** [2026-02-22-domain-gap-detection-brainstorm.md](../../brainstorms/2026-02-22-domain-gap-detection-brainstorm.md)

## Problem Statement

Domain leaders participate in brainstorming to assess implications in their domain, but they don't identify missing agents or skills needed to perform the proposed work. This means capability gaps are only surfaced later during `/plan` Phase 1.5, after the brainstorm has already concluded. Surfacing gaps earlier allows better-informed decisions about what to build.

## Goals

- G1: Domain leaders identify and report capability gaps during brainstorm assessment
- G2: Brainstorm document consolidates all domain leader gaps into one section
- G3: `/plan` Phase 1.5 references brainstorm gaps to prioritize registry searches

## Non-Goals

- NG1: Installing agents/skills during brainstorm (stays in `/plan`)
- NG2: Creating new agents or skills for gap detection
- NG3: Structured gap protocols or machine-parseable tokens
- NG4: Modifying `agent-finder` or `functional-discovery` agents
- NG5: Querying external registries during brainstorm

## Functional Requirements

- FR1: Each domain leader agent (CTO, CMO, COO, CPO, CLO) MUST include a "Capability Gaps" section in their brainstorm assessment output when they identify missing capabilities
- FR2: The Capability Gaps section MUST list what's missing, which domain it affects, and why it's needed for the proposed work
- FR3: The brainstorm command MUST consolidate all domain leader gaps into a single "Capability Gaps" section in the brainstorm document (only when domain leaders participate)
- FR4: `/plan` Phase 1.5b MUST read the brainstorm document's Capability Gaps section (if present) and use it to inform `functional-discovery` searches
- FR5: If no domain leaders participate in a brainstorm, no Capability Gaps section appears

## Technical Requirements

- TR1: Changes are prompt-only -- no code, no new files, no infrastructure changes
- TR2: Domain leader prompt additions MUST be concise (~10 lines each) to stay within token budget
- TR3: Gap descriptions MUST be natural language (not structured protocols)
- TR4: The brainstorm document Capability Gaps section MUST only appear when at least one domain leader reported gaps

## Files to Modify

| File | Type | Change |
|------|------|--------|
| `plugins/soleur/agents/engineering/cto.md` | Agent | Add gap detection instruction |
| `plugins/soleur/agents/marketing/cmo.md` | Agent | Add gap detection instruction |
| `plugins/soleur/agents/operations/coo.md` | Agent | Add gap detection instruction |
| `plugins/soleur/agents/product/cpo.md` | Agent | Add gap detection instruction |
| `plugins/soleur/agents/legal/clo.md` | Agent | Add gap detection instruction |
| `plugins/soleur/commands/soleur/brainstorm.md` | Command | Add gap consolidation + document template section |
| `plugins/soleur/commands/soleur/plan.md` | Command | Add brainstorm gap reference in Phase 1.5 |
