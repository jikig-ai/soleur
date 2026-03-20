# Legal Agents & Skills

**Issue:** #114
**Branch:** feat-legal-agents
**Date:** 2026-02-19

## Problem Statement

The Soleur plugin has no legal domain -- no agents, skills, or content for generating or auditing legal documents. Users building products need Terms & Conditions, Privacy Policies, Cookie Policies, GDPR compliance documents, and more. Currently this requires manual drafting or external tools. The soleur.ai website itself has no legal pages.

## Goals

- G1: Create a Legal top-level agent domain with document generation and compliance auditing capabilities
- G2: Support 7 legal document types: Terms & Conditions, Privacy Policy, Cookie Policy, GDPR Policy, Acceptable Use Policy, Data Processing Agreement, Disclaimer / Limitation of Liability
- G3: Provide user-facing skills for both generation and auditing workflows
- G4: Dogfood the tools by generating soleur.ai's own legal pages
- G5: All generated content clearly marked as drafts requiring professional legal review

## Non-Goals

- NG1: Providing actual legal advice or replacing professional legal counsel
- NG2: Automated cookie consent banners or GDPR consent management UI
- NG3: Legal document version tracking or diff tooling
- NG4: Jurisdiction-specific legal database or case law references
- NG5: A dedicated publishing agent for Eleventy pages (handled within the generate skill)

## Functional Requirements

- FR1: `legal-document-generator` agent generates draft legal documents from company context (name, product, data practices, jurisdiction)
- FR2: `legal-compliance-auditor` agent analyzes existing legal documents and produces a findings report with severity ratings
- FR3: `legal-generate` skill provides interactive workflow for document generation, supporting both markdown and Eleventy `.njk` output formats
- FR4: `legal-audit` skill scans a project's legal documents and invokes the auditor with structured reporting
- FR5: Generator supports all 7 document types with appropriate sections per type
- FR6: Auditor checks for gaps, outdated clauses, missing disclosures, and cross-document consistency
- FR7: All generated documents include "DRAFT - Requires legal review" disclaimers

## Technical Requirements

- TR1: Agents live under `agents/legal/` as a new 5th top-level domain
- TR2: Skills live flat under `skills/legal-generate/` and `skills/legal-audit/` (loader doesn't recurse)
- TR3: Register new domain in docs site data files (`agents.js` domain labels, CSS vars, domain order)
- TR4: Register new skills in `skills.js` SKILL_CATEGORIES map
- TR5: Update plugin.json version (minor bump for new agents + skills)
- TR6: Update CHANGELOG.md, README.md (versioning triad)
- TR7: Update plugin.json description with new agent/skill counts

## Architecture

```
agents/
  legal/                              # New 5th top-level domain
    legal-document-generator.md       # Generates draft legal documents
    legal-compliance-auditor.md       # Audits existing legal documents

skills/
  legal-generate/
    SKILL.md                          # User-facing generation skill
  legal-audit/
    SKILL.md                          # User-facing audit skill
```

## Acceptance Criteria

- [ ] `legal-document-generator` agent can generate all 7 document types
- [ ] `legal-compliance-auditor` agent produces structured audit reports
- [ ] `legal-generate` skill walks user through context gathering and document generation
- [ ] `legal-audit` skill scans and reports on existing legal documents
- [ ] Legal domain appears on docs site agents page with correct styling
- [ ] Legal skills appear on docs site skills page in correct category
- [ ] Plugin version bumped (minor) with changelog entry
- [ ] soleur.ai legal pages generated using the new tools (dogfooding)
