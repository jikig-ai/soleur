---
title: "chore: harmonize Cloudflare dual legal basis across Privacy Policy and GDPR Policy"
type: fix
date: 2026-03-20
---

# chore: harmonize Cloudflare dual legal basis across Privacy Policy and GDPR Policy

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 3 edits + 2 new considerations + acceptance criteria tightened
**Research sources:** EDPB Guidelines 1/2024 on legitimate interest, Cloudflare DPA, ICO legitimate interest guidance, cross-document grep analysis

### Key Improvements

1. **Edit 2 balancing test gap identified:** GDPR Policy Section 3.7 ends with "A balancing test is not required for contract performance as a legal basis." Adding a legitimate interest bullet without a balancing test or updating that closing sentence would create an internal inconsistency -- EDPB Guidelines 1/2024 require a three-part test for every Article 6(1)(f) invocation
2. **"Last Updated" lines needed on all three documents:** Original plan only mentioned updating the DPD. The Privacy Policy and GDPR Policy also have "Last Updated" lines that must reflect this change
3. **Recital 49 citation strengthens Edit 2:** GDPR Recital 49 explicitly names network security as a legitimate interest, providing direct statutory backing for the CDN/DDoS protection rationale

### New Considerations Discovered

- GDPR Policy Section 3.7 closing sentence "A balancing test is not required for contract performance as a legal basis" must be updated to account for the new legitimate interest bullet -- either append a balancing test paragraph or amend the sentence to scope it to the first three bullets only
- The EDPB's three-step test (legitimate interest identification, necessity, balancing) should be documented inline for the CDN/proxy legitimate interest claim in the GDPR Policy, consistent with the pattern used in Sections 3.3, 3.4, and 3.6

---

## Overview

DPD Section 4.2 (the authoritative processor table) correctly states a dual legal basis for Cloudflare: contract performance (Article 6(1)(b)) for authenticated users, legitimate interest (Article 6(1)(f)) for unauthenticated traffic. Three companion locations in the DPD, GDPR Policy, and Privacy Policy still use blanket "contract performance" without this qualifier. This is a P3 precision fix -- no false statements exist, but the companion documents should match the processor table.

## Problem Statement

The dual-basis fix applied in #890 (PR #899) to DPD Section 4.2 made the asymmetry visible: three other locations describe Cloudflare-related processing under blanket "contract performance" without acknowledging that unauthenticated CDN/proxy traffic uses legitimate interest.

**Authoritative wording (DPD Section 4.2, line 152):**

> Contract performance (Article 6(1)(b)) for authenticated users; legitimate interest (Article 6(1)(f)) for unauthenticated traffic

## Proposed Solution

Apply 3 targeted edits to propagate the dual legal basis, then sync each change to the corresponding Eleventy mirror file. Update "Last Updated" lines on all three documents.

### Edit 1: DPD Section 2.1b(d) -- blanket contract performance qualifier

