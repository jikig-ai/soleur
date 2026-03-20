---
title: "chore: add Web Platform to DPD Section 7.2 breach notification scope"
type: fix
date: 2026-03-20
---

# chore: add Web Platform to DPD Section 7.2 breach notification scope

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** Problem Statement, Proposed Solution (Edit 2 refined), SpecFlow Analysis, Acceptance Criteria
**Research sources:** GDPR Articles 33-34, EDPB Guidelines 9/2022 on breach notification, 3 institutional learnings, cross-document grep analysis of all legal docs

### Key Improvements

1. **Edit 2 wording refined:** Original proposed text could be read as limiting email notification to Web Platform-only breaches. Revised wording preserves the existing "direct communication" phrasing and adds email as a concrete channel, avoiding regression in non-Web-Platform breach scenarios.
2. **Cross-document consistency verified:** GDPR Policy Section 11.2 already correctly enumerates Web Platform breach scenarios (Supabase, Hetzner, Proton, GitHub) and mentions notifying "affected users." No GDPR Policy changes needed -- the DPD is the only gap.
3. **Article 33 vs 34 distinction noted:** Section 7.2(a)'s 72-hour commitment conflates the Article 33 supervisory authority timeline with Article 34 data subject notification (which has no fixed deadline). This is a pre-existing issue out of scope for #907 but noted for future audit.

### New Considerations Discovered

