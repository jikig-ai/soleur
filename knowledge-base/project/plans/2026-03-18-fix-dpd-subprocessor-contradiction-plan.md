---
title: "fix: DPD Section 4.1 contradiction with Section 2.3(e) on sub-processors"
type: fix
date: 2026-03-18
---

# fix: DPD Section 4.1 contradiction with Section 2.3(e) on sub-processors

## Overview

The Data Protection Disclosure (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`) contains an internal contradiction: Section 4.1 ("No Sub-processors") states there are no sub-processors to disclose, while Section 2.3(e) explicitly names Buttondown as a data processor on behalf of Jikigai. The Section 4.2 table also lists Buttondown as "data processor on behalf of Jikigai." This fix resolves the contradiction by restructuring Section 4.1 to distinguish Plugin-level processing (none) from Docs Site processing (Buttondown).

## Problem Statement

**Current state:**

- **Section 4.1** (line 122-124): Heading "No Sub-processors" with body: "Because Soleur does not process Personal Data on behalf of Users, there are no Sub-processors to disclose under Article 28(2) of the GDPR."
- **Section 2.3(e)** (line 91): Correctly identifies Buttondown as "a data processor on behalf of Jikigai" for newsletter subscription management.
- **Section 4.2 table** (line 135): Lists Buttondown with relationship "Buttondown acts as data processor on behalf of Jikigai."

The contradiction: Section 4.1 says no sub-processors exist, but Section 2.3(e) discloses Buttondown as a processor, and the table in 4.2 reinforces this. The document contradicts itself.

**Why this matters:** Internal contradictions in legal documents undermine credibility and could create compliance exposure. A GDPR supervisory authority reviewing the DPD would flag the inconsistency.

**Root cause:** Section 4.1 was written for the Plugin's local-only architecture (correct for the Plugin itself). When Buttondown was added as a newsletter processor in the March 10, 2026 update (Section 2.3(e)), Section 4.1 was not updated to reflect the new processing relationship.

## Proposed Solution

Restructure Section 4 to clearly distinguish two scopes:

1. **Plugin scope:** The Plugin itself has no sub-processors (correct -- it runs locally and processes nothing on behalf of users).
2. **Docs Site scope:** Jikigai engages Buttondown as a data processor for newsletter subscription management. While Buttondown is technically a "processor" (not a "sub-processor" since Jikigai is the Controller, not a Processor), the disclosure belongs in Section 4 because users expect to find third-party data processing relationships there.

**Key GDPR terminology note:** Under Article 28, a "sub-processor" is a processor engaged by another processor. Since Jikigai acts as Controller (not Processor) for newsletter data, Buttondown is a **processor**, not a sub-processor. Section 4.1's heading and framing should reflect this distinction accurately.

### Proposed Section 4.1 Rewrite

Replace the current Section 4.1 ("No Sub-processors") with a two-part structure:

**4.1 Plugin Sub-processors**

The Plugin does not process Personal Data on behalf of Users (see Section 2.1). Accordingly, there are no Plugin-level Sub-processors to disclose under Article 28(2) of the GDPR.

**4.2 Docs Site Processors** (renumber current 4.2 to 4.3)

For processing activities where Jikigai acts as Controller (see Section 2.3), the following third-party processor is engaged:

| Processor | Processing Activity | Data Processed | Legal Basis | Sub-processor List |
|-----------|-------------------|----------------|-------------|-------------------|
| Buttondown ([buttondown.com](https://buttondown.com)) | Newsletter subscription management and email delivery | Email addresses of subscribers | Consent (Article 6(1)(a)) -- double opt-in | [Buttondown Sub-processors](https://buttondown.com/legal/dpa) |

This disclosure is consistent with Section 2.3(e).

**4.3 Third-Party Services Used by Users** (renumbered from current 4.2)

Keep the existing content but remove the Buttondown row from the table (it now belongs in 4.2) and clarify that the remaining services are user-initiated interactions, not Jikigai-engaged processors.

## Acceptance Criteria

- [ ] Section 4.1 heading changed from "No Sub-processors" to "Plugin Sub-processors" (or equivalent) -- scoped to Plugin only (`data-protection-disclosure.md:122`)
- [ ] Section 4.1 body updated to explicitly scope the "no sub-processors" statement to the Plugin (`data-protection-disclosure.md:124`)
- [ ] New Section 4.2 added disclosing Buttondown as a Docs Site processor with structured table (`data-protection-disclosure.md`)
- [ ] Current Section 4.2 renumbered to 4.3 (`data-protection-disclosure.md:127-137`)
- [ ] Buttondown removed from Section 4.3 table (no longer mixed with user-initiated services) (`data-protection-disclosure.md:135`)
- [ ] Cross-reference to Section 2.3(e) included in new Section 4.2
- [ ] "Last Updated" date bumped to current date (`data-protection-disclosure.md:20-21`)
- [ ] No other legal documents require changes (Privacy Policy and GDPR Policy already correctly describe Buttondown as a processor)

## Test Scenarios

- Given the updated DPD, when reading Section 4.1, then it clearly states the Plugin has no sub-processors (scoped to Plugin)
- Given the updated DPD, when reading Section 4.2, then Buttondown is disclosed as a processor for Docs Site newsletter management
- Given the updated DPD, when cross-referencing Section 4.2 with Section 2.3(e), then the two sections are consistent
- Given the updated DPD, when reading Section 4.3, then the third-party services table no longer contains Buttondown (it moved to 4.2)
- Given the Privacy Policy and GDPR Policy, when cross-referencing with the updated DPD, then all three documents describe Buttondown's role consistently

## Context

### Cross-Document Consistency Check

The following documents reference Buttondown and were verified for consistency:

| Document | Section | Statement | Status |
|----------|---------|-----------|--------|
| Privacy Policy | 5.3 | "Buttondown acts as a data processor on our behalf" | Consistent -- no change needed |
| GDPR Policy | Section 3.6 / Item 6 | "Data is processed by Buttondown (US-based, SCCs in place)" | Consistent -- no change needed |
| DPD | 2.3(e) | "Buttondown acts as a data processor on behalf of Jikigai" | Consistent -- no change needed |
| DPD | 4.1 | "No Sub-processors to disclose" | **Contradicts 2.3(e) -- this is the fix target** |
| DPD | 4.2 table | "Buttondown acts as data processor on behalf of Jikigai" | Needs relocation to new 4.2 |

### Files Modified

- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- sole file requiring changes

### Related Issues

- Closes #664
- Found by legal-compliance-auditor during PR #528 review

## References

- [GDPR Article 28 -- Processor](https://gdpr-info.eu/art-28-gdpr/) -- defines processor and sub-processor obligations
- [GDPR Article 4(8) -- Definition of Processor](https://gdpr-info.eu/art-4-gdpr/) -- processor vs sub-processor distinction
- GitHub Issue #664: [legal: DPD Section 4.1 contradicts Section 2.3(e) on sub-processors](https://github.com/jikig-ai/soleur/issues/664)
