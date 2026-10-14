# Rule Audit CI Brainstorm

**Date:** 2026-03-30
**Issue:** #451
**Branch:** rule-audit-ci
**Prior art:** #422 brainstorm (archived), PR #450 (compound Phase 1.5 warning)

## What We're Building

A scheduled GitHub Actions workflow that audits always-loaded governance rules
(AGENTS.md + constitution.md) for budget compliance and cross-layer duplication,
then creates GitHub issues and PRs with tier migration proposals.

The compound skill's Phase 1.5 already warns at 250 rules per-session. This CI
system provides the automated cleanup pipeline that was deferred from #422 when
the count was 219. We've now hit 313 (constitution: 251, AGENTS.md: 62).

### Components

1. **Rule budget counter** -- Counts always-loaded rules, fails if over threshold
2. **Cross-layer duplication detector** -- Finds rules duplicated across tiers
   (hooks, AGENTS.md, constitution.md, agent descriptions, skill instructions)
3. **Report generator** -- Produces issue body and PR diff with tier migration
   proposals and deletion candidates
4. **Fingerprint deduplicator** -- SHA-based fingerprint of sorted findings to
   avoid creating duplicate issues/PRs on consecutive runs

## Why This Approach

**Trigger:** Always-loaded rules reached 313, crossing the 300 threshold defined
in #451. Growth rate: +94 rules in 25 days since the original brainstorm.

**Why CI, not just compound warnings:** The compound Phase 1.5 warning fires
per-session but depends on human action. At current growth rate (~3.7 rules/day),
passive warnings aren't sufficient. The CI audit creates actionable PRs that can
be reviewed and merged without manual rule archaeology.

**Why shell scripts:** Existing hook scripts in `.claude/hooks/` use shell. The
governance files use consistent bullet-point formatting that shell + grep handles
well. No build step needed in CI.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Original #422 design holds** | Five-tier model, bi-weekly schedule, issue+PR creation, fingerprint deduplication all confirmed |
| 2 | **Shell + grep/awk** for audit scripts | Portable, no build step, matches existing hook patterns |
| 3 | **Exact substring + keyword matching** for duplication | Low false positives. Match key phrases shared across tiers. May miss paraphrased duplicates but that's acceptable |
| 4 | **Migrations + deletion candidates** in PR scope | Flag rules for tier migration AND potential obsolescence. Deletion candidates are flagged, not auto-removed |
| 5 | **Bi-weekly schedule** | Balance between catching drift and noise. `0 9 1,15 * *` or similar |
| 6 | **Modular shell scripts** in `scripts/rule-audit/` | Separate scripts for counting, duplication detection, and report generation. GH Action orchestrates. Each independently testable |
| 7 | **SHA fingerprint** for idempotent issue/PR creation | SHA256 of sorted findings list. Stored as label or in issue body. Skip creation if fingerprint matches existing open issue |

## Architecture

### Five Enforcement Tiers (from #422, unchanged)

| Tier | Layer | Context Cost | When to Use |
|------|-------|-------------|-------------|
| 1 | PreToolUse hooks | Zero (not loaded into context) | Mechanical enforcement (block commits on main, etc.) |
| 2 | AGENTS.md | Always loaded | Sharp edges the agent will violate without being told every turn |
| 3 | constitution.md | Always loaded | Conventions and judgment calls |
| 4 | Agent descriptions | On agent reference | Domain-specific guidance |
| 5 | Skill instructions | On skill invocation | Workflow-specific procedures |

### Script Structure

```text
scripts/rule-audit/
  count-rules.sh        # Count always-loaded rules, output budget report
  detect-duplication.sh  # Cross-reference tiers for shared phrases
  generate-report.sh     # Build issue body + PR diff from findings
  fingerprint.sh         # SHA256 of sorted findings, check for existing issues
```

### Workflow

```text
.github/workflows/rule-audit.yml
  schedule: cron '0 9 1,15 * *'  (bi-weekly, 1st and 15th)
  workflow_dispatch: (manual trigger)

  Steps:
  1. count-rules.sh → budget stats
  2. detect-duplication.sh → duplication findings
  3. generate-report.sh → issue body + branch diff
  4. fingerprint.sh → check if identical issue exists
  5. If new findings: create issue + PR via gh CLI
  6. If identical: skip (idempotent)
```

### Duplication Detection Strategy

Cross-reference rules between layers using keyword extraction:

1. Extract key phrases from each rule (strip common words, normalize whitespace)
2. For each AGENTS.md/constitution.md rule, check if a PreToolUse hook enforces
   the same constraint (match against hook script patterns and comments)
3. For each always-loaded rule, check if an agent description or skill instruction
   contains the same guidance (check `agents/**/*.md` and `skills/*/SKILL.md`)
4. Flag matches with: source tier, target tier, matched phrase, migration direction

### Fingerprint Deduplication

```text
1. Sort all findings alphabetically
2. SHA256 hash the sorted list
3. Search open issues for label 'rule-audit-fingerprint:<hash>'
4. If found: skip issue/PR creation
5. If not found: create issue with fingerprint label, create PR
```

## Non-Goals

- **Semantic/fuzzy matching** -- Exact keyword matching is sufficient at current
  scale. Revisit if false negative rate becomes a problem.
- **Rule manifest YAML** -- Deferred from #422. Still not needed. The audit
  script parses governance files directly.
- **Auto-merge of migration PRs** -- All tier migrations require human review.
  The PR is a proposal, not an auto-fix.
- **Session counting infrastructure** -- Trigger B (zero-violation decay) from
  the original brainstorm remains deferred.

## Open Questions

1. **Budget threshold for CI failure.** The compound warns at 250. Should the CI
   audit use a higher threshold (300? 350?) for creating issues, or match the
   250 warning?
2. **Hook test coverage verification.** Should the audit check that hooks have
   test coverage in `test-pretooluse-hooks.yml` before proposing a rule migrates
   to hook-only enforcement?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO assessment pending (background agent). Key technical concerns:
script portability in GH Actions, fingerprint collision avoidance, PR diff
generation for multi-file tier migrations, and interaction with existing
`test-pretooluse-hooks.yml` workflow.
