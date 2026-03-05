# Spec: Automated Rule Retirement

**Issue:** #422
**Date:** 2026-03-05
**Status:** Draft

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

### FR1: Scheduled Rule Layer Audit (GitHub Action)

- FR1.1: Parse constitution.md rules (Always/Never/Prefer per domain)
- FR1.2: Parse AGENTS.md rules (Hard Rules, Workflow Gates)
- FR1.3: Parse PreToolUse hook comment headers and match patterns
- FR1.4: Cross-reference hooks against prose rules to detect supersession
- FR1.5: Detect duplicate rules across constitution.md and AGENTS.md
- FR1.6: Generate a markdown audit report with findings
- FR1.7: Create a GitHub issue with the audit report
- FR1.8: Create a PR with proposed tier migrations (move, annotate, or archive rules)
- FR1.9: Run on a bi-weekly cron schedule

### FR2: Compound Rule Budget Gate

- FR2.1: Count total rules per governance layer during compound
- FR2.2: Compute approximate token cost of always-loaded rules
- FR2.3: Warn when total always-loaded rules exceed threshold (default: 200)
- FR2.4: Cross-reference newly proposed rules against existing hooks
- FR2.5: Display budget stats and duplication alerts (warn only, never block)
- FR2.6: Auto-file a GitHub issue for any findings

## Technical Requirements

- TR1: Audit script must run in GitHub Actions without sudo or external dependencies beyond gh CLI and standard Unix tools
- TR2: Compound integration must extend existing Phase 1.5 (Deviation Analyst) in compound/SKILL.md
- TR3: Hook-superseded rules propose migration (tier demotion with annotation), not deletion
- TR4: GitHub issues created by both mechanisms must use consistent labels for tracking
- TR5: Audit script must be idempotent -- running twice with no changes produces no new issues/PRs

## Enforcement Tier Model

| Tier | Layer | Context Cost | When to Use |
|------|-------|-------------|-------------|
| 1 | PreToolUse hook | Zero (invisible) | Rules expressible as pattern matches |
| 2 | AGENTS.md | Always loaded | Sharp edges hooks can't cover |
| 3 | constitution.md | Always loaded | Conventions informing style/judgment |
| 4 | Agent descriptions | On agent reference | Domain-specific guidance |
| 5 | Skill instructions | On skill invocation | Workflow-specific rules |

**Migration rule:** When a rule gains hook enforcement (Tier 1), its prose version migrates from Tier 2 to Tier 3 with a `[hook-enforced]` annotation. Rules duplicated between Tier 2 and Tier 3 consolidate to Tier 2 only.

## Open Questions

1. Token budget threshold -- 200 always-loaded rules as default?
2. Audit script language -- shell + jq or something with better parsing?
3. Should audit PR propose deletions or only migrations?
4. Should audit verify hook CI test coverage before proposing migration?
5. Trigger B (zero-violation decay) -- revisit when session reporting exists
