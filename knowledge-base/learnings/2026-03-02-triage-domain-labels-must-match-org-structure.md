# Learning: Triage domain labels must match organizational structure

## Problem

The daily triage workflow (PR #375) introduced 7 ad-hoc domain labels (`domain/plugin`, `domain/ci`, `domain/docs`, `domain/community`, `domain/infra`, `domain/legal`, `domain/marketing`) that didn't align with Soleur's 8 department leaders (Engineering/CTO, Finance/CFO, Legal/CLO, Marketing/CMO, Operations/COO, Product/CPO, Sales/CRO, Support/CCO).

This caused a disconnect: triage classified issues into domains that couldn't route to any domain leader. For example, `domain/plugin` and `domain/ci` both belong to Engineering but were separate labels with no leader mapping.

## Solution

1. Replaced the 7 ad-hoc labels with 8 labels matching Soleur departments: `domain/engineering`, `domain/finance`, `domain/legal`, `domain/marketing`, `domain/operations`, `domain/product`, `domain/sales`, `domain/support`
2. Updated the classification rubric in the workflow prompt to describe what each department covers (e.g., engineering = plugin code + CI/CD + infra + docs)
3. Re-labeled all open issues from old to new domains
4. Deleted the old labels from GitHub
5. Updated the ticket-triage agent to reference the 8 departments

## Key Insight

Any automated system that classifies by domain must use the canonical organizational taxonomy, not an ad-hoc one invented at implementation time. This is the same class of problem as "domain enumeration drift" (see `2026-02-22-domain-prerequisites-refactor-table-driven-routing.md`). The fix is simple: when adding a new workflow that routes by domain, reference the Domain Leaders table in `plugins/soleur/AGENTS.md` as the single source of truth.

## Tags
category: integration-issues
module: ci-workflows