**Source file:** `docs/legal/data-protection-disclosure.md` (line 72)
**Mirror file:** `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (line 81)

**Current (line 72):**

> **(d)** The legal basis for this processing is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the User signed up for.

**Proposed:**

> **(d)** The legal basis for this processing is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the User signed up for. For Cloudflare CDN/proxy processing of unauthenticated traffic (visitors who have not signed up), the legal basis is **legitimate interest** (Article 6(1)(f) GDPR) -- see Section 4.2 for the full dual-basis disclosure.

**Rationale:** Section 2.1b(d) describes legal basis for "this processing" (all Web Platform processing). Adding a qualifier for the Cloudflare edge case aligns it with Section 4.2 without restructuring the paragraph.

#### Research Insights

**Best Practices:**
- The DPD's Section 2.1b(d) is a summary paragraph, not the authoritative disclosure. The cross-reference to Section 4.2 is the correct pattern -- it avoids duplicating the full balancing test while ensuring readers know a dual basis exists.
- EDPB Guidelines 1/2024 allow controllers to reference detailed disclosures elsewhere in the same document rather than repeating the full analysis at every mention.

**Edge Cases:**
- Verify the cross-reference "Section 4.2" remains accurate after any future section renumbering. A broken cross-reference would leave readers without the full dual-basis explanation.

### Edit 2: GDPR Policy Section 3.7 -- add CDN/proxy bullet

**Source file:** `docs/legal/gdpr-policy.md` (lines 85-87)
**Mirror file:** `plugins/soleur/docs/pages/legal/gdpr-policy.md` (lines 94-96)

**Current:** Three bullets (account, payment, infrastructure) all under contract performance, followed by "A balancing test is not required for contract performance as a legal basis."

**Proposed:** Add a fourth bullet after the infrastructure bullet:

> - **CDN/proxy processing:** For authenticated users, the lawful basis is **contract performance** (Article 6(1)(b)) -- Cloudflare processes requests as part of delivering the Web Platform service. For unauthenticated traffic (visitors who have not signed up), the lawful basis is **legitimate interest** (Article 6(1)(f)) -- operating CDN and DDoS protection for `app.soleur.ai` is necessary for infrastructure security and service availability (see also GDPR Recital 49). Data processed: IP addresses, request headers, TLS termination data. Processed by Cloudflare (see DPD Section 4.2).

**Additionally**, replace the closing sentence:

**Current (line 89):**

> A balancing test is not required for contract performance as a legal basis.

**Proposed:**

> A balancing test is not required for the contract performance basis used in account, payment, and infrastructure processing above. For the legitimate interest basis applied to unauthenticated CDN/proxy traffic, the balancing test considers: (a) the processing is limited to standard HTTP connection metadata (IP addresses, request headers), (b) operating CDN and DDoS protection is within the reasonable expectations of anyone visiting a web application, (c) Cloudflare does not use this data for profiling or advertising, and (d) the processing is necessary for infrastructure security and cannot be achieved without processing technical connection data from all visitors. Data subjects may object under Article 21 by contacting legal@jikigai.com.

**Rationale:** Section 3.7 enumerates Web Platform processing activities with per-activity legal basis. Adding Cloudflare as a fourth activity matches the structure. The existing closing sentence must be updated because it currently claims no balancing test is needed for the entire section -- which becomes incorrect once a legitimate interest basis is introduced.

#### Research Insights

**Best Practices (EDPB Guidelines 1/2024):**
- The EDPB's three-step test requires: (1) identifying a legitimate interest, (2) demonstrating necessity, and (3) a balancing exercise weighing controller interests against data subject rights
- GDPR Recital 49 explicitly states: "The processing of personal data to the extent strictly necessary and proportionate for the purposes of ensuring network and information security [...] constitutes a legitimate interest of the data controller concerned"
- The EDPB notes that network security solutions involving large-scale analysis of communications content and metadata may require a more rigorous balancing test -- but CDN/proxy processing of standard HTTP metadata (IP, headers) falls well below this threshold

**Consistency Check:**
- Sections 3.3 (repository interactions), 3.4 (CLA signatures), and 3.6 (newsletter technical metadata) all include inline balancing tests when invoking legitimate interest. The new CDN/proxy bullet must follow the same pattern for internal consistency.
- The Cloudflare DPA already classifies this processing as limited to "connection metadata" -- the balancing test language should mirror this characterization.

**Edge Cases:**
- If Cloudflare's Bot Management or WAF features are enabled in the future, the scope of "technical data processed" may expand beyond basic connection metadata. The balancing test should be reviewed if Cloudflare's processing scope changes.

### Edit 3: Privacy Policy Section 6 -- add Cloudflare technical data mention

**Source file:** `docs/legal/privacy-policy.md` (line 186)
**Mirror file:** `plugins/soleur/docs/pages/legal/privacy-policy.md` (line 195)

**Current (line 186):**

> For the Web Platform (app.soleur.ai), the legal basis for processing account data, workspace data, and subscription data is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the user signed up for. For payment processing via Stripe, the legal basis is also contract performance -- processing is necessary to fulfill the subscription agreement.

**Proposed:**

> For the Web Platform (app.soleur.ai), the legal basis for processing account data, workspace data, and subscription data is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the user signed up for. For payment processing via Stripe, the legal basis is also contract performance -- processing is necessary to fulfill the subscription agreement. For technical data processed by Cloudflare (IP addresses, request headers -- see Section 5.8), the legal basis is contract performance for authenticated users and **legitimate interest** (Article 6(1)(f) GDPR) for unauthenticated traffic.

**Rationale:** Section 6 scopes legal basis by data category. Account/workspace/subscription data are correctly scoped to contract performance. Adding a sentence for Cloudflare's technical data processing explicitly covers the CDN/proxy edge case and cross-references Section 5.8 (which already describes Cloudflare's data processing).

#### Research Insights

**Best Practices:**
- Privacy Policy Section 6 is a user-facing summary, not the detailed disclosure (that role belongs to the GDPR Policy). A brief mention with a cross-reference to Section 5.8 is the correct level of detail -- it avoids overwhelming end users while ensuring the dual basis is visible.
- The ICO (UK data protection authority) guidance recommends that privacy policies state the legal basis clearly but may reference other documents for detailed balancing tests.

**Edge Cases:**
- Section 5.8 already describes Cloudflare's data processing activities but does not mention the legal basis. This is correct -- Section 5.8 covers "what data" and Section 6 covers "what legal basis." The cross-reference connects both.

## Mirror File Sync

Each edit must be applied to both the source file and its Eleventy mirror. The mirror files are in `plugins/soleur/docs/pages/legal/` and have different frontmatter (Eleventy `layout`/`permalink`/`description` vs. `type`/`jurisdiction`/`generated-date`) but identical body content.

**Mirror pairs:**

| Source | Mirror |
|--------|--------|
| `docs/legal/data-protection-disclosure.md` | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` |
| `docs/legal/gdpr-policy.md` | `plugins/soleur/docs/pages/legal/gdpr-policy.md` |
| `docs/legal/privacy-policy.md` | `plugins/soleur/docs/pages/legal/privacy-policy.md` |

