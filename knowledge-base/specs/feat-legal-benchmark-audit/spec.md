# Spec: Legal Benchmark Audit Mode

**Brainstorm:** [2026-02-25-legal-benchmark-audit-brainstorm.md](../../brainstorms/2026-02-25-legal-benchmark-audit-brainstorm.md)
**Branch:** `feat-legal-benchmark-audit`

## Problem Statement

All 7 legal documents are AI-generated drafts that have only been checked for internal consistency and cross-document agreement. There is no way to validate them against external authoritative standards (regulatory checklists) or compare their coverage against peer SaaS companies' policies. This leaves blind spots that internal-only auditing cannot catch.

## Goals

- G1: Enable regulatory benchmarking of legal documents against GDPR Article 13/14, CCPA, ICO, and CNIL checklists
- G2: Enable peer comparison against similar-stage SaaS company policies (Basecamp, GitHub, GitLab)
- G3: Produce integrated findings in the existing CRITICAL/HIGH/MEDIUM/LOW severity format
- G4: Expose this as a `benchmark` sub-command on the existing `legal-audit` skill

## Non-Goals

- NG1: Comparing against Stripe Atlas corporate formation documents (wrong document type)
- NG2: Creating a new agent (extend existing `legal-compliance-auditor`)
- NG3: Caching peer policies locally (live fetch only)
- NG4: Replacing professional legal review (all output remains DRAFT advisory)

## Functional Requirements

- FR1: `legal-audit benchmark` sub-command triggers the enhanced audit mode
- FR2: Agent checks each document against regulatory disclosure checklists per jurisdiction
- FR3: Agent fetches peer SaaS policies via WebFetch and compares clause coverage
- FR4: Agent selects most relevant peer per document type from curated list
- FR5: Findings from regulatory and peer checks use the same severity format as compliance findings
- FR6: Plain `legal-audit` (without `benchmark`) continues to work as before

## Technical Requirements

- TR1: Modify `legal-compliance-auditor` agent instructions to include regulatory checklist and peer comparison sections
- TR2: Add `benchmark` sub-command to `legal-audit` skill SKILL.md
- TR3: No new agents or skills created
- TR4: Version bump (MINOR) for new capability
