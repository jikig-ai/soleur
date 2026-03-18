---
title: "fix: Add Buttondown to GDPR international transfers and data retention sections"
type: fix
date: 2026-03-18
---

# fix: Add Buttondown to GDPR international transfers and data retention sections

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 3 (Proposed Solution, Acceptance Criteria, Context)
**Research conducted:** Buttondown DPA, subprocessor list, GDPR compliance page, EU-US transfer mechanism analysis

### Key Improvements
1. Verified SCCs as the correct transfer mechanism (Buttondown's DPA confirms Module 2 SCCs per EU Implementing Decision 2021/914; Buttondown is NOT certified under EU-US Data Privacy Framework)
2. Corrected proposed Section 6 text to reference Buttondown's DPA (not just privacy policy) as the authoritative transfer document
3. Added DPA-sourced data retention language: "at controller's option, delete or return all Personal Data" upon termination
4. Added verification step: grep for "Buttondown" consistency across all legal docs post-edit

### New Considerations Discovered
- Buttondown's DPA references SCCs Module 2 (Controller to Processor) with Option 2 for sub-processor authorization -- consistent with existing Privacy Policy Section 5.3 claim
- Buttondown hosts on Heroku (Salesforce) and AWS in the United States; all 12 listed subprocessors are US-based
- Buttondown is NOT listed on the EU-US Data Privacy Framework participant list -- SCCs are the sole transfer mechanism (do NOT reference DPF)
- The Privacy Policy Section 5.3 already correctly states "SCCs" -- the GDPR Policy Section 6 addition should be consistent with this

---

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

Add a Buttondown bullet point after the GitHub bullet, following the same pattern as the existing Anthropic and GitHub entries. The text references SCCs as the transfer mechanism, consistent with Buttondown's DPA (Module 2, Controller to Processor, per EU Implementing Decision 2021/914):

```markdown
- **Buttondown (Newsletter):** Newsletter subscriber email addresses are processed by Buttondown, a US-based service hosted on infrastructure in the United States. International data transfers are governed by **Standard Contractual Clauses (SCCs)** (Module 2, Controller to Processor) per Buttondown's [Data Processing Agreement](https://buttondown.com/legal/data-processing-agreement). See also [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy).
```

### Research Insights -- Section 6

**Verified transfer mechanism:** Buttondown's DPA (fetched 2026-03-18) confirms: "the parties agree that the transfer shall be governed by the Standard Contractual Clauses issued by the European Commission pursuant to Implementing Decision (EU) 2021/914." This implements Module 2 (Controller to Processor), Option 2 for sub-processor authorization.

**Why NOT reference DPF:** Buttondown is not certified under the EU-US Data Privacy Framework. Unlike GitHub (which maintains DPF certification as the primary mechanism with SCCs as supplementary), Buttondown relies solely on SCCs. The plan text correctly avoids DPF references.

**UK/Swiss coverage:** Buttondown's DPA also includes the UK Addendum and Swiss FADP modifications. These are not needed in Soleur's GDPR Policy (which targets EU/EEA), but are worth noting for completeness.

**Consistency check:** The existing Privacy Policy Section 5.3 states "Buttondown is a US-based service. International data transfers are covered by Standard Contractual Clauses (SCCs)." The new GDPR Policy Section 6 text is consistent with this.

### Section 8 (Data Retention) -- GDPR Policy

Add a new subsection 8.3 "Newsletter Subscriber Data" before the existing 8.3 "Third-Party Retention" (which becomes 8.4). The newsletter retention is more specific than the generic third-party section, so it comes first:

```markdown
### 8.3 Newsletter Subscriber Data

Newsletter subscriber email addresses are retained by Buttondown for as long as the subscriber remains subscribed. Upon unsubscription, the email address is removed from the active subscriber list. Buttondown may retain anonymized aggregate data (e.g., subscriber counts) after unsubscription. Upon termination of the service relationship, Buttondown will, at Jikigai's option, delete or return all personal data in accordance with Buttondown's Data Processing Agreement.
```

### Research Insights -- Section 8

**DPA deletion terms:** Buttondown's DPA states: "Upon termination, the Data Processor shall, at the Data Controller's option, delete or return all Personal Data." This is standard GDPR Article 28(3)(g) language and should be reflected in the retention section.

**No fixed retention period:** Buttondown's privacy policy states data is kept "for as long as it is necessary for the purposes set out in this privacy policy, unless a longer retention period is required or permitted by law" and "no purpose in this policy will require us keeping your personal information for longer than the period of time in which users have an account with us." This aligns with the "until unsubscription" framing.

**Consistency with Privacy Policy Section 7:** The Privacy Policy already states "Your email address is retained by Buttondown for as long as you remain subscribed. Upon unsubscription, your email is removed from the active subscriber list. Buttondown may retain anonymized aggregate data (e.g., subscriber counts) after unsubscription." The GDPR Policy Section 8.3 text should mirror this language closely, with the addition of the DPA termination clause.

### Section 10 (International Data Transfers) -- Privacy Policy

Add a Buttondown paragraph after the Anthropic paragraph:

```markdown
For newsletter subscriptions, subscriber email addresses are transmitted to Buttondown, a US-based service. International data transfers are governed by Standard Contractual Clauses (SCCs) per Buttondown's [Data Processing Agreement](https://buttondown.com/legal/data-processing-agreement). See [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy) for details.
```

### "Last Updated" Dates

Update the "Last Updated" date across all modified files to "March 18, 2026 (Buttondown international transfers and data retention)" to reflect today's date and the change description.

## Acceptance Criteria

- [x] GDPR Policy Section 6 lists Buttondown as a US-based processor with SCCs (Module 2) as the transfer mechanism, linking to Buttondown's DPA (`docs/legal/gdpr-policy.md`)
- [x] GDPR Policy Section 8 includes newsletter subscriber data retention terms as new subsection 8.3 (`docs/legal/gdpr-policy.md`)
- [x] GDPR Policy Section 8 existing "Third-Party Retention" renumbered from 8.3 to 8.4 (`docs/legal/gdpr-policy.md`)
- [x] Privacy Policy Section 10 mentions Buttondown international transfers with DPA link (`docs/legal/privacy-policy.md`)
- [x] Eleventy copy of GDPR Policy body content matches source (`plugins/soleur/docs/pages/legal/gdpr-policy.md`)
- [x] Eleventy copy of Privacy Policy body content matches source (`plugins/soleur/docs/pages/legal/privacy-policy.md`)
- [x] "Last Updated" dates updated across all modified files (both header and hero section in Eleventy copies)
- [x] No other sections need updating (Section 2.2, 3.6, 4.2, 5, 10 already reference Buttondown correctly)
- [x] DPD is NOT modified (Buttondown is already adequately disclosed in Section 2.3(e); Section 6.2 generic language is intentional for a disclosure document)
- [x] Grep verification: `grep -r "Buttondown" docs/legal/ plugins/soleur/docs/pages/legal/` shows consistent references across all locations
- [x] Links to Buttondown DPA (`https://buttondown.com/legal/data-processing-agreement`) are valid (verified 2026-03-18)
- [x] No references to EU-US Data Privacy Framework for Buttondown (Buttondown is not DPF-certified)

## Test Scenarios

- Given the GDPR Policy, when a reader consults Section 6 only, then they find Buttondown listed as a US-based processor with SCCs (Module 2) and a link to Buttondown's DPA
- Given the GDPR Policy, when a reader consults Section 8 only, then they find newsletter data retention terms (retained until unsubscription, with DPA termination clause)
- Given the GDPR Policy Section 8, when checking subsection numbering, then 8.3 is "Newsletter Subscriber Data" and 8.4 is "Third-Party Retention"
- Given the Privacy Policy, when a reader consults Section 10 only, then they find Buttondown international transfer information with DPA link
- Given both `docs/legal/` and `plugins/soleur/docs/pages/legal/` copies, when comparing Section 6, 8, and 10 content, then the body text matches (frontmatter differs by design)
- Given a grep for "Buttondown" across all legal docs, when checking consistency, then all references use consistent naming and link patterns

## Context

### Dual-Location Legal Docs Pattern

From learning `2026-02-21-gdpr-article-30-email-provider-documentation.md`: Legal documents exist in TWO locations:

- `docs/legal/*.md` -- source markdown with YAML frontmatter (`type`, `jurisdiction`, `generated-date`)
- `plugins/soleur/docs/pages/legal/*.md` -- Eleventy site copies with different frontmatter (`layout`, `permalink`, `description`)

Body content must match. Both must be updated in sync. This is the most common source of inconsistency in legal doc updates.

### Cross-Reference Link Format Differences

From learning `2026-02-26-cla-system-implementation-and-gdpr-compliance.md`: The two locations use different link formats:

- `docs/legal/`: Relative markdown links (e.g., `[Privacy Policy](privacy-policy.md)`)
- `plugins/soleur/docs/pages/legal/`: Absolute HTML links (e.g., `[Privacy Policy](/pages/legal/privacy-policy.html)`)

External links (like Buttondown URLs) are identical in both locations. Only internal cross-references differ.

### Buttondown's Data Processing Infrastructure

From research (2026-03-18):

- **Hosting:** Heroku (Salesforce) and Amazon Web Services, both US-based, SOC 2 Type II and ISO 27001 certified
- **Transfer mechanism:** Standard Contractual Clauses, Module 2 (Controller to Processor), per EU Implementing Decision (EU) 2021/914
- **NOT DPF-certified:** Unlike GitHub, Buttondown does not participate in the EU-US Data Privacy Framework
- **Subprocessors:** 12 US-based subprocessors including AWS, Heroku, Mailgun, Postmark, Stripe, Cloudflare, Sentry
- **DPA URL:** `https://buttondown.com/legal/data-processing-agreement` (verified active 2026-03-18)
- **Security:** Encryption in transit (TLS 1.2+) and at rest (AES-256), role-based access control with MFA

### Institutional Learnings Applied

1. **Cross-document consistency** (2026-02-21): When naming a new processor, check ALL sections that reference it. The legal-compliance-auditor originally caught this gap.
2. **Dual-location update** (2026-02-26): Both `docs/legal/` and `plugins/soleur/docs/pages/legal/` must be updated in sync. Body content must match; frontmatter differs by design.
3. **Grep verification** (2026-03-10): After all edits, run grep verification for consistency. Patterns: `"Buttondown"`, `"newsletter"`, `"SCCs"` across `**/legal/*.md`.
4. **Entity attribution** (2026-03-02): Use "Jikigai" (not "Soleur") in legal contexts. The Section 6 text correctly says "between Jikigai and Buttondown."

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
  - `knowledge-base/project/learnings/2026-02-20-dogfood-legal-agents-cross-document-consistency.md` (generate-audit-fix-reaudit cycle)
  - `knowledge-base/project/learnings/2026-03-02-legal-doc-bulk-consistency-fix-pattern.md` (entity attribution and grep verification)
- External sources:
  - [Buttondown GDPR & EU Compliance](https://buttondown.com/legal/gdpr-eu-compliance)
  - [Buttondown Data Processing Agreement](https://buttondown.com/legal/data-processing-agreement)
  - [Buttondown Subprocessors](https://buttondown.com/legal/subprocessors)
  - [Buttondown Privacy Policy](https://buttondown.com/legal/privacy)