### Research Insights

**Best Practices:**
- The mirror files have different frontmatter but identical body content. Apply edits to body content only. Do not modify Eleventy-specific frontmatter (`layout`, `permalink`, `description`) in the mirror files.
- After editing, run `diff` between source and mirror bodies (excluding frontmatter) to verify they match. Past learnings (`2026-03-18-dpd-processor-table-dual-file-sync.md` from the prior audit) document that these files drift silently.

## "Last Updated" Lines

All three documents have "Last Updated" lines that must reflect this change:

| Document | Current "Last Updated" Line |
|----------|----------------------------|
| DPD (line 12) | `March 20, 2026 (renamed Section 3.1 heading, removed Buttondown from Section 4.3, updated Cloudflare legal basis to dual basis, added Section 10.3 Web Platform account deletion, added Section 5.3 Web Platform data subject rights)` |
| GDPR Policy (line 13) | `March 20, 2026 (added Web Platform to Section 1 scope enumeration, removed infrastructure identifiers from processing descriptions)` |
| Privacy Policy (line 11) | `March 20, 2026 (added Web Platform to scope introduction, added Web Platform security measures to Section 11, removed infrastructure identifiers from processing descriptions)` |

**Proposed updates:** Append to each parenthetical:
- DPD: `, harmonized Cloudflare dual legal basis in Section 2.1b(d)`
- GDPR Policy: `, added CDN/proxy dual legal basis to Section 3.7`
- Privacy Policy: `, added Cloudflare dual legal basis to Section 6`

## Acceptance Criteria

- [ ] DPD Section 2.1b(d) includes Cloudflare unauthenticated traffic qualifier with cross-reference to Section 4.2
- [ ] GDPR Policy Section 3.7 has a fourth bullet for CDN/proxy processing with dual legal basis
- [ ] GDPR Policy Section 3.7 closing sentence updated to scope "no balancing test" to contract performance bullets only, with inline balancing test for the legitimate interest portion
- [ ] Privacy Policy Section 6 mentions Cloudflare technical data processing with dual legal basis and cross-references Section 5.8
- [ ] All three edits are mirrored to `plugins/soleur/docs/pages/legal/` counterparts
- [ ] `grep -c "legitimate interest" docs/legal/data-protection-disclosure.md` count increases by 1
- [ ] `grep -c "legitimate interest" docs/legal/gdpr-policy.md` count increases by at least 1
- [ ] `grep -c "legitimate interest" docs/legal/privacy-policy.md` count increases by 1
- [ ] No conflict markers in any edited file
- [ ] "Last Updated" lines updated on all three documents (source and mirror)
- [ ] GDPR Policy CDN/proxy bullet includes balancing test consistent with Sections 3.3, 3.4, 3.6 pattern
- [ ] Recital 49 cited in GDPR Policy CDN/proxy bullet

## Test Scenarios

- Given the DPD Section 4.2 processor table states dual legal basis for Cloudflare, when reading DPD Section 2.1b(d), then it should reference the same dual basis
- Given GDPR Policy Section 3.7 lists Web Platform processing activities, when reading the section, then CDN/proxy processing should appear as a separate bullet with dual basis
- Given GDPR Policy Section 3.7 previously stated "A balancing test is not required for contract performance", when reading the updated section, then the closing text should scope that statement to the first three bullets and include a balancing test for the CDN/proxy legitimate interest
- Given Privacy Policy Section 6 describes legal bases by data category, when reading the section, then Cloudflare technical data should be explicitly mentioned with dual basis
- Given all six files (3 source + 3 mirror) are edited, when diffing body content between each source/mirror pair, then the bodies should be identical

## Context

- **Origin:** #912, identified during cross-document review of PR #899 (resolving #890)
- **Severity:** P3 -- the DPD Section 4.2 table is the authoritative processor-level disclosure, so no legal risk
- **Related PRs:** #899 (cross-document audit), #890 (original findings)
- **Related plan:** `2026-03-20-chore-legal-cross-document-audit-findings-plan.md` (Finding 6 in that plan specifically identified this issue)

## References

- DPD Section 4.2 processor table (authoritative dual-basis wording): `docs/legal/data-protection-disclosure.md:152`
- DPD Section 2.1b(d): `docs/legal/data-protection-disclosure.md:72`
- GDPR Policy Section 3.7: `docs/legal/gdpr-policy.md:81-89`
- Privacy Policy Section 6: `docs/legal/privacy-policy.md:186`
- EDPB Guidelines 1/2024 on legitimate interest: https://www.edpb.europa.eu/system/files/2024-10/edpb_guidelines_202401_legitimateinterest_en.pdf
- ICO legitimate interest guidance: https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/lawful-basis/legitimate-interests/what-is-the-legitimate-interests-basis/
- Cloudflare DPA: https://www.cloudflare.com/cloudflare-customer-dpa/
- Cloudflare GDPR compliance: https://www.cloudflare.com/trust-hub/gdpr/
- Issue: #912
