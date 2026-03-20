---
title: "legal: DPD Section 5 missing Web Platform data subject rights"
type: fix
date: 2026-03-20
semver: patch
---

# legal: DPD Section 5 missing Web Platform data subject rights

Closes #888

## Overview

The Data Protection Disclosure (DPD) Section 5 (Data Subject Rights) only covers Local Data (5.1) and Docs Site/GitHub Data (5.2). It omits a section for exercising rights against Jikigai for Web Platform account/workspace/subscription data, despite DPD Section 2.1b establishing Jikigai as controller for that data.

The T&C Section 7.4 and Privacy Policy Section 8.1 both direct Web Platform users to exercise GDPR rights via legal@jikigai.com and reference the GDPR Policy Section 5. The GDPR Policy covers Web Platform rights in its intro paragraph ("For data processed through the Web Platform (app.soleur.ai), these rights are exercisable directly against Jikigai by contacting legal@jikigai.com"). But the DPD -- the document specifically about the data processing relationship -- has no Web Platform rights section.

## Problem Statement

This is a GDPR transparency gap. The DPD is the document that describes how data subjects can exercise their rights in the context of the data processing relationship. Section 2.1b declares Jikigai as controller for Web Platform data. Section 5 should tell those data subjects how to exercise their rights. It currently does not.

## Proposed Solution

Add a new Section 5.3 "Web Platform Data" between the existing Section 5.2 and the `---` separator (before Section 6). The content should:

1. Enumerate GDPR rights (access, rectification, erasure, restriction, portability, objection) for Web Platform data
2. Specify the contact channel (legal@jikigai.com)
3. State the response timeline (one month per Article 12(3))
4. Reference the companion GDPR Policy Section 5 for full details
5. Note the data categories covered (account data, workspace data, subscription data -- consistent with Section 2.1b)

Apply identical content to both files, adjusting only link syntax (relative markdown links in `docs/legal/`, absolute HTML paths in `plugins/soleur/docs/pages/legal/`).

## Files to Modify

| File | Change |
|------|--------|
| `docs/legal/data-protection-disclosure.md` | Add Section 5.3 Web Platform Data, update "Last Updated" date |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Add Section 5.3 Web Platform Data (HTML-style links), update "Last Updated" date |

## Acceptance Criteria

- [ ] DPD Section 5.3 exists in both `docs/legal/data-protection-disclosure.md` and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] Section 5.3 enumerates all six GDPR rights (Articles 15-18, 20-21) for Web Platform data
- [ ] Section 5.3 specifies legal@jikigai.com as the contact channel
- [ ] Section 5.3 states the one-month response timeline (Article 12(3))
- [ ] Section 5.3 references GDPR Policy Section 5 for full details
- [ ] Section 5.3 data categories match Section 2.1b (account data, workspace data, subscription data)
- [ ] "Last Updated" date in both files reflects the change date
- [ ] Both files remain in sync (identical legal content, differing only in link format)
- [ ] No existing section numbering is broken (5.3 is new, no renumbering needed -- Section 6 follows)

## Test Scenarios

- Given the DPD is opened, when a Web Platform user reads Section 5, then they find clear instructions for exercising their data subject rights against Jikigai for Web Platform data
- Given a user reads both the DPD and the GDPR Policy, when they compare the rights sections, then the DPD Section 5.3 is consistent with GDPR Policy Section 5's Web Platform guidance
- Given a user reads both copies of the DPD (docs/legal/ and plugins/soleur/docs/pages/legal/), when they compare them, then the legal content is identical (links differ only in format)

## Non-Goals

- Do not modify the GDPR Policy Section 5 (it already covers Web Platform rights in the intro paragraph)
- Do not modify the Privacy Policy or T&C (they already correctly reference the GDPR Policy Section 5)
- Do not add a supervisory authority subsection to the DPD (that belongs in the GDPR Policy, which already has it at Section 5.3)
- Do not renumber existing DPD sections

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

## Context

- **Cross-document audit origin:** Found during #736 audit
- **Priority:** P1 -- GDPR gap in a data processing transparency document
- **Risk:** Low implementation risk (additive change only, no renumbering, no breaking changes)
- **Semver:** patch (legal document fix, no new features)

## References

- GitHub Issue: #888
- DPD Section 2.1b (establishes Jikigai as controller for Web Platform data)
- GDPR Policy Section 5 (covers Web Platform rights in intro paragraph)
- T&C Section 7.4 (directs users to GDPR Policy Section 5)
- Privacy Policy Section 8.1 (directs users to legal@jikigai.com for Web Platform rights)
