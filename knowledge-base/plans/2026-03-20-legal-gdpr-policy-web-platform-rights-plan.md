---
title: "legal: GDPR Policy Section 5 missing Web Platform-specific rights subsection"
type: fix
date: 2026-03-20
semver: patch
---

# legal: GDPR Policy Section 5 missing Web Platform-specific rights subsection

Closes #909

## Overview

GDPR Policy Section 5 (Data Subject Rights) has three subsections: 5.1 (Rights Exercisable Against Third Parties), 5.2 (Rights Exercisable Locally), and 5.3 (Supervisory Authority). Web Platform data subject rights are mentioned only in the Section 5 intro paragraph: "For data processed through the Web Platform (app.soleur.ai), these rights are exercisable directly against Jikigai by contacting legal@jikigai.com."

Both the DPD Section 5.3 and T&C Section 8.4 cross-reference "GDPR Policy Section 5" for "full details" on Web Platform rights. But the section lacks a dedicated subsection -- the intro paragraph is the only coverage.

## Problem Statement

This is a GDPR transparency gap. Two companion documents (DPD, T&C) direct Web Platform users to GDPR Policy Section 5 for full details on exercising their data subject rights, but Section 5 only offers a one-sentence mention in its intro paragraph. The DPD itself already has a detailed Section 5.3 enumerating all six GDPR rights for Web Platform data (added in #888/#898), making the GDPR Policy the only document in the legal suite without explicit Web Platform rights enumeration.

### Cross-Document Consistency Audit

| Document | Section | Web Platform Rights Coverage | Status |
|----------|---------|------------------------------|--------|
| GDPR Policy | 5 (intro) | One sentence in intro paragraph | **GAP** (this issue) |
| DPD | 5.3 | Full enumeration of 6 rights with qualifications | Covered (#888) |
| Privacy Policy | 8.1 | Lists 7 rights, directs Web Platform users to legal@jikigai.com | Covered |
| T&C | 8.4 | Directs to GDPR Policy Section 5 for "full details" | Cross-ref (depends on this fix) |

## Proposed Solution

Add a new Section 5.3 "Rights Exercisable Against Jikigai (Web Platform)" between the current Section 5.2 (Rights Exercisable Locally) and Section 5.3 (Supervisory Authority). Renumber the current Section 5.3 to Section 5.4.

### Placement Rationale

The three existing subsections follow a logical hierarchy: third-party rights (5.1), local rights (5.2), supervisory authority (5.3). Web Platform rights exercisable directly against Jikigai fit naturally between local rights and supervisory authority -- they are "rights exercisable against the controller" which is the middle ground between third-party and local. The supervisory authority section is a structural catch-all that belongs last.

### Content Alignment

The new section mirrors the DPD Section 5.3 content for consistency, with adjustments for the GDPR Policy's role as the canonical rights reference:

1. Enumerate all six GDPR rights (Articles 15-18, 20-21) for Web Platform data
2. Specify the contact channel (legal@jikigai.com)
3. State the 5-business-day acknowledgment and one-month response timeline (Article 12(3))
4. Note data categories (account data, workspace data, subscription metadata -- matching Section 3.7)
5. Qualify Right to Object for contract-performance legal basis
6. Cross-reference French tax law retention for Right to Erasure

### Research Insights

**Right to Object nuance:** The Web Platform's legal basis is contract performance (Article 6(1)(b)), not legitimate interest. Under Article 21(1), the right to object applies to processing based on Article 6(1)(e) or 6(1)(f). For contract-performance processing, the right to object is limited -- it applies only when processing extends beyond strict contractual necessity. The DPD Section 5.3(f) already handles this correctly and the new GDPR Policy section should match.

**Right to Erasure limitation:** French tax law (Code de commerce Art. L123-22) requires 10-year retention of commercial records. GDPR Policy Section 8.4 already documents this for Web Platform data. The new rights section should cross-reference this to avoid contradicting the retention policy.

**Renumbering impact:** Renumbering Section 5.3 to 5.4 affects any cross-references to "Section 5.3 (Supervisory Authority)." The DPD does not cross-reference GDPR Policy Section 5.3 by number -- it references "GDPR Policy Section 5" broadly. No other legal documents reference Section 5.3 by specific number. Renumbering is safe.

**Response timelines:** The 5-business-day acknowledgment and one-month response timeline appear in: GDPR Policy Section 14, T&C Section 17, and DPD Section 5.3. All must remain consistent.

## Files to Modify

| File | Change |
|------|--------|
| `docs/legal/gdpr-policy.md` | Add Section 5.3, renumber 5.3 to 5.4, update "Last Updated" |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | Add Section 5.3, renumber 5.3 to 5.4, update "Last Updated" |

## Acceptance Criteria

- [ ] GDPR Policy Section 5.3 "Rights Exercisable Against Jikigai (Web Platform)" exists in both `docs/legal/gdpr-policy.md` and `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [ ] Section 5.3 enumerates all six GDPR rights (Articles 15-18, 20-21) for Web Platform data
- [ ] Section 5.3 specifies legal@jikigai.com as the contact channel
- [ ] Section 5.3 states the 5-business-day acknowledgment timeline (matching Section 14 and DPD Section 5.3)
- [ ] Section 5.3 states the one-month response timeline (Article 12(3))
- [ ] Section 5.3 data categories match Section 3.7 (account data, workspace data, subscription metadata)
- [ ] Right to Erasure clause notes French tax law retention (Code de commerce Art. L123-22), cross-referencing Section 8.4
- [ ] Right to Object clause qualifies applicability for contract-performance legal basis (Article 6(1)(b))
- [ ] Former Section 5.3 (Supervisory Authority) renumbered to Section 5.4
- [ ] "Last Updated" date in both files reflects the change date
- [ ] Both file copies remain in sync (identical legal content, differing only in link format and HTML wrapper)
- [ ] No cross-reference to "Section 5.3 (Supervisory Authority)" is broken by the renumbering
- [ ] Article 30 register count in Section 10 remains accurate (no new processing activity added)

## Test Scenarios

- Given the GDPR Policy is opened, when a Web Platform user reads Section 5, then they find a dedicated subsection (5.3) with clear instructions for exercising each of their six data subject rights against Jikigai
- Given a user follows the T&C Section 8.4 cross-reference to "GDPR Policy Section 5", when they arrive at Section 5, then they find detailed Web Platform rights coverage (not just an intro paragraph mention)
- Given a user reads both the GDPR Policy Section 5.3 and the DPD Section 5.3, when they compare the rights enumeration, then the content is consistent (same six rights, same qualifications, same timelines)
- Given a user exercises the right to erasure for payment records via the GDPR Policy, when Jikigai responds, then the response correctly explains the 10-year French tax law retention period
- Given a developer reads the Eleventy copy and the source copy, when they compare them, then the legal content is identical (links differ only in format)

## Non-Goals

- Do not modify the DPD Section 5.3 (already correct and complete from #888)
- Do not modify the Privacy Policy Section 8.1 (already correctly directs to legal@jikigai.com)
- Do not modify the T&C Section 8.4 (its cross-reference to "GDPR Policy Section 5" will be satisfied by this fix)
- Do not add newsletter/CLA-specific rights subsections (the intro paragraph adequately covers these third-party-mediated cases)
- Do not restructure the entire Section 5 hierarchy (minimal change principle)

## Draft Content

### New Section 5.3 (inserted between current 5.2 and 5.3)

```markdown
### 5.3 Rights Exercisable Against Jikigai (Web Platform)

For data processed through the Web Platform (app.soleur.ai) where Jikigai acts as data controller (see Section 2.1), data subjects may exercise the following rights by contacting legal@jikigai.com:

- **Right of Access (Article 15):** Request confirmation of whether personal data is being processed and obtain a copy of the data (account data, workspace data, subscription metadata).
- **Right to Rectification (Article 16):** Request correction of inaccurate personal data held by Jikigai.
- **Right to Erasure (Article 17):** Request deletion of personal data under applicable conditions. Note: payment records subject to French tax law retention (Code de commerce Art. L123-22) may be retained for up to 10 years (see Section 8.4).
- **Right to Restriction of Processing (Article 18):** Request that Jikigai restrict processing of personal data.
- **Right to Data Portability (Article 20):** Request personal data in a structured, commonly used, machine-readable format.
- **Right to Object (Article 21):** Object to processing of personal data. The legal basis for Web Platform processing is contract performance (Article 6(1)(b)), so this right applies primarily when processing extends beyond strict contractual necessity.

Jikigai will acknowledge requests within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3).
```

### Renumbered Section 5.4

```markdown
### 5.4 Supervisory Authority
```

(Content unchanged, only heading number changes from 5.3 to 5.4.)

### Section 5 Intro Paragraph

The existing intro paragraph already mentions Web Platform rights. After the new Section 5.3 exists, the intro paragraph can optionally add a forward reference ("see Section 5.3 below") but this is not required -- the subsection heading is discoverable. Keep the intro paragraph unchanged to minimize diff size.

## Context

- **Parent issue:** #909
- **Sibling issue (completed):** #888 (DPD Section 5.3, merged in #898)
- **Cross-document audit origin:** #888 audit identified this gap
- **Priority:** P2 -- cross-reference sends users to a section that does not fully deliver
- **Risk:** Low implementation risk (additive change with one renumber, no breaking cross-references)
- **Semver:** patch (legal document fix, no new features)

## References

- GitHub Issue: #909
- DPD Section 5.3 (the Web Platform rights subsection added by #888, serves as content template)
- GDPR Policy Section 2.1 (establishes Jikigai as controller for Web Platform data)
- GDPR Policy Section 3.7 (Web Platform lawful basis: contract performance)
- GDPR Policy Section 8.4 (Web Platform data retention, including French tax law 10-year retention)
- GDPR Policy Section 14 (contact information with 5-business-day acknowledgment timeline)
- T&C Section 8.4 (cross-references "GDPR Policy Section 5 for full details")
- DPD Section 5.3 (cross-references "companion GDPR Policy Section 5")
- Privacy Policy Section 8.1 (lists 7 rights, directs to legal@jikigai.com)
