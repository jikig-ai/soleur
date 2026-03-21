---
title: "legal: DPD Section 5 missing Web Platform data subject rights"
type: fix
date: 2026-03-20
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Draft Content, Acceptance Criteria, Non-Goals, References)
**Analysis performed:** Cross-document consistency audit across DPD, GDPR Policy, Privacy Policy, T&C

### Key Improvements

1. Verified draft Section 5.3 content against all four companion legal documents for consistency
2. Discovered adjacent DPD gaps (Section 10 missing Web Platform account deletion, Section 7.2 not explicitly mentioning Web Platform) -- filed as out-of-scope findings to track separately
3. Refined Right to Object (Article 21) wording to align with GDPR Policy's treatment of contract-performance legal basis
4. Added cross-document verification checklist to acceptance criteria

### New Considerations Discovered

- DPD Section 10 (Termination and Data Deletion) has a parallel gap: no Web Platform account deletion subsection. This should be tracked as a separate issue.
- DPD Section 7.2 (Platform Breaches) references "GitHub repository, Docs Site, or distribution channels" but does not explicitly mention "Web Platform" -- a minor ambiguity that could be addressed in a follow-up.
- The Privacy Policy Section 8.1 lists seven rights (including "right to lodge a complaint"), while the GDPR Policy Section 5 and the DPD Section 5 list six rights. The DPD draft correctly matches the GDPR Policy's six-right enumeration, since the supervisory authority complaint right is structural (not exercised against the controller) and is covered in GDPR Policy Section 5.3.
- The "5 business days acknowledgment" timeline in the draft matches the T&C Section 16 and GDPR Policy Section 11. This is a voluntary commitment beyond the GDPR Article 12(3) one-month requirement -- it must remain consistent across all documents.

---

# legal: DPD Section 5 missing Web Platform data subject rights

Closes #888

## Overview

The Data Protection Disclosure (DPD) Section 5 (Data Subject Rights) only covers Local Data (5.1) and Docs Site/GitHub Data (5.2). It omits a section for exercising rights against Jikigai for Web Platform account/workspace/subscription data, despite DPD Section 2.1b establishing Jikigai as controller for that data.

The T&C Section 7.4 and Privacy Policy Section 8.1 both direct Web Platform users to exercise GDPR rights via <legal@jikigai.com> and reference the GDPR Policy Section 5. The GDPR Policy covers Web Platform rights in its intro paragraph ("For data processed through the Web Platform (app.soleur.ai), these rights are exercisable directly against Jikigai by contacting <legal@jikigai.com>"). But the DPD -- the document specifically about the data processing relationship -- has no Web Platform rights section.

### Cross-Document Consistency Audit

Verified the following documents for alignment before drafting Section 5.3:

| Document | Section | Web Platform Rights Coverage | Status |
|----------|---------|------------------------------|--------|
| GDPR Policy | 5 (intro) + 5.1-5.3 | Intro paragraph directs Web Platform users to <legal@jikigai.com>; Section 5.3 is Supervisory Authority | Covered (intro only, no dedicated subsection) |
| Privacy Policy | 8.1 | Lists 7 rights, directs Web Platform users to <legal@jikigai.com> | Covered |
| T&C | 7.4 | Directs Web Platform users to <legal@jikigai.com>, references GDPR Policy Section 5 | Covered |
| DPD | 5.1-5.2 | Local Data and Docs Site/GitHub only -- **no Web Platform coverage** | **GAP** |

The draft Section 5.3 closes this gap while maintaining consistency with the other three documents.

## Problem Statement

This is a GDPR transparency gap. The DPD is the document that describes how data subjects can exercise their rights in the context of the data processing relationship. Section 2.1b declares Jikigai as controller for Web Platform data. Section 5 should tell those data subjects how to exercise their rights. It currently does not.

## Proposed Solution

Add a new Section 5.3 "Web Platform Data" between the existing Section 5.2 and the `---` separator (before Section 6). The content should:

