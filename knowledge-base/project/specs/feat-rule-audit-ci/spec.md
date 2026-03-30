# Spec: Automated Rule Audit CI

**Issue:** #451
**Date:** 2026-03-30
**Status:** Draft
**Prior art:** #422 spec (archived), PR #450 (compound Phase 1.5)

## Problem Statement

Always-loaded governance rules (AGENTS.md + constitution.md) have reached 313,
exceeding the 300 threshold defined in #451. Growth rate is ~3.7 rules/day since
the original brainstorm on 2026-03-05 (from 219 to 313 in 25 days). The compound
Phase 1.5 warning at 250 fires per-session but depends on human action.
Automated CI audit with actionable PRs is needed to control growth.

## Goals

- Detect cross-layer rule duplication automatically on a bi-weekly schedule
- Generate GitHub issues with audit findings and fingerprinted deduplication
- Generate PRs with proposed tier migrations and deletion candidates
- Provide an on-demand manual trigger via workflow_dispatch

## Non-Goals

- Semantic/fuzzy matching for duplication (exact keyword matching only)
- Rule manifest YAML (parse governance files directly)
- Auto-merge of migration PRs (human review required)
- Session counting infrastructure (Trigger B remains deferred)
- Blocking compound flow or CI pipelines on rule budget

## Functional Requirements

### FR1: Rule Budget Counter

- FR1.1: Count always-loaded rules using `grep -c '^- '` on AGENTS.md and
  constitution.md
- FR1.2: Output budget report: total count, per-file breakdown, delta from
  threshold
- FR1.3: Exit with warning status if count exceeds 300

### FR2: Cross-Layer Duplication Detector

- FR2.1: Extract key phrases from each rule in AGENTS.md and constitution.md
  (strip common words, normalize whitespace)
- FR2.2: Cross-reference against PreToolUse hook scripts (`.claude/hooks/`)
  for hook-superseded prose rules
- FR2.3: Cross-reference against agent descriptions (`agents/**/*.md`) and
  skill instructions (`skills/*/SKILL.md`) for duplicated guidance
- FR2.4: Output list of matches with source tier, target tier, matched phrase,
  and recommended migration direction

### FR3: Report Generator

- FR3.1: Build GitHub issue body with: budget stats, duplication findings
  table, migration proposals, deletion candidates
- FR3.2: Build PR diff proposing tier migrations (move rules between files)
  and flagging deletion candidates with `[CANDIDATE FOR DELETION]` comments
- FR3.3: Include the tier model table in issue body for reviewer context

### FR4: Fingerprint Deduplication

- FR4.1: Sort all findings alphabetically and compute SHA256 hash
- FR4.2: Search open issues for label `rule-audit:<hash-prefix>` (first 12 chars)
- FR4.3: Skip issue/PR creation if matching fingerprint found
- FR4.4: Apply fingerprint label to newly created issues

### FR5: GitHub Actions Workflow

- FR5.1: Schedule: `cron: '0 9 1,15 * *'` (bi-weekly, 1st and 15th at 09:00 UTC)
- FR5.2: Support `workflow_dispatch` for manual trigger
- FR5.3: Orchestrate scripts in order: count → detect → report → fingerprint →
  create issue/PR
- FR5.4: Use `GITHUB_TOKEN` for issue/PR creation (no additional secrets needed)

## Technical Requirements

- TR1: Scripts in `scripts/rule-audit/` (shell + grep/awk)
- TR2: Each script independently executable and testable
- TR3: Fingerprint label format: `rule-audit:<sha256-prefix-12>`
- TR4: PR branch naming: `chore/rule-audit-YYYY-MM-DD`
- TR5: Issue title format: `chore: rule audit findings (YYYY-MM-DD)`
- TR6: No heredoc indentation in workflow YAML (per AGENTS.md rule)

## Enforcement Tier Model

| Tier | Layer | Context Cost | When to Use |
|------|-------|-------------|-------------|
| 1 | PreToolUse hooks | Zero | Mechanical enforcement |
| 2 | AGENTS.md | Always loaded | Sharp edges |
| 3 | constitution.md | Always loaded | Conventions and judgment |
| 4 | Agent descriptions | On reference | Domain-specific guidance |
| 5 | Skill instructions | On invocation | Workflow-specific procedures |

**Migration direction:** Rules should live at the cheapest tier that provides
adequate enforcement. When a rule gains hook enforcement (Tier 1), its prose
version migrates from Tier 2 → Tier 3 with `[hook-enforced]` annotation.

## Open Questions

1. Budget threshold for CI issue creation: 300 (matching #451 trigger) or match
   compound's 250 warning?
2. Should the audit verify hook test coverage before proposing hook-only
   enforcement for a rule?
