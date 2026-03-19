---
title: "legal: DPD Section 4.2 missing GitHub Pages and Plausible from Docs Site Processors table"
type: fix
date: 2026-03-18
semver: patch
---

# legal: DPD Section 4.2 missing GitHub Pages and Plausible from Docs Site Processors table

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 3 (Proposed Solution, GDPR Terminology Notes, Acceptance Criteria)
**Research sources:** Plausible DPA (plausible.io/dpa), Plausible Privacy Policy (plausible.io/privacy), GitHub Pages documentation (docs.github.com), institutional learnings (5 files), legal-compliance-auditor agent spec

### Key Improvements
1. Verified Plausible's DPA confirms processor status and EU-only hosting (Hetzner Germany, BunnyWay Slovenia) -- strengthens the case for listing in processor table
2. Verified GitHub Pages documentation confirms IP address logging for all visitors -- confirms processor classification
3. Added grep verification step from institutional learnings to catch any remaining blanket statements
4. Added Plausible sub-processor details (BunnyWay, Hetzner) for completeness in the "Sub-processor List" column link text

### New Considerations Discovered
- The Plausible DPA explicitly states Plausible is a "data processor" under GDPR despite processing only anonymous data -- this removes the ambiguity noted in the original plan about whether listing Plausible is strictly necessary (it is, per their own DPA)
- Plausible hashes IP addresses with salts rotated every 24 hours -- this detail should be reflected in the "Data Processed" column to be precise about what "IP addresses are not stored" means

## Overview

The DPD Section 4.2 ("Docs Site Processors") lists only Buttondown in its processor table, but Section 2.3(a) also discloses GitHub Pages and Plausible Analytics as processing activities where Jikigai acts as Controller on the Docs Site. A regulator reading Section 4 in isolation gets an incomplete picture of the Docs Site processing chain.

Additionally, the `docs/legal/data-protection-disclosure.md` source copy is entirely out of sync -- it still has the old Section 4.1 "No Sub-processors" heading and Buttondown mixed into the user-initiated services table (Section 4.2), predating the March 18 restructuring from PR #686.