1. Enumerate GDPR rights (access, rectification, erasure, restriction, portability, objection) for Web Platform data
2. Specify the contact channel (<legal@jikigai.com>)
3. State the response timeline (one month per Article 12(3))
4. Reference the companion GDPR Policy Section 5 for full details
5. Note the data categories covered (account data, workspace data, subscription data -- consistent with Section 2.1b)

Apply identical content to both files, adjusting only link syntax (relative markdown links in `docs/legal/`, absolute HTML paths in `plugins/soleur/docs/pages/legal/`).

### Research Insights

**Right to Object nuance:** The Web Platform's legal basis is contract performance (Article 6(1)(b)), not legitimate interest (Article 6(1)(f)). Under Article 21(1), the right to object applies to processing based on Article 6(1)(e) (public interest) or Article 6(1)(f) (legitimate interest). For contract-performance processing, the right to object is limited -- it applies only when processing extends beyond strict contractual necessity. The draft correctly qualifies this. The GDPR Policy intro paragraph does not make this distinction, so the DPD adds useful specificity.

**Right to Erasure limitation:** French tax law (Code de commerce Art. L123-22) requires retention of commercial records for 10 years. The DPD Section 2.3(g) already documents this for payment records. The draft correctly cross-references this limitation in the Right to Erasure clause (c), preventing a contradiction between Section 5.3 (promising erasure) and Section 2.3(g) (requiring retention).

**Data categories alignment:** Section 2.1b lists "User account data, workspace data, and subscription data." Section 2.1b(c) expands this to "email addresses, hashed passwords, authentication tokens, session data, encrypted API keys, subscription metadata, and technical data (IP addresses, request headers)." The draft Section 5.3 intro uses the high-level categories from 2.1b, and the Right of Access clause (a) uses the same three categories. This is the correct level of specificity for a rights section -- too much detail would create a maintenance burden when data categories change.

## Files to Modify

| File | Change |
|------|--------|
| `docs/legal/data-protection-disclosure.md` | Add Section 5.3 Web Platform Data, update "Last Updated" date |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Add Section 5.3 Web Platform Data (HTML-style links), update "Last Updated" date |

## Acceptance Criteria

- [x] DPD Section 5.3 exists in both `docs/legal/data-protection-disclosure.md` and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [x] Section 5.3 enumerates all six GDPR rights (Articles 15-18, 20-21) for Web Platform data
- [x] Section 5.3 specifies <legal@jikigai.com> as the contact channel
- [x] Section 5.3 states the one-month response timeline (Article 12(3))
- [x] Section 5.3 states the 5-business-day acknowledgment timeline (matching T&C Section 16 and GDPR Policy Section 11)
- [x] Section 5.3 references GDPR Policy Section 5 for full details
- [x] Section 5.3 data categories match Section 2.1b (account data, workspace data, subscription data)
- [x] Right to Erasure clause cross-references Section 2.3(g) French tax law retention
- [x] Right to Object clause qualifies applicability for contract-performance legal basis
- [x] "Last Updated" date in both files reflects the change date
- [x] Both files remain in sync (identical legal content, differing only in link format)
- [x] No existing section numbering is broken (5.3 is new, no renumbering needed -- Section 6 follows)
- [x] Cross-document consistency: response timelines match GDPR Policy Section 11 and T&C Section 16

## Test Scenarios

- Given the DPD is opened, when a Web Platform user reads Section 5, then they find clear instructions for exercising their data subject rights against Jikigai for Web Platform data
- Given a user reads both the DPD and the GDPR Policy, when they compare the rights sections, then the DPD Section 5.3 is consistent with GDPR Policy Section 5's Web Platform guidance
- Given a user reads both copies of the DPD (docs/legal/ and plugins/soleur/docs/pages/legal/), when they compare them, then the legal content is identical (links differ only in format)
- Given a user exercises the right to erasure for payment records, when Jikigai responds, then the response correctly explains the 10-year French tax law retention period for subscription records

## Non-Goals

