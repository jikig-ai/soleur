---
title: "fix: Privacy Policy section cross-reference 5.4 should be 5.3"
type: fix
date: 2026-03-18
deepened: 2026-03-18
---

# fix: Privacy Policy section cross-reference 5.4 should be 5.3

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 2 (Context, Acceptance Criteria)
**Research approach:** Targeted verification -- confirmed fix correctness, checked for similar issues across docs

### Key Findings
1. Only one `See Section` cross-reference exists in the entire privacy policy -- the broken one on line 101
2. No other files in `plugins/soleur/docs/` reference "Section 5.4" -- blast radius is zero
3. Section numbering is stable (5.1 Anthropic, 5.2 GitHub, 5.3 Buttondown, 5.4 Other) -- no renumbering needed

## Overview

Line 101 of `plugins/soleur/docs/pages/legal/privacy-policy.md` contains a wrong section cross-reference. The Newsletter Subscription Data section (4.6) refers readers to "Section 5.4 for details" about Buttondown as a third-party processor, but Buttondown is documented in **Section 5.3** ("Buttondown (Newsletter)"). Section 5.4 is "Other Third-Party Integrations", which is unrelated to Buttondown.

## Acceptance Criteria

- [x] Line 101 of `plugins/soleur/docs/pages/legal/privacy-policy.md` reads `See Section 5.3 for details.` instead of `See Section 5.4 for details.`
- [x] No other content in the file is changed
- [x] The Eleventy docs site builds successfully after the change

## Test Scenarios

- Given the privacy policy markdown, when reading the Newsletter Subscription Data bullet about third-party processor, then it references Section 5.3 (Buttondown)
- Given the updated file, when building the Eleventy docs site, then the build completes without errors

## Context

- **File:** `plugins/soleur/docs/pages/legal/privacy-policy.md`
- **Line:** 101
- **Current text:** `- **Third-party processor:** Buttondown acts as a data processor. See Section 5.4 for details.`
- **Corrected text:** `- **Third-party processor:** Buttondown acts as a data processor. See Section 5.3 for details.`
- **Section 5.3:** Buttondown (Newsletter) -- the correct target (line 120)
- **Section 5.4:** Other Third-Party Integrations -- incorrect target (line 128)

### Verification Details

Section 5 subsection numbering confirmed via `grep -n "^### 5\."`:

| Line | Section | Heading |
|------|---------|---------|
| 105 | 5.1 | Anthropic Claude API |
| 114 | 5.2 | GitHub |
| 120 | 5.3 | Buttondown (Newsletter) |
| 128 | 5.4 | Other Third-Party Integrations |

The cross-reference on line 101 is in section 4.6 (Newsletter Subscription Data) and says "Buttondown acts as a data processor. See Section 5.4 for details." -- but 5.4 is the generic catch-all, not the Buttondown-specific section. The correct target is 5.3.

**Scope check:** `grep "See Section" privacy-policy.md` returns only line 101. No other cross-references to audit.

**Blast radius check:** `grep "Section 5.4" plugins/soleur/docs/` returns only line 101. No other docs reference this section number.

## References

- Related issue: #694
