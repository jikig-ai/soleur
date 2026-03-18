---
title: "fix: Privacy Policy section cross-reference 5.4 should be 5.3"
type: fix
date: 2026-03-18
---

# fix: Privacy Policy section cross-reference 5.4 should be 5.3

## Overview

Line 101 of `plugins/soleur/docs/pages/legal/privacy-policy.md` contains a wrong section cross-reference. The Newsletter Subscription Data section (4.6) refers readers to "Section 5.4 for details" about Buttondown as a third-party processor, but Buttondown is documented in **Section 5.3** ("Buttondown (Newsletter)"). Section 5.4 is "Other Third-Party Integrations", which is unrelated to Buttondown.

## Acceptance Criteria

- [ ] Line 101 of `plugins/soleur/docs/pages/legal/privacy-policy.md` reads `See Section 5.3 for details.` instead of `See Section 5.4 for details.`
- [ ] No other content in the file is changed
- [ ] The Eleventy docs site builds successfully after the change

## Test Scenarios

- Given the privacy policy markdown, when reading the Newsletter Subscription Data bullet about third-party processor, then it references Section 5.3 (Buttondown)
- Given the updated file, when building the Eleventy docs site, then the build completes without errors

## Context

- **File:** `plugins/soleur/docs/pages/legal/privacy-policy.md`
- **Line:** 101
- **Current text:** `- **Third-party processor:** Buttondown acts as a data processor. See Section 5.4 for details.`
- **Corrected text:** `- **Third-party processor:** Buttondown acts as a data processor. See Section 5.3 for details.`
- **Section 5.3:** Buttondown (Newsletter) -- the correct target
- **Section 5.4:** Other Third-Party Integrations -- incorrect target

## References

- Related issue: #694
