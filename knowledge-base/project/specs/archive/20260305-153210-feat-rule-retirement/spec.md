# Spec: Automated Rule Retirement

**Issue:** #422
**Date:** 2026-03-05
**Status:** Implemented (v1 -- simplified)

## Problem Statement

Governance rules accumulate across 5 layers (constitution.md, AGENTS.md, PreToolUse hooks, agent descriptions, skill instructions) without deduplication. Constitution.md (197 rules) and AGENTS.md (22 rules) are loaded every turn, inflating context cost by 10-22% per interaction. The same rule can exist in multiple layers simultaneously.

## Goals

- Detect and surface duplicated rules across governance layers
- Propose tier migrations to reduce per-turn context cost
- Prevent rule duplication at the source during compound captures
- Track findings as GitHub issues so nothing is lost

## Non-Goals

- Autonomous rule deletion without human review
- Session counting infrastructure (Trigger B from original issue -- deferred)
- Cross-session violation aggregation
- Rule manifest/metadata file (deferred unless scale demands it)
- Blocking compound flow on rule budget violations

## Functional Requirements

### FR1: Scheduled Rule Layer Audit (GitHub Action) -- DEFERRED to #451

Deferred after plan review. Three reviewers rejected as premature at current scale (3 hooks, 9 supersessions). Revisit when always-loaded rules exceed 300.

### FR2: Manual Rule Migration (v1 -- implemented)

- FR2.1: Annotate hook-superseded rules in AGENTS.md and constitution.md with `[hook-enforced: ...]`
- FR2.2: Add corresponding prose rule comments to hook scripts for maintenance traceability
- FR2.3: Standardize annotation format across both files

### FR3: Compound Rule Budget Check (v1 -- implemented)

- FR3.1: Count always-loaded rules during compound Phase 1.5
- FR3.2: Warn when total exceeds 250
- FR3.3: Check if existing hooks cover proposed enforcement before proposing new rules

## Technical Requirements

- TR1: Compound integration extends existing Phase 1.5 (Deviation Analyst) in compound/SKILL.md
- TR2: Hook-superseded rules annotated in-place (not deleted) to preserve defense-in-depth
- TR3: Hook scripts include prose rule cross-references as comments for maintenance

## Enforcement Tier Model

| Tier | Layer | Context Cost | When to Use |
|------|-------|-------------|-------------|
| 1 | PreToolUse hook | Zero (invisible) | Rules expressible as pattern matches |
| 2 | AGENTS.md | Always loaded | Sharp edges hooks can't cover |
| 3 | constitution.md | Always loaded | Conventions informing style/judgment |
| 4 | Agent descriptions | On agent reference | Domain-specific guidance |
| 5 | Skill instructions | On skill invocation | Workflow-specific rules |

**Migration rule:** When a rule gains hook enforcement (Tier 1), its prose version migrates from Tier 2 to Tier 3 with a `[hook-enforced]` annotation. Rules duplicated between Tier 2 and Tier 3 consolidate to Tier 2 only.

## Resolved Questions

1. **Token budget threshold:** 250 always-loaded rules (current is 219, giving 14% headroom)
2. **Audit script language:** N/A -- CI audit deferred. Manual annotations only.
3. **Deletions vs migrations:** Annotations only (no deletions). Defense-in-depth preserved.
4. **Hook CI test coverage:** Not required for annotation -- annotations are informational.
5. **Trigger B (zero-violation decay):** Deferred. Revisit when session reporting exists.
6. **Guard count:** 6 guards across 3 scripts (not 5 as originally stated in brainstorm).

## Deferred Work

- Scheduled CI audit workflow (#451) -- revisit when rule count exceeds 300
- Session counting infrastructure (Trigger B from original issue)
- Rule manifest/metadata file
