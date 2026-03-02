---
title: Change Governing Law from Delaware to France
type: feat
date: 2026-03-02
---

# Change Governing Law from Delaware to France

## Overview

Replace all Delaware governing law references in Soleur's Terms & Conditions and Disclaimer with French law / Courts of Paris. Collapse the 3-tier US/EU/Other structure into a uniform French law default with a preserved EU/EEA consumer paragraph. Fix the Disclaimer entity attribution.

## Problem Statement

Jikigai is incorporated in France (25 rue de Ponthieu, 75008 Paris). The CLAs already use French law / Paris courts. The T&Cs and Disclaimer incorrectly reference Delaware -- inherited from a US-centric template. This creates an internal jurisdictional inconsistency.

## Proposed Solution

### New Section 14 Structure (Terms & Conditions)

Replace the current 3-subsection structure (14.1 US / 14.2 EU / 14.3 Other) with 3 subsections modeled on CLA Section 8(a):

**14.1 Governing Law** -- Uniform French law clause:

> These Terms shall be governed by and construed in accordance with the laws of France, without regard to its conflict of laws provisions.

**14.2 Jurisdiction** -- Courts of Paris as default venue:

> Any disputes arising under or in connection with these Terms shall be subject to the exclusive jurisdiction of the courts of Paris, France.

**14.3 EU/EEA Consumers** -- Preserved explicit rights + ODR reference:

> If you are a consumer in the EU/EEA, nothing in these Terms affects your rights under mandatory EU or member state consumer protection laws, including your right to bring proceedings in the courts of your country of habitual residence. The European Commission provides an Online Dispute Resolution (ODR) platform at https://ec.europa.eu/consumers/odr. We are not obligated to participate in ODR procedures but will consider doing so on a case-by-case basis.

### New Section 8 Structure (Disclaimer)

Mirror the T&Cs structure, adapted for Disclaimer context:

**8.1 Governing Law** -- French law clause (same as T&Cs 14.1)
**8.2 Jurisdiction** -- Courts of Paris (same as T&Cs 14.2)
**8.3 EU/EEA Consumers** -- Explicit consumer rights (no ODR reference -- Disclaimer is not a transactional document)

### Additional Changes

- **Disclaimer entity fix:** Change "operated by Soleur" to "operated by Jikigai" in the Disclaimer header (matches T&Cs and the Legal Entity section)
- **Last Updated date:** Update to the change date in both documents
- **Frontmatter:** Update `jurisdiction: EU, US` to `jurisdiction: FR, EU` in `docs/legal/` versions of both files

## Acceptance Criteria

- [ ] T&Cs Section 14 uses French law / Courts of Paris with 3-subsection structure (law, jurisdiction, EU/EEA)
- [ ] No geographic tier splitting -- single governing law applies to all users
- [ ] Disclaimer Section 8 mirrors the same structure
- [ ] Disclaimer entity attribution corrected from "Soleur" to "Jikigai"
- [ ] Last Updated dates bumped in both documents
- [ ] Frontmatter `jurisdiction:` field updated to `FR, EU`
- [ ] All 4 files updated in sync (2 docs x 2 locations)
- [ ] Zero Delaware references in `docs/legal/` and `plugins/soleur/docs/pages/legal/` (grep verified)
- [ ] Post-change compliance audit passes (legal-compliance-auditor agent)

## Test Scenarios

- Given the updated T&Cs, when grepping for "Delaware" in `docs/legal/` and `plugins/soleur/docs/pages/legal/`, then zero results
- Given the Disclaimer header, when reading the operator attribution, then it says "Jikigai" not "Soleur"
- Given Section 14, when reviewing subsections, then no US-specific or Other-user subsections exist

## Files to Change

| # | File | Changes |
|---|------|---------|
| 1 | `docs/legal/terms-and-conditions.md` | Section 14 rewrite, Last Updated, frontmatter jurisdiction |
| 2 | `plugins/soleur/docs/pages/legal/terms-and-conditions.md` | Section 14 rewrite, Last Updated |
| 3 | `docs/legal/disclaimer.md` | Section 8 rewrite, entity fix in header, Last Updated, frontmatter jurisdiction |
| 4 | `plugins/soleur/docs/pages/legal/disclaimer.md` | Section 8 rewrite, entity fix in header, Last Updated |

## Implementation Sequence

1. **Edit `docs/legal/terms-and-conditions.md`** -- replace Section 14, update frontmatter, Last Updated
2. **Edit `plugins/soleur/docs/pages/legal/terms-and-conditions.md`** -- mirror Section 14 content, update Last Updated
3. **Edit `docs/legal/disclaimer.md`** -- replace Section 8, fix entity attribution, update frontmatter, Last Updated
4. **Edit `plugins/soleur/docs/pages/legal/disclaimer.md`** -- mirror Section 8 content, fix entity attribution, update Last Updated
5. **Grep verification** -- confirm zero Delaware references in legal document directories
6. **Run legal-compliance-auditor** -- cross-document consistency check

## Deferred Work (Follow-up Issues)

- Add 30-day amicable resolution clause (if legal counsel recommends it -- separate PR)
- Add mandatory-law savings clause for non-EU users (if needed -- separate PR)
- Add future effective date mechanism for material T&Cs changes (Section 12 compliance process)
- Review enforceability of Sections 9, 10, 11 of T&Cs under French consumer law (Code civil Art. 1171)
- Consider adding governing law clauses to Privacy Policy, GDPR Policy, Cookie Policy, AUP
- Update legal-document-generator agent jurisdiction defaults
- Align Disclaimer Section 9 (Changes) with T&Cs Section 12 advance notice provision

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-02-french-governing-law-brainstorm.md`
- Spec: `knowledge-base/specs/feat-french-governing-law/spec.md`
- CLA governing law clause (structural template): `docs/legal/individual-cla.md:66`
- Issue: #360
- Draft PR: #359
