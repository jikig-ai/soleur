---
title: "Dogfood Legal Agents"
type: feat
date: 2026-02-20
deepened: 2026-02-20
---

# Dogfood Legal Agents

## Enhancement Summary

**Deepened on:** 2026-02-20
**Research areas:** GDPR/CCPA compliance requirements, SaaS legal document best practices, agent dogfooding patterns
**Key improvements:** Added jurisdiction-specific section requirements, Soleur-specific data practice clarifications, cross-document consistency checklist

## Overview

Generate all 7 supported legal document types for Soleur using legal-document-generator, then audit them using legal-compliance-auditor. Validates both agents end-to-end with real company context. Jurisdiction: EU/GDPR + US.

## Problem Statement

Legal domain (v2.20.0) has two agents, two skills, no real usage. Need to validate output quality, cross-references, disclaimers, and compliance auditing against actual company data.

## Steps

1. Extract company context from `knowledge-base/overview/brand-guide.md`
2. Generate 7 legal documents via legal-document-generator agent
3. Write to `docs/legal/`
4. Audit all 7 via legal-compliance-auditor agent
5. Fix Critical/High findings
6. Re-audit to confirm

## Success Criteria

- [x] 7 documents in `docs/legal/`
- [x] Audit findings documented in conversation (51 findings: 8C, 20H, 16M, 7L)
- [x] Critical/High findings resolved

## Research Insights

### Soleur-Specific Data Practice Clarifications

Since the plugin runs locally with no cloud data collection, each document should emphasize:
- "Data stored on your local filesystem is not transmitted to Soleur servers"
- GitHub Pages hosting disclosure (GitHub may collect IP addresses for the docs site)
- Knowledge-base files are local-only; Soleur has no access to user data
- If docs site uses analytics, disclose third-party processors

### Privacy Policy - Required GDPR Sections (Articles 13/14)

- Controller identity and contact details
- Purposes and legal basis for processing
- Data categories collected
- Recipients/third parties (GitHub Pages, any analytics)
- Retention periods
- Data subject rights (access, rectification, erasure, portability, objection)
- Right to withdraw consent and lodge complaints
- International transfer disclosures

### Privacy Policy - US/CCPA Requirements (2026 updates)

- Right to correction disclosure
- Dark pattern prohibitions in consent mechanisms
- Opt-out confirmation mechanism
- Automated Decision-Making Technology (ADMT) disclosure if applicable

### Terms and Conditions - Essential Clauses

- Service description and license grant
- IP ownership: Soleur owns code, user owns knowledge-base files
- AS-IS warranty disclaimer (free/open-source tool)
- Liability cap ($100 or amount paid in 12 months)
- Indemnification, termination, governing law
- Modification rights with notice period

### Cookie Policy

- If docs site uses cookies: prior consent banner with opt-in, cookie table with categories
- If no cookies: simple statement "This site does not use cookies"
- Essential cookies exception still requires disclosure

### Data Processing Agreement

- Soleur is likely NOT a processor under GDPR since the plugin is local-only
- DPA should clarify this relationship explicitly
- If future cloud features are added, DPA becomes required under Article 28

### Acceptable Use Policy - CLI Tool Context

- Prohibit malicious automation via agents (spam, phishing, exploits)
- Prohibit circumventing rate limits or security controls
- Prohibit generating harmful/illegal content
- Require respecting third-party API terms (GitHub, Claude)

### Cross-Document Consistency Checklist

- Contact information matches across all 7 documents
- Data practices described consistently (local-only processing)
- Jurisdiction claims consistent (EU/GDPR + US in all docs)
- Cross-references point to documents that actually exist
- "Last Updated" dates consistent

## References

- Legal agents: `plugins/soleur/agents/legal/`
- Legal skills: `plugins/soleur/skills/legal-generate/`, `plugins/soleur/skills/legal-audit/`
- Brand guide: `knowledge-base/overview/brand-guide.md`
- Learnings: agent-prompt-sharp-edges-only, growth-strategist-agent-skill-development
