---
title: "Dogfood Legal Agents - Tasks"
feature: feat-dogfood-legal-agents
date: 2026-02-20
---

# Tasks

## Phase 1: Generate Documents

- [ ] 1.1 Create `docs/legal/` directory
- [ ] 1.2 Generate Terms & Conditions (`docs/legal/terms-and-conditions.md`)
- [ ] 1.3 Generate Privacy Policy (`docs/legal/privacy-policy.md`)
- [ ] 1.4 Generate Cookie Policy (`docs/legal/cookie-policy.md`)
- [ ] 1.5 Generate GDPR Policy (`docs/legal/gdpr-policy.md`)
- [ ] 1.6 Generate Acceptable Use Policy (`docs/legal/acceptable-use-policy.md`)
- [ ] 1.7 Generate Data Processing Agreement (`docs/legal/data-processing-agreement.md`)
- [ ] 1.8 Generate Disclaimer (`docs/legal/disclaimer.md`)
- [ ] 1.9 Verify all documents have DRAFT disclaimers and YAML frontmatter

## Phase 2: Audit

- [ ] 2.1 Run compliance auditor against all 7 documents (EU/GDPR + US jurisdiction)
- [ ] 2.2 Review cross-document consistency findings
- [ ] 2.3 Catalog Critical and High severity findings

## Phase 3: Fix and Re-audit

- [ ] 3.1 Apply fixes for Critical findings
- [ ] 3.2 Apply fixes for High findings
- [ ] 3.3 Re-audit to confirm resolution
- [ ] 3.4 Verify Critical count is 0