**Severity:** Low -- pre-existing gap. The March 18 restructuring (PR #686) made the omission more visible by creating a dedicated "Docs Site Processors" heading.

**Source:** Found by architecture-strategist and security-sentinel review agents during PR #686 review. Filed as GitHub issue #693.

## Problem Statement

**Two files need changes:**

1. **`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`** (Eleventy source, serves the live Docs Site)
   - Section 4.2 table (line 130-132) lists only Buttondown
   - Section 2.3(a) (line 87) already correctly describes GitHub Pages hosting and Plausible Analytics
   - Gap: GitHub Pages and Plausible are disclosed in Section 2.3(a) but not represented in the Section 4.2 processor table

2. **`docs/legal/data-protection-disclosure.md`** (root source copy, used for GitHub rendering)
   - Still has the OLD structure: Section 4.1 "No Sub-processors" (contradicts Section 2.3(e))
   - Section 4.2 table mixes Buttondown with user-initiated services
   - Was NOT updated during PR #686's restructuring
   - Must be brought in sync with the Eleventy source

## Proposed Solution

### Option Analysis

The issue suggests two approaches:
1. Add GitHub Pages and Plausible rows to the Section 4.2 table
2. Add a clarifying note explaining why they are excluded

**Decision: Option 1 (add rows)** -- for three reasons:
- GitHub Pages collects IP addresses and browser metadata on Jikigai's behalf (it is a data processor under GDPR). GitHub Pages documentation confirms: "the visitor's IP address is logged and stored for security purposes, regardless of whether the visitor has signed into GitHub or not."
- Plausible's own DPA (plausible.io/dpa) explicitly states: "The parties agree that customer is the data controller and that Plausible Analytics is its data processor." This removes the ambiguity about whether Plausible qualifies as a processor -- Plausible itself asserts processor status. Although it processes only anonymous aggregated data, listing it with a note about anonymous data is more transparent than omitting it.
- Adding rows is consistent with the GDPR Policy's Article 30 register (Section 10.1) which already enumerates both as processing activities

### Changes to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`

Add two rows to the Section 4.2 table:

| Processor | Processing Activity | Data Processed | Legal Basis | Sub-processor List |
|-----------|-------------------|----------------|-------------|-------------------|
| GitHub Pages ([pages.github.com](https://pages.github.com)) | Docs Site hosting | IP addresses, browser user-agent strings, page request data | Legitimate interest (Article 6(1)(f)) | [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) |
| Plausible Analytics ([plausible.io](https://plausible.io)) | Privacy-respecting website analytics (cookie-free, EU-hosted) | Aggregated anonymous data only: page URLs, referrer URLs, country, device type, browser type. IP addresses are hashed for daily unique visitor counts and never stored (salts rotated every 24 hours). | Legitimate interest (Article 6(1)(f)) | [Plausible DPA](https://plausible.io/dpa) |
| Buttondown ([buttondown.com](https://buttondown.com)) | Newsletter subscription management and email delivery | Email addresses of subscribers | Consent (Article 6(1)(a)) -- double opt-in | [Buttondown Sub-processors](https://buttondown.com/legal/dpa) |

Update the paragraph below the table: "This disclosure is consistent with Section 2.3(a) and Section 2.3(e)." (currently only references 2.3(e)).

Bump "Last Updated" date.

### Changes to `docs/legal/data-protection-disclosure.md`

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

- [x] DPD Section 4.2 table includes GitHub Pages row with processing activity, data processed, legal basis, and sub-processor list link (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
- [x] DPD Section 4.2 table includes Plausible Analytics row with explicit note that data is anonymous/aggregated (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
- [x] DPD Section 4.2 cross-reference updated to include Section 2.3(a) alongside 2.3(e)
- [x] "Last Updated" date bumped on both DPD files
- [x] `docs/legal/data-protection-disclosure.md` Section 4 restructured to match Eleventy source (4.1 Plugin Sub-processors, 4.2 Docs Site Processors, 4.3 Third-Party Services)
- [x] `docs/legal/data-protection-disclosure.md` Section 4.2 table includes all three processor rows
- [x] Buttondown removed from `docs/legal/` Section 4.3 user-initiated services table
- [x] Cross-document consistency verified (Privacy Policy, GDPR Policy, Cookie Policy -- no changes needed)
- [x] Grep verification: no unscoped "No Sub-processors" statements remain across legal docs
- [x] Grep verification: `docs/legal/` source copy no longer contains old Section 4.1 "No Sub-processors" heading
- [x] Markdownlint passes on both files (pre-existing MD034 bare-email warnings in Section 12 unrelated to this change)

## Test Scenarios

- Given the updated DPD, when reading Section 4.2 table, then GitHub Pages, Plausible Analytics, and Buttondown are all listed as Docs Site processors
- Given the updated DPD Section 4.2, when cross-referencing with Section 2.3(a), then both sections describe the same processing activities for GitHub Pages and Plausible
- Given the `docs/legal/` source copy, when comparing Section 4 structure with the Eleventy source, then the section numbering and content are aligned
- Given the Plausible row in Section 4.2, when reading the "Data Processed" column, then it explicitly states data is anonymous and aggregated (not Personal Data)
- Given the GDPR Policy Article 30 register, when cross-referencing with DPD Section 4.2, then all Docs Site processing activities are represented in both documents

## GDPR Terminology Notes

- **GitHub Pages** acts as a **data processor** on Jikigai's behalf for Docs Site hosting. GitHub's documentation explicitly states: "the visitor's IP address is logged and stored for security purposes, regardless of whether the visitor has signed into GitHub or not." Although GitHub's formal DPA applies only to paid plans (Enterprise Cloud, Teams), GitHub's standard terms acknowledge processor obligations for free-plan organizations and GitHub maintains EU-US Data Privacy Framework certification and Standard Contractual Clauses. The GDPR Policy Section 2.2 already correctly describes this relationship.
- **Plausible Analytics** is explicitly a **data processor** per its own DPA (plausible.io/dpa): "The parties agree that customer is the data controller and that Plausible Analytics is its data processor." All site data is hosted exclusively in the EU on EU-owned infrastructure (Hetzner Germany for servers, BunnyWay Slovenia for CDN) and never leaves the EU. IP addresses are received in HTTP requests but immediately hashed for daily unique visitor counts -- raw IP addresses and User-Agent strings are never stored in logs, databases, or anywhere on disk. Hash salts are deleted every 24 hours, making visitor re-identification impossible. The ePrivacy Directive Article 5(3) exemption (no cookies/local storage) is already documented in the GDPR Policy.
- **Buttondown** remains a **data processor** (not sub-processor) since Jikigai is Controller for newsletter data.

### Research Insights

**Processor table ordering:** List processors in order of data sensitivity (least to most personal data): GitHub Pages (IP addresses -- logged but standard web hosting), Plausible Analytics (anonymous aggregated data only), Buttondown (email addresses -- directly identifying PII). This ordering makes the table easier to scan for regulators assessing data protection risk.

**Plausible's "Sub-processor List" column:** The Plausible DPA at plausible.io/dpa is the correct link. It discloses two sub-processors that access site data: BunnyWay d.o.o. (Slovenian, CDN) and Hetzner Online GmbH (German, servers). Additional sub-processors listed in plausible.io/privacy handle account management only (Paddle for payments, Postmark for emails) and do not access site visitor data.

**GitHub Pages "Sub-processor List" column:** GitHub does not publish a standalone sub-processor list for Pages. The GitHub Privacy Statement (docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) is the appropriate reference, consistent with how the GDPR Policy Section 2.2 already references it.

**Post-edit grep verification** (from learning `2026-03-10-first-pii-collection-legal-update-pattern.md`): After applying edits, run grep verification across all legal docs to confirm no blanket statements were missed:
- `grep -r "no Sub-processors" docs/legal/ plugins/soleur/docs/pages/legal/` -- should return zero matches after fix
- `grep -r "No Sub-processors" docs/legal/ plugins/soleur/docs/pages/legal/` -- should return zero matches after fix
- `grep -r "no.*sub-processor" docs/legal/ plugins/soleur/docs/pages/legal/` -- verify only scoped "no Plugin-level Sub-processors" remains

## Edge Cases and Considerations

**Plausible as "processor" vs. "not processing Personal Data":** There is a tension: Plausible's own DPA classifies them as a data processor, yet the data they process is arguably not Personal Data under Article 4(1) since IP addresses are never stored. The plan resolves this by listing Plausible in the processor table (consistent with their self-classification and with transparency principles) while explicitly noting in the "Data Processed" column that data is anonymous and aggregated. This is the conservative, regulator-friendly approach.

**GitHub Pages DPA availability on free plans:** GitHub's formal Data Protection Agreement applies only to paid plans (Enterprise Cloud, Teams). Jikigai's free-plan organization is covered by GitHub's standard Terms of Service, under which GitHub acknowledges processor obligations and maintains EU-US Data Privacy Framework certification and SCCs. The "Sub-processor List" column should link to the GitHub Privacy Statement rather than a DPA that Jikigai cannot access. The GDPR Policy Section 2.2 already documents this limitation -- no change needed there.

**Frontmatter differences between file locations** (from learning `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md`):
- `docs/legal/`: Has `type`, `jurisdiction`, `generated-date` YAML frontmatter; uses `.md` relative links
- `plugins/soleur/docs/pages/legal/`: Has `layout`, `permalink`, `description` YAML frontmatter; uses `/pages/legal/*.html` absolute links; wrapped in `<section>` HTML tags
- Body content (Section 4) should be identical in both files; only frontmatter and link format differ

**Table column width in markdown rendering:** The "Data Processed" column for Plausible is longer than the others due to the detailed anonymous-data note. This may render poorly in narrow GitHub markdown views. Keep the note concise but complete -- readability in the Docs Site (which uses wider prose layout) takes precedence over raw markdown rendering.

## Context

### Files Modified

- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- add GitHub Pages and Plausible rows to Section 4.2 table
- `docs/legal/data-protection-disclosure.md` -- sync Section 4 structure with Eleventy source, add all three processor rows

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
