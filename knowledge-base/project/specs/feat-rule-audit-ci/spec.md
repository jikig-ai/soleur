# Spec: Automated Rule Audit CI

**Issue:** #451
**Date:** 2026-03-30
**Status:** Draft
**Prior art:** #422 spec (archived), PR #450 (compound Phase 1.5)

[Updated 2026-03-30: Simplified after plan review — single script, issue-only
reporting, title-based dedup.]

## Problem Statement

Always-loaded governance rules (AGENTS.md + constitution.md) have reached 313,
exceeding the 300 threshold defined in #451. Growth rate is ~3.7 rules/day since
the original brainstorm on 2026-03-05 (from 219 to 313 in 25 days). The compound
Phase 1.5 warning at 250 fires per-session but depends on human action.
Automated CI audit with actionable issues is needed to control growth.

## Goals

- Count always-loaded rules and report budget status on a bi-weekly schedule
- Identify hook-enforced rules as tier migration candidates
- Create/update a GitHub issue with findings (title-based deduplication)
- Provide an on-demand manual trigger via workflow_dispatch

## Non-Goals

- Automated PR generation (human or agent makes edits from issue findings)
- Cross-tier phrase matching against agents/skills (deferred to #1304)
- Semantic/fuzzy matching for duplication
- Rule manifest YAML
- Session counting infrastructure (Trigger B remains deferred)
- Blocking compound flow or CI pipelines on rule budget

## Functional Requirements

### FR1: Rule Budget Counter

- FR1.1: Count always-loaded rules using `grep -c '^- '` on AGENTS.md and
  constitution.md
- FR1.2: Report total count, per-file breakdown, and whether threshold (300)
  is exceeded

### FR2: Hook-Enforced Migration Candidate Detection

- FR2.1: Extract `[hook-enforced: ...]` annotated rules from AGENTS.md with
  line numbers
- FR2.2: Extract `[hook-enforced: ...]` annotated rules from constitution.md
  with line numbers
- FR2.3: Verify referenced hook scripts exist in `.claude/hooks/`
- FR2.4: List AGENTS.md hook-enforced rules as migration candidates (could move
  to constitution.md since they're already hook-enforced)
- FR2.5: Flag any broken hook references (script renamed or deleted)

### FR3: Issue Reporting

- FR3.1: Build GitHub issue body with: budget stats table, migration candidates
  table, broken hook references, tier model reference
- FR3.2: Title-based dedup: search for open issue with "rule audit findings" in
  title
- FR3.3: If open issue exists: add comment with updated findings
- FR3.4: If no open issue: create new issue with `--milestone "Post-MVP / Later"`
- FR3.5: Issue body written to temp file (no inline heredoc indentation)

### FR4: GitHub Actions Workflow

- FR4.1: Schedule: `cron: '0 9 1,15 * *'` (bi-weekly, 1st and 15th at 09:00 UTC)
- FR4.2: Support `workflow_dispatch` for manual trigger
- FR4.3: `permissions: issues: write` only
- FR4.4: `timeout-minutes: 5`
- FR4.5: Discord failure notification on `if: failure()`
- FR4.6: `actions/checkout` with pinned SHA
- FR4.7: `GH_TOKEN: ${{ github.token }}` and `GH_REPO: ${{ github.repository }}`

## Technical Requirements

- TR1: Single script at `scripts/rule-audit.sh`
- TR2: Shell script uses `set -euo pipefail` and SCRIPT_DIR/REPO_ROOT pattern
- TR3: Issue title format: `chore: rule audit findings (YYYY-MM-DD)`
- TR4: No heredoc indentation in workflow YAML (per AGENTS.md rule)
- TR5: Retry `gh` CLI once on failure (rate limits)

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
version migrates from Tier 2 to Tier 3 with `[hook-enforced]` annotation.

## Resolved Questions

1. Budget threshold: 300 (matching #451 trigger). Compound warns at 250.
2. Hook test coverage verification: Not in scope for v1. The audit flags
   migration candidates; the human verifies hook coverage before acting.
3. Script architecture: Single script (plan review rejected 4-script modularity
   as over-factored).
4. Deduplication: Title-based search (plan review rejected fingerprint labels as
   over-engineered for bi-weekly frequency).
5. PR generation: Deferred (plan review rejected automated Markdown surgery as
   brittle; issue-only gives 90% value at 20% complexity).
