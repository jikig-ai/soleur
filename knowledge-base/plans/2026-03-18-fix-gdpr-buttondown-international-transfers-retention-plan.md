---
title: "fix: Add Buttondown to GDPR international transfers and data retention sections"
type: fix
date: 2026-03-18
---

# fix: Add Buttondown to GDPR international transfers and data retention sections

## Overview

The GDPR Policy (and its Eleventy docs site copy) mentions Buttondown in Sections 3.6 (Lawful Basis), 4.2 (Categories of Personal Data), and 10 (Article 30 Register), but omits it from two key sections:

1. **Section 6 (International Data Transfers)** -- does not list Buttondown as a US-based processor or document the transfer mechanism (SCCs).
2. **Section 8 (Data Retention)** -- does not specify newsletter subscriber data retention terms.

The Privacy Policy has the same omission in its Section 10 (International Data Transfers), though the Buttondown-specific subsection (5.3) already notes "US-based service" and "SCCs."

The DPD (Data Protection Disclosure) Section 6.2 uses generic language ("third-party transfers") that implicitly covers Buttondown but does not name it explicitly. This is lower priority since the DPD already describes the newsletter processing in Section 2.3(e) with Buttondown named.

## Problem Statement / Motivation

Issue #665 -- found by legal-compliance-auditor during PR #528 review. The information exists in the Article 30 register (Section 10) and other sections, but is missing from the dedicated International Transfers and Data Retention sections. This is a cross-reference consistency gap, not a missing disclosure -- the data is disclosed elsewhere in the same document. However, GDPR best practice requires each section to be self-contained so readers consulting only Section 6 or Section 8 get complete information.

## Proposed Solution

Add Buttondown entries to the relevant sections across all four affected files (two source files in `docs/legal/`, two Eleventy copies in `plugins/soleur/docs/pages/legal/`).

### Section 6 (International Data Transfers) -- GDPR Policy

Add a Buttondown bullet point after the GitHub bullet, following the same pattern:

```markdown
- **Buttondown (Newsletter):** Newsletter subscriber email addresses are processed by Buttondown, a US-based service. International data transfers are covered by **Standard Contractual Clauses (SCCs)** between Jikigai and Buttondown. See [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy).
```

### Section 8 (Data Retention) -- GDPR Policy

Add a new subsection 8.4 (renumbering existing 8.3 to remain after):

```markdown
### 8.4 Newsletter Subscriber Data

Newsletter subscriber email addresses are retained by Buttondown for as long as the subscriber remains subscribed. Upon unsubscription, the email address is removed from the active subscriber list. Buttondown may retain anonymized aggregate data (e.g., subscriber counts) after unsubscription.
```

The existing "8.3 Third-Party Retention" should be renumbered to 8.4, and the new newsletter section becomes 8.3 (or inserted as 8.3 with Third-Party becoming 8.4). The newsletter retention is more specific than the generic third-party section, so it should come before it.

### Section 10 (International Data Transfers) -- Privacy Policy

Add a Buttondown paragraph after the Anthropic paragraph:

```markdown
For newsletter subscriptions, subscriber email addresses are transmitted to Buttondown, a US-based service. International data transfers are covered by Standard Contractual Clauses (SCCs). See [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy) for details.
```

### "Last Updated" Dates

Update the "Last Updated" date across all modified files to reflect today's date and the change description.

## Acceptance Criteria

- [ ] GDPR Policy Section 6 lists Buttondown as a US-based processor with SCCs as the transfer mechanism (`docs/legal/gdpr-policy.md`)
- [ ] GDPR Policy Section 8 includes newsletter subscriber data retention terms (`docs/legal/gdpr-policy.md`)
- [ ] Privacy Policy Section 10 mentions Buttondown international transfers (`docs/legal/privacy-policy.md`)
- [ ] Eleventy copy of GDPR Policy matches source (`plugins/soleur/docs/pages/legal/gdpr-policy.md`)
- [ ] Eleventy copy of Privacy Policy matches source (`plugins/soleur/docs/pages/legal/privacy-policy.md`)
- [ ] "Last Updated" dates updated across all modified files (both header and hero section in Eleventy copies)
- [ ] No other sections need updating (Section 2.2, 3.6, 4.2, 5, 10 already reference Buttondown correctly)
- [ ] DPD is NOT modified (Buttondown is already adequately disclosed in Section 2.3(e); Section 6.2 generic language is intentional for a disclosure document)

## Test Scenarios

- Given the GDPR Policy, when a reader consults Section 6 only, then they find Buttondown listed as a US-based processor with SCCs
- Given the GDPR Policy, when a reader consults Section 8 only, then they find newsletter data retention terms (retained until unsubscription)
- Given the Privacy Policy, when a reader consults Section 10 only, then they find Buttondown international transfer information
- Given both `docs/legal/` and `plugins/soleur/docs/pages/legal/` copies, when comparing Section 6, 8, and 10 content, then the body text matches (frontmatter differs by design)

## Context

### Dual-Location Legal Docs Pattern

From learning `2026-02-21-gdpr-article-30-email-provider-documentation.md`: Legal documents exist in TWO locations:

- `docs/legal/*.md` -- source markdown with YAML frontmatter (`type`, `jurisdiction`, `generated-date`)
- `plugins/soleur/docs/pages/legal/*.md` -- Eleventy site copies with different frontmatter (`layout`, `permalink`, `description`)

Body content must match. Both must be updated in sync. This is the most common source of inconsistency in legal doc updates.

### Files to Modify

1. `docs/legal/gdpr-policy.md` -- Section 6, Section 8, "Last Updated" date
2. `plugins/soleur/docs/pages/legal/gdpr-policy.md` -- Section 6, Section 8, "Last Updated" date (both in frontmatter hero and body)
3. `docs/legal/privacy-policy.md` -- Section 10, "Last Updated" date
4. `plugins/soleur/docs/pages/legal/privacy-policy.md` -- Section 10, "Last Updated" date (both in hero and body)

### Files NOT Modified

- `docs/legal/data-processing-agreement.md` -- Buttondown already disclosed in Section 2.3(e); Section 6.2 generic language is by design
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- same reasoning

## References

- Issue: #665
- Found by: legal-compliance-auditor during PR #528 review
- Related learnings:
  - `knowledge-base/project/learnings/2026-02-21-gdpr-article-30-email-provider-documentation.md` (cross-document consistency pattern)
  - `knowledge-base/project/learnings/2026-02-26-cla-system-implementation-and-gdpr-compliance.md` (dual-location update pattern)
  - `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md` (newsletter legal update pattern)