- Privacy Policy has no breach notification section at all (it defers to the DPD and GDPR Policy). No action needed for this PR.
- Section 8.2(b) (Future Changes notification) also lists only "GitHub repository, Docs Site, and release notes" without mentioning the Web Platform as a notification channel. This is a separate consistency gap -- filed as a note for the cross-document audit (#888) but out of scope here.

---

## Overview

DPD Section 7.2 (Platform Breaches) lists "the Soleur GitHub repository, Docs Site, or distribution channels" as covered platforms but omits the Web Platform (app.soleur.ai). The Web Platform processes the highest-sensitivity user data (email addresses, hashed passwords, auth tokens, encrypted API keys, subscription metadata) and would be the highest-impact breach scenario. Explicit mention removes ambiguity about whether "distribution channels" covers it.

Found during cross-document audit for #888.

## Problem Statement

Section 7.2 was written before the Web Platform existed. When cloud features were added (Sections 2.1b, 4.2, 5.3, 6.4, 8, 9.2, 10.3), the breach notification section was not updated to include the new platform. While "distribution channels" arguably covers the Web Platform, GDPR Article 34 transparency obligations favor explicit enumeration over implicit inclusion.

Additionally, Section 7.2(b) specifies notification via "the Soleur GitHub repository and, where possible, through direct communication" but does not mention email notification to Web Platform users -- despite the Web Platform collecting email addresses for exactly this kind of communication.

### Research Insights

**GDPR Article 34 Requirements:**
- Article 34 requires communication "in clear and plain language" describing the nature of the breach, likely consequences, and measures taken. The DPD Section 7.2(c) already satisfies this content requirement.
- Article 34(3)(c) permits "public communication" as a fallback only when "individual communication would involve disproportionate effort." Since the Web Platform has users' email addresses on file, individual email notification is the expected primary channel -- public GitHub repository notice alone would not satisfy Article 34 for Web Platform users.
- The EDPB Guidelines 9/2022 (Section 73) recommend that controllers use "direct communication channels such as email, SMS, or postal mail" and reserve website notices for situations where contact details are unavailable.

**Cross-Document Verification:**
- GDPR Policy Section 11.1 correctly separates Article 33 (CNIL, 72h) from Article 34 (data subjects, "without undue delay") obligations.
- GDPR Policy Section 11.2 already lists Web Platform-specific breach scenarios (Supabase DB access, Hetzner server compromise, Proton AG access, GitHub org compromise).
- Privacy Policy contains no breach notification section (defers entirely to DPD and GDPR Policy).
- No other legal document references "distribution channels" -- the DPD is the sole source for this platform enumeration.

## Proposed Solution

Two targeted text edits to Section 7.2, applied to both the root copy and the Eleventy copy:

### Edit 1: Section 7.2 platform list (line 237 in root, line 246 in Eleventy)

**Current:**
> In the unlikely event that a breach affects the Soleur GitHub repository, Docs Site, or distribution channels:

**Proposed:**
> In the unlikely event that a breach affects the Soleur GitHub repository, Docs Site, Web Platform (app.soleur.ai), or distribution channels:

### Edit 2: Section 7.2(b) notification channels (line 240 in root, line 249 in Eleventy)

**Current:**
> **(b)** Notification will be provided via the [Soleur GitHub repository](https://github.com/jikig-ai/soleur) and, where possible, through direct communication.

**Proposed:**
> **(b)** Notification will be provided via the [Soleur GitHub repository](https://github.com/jikig-ai/soleur) and, where possible, through direct communication (including email notification for Web Platform users with an account on file).

**Rationale for Edit 2:** The Web Platform collects user email addresses (Section 2.3(f)). For a breach affecting user PII, email notification is a concrete obligation under GDPR Article 34, not merely "where possible." The parenthetical addition makes the email channel explicit for Web Platform users while preserving the existing "direct communication" phrasing for non-Web-Platform breaches (GitHub repository compromise, Docs Site, distribution channels). This avoids narrowing the notification commitment for platform-only scenarios.

### Research Insights

**Best Practices:**
- EDPB Guidelines 9/2022 recommend specifying notification channels in advance rather than leaving them open-ended. Pre-committed channels build trust and reduce response-time ambiguity during an actual incident.
- Industry pattern (Stripe, GitHub, Basecamp): breach notification policies enumerate concrete channels (email, in-app banner, status page) rather than using vague "where possible" language.

**Why parenthetical over separate clause:**
- A separate clause like "For Web Platform users, notification will also be sent via email" creates a structural implication that other platforms do *not* get email -- which may not be the intent. The parenthetical clarifies the email channel as an example of "direct communication" that applies specifically when an email is on file.

## Files to Modify

| File | Role |
|------|------|
| `docs/legal/data-protection-disclosure.md` | Root copy (GitHub rendering) |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Eleventy copy (docs site build) |

Both files must receive identical content changes. The Eleventy copy has different frontmatter and link formats but the Section 7.2 body text is identical.

## SpecFlow Analysis

**Edge cases considered:**

1. **Breach affecting only one platform:** The "or" conjunction in the platform list correctly handles partial breaches. No structural change needed.
2. **User without email (deleted account):** Section 10.3 covers account deletion and data removal. Post-deletion breach notification falls to the GitHub repository channel. The parenthetical "with an account on file" scopes email notification to active accounts only.
3. **"Last Updated" date:** Must be updated in both files to reflect this change.
4. **Breach affecting a sub-processor (Supabase, Stripe, Hetzner):** The platform list says "Web Platform" -- a Supabase breach that exposes Web Platform user data is a Web Platform breach for notification purposes. The GDPR Policy Section 11.2 already enumerates these sub-processor scenarios. No additional DPD language needed.
5. **Consistency with GDPR Policy Section 11:** The GDPR Policy uses "notify the affected data subjects" (Article 34 language) without specifying channels. The DPD's channel-specific language is complementary, not contradictory. No GDPR Policy edit needed.

**No gaps identified.** This is a pure text substitution with no conditional logic or cross-reference changes.

## Acceptance Criteria

- [x] Section 7.2 platform list includes "Web Platform (app.soleur.ai)" in `docs/legal/data-protection-disclosure.md`
- [x] Section 7.2(b) specifies email notification for Web Platform users in `docs/legal/data-protection-disclosure.md`
- [x] Identical changes applied to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [x] "Last Updated" date updated in both files
- [x] `diff` between root and Eleventy copies shows only expected frontmatter/link differences (no content drift)
- [x] Grep for "distribution channels" across all legal docs confirms no other sections need updating

## Test Scenarios

- Given a reader of DPD Section 7.2, when they check which platforms are covered by breach notification, then "Web Platform (app.soleur.ai)" is explicitly listed
- Given a Web Platform user reading Section 7.2(b), when they check how they will be notified of a breach, then email notification is explicitly mentioned
- Given both DPD copies, when comparing Section 7 content, then the text is identical
- Given GDPR Policy Section 11 and DPD Section 7.2, when comparing breach notification scope, then the Web Platform is covered in both documents

## Context

**Institutional learnings applied:**
- `2026-03-18-dpd-processor-table-dual-file-sync.md`: Every structural change must touch both files in the same PR
- `2026-03-20-legal-doc-product-addition-prevention-strategies.md`: Exhaustive grep before implementation (Strategy 2) -- confirmed Section 7.2 is the only breach-related section that omits Web Platform
- `2026-03-18-legal-cross-document-audit-review-cycle.md`: Run legal-compliance-auditor AFTER all edits, not during. Budget for one fix-reverify cycle.

**Semver label:** `semver:patch` (documentation fix, no code changes)

## References

- Issue: #907
- Cross-document audit: #888
- DPD dual-file learning: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md`
- [GDPR Article 34 -- Communication of a personal data breach to the data subject](https://gdpr-info.eu/art-34-gdpr/)
- [EDPB Guidelines 9/2022 on personal data breach notification under GDPR](https://www.edpb.europa.eu/system/files/2023-04/edpb_guidelines_202209_personal_data_breach_notification_v2.0_en.pdf)
- [GDPR Data Breach Notification Requirements](https://gdprlocal.com/data-breach-notification-requirements/)
