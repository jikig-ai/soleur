---
title: "CLO Domain Leader for Legal"
type: feat
date: 2026-02-22
---

# feat: CLO Domain Leader for Legal

## Overview

Add a CLO (Chief Legal Officer) domain leader agent that orchestrates the existing legal specialists (legal-document-generator, legal-compliance-auditor) and hooks into the brainstorm command's domain detection workflow. This follows the established domain leader pattern (CMO, CTO, COO).

## Problem Statement / Motivation

The legal domain has 2 specialist agents but no orchestrator. The primary value is brainstorm integration: when someone brainstorms a feature with legal implications (GDPR compliance, terms of service, data processing), there is no mechanism to surface legal concerns during Phase 0.5. Other domains (Marketing, Engineering, Operations) auto-detect relevance and offer expert participation. Legal should follow the same pattern.

Related: #181 (this issue), #154 (domain leader interface -- closed).

## Proposed Solution

Create `agents/legal/clo.md` following the COO 3-phase pattern (Assess, Recommend/Delegate, Sharp Edges), then add legal domain detection to the brainstorm command's Phase 0.5.

### CLO Agent Design

Follow the COO pattern (lightweight orchestrator with 2 specialists):

**Phase 1 -- Assess:**
- Check for existing legal documents in `docs/legal/`, `knowledge-base/`, or project root
- Inventory which document types exist (Terms, Privacy, Cookie, GDPR, AUP, DPA, Disclaimer)
- Report: structured table of legal document health (document type, exists/missing, staleness)
- Do NOT check cross-document consistency here -- that is the auditor's job. Inventory only.

**Phase 2 -- Recommend and Delegate:**
- Recommend actions based on assessment (missing documents, stale documents, compliance gaps)
- Prioritize by legal risk and compliance urgency, then by impact

**Delegation table:**

| Agent | When to delegate |
|-------|-----------------|
| legal-document-generator | Generate new or regenerate outdated legal documents |
| legal-compliance-auditor | Audit existing documents for compliance gaps and cross-document consistency |

**Common sequential workflow:** audit (legal-compliance-auditor) -> generate/fix (legal-document-generator) -> re-audit (legal-compliance-auditor). Many tasks only need 1 agent -- do not force the full pipeline.

**Phase 3 -- Sharp Edges:**
- Defer technical architecture decisions to the CTO
- Do not provide legal advice -- all output is draft requiring professional review
- When assessing features that cross domains (e.g., data processing with infrastructure), flag cross-domain implications but defer non-legal concerns to respective leaders

### Brainstorm Command Updates

Add to Phase 0.5:

1. **Assessment question #5:** "Legal implications -- Does this feature involve creating, updating, or auditing legal documents such as terms of service, privacy policies, data processing agreements, or compliance documentation?"

2. **Routing block:** Standard 2-option pattern (include legal assessment / brainstorm normally)

3. **Participation section:** CLO task prompt for brainstorm participation

Note: The brainstorm comment at line 61 says "consider table-driven refactor at 5+ domains." With 4 domains assessed (marketing, engineering, operations, legal) plus the brand-specific special case, we are at the threshold. This plan adds the 5th assessment question but keeps the current sequential approach -- a table-driven refactor can be a separate follow-up if the pattern becomes unwieldy.

### Sibling Agent Disambiguation

Update descriptions of existing legal agents to append a CLO cross-reference:
- legal-document-generator: append "; use clo for cross-cutting legal strategy and multi-agent coordination"
- legal-compliance-auditor: append "; use clo for cross-cutting legal strategy and multi-agent coordination"

Existing disambiguation between the two specialists is preserved. The CLO reference is appended after their existing cross-references.

### Documentation Updates

- AGENTS.md: Add CLO to "Current Domain Leaders" table
- README.md (plugin): Update agent count (47 -> 48), update legal row in agents table (2 -> 3 agents)
- plugin.json: Update description count (47 -> 48 agents)
- CHANGELOG.md: Document the addition
- Root README.md: Update version badge
- `.github/ISSUE_TEMPLATE/bug_report.yml`: Update version placeholder
- Version: MINOR bump from current main version (merge main first to get latest)

## Acceptance Criteria

- [ ] `agents/legal/clo.md` exists and follows the COO 3-phase pattern (Assess, Recommend/Delegate, Sharp Edges)
- [ ] CLO description includes disambiguation with legal-document-generator and legal-compliance-auditor
- [ ] legal-document-generator and legal-compliance-auditor descriptions updated with CLO cross-reference
- [ ] Brainstorm command Phase 0.5 has legal domain assessment question (#5)
- [ ] Brainstorm command has legal routing block and CLO participation section
- [ ] AGENTS.md "Current Domain Leaders" table includes CLO
- [ ] README.md agent count updated to 48, legal row shows 3 agents
- [ ] plugin.json description updated to "48 agents"
- [ ] CHANGELOG.md documents the addition
- [ ] Root README.md version badge updated
- [ ] `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder updated
- [ ] Version bumped across all 3 versioning files
- [ ] Agent description cumulative word count stays under 2500

## Test Scenarios

- Given a brainstorm about "add GDPR compliance", when Phase 0.5 runs, then legal implications are detected and CLO participation is offered
- Given the user declines CLO participation, when Phase 0.5 completes, then brainstorm continues normally without legal input
- Given CLO participation accepted, when CLO assesses, then it inventories existing legal documents and reports gaps (without duplicating auditor's consistency checking)
- Given missing legal documents detected, when CLO delegates, then it spawns legal-document-generator
- Given existing documents with compliance gaps, when CLO delegates, then it spawns legal-compliance-auditor first
- Given both legal and marketing implications detected, when Phase 0.5 runs, then each domain is asked about separately

## References

- COO agent (closest pattern): `plugins/soleur/agents/operations/coo.md`
- CMO agent (full orchestration pattern): `plugins/soleur/agents/marketing/cmo.md`
- Brainstorm Phase 0.5: `plugins/soleur/commands/soleur/brainstorm.md:57-199`
- Domain leader interface: `plugins/soleur/AGENTS.md` (Domain Leader Interface section)
- Learnings: `knowledge-base/learnings/2026-02-21-domain-leader-pattern-and-llm-detection.md`
- Learnings: `knowledge-base/learnings/integration-issues/adding-new-agent-domain-checklist.md`
