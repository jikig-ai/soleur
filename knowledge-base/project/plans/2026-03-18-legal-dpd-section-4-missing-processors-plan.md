---
title: "legal: DPD Section 4.2 missing GitHub Pages and Plausible from Docs Site Processors table"
type: fix
date: 2026-03-18
semver: patch
---

# legal: DPD Section 4.2 missing GitHub Pages and Plausible from Docs Site Processors table

## Overview

The DPD Section 4.2 ("Docs Site Processors") lists only Buttondown in its processor table, but Section 2.3(a) also discloses GitHub Pages and Plausible Analytics as processing activities where Jikigai acts as Controller on the Docs Site. A regulator reading Section 4 in isolation gets an incomplete picture of the Docs Site processing chain.

Additionally, the `docs/legal/data-processing-agreement.md` source copy is entirely out of sync -- it still has the old Section 4.1 "No Sub-processors" heading and Buttondown mixed into the user-initiated services table (Section 4.2), predating the March 18 restructuring from PR #686.

**Severity:** Low -- pre-existing gap. The March 18 restructuring (PR #686) made the omission more visible by creating a dedicated "Docs Site Processors" heading.

**Source:** Found by architecture-strategist and security-sentinel review agents during PR #686 review. Filed as GitHub issue #693.

## Problem Statement

**Two files need changes:**

1. **`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`** (Eleventy source, serves the live Docs Site)
   - Section 4.2 table (line 130-132) lists only Buttondown
   - Section 2.3(a) (line 87) already correctly describes GitHub Pages hosting and Plausible Analytics
   - Gap: GitHub Pages and Plausible are disclosed in Section 2.3(a) but not represented in the Section 4.2 processor table

2. **`docs/legal/data-processing-agreement.md`** (root source copy, used for GitHub rendering)
   - Still has the OLD structure: Section 4.1 "No Sub-processors" (contradicts Section 2.3(e))
   - Section 4.2 table mixes Buttondown with user-initiated services
   - Was NOT updated during PR #686's restructuring
   - Must be brought in sync with the Eleventy source

## Proposed Solution

### Option Analysis

The issue suggests two approaches:
1. Add GitHub Pages and Plausible rows to the Section 4.2 table
2. Add a clarifying note explaining why they are excluded

**Decision: Option 1 (add rows)** -- for two reasons:
- GitHub Pages collects IP addresses and browser metadata on Jikigai's behalf (it is a data processor under GDPR)
- While Plausible processes only anonymous aggregated data, it is still a named third-party service engaged by Jikigai for analytics -- listing it with a note about anonymous data is more transparent than omitting it
- Adding rows is consistent with the GDPR Policy's Article 30 register (Section 10.1) which already enumerates both as processing activities

### Changes to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`

Add two rows to the Section 4.2 table:

| Processor | Processing Activity | Data Processed | Legal Basis | Sub-processor List |
|-----------|-------------------|----------------|-------------|-------------------|
| GitHub Pages ([pages.github.com](https://pages.github.com)) | Docs Site hosting | IP addresses, browser user-agent strings, page request data | Legitimate interest (Article 6(1)(f)) | [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) |
| Plausible Analytics ([plausible.io](https://plausible.io)) | Privacy-respecting website analytics (cookie-free) | Aggregated anonymous data only: page URLs, referrer URLs, country, device type, browser type. IP addresses are not stored. | Legitimate interest (Article 6(1)(f)) | [Plausible DPA](https://plausible.io/dpa) |
| Buttondown ([buttondown.com](https://buttondown.com)) | Newsletter subscription management and email delivery | Email addresses of subscribers | Consent (Article 6(1)(a)) -- double opt-in | [Buttondown Sub-processors](https://buttondown.com/legal/dpa) |

Update the paragraph below the table: "This disclosure is consistent with Section 2.3(a) and Section 2.3(e)." (currently only references 2.3(e)).

Bump "Last Updated" date.

### Changes to `docs/legal/data-processing-agreement.md`

Synchronize the entire Section 4 with the Eleventy source:
- Replace Section 4.1 "No Sub-processors" with "Plugin Sub-processors" (scoped to Plugin only)
- Replace Section 4.2 "Third-Party Services Used by Users" with "Docs Site Processors" containing the full three-row table
- Add Section 4.3 "Third-Party Services Used by Users" with the user-initiated services table (without Buttondown, which moved to 4.2)
- Bump "Last Updated" date

### Cross-Document Consistency Check

| Document | Mentions GitHub Pages/Plausible as processors? | Status |
|----------|-----------------------------------------------|--------|
| Privacy Policy (Section 4.3, 5.2, 6.1) | Yes -- GitHub Pages hosting and Plausible analytics described | Consistent -- no change needed |
| GDPR Policy (Sections 2.1, 3.2, 4.2, 4.3, 10.1) | Yes -- Article 30 register enumerates both | Consistent -- no change needed |
| Cookie Policy | References Plausible as cookie-free | Consistent -- no change needed |
| DPD Section 2.3(a) | Yes -- both described | Consistent -- no change needed |
| DPD Section 4.2 table | **Only Buttondown** | **Fix target** |
| `docs/legal/` source copy | **Entirely out of sync** | **Fix target** |

## Acceptance Criteria

- [ ] DPD Section 4.2 table includes GitHub Pages row with processing activity, data processed, legal basis, and sub-processor list link (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
- [ ] DPD Section 4.2 table includes Plausible Analytics row with explicit note that data is anonymous/aggregated (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
- [ ] DPD Section 4.2 cross-reference updated to include Section 2.3(a) alongside 2.3(e)
- [ ] "Last Updated" date bumped on both DPD files
- [ ] `docs/legal/data-processing-agreement.md` Section 4 restructured to match Eleventy source (4.1 Plugin Sub-processors, 4.2 Docs Site Processors, 4.3 Third-Party Services)
- [ ] `docs/legal/data-processing-agreement.md` Section 4.2 table includes all three processor rows
- [ ] Buttondown removed from `docs/legal/` Section 4.3 user-initiated services table
- [ ] Cross-document consistency verified (Privacy Policy, GDPR Policy, Cookie Policy -- no changes needed)
- [ ] Markdownlint passes on both files

## Test Scenarios

- Given the updated DPD, when reading Section 4.2 table, then GitHub Pages, Plausible Analytics, and Buttondown are all listed as Docs Site processors
- Given the updated DPD Section 4.2, when cross-referencing with Section 2.3(a), then both sections describe the same processing activities for GitHub Pages and Plausible
- Given the `docs/legal/` source copy, when comparing Section 4 structure with the Eleventy source, then the section numbering and content are aligned
- Given the Plausible row in Section 4.2, when reading the "Data Processed" column, then it explicitly states data is anonymous and aggregated (not Personal Data)
- Given the GDPR Policy Article 30 register, when cross-referencing with DPD Section 4.2, then all Docs Site processing activities are represented in both documents

## GDPR Terminology Notes

- **GitHub Pages** acts as a **data processor** on Jikigai's behalf for Docs Site hosting. GitHub collects IP addresses and browser metadata as part of standard web server logging. Although GitHub's formal DPA applies only to paid plans, GitHub's standard terms acknowledge processor obligations for free-plan organizations.
- **Plausible Analytics** presents a nuanced case: it processes only anonymous aggregated data that arguably does not constitute Personal Data under Article 4(1). However, listing it in the processor table with this clarification is more transparent than omitting it. The ePrivacy Directive Article 5(3) exemption (no cookies/local storage) is already documented in the GDPR Policy.
- Buttondown remains a **data processor** (not sub-processor) since Jikigai is Controller for newsletter data.

## Context

### Files Modified

- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- add GitHub Pages and Plausible rows to Section 4.2 table
- `docs/legal/data-processing-agreement.md` -- sync Section 4 structure with Eleventy source, add all three processor rows

### Related Issues

- Closes #693
- Related: #686 (DPD restructuring that exposed this gap)
- Related: #664 (prior DPD sub-processor contradiction fix)

### Institutional Learnings Applied

- `2026-03-18-dpd-sub-processor-contradiction-fix.md`: When adding a new data processing relationship, audit ALL sections -- interdependent sections create contradictions when only one is updated
- `2026-02-21-cookie-free-analytics-legal-update-pattern.md`: Legal documents must be updated in lockstep with technical changes; the dual-file-location gotcha (Eleventy source + root copies) requires both to be updated
- `2026-02-20-dogfood-legal-agents-cross-document-consistency.md`: Cross-document consistency must be verified post-generation; budget for a generate-audit-fix-reaudit cycle
- Constitution rule (line 206): "Legal documents exist in two locations (`docs/legal/` for source markdown and `plugins/soleur/docs/pages/legal/` for docs site Eleventy templates) -- both must be updated in sync when legal content changes"

## References

- GitHub Issue #693: [DPD Section 4.2 missing GitHub Pages and Plausible](https://github.com/jikig-ai/soleur/issues/693)
- [GDPR Article 28 -- Processor](https://gdpr-info.eu/art-28-gdpr/)
- [GDPR Article 4(1) -- Definition of Personal Data](https://gdpr-info.eu/art-4-gdpr/)
- [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- [Plausible DPA](https://plausible.io/dpa)