- Do not modify the GDPR Policy Section 5 (it already covers Web Platform rights in the intro paragraph)
- Do not modify the Privacy Policy or T&C (they already correctly reference the GDPR Policy Section 5)
- Do not add a supervisory authority subsection to the DPD (that belongs in the GDPR Policy, which already has it at Section 5.3)
- Do not renumber existing DPD sections
- Do not address the DPD Section 10 gap (missing Web Platform account deletion) -- track as separate issue
- Do not address the DPD Section 7.2 ambiguity (Web Platform not explicitly named in breach notification) -- track as separate issue

## Draft Content for Section 5.3

The new section should follow this structure, inserted after Section 5.2 and before the `---` separator:

```markdown
### 5.3 Web Platform Data

For data processed through the Web Platform (app.soleur.ai) where Jikigai acts as controller (see Section 2.1b), data subjects may exercise the following rights by contacting legal@jikigai.com:

- **(a)** **Right of Access (Article 15):** Request confirmation of whether personal data is being processed and obtain a copy of the data (account data, workspace data, subscription metadata).
- **(b)** **Right to Rectification (Article 16):** Request correction of inaccurate personal data held by Jikigai.
- **(c)** **Right to Erasure (Article 17):** Request deletion of personal data under applicable conditions. Note: subscription records subject to French tax law retention (Code de commerce Art. L123-22) may be retained for up to 10 years (see Section 2.3(g)).
- **(d)** **Right to Restriction of Processing (Article 18):** Request that Jikigai restrict processing of personal data.
- **(e)** **Right to Data Portability (Article 20):** Request personal data in a structured, commonly used, machine-readable format.
- **(f)** **Right to Object (Article 21):** Object to processing of personal data. The legal basis for Web Platform processing is contract performance (Article 6(1)(b)), so this right applies primarily when processing extends beyond strict contractual necessity.

Jikigai will acknowledge requests within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). For full details on how each right applies, see the companion [GDPR Policy](gdpr-policy.md) Section 5.
```

For the Eleventy template version, replace `[GDPR Policy](gdpr-policy.md)` with `[GDPR Policy](/pages/legal/gdpr-policy.html)`.

## Adjacent Gaps Discovered (Out of Scope)

These gaps were found during the cross-document audit and should be tracked as separate issues:

1. **DPD Section 10 -- Missing Web Platform Account Deletion:** Section 10 covers Plugin Removal (10.1) and Docs Site/Repository Data (10.2) but has no subsection for Web Platform account deletion. Section 2.3(f) states "deleted on account deletion request" but Section 10 does not describe the deletion process.

2. **DPD Section 7.2 -- Web Platform Not Explicitly Named:** Section 7.2 (Platform Breaches) covers "Soleur GitHub repository, Docs Site, or distribution channels" but does not explicitly mention the Web Platform. A Web Platform breach would arguably be the highest-impact breach scenario and should be explicitly called out.

## Context

- **Cross-document audit origin:** Found during #736 audit
- **Priority:** P1 -- GDPR gap in a data processing transparency document
- **Risk:** Low implementation risk (additive change only, no renumbering, no breaking changes)
- **Semver:** patch (legal document fix, no new features)

## References

- GitHub Issue: #888
- DPD Section 2.1b (establishes Jikigai as controller for Web Platform data)
- DPD Section 2.1b(c) (lists data categories: email, hashed passwords, auth tokens, session data, encrypted API keys, subscription metadata, technical data)
- DPD Section 2.3(g) (documents French tax law 10-year retention for subscription records)
- GDPR Policy Section 5 (covers Web Platform rights in intro paragraph; Section 5.3 is Supervisory Authority)
- GDPR Policy Section 11 (contact information with 5-business-day acknowledgment timeline)
- T&C Section 7.4 (directs users to GDPR Policy Section 5)
- T&C Section 16 (contact information with 5-business-day acknowledgment and one-month response timeline)
- Privacy Policy Section 8.1 (directs users to <legal@jikigai.com> for Web Platform rights)
