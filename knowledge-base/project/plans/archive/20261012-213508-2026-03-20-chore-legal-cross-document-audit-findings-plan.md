---
title: "chore: resolve pre-existing legal audit findings from cross-document review"
type: fix
date: 2026-03-20
---

# chore: resolve pre-existing legal audit findings from cross-document review

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 7 findings + implementation order + acceptance criteria
**Research sources:** 6 institutional learnings, GDPR/Cloudflare legal basis research, cross-document grep analysis, mirror file diff analysis

### Key Improvements

1. **Finding 6 scope expanded:** Cloudflare dual legal basis change affects 3 documents (DPD, GDPR Policy, Privacy Policy), not just the DPD processor table -- grep analysis found Cloudflare legal basis references in all three
2. **Mirror file sync confirmed as mandatory:** `diff -q` confirmed all 3 affected files differ between `docs/legal/` and `plugins/soleur/docs/pages/legal/` -- these are hand-maintained Eleventy templates with different frontmatter, HTML wrappers, and link formats (institutional learning `2026-03-18-dpd-processor-table-dual-file-sync.md`)
3. **Post-edit verification cycle added:** Institutional learnings document that legal edits always surface additional cross-reference gaps; added mandatory compliance auditor pass and grep verification to implementation order

### New Considerations Discovered

- Privacy Policy Section 6 describes Web Platform legal basis as blanket "contract performance" -- the Cloudflare dual-basis fix (Finding 6) should propagate there
- GDPR Policy Section 2.2 lists Cloudflare without specifying its legal basis (it references the DPD), so no separate update needed there -- but verify the cross-reference works
- The `plugins/soleur/docs/pages/legal/` files use `/pages/legal/*.html` link format instead of `.md` relative links, and have Eleventy `layout`/`permalink`/`description` frontmatter instead of `type`/`jurisdiction`/`generated-date`
- Buttondown appears in DPD Section 4.3 (Third-Party Services Used by Users) as a data processor despite that table being for user-controlled services -- this was a known issue from learning `2026-03-18-dpd-sub-processor-contradiction-fix.md`

---

## Overview

Cross-document audit during #736 identified 6 P2 and 1 P3 finding across the Privacy Policy, Data Protection Disclosure (DPD), and GDPR Policy. All findings are consistency gaps -- scopes, headings, or placements that became stale when the Web Platform was introduced. No false statements exist; the documents simply need alignment with each other and with the T&C (already updated in #880).

## Problem Statement

The Web Platform (app.soleur.ai) was added to the T&C in #880, and prior PRs (#732, #736) updated the DPD and GDPR Policy with Web Platform processor tables, data processing sections, and transfer mechanisms. However, several sections in the Privacy Policy, DPD, and GDPR Policy were not updated to reflect the expanded scope. These consistency gaps could confuse users or raise questions during a regulatory audit.

## Proposed Solution

Apply 7 targeted edits across 3 legal documents, then sync all changes to the Eleventy mirror files. Each edit is a text substitution or addition -- no structural reorganization required.

## Findings and Fixes

### Finding 1 (P2): Privacy Policy Section 1 intro omits Web Platform from scope

**File:** `docs/legal/privacy-policy.md`
**Section:** 1. Introduction (line 15)
**Current:** Scope defined as "the Plugin" and "the Docs Site" only.
**Fix:** Add "and the Soleur Web Platform at app.soleur.ai" to the introductory sentence, after "the Docs Site". The phrase should read:

> ...handles information in connection with the Soleur Company-as-a-Service platform ("the Plugin"), a Claude Code plugin providing agents, skills, commands, and a knowledge base for structured software development workflows, the Soleur documentation website located at soleur.ai ("the Docs Site"), and the Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) ("the Web Platform").

**Note:** Section 4.7 already covers Web Platform data, so the intro just needs the scope addition.

#### Research Insights

**Best Practices:**

- The GDPR Article 13 transparency principle requires that the scope of a privacy policy be clear at first glance. The introduction must enumerate all products/services covered so that users can immediately understand which processing activities are described.
- Industry standard (per Basecamp, GitHub, Stripe) is to define each product/service with a parenthetical short name in the intro, then use that short name consistently throughout the document.

**Edge Cases:**

- The Eleventy mirror file (`plugins/soleur/docs/pages/legal/privacy-policy.md`) renders this intro differently -- it uses an `<h1>` within a `<section class="page-hero">` HTML wrapper with the effective date. The intro body text is identical, so the same substitution applies.

### Finding 2 (P2): Privacy Policy Section 11 (Security) omits Web Platform security measures

**File:** `docs/legal/privacy-policy.md`
**Section:** 11. Security (lines 247-254)
**Current:** Only covers Plugin local security ("Because the Plugin runs locally...").
**Fix:** Add a second paragraph after the existing Plugin recommendations describing Web Platform security measures. Draw from DPD Section 8.1(c) which already documents these:

> For the Web Platform (app.soleur.ai), Jikigai implements the following security measures:
>
> - **Encryption at rest:** User API keys are encrypted using AES-256-GCM before storage.
> - **Encryption in transit:** All communication with the Web Platform is protected by TLS.
> - **EU-only hosting:** Web Platform infrastructure is hosted on Hetzner servers in Helsinki, Finland (EU), with no data transfers outside the EU for infrastructure-hosted data.
> - **Payment security:** Card data is handled exclusively by Stripe (PCI DSS Level 1 certified) via Stripe Checkout and never reaches Jikigai servers (PCI SAQ-A).
> - **Authentication:** User passwords are hashed by Supabase (bcrypt via GoTrue); authentication tokens are JWT-based.

#### Research Insights

**Best Practices:**

- Security sections in privacy policies should describe measures at a level that builds user confidence without revealing implementation details that could aid attackers. The bullet-point format above strikes this balance: it names the encryption standard (AES-256-GCM) and certifications (PCI DSS Level 1) without describing key management or rotation internals.
- GDPR Article 32 requires "appropriate technical and organizational measures." Listing specific measures (encryption, TLS, EU-hosting, PCI compliance) demonstrates Article 32 compliance.

**Cross-Reference Check:**

- GDPR Policy Section 7 ("Data Security Measures") currently covers only local security (7.1) and user recommendations (7.2). It does NOT describe Web Platform security measures. However, this was NOT listed in issue #890, so it should be filed as a separate issue rather than scope-creeping this PR. The compliance auditor post-edit pass will catch this.

### Finding 3 (P2): DPD Section 3.1 heading "Local-Only Architecture" is misleading

**File:** `docs/legal/data-protection-disclosure.md`
**Section:** 3.1 (line 106)
**Current heading:** `### 3.1 Local-Only Architecture`
**Fix:** Rename to `### 3.1 Plugin Architecture (Local-Only)` to clarify this section describes the Plugin only, since the DPD now also describes Web Platform cloud processing in other sections.

#### Research Insights

**Best Practices:**

- Section headings in legal documents serve as a table of contents for readers. A heading that says "Local-Only Architecture" in a document that also describes cloud processing creates confusion during cursory review. Adding the "(Local-Only)" parenthetical while leading with "Plugin Architecture" signals clearly which product the section covers.

**Edge Cases:**

- Verify that no internal cross-references use the heading text "Local-Only Architecture" as anchor text. Grep for `Local-Only Architecture` across all legal docs. If found, update the reference text too.

### Finding 4 (P2): GDPR Policy Section 1 second paragraph omits Web Platform

**File:** `docs/legal/gdpr-policy.md`
**Section:** 1. Introduction, second paragraph (line 21)
**Current:** "This policy applies to all individuals located in the European Economic Area ('EEA') who use or interact with Soleur, including the plugin software, documentation site, and GitHub repository."
**Fix:** Add "Web Platform (app.soleur.ai)," to the enumeration:

> This policy applies to all individuals located in the European Economic Area ("EEA") who use or interact with Soleur, including the plugin software, Web Platform (app.soleur.ai), documentation site, and GitHub repository.

#### Research Insights

**Best Practices:**

- GDPR Article 13 requires transparency about what services are covered. The GDPR Policy already has substantial Web Platform content (Sections 2.1, 2.2, 3.7, 4.2, 6, 7.2, 8.4, 9, 10), so the scope statement must match the actual content.
- Place the Web Platform after "plugin software" in the enumeration order since it is the second-most significant product (not an ancillary service like the docs site or GitHub repo).

### Finding 5 (P2): DPD Section 4.3 Buttondown placement error

**File:** `docs/legal/data-protection-disclosure.md`
**Section:** 4.3 Third-Party Services Used by Users (lines 156-167)
**Current:** Buttondown appears in the "Third-Party Services Used by Users" table (Section 4.3) with a description saying it "acts as data processor on behalf of Jikigai." This contradicts its placement -- services in 4.3 are described as "initiated and controlled by the User, not by Soleur."
**Fix:** Remove the Buttondown row from the Section 4.3 table. Buttondown is already correctly listed in Section 4.2 ("Service Processors") in the "Docs Site and Newsletter Processors" table. No content needs to be added elsewhere.

#### Research Insights

**Institutional Learning Applied:** `2026-03-18-dpd-sub-processor-contradiction-fix.md`
> "GDPR terminology precision matters: Buttondown is a **processor** (not sub-processor) because Jikigai acts as Controller, not Processor. Article 28 defines sub-processors as processors engaged by other processors."

The Buttondown row in Section 4.3 even self-identifies as "data processor on behalf of Jikigai," which is the definition of a Section 4.2 service. The row's description contains correct information but is in the wrong table. Removing it (not moving it) is the right action since Section 4.2 already has the complete entry.

**Verification step:** After removing the row, confirm the Section 4.3 table still has a proper header row and at least the remaining 3 rows (Anthropic, GitHub, npm).

### Finding 6 (P2): Cloudflare legal basis in DPD

**File:** `docs/legal/data-protection-disclosure.md` (primary), plus propagation to GDPR Policy and Privacy Policy
**Section:** 4.2 Service Processors, Web Platform Processors table (line 152)
**Current:** Cloudflare's legal basis is listed as "Contract performance (Article 6(1)(b))" in the Web Platform Processors table.
**Problem:** For unauthenticated visitors hitting the Cloudflare CDN/proxy, there is no contract in place. Contract performance only applies to authenticated Web Platform users who accepted the T&C.
**Fix:** Change Cloudflare's legal basis to "Contract performance (Article 6(1)(b)) for authenticated users; legitimate interest (Article 6(1)(f)) for unauthenticated traffic".

#### Research Insights

**GDPR Best Practices for CDN Legal Basis:**

- [Cloudflare's own GDPR guidance](https://www.cloudflare.com/trust-hub/gdpr/) and [community discussions](https://community.cloudflare.com/t/gdpr-and-cloudflare/18736) confirm that the standard legal basis for CDN processing of unauthenticated visitor traffic is **legitimate interest** (Article 6(1)(f)), not contract performance. The legitimate interest is the website operator's strong economic interest in safe, secure, and performant delivery of its web properties.
- The dual-basis approach (contract for authenticated, legitimate interest for unauthenticated) is the most defensible position and mirrors the pattern already used for GitHub Pages in the DPD Docs Site processors table.

**Expanded Scope (discovered during research):**
The original plan stated "The GDPR Policy Section 2.1 already mentions Cloudflare under Web Platform context, so a matching update there is not needed." However, cross-document grep revealed:

1. **DPD Section 4.2 table** (line 152): Legal basis column says "Contract performance (Article 6(1)(b))" -- **must update**
2. **Privacy Policy Section 6** (line 186): "For the Web Platform (app.soleur.ai), the legal basis for processing account data, workspace data, and subscription data is contract performance (Article 6(1)(b))" -- this is a blanket statement covering all Web Platform processing. Cloudflare CDN traffic for unauthenticated visitors is not "account data, workspace data, or subscription data," so technically the existing text is correctly scoped by data category. **No change needed** -- the sentence explicitly scopes to "account data, workspace data, and subscription data" and Cloudflare IP/header processing does not fall into those categories.
3. **GDPR Policy Section 2.2** (line 45): Lists Cloudflare with transfer mechanism details but does not specify a legal basis -- it defers to the DPD. **No change needed.**
4. **GDPR Policy Section 3.7** (lines 81-89): "Web Platform Service Delivery" describes legal bases for account, payment, and infrastructure processing. Cloudflare is not explicitly mentioned in this section. **No change needed** -- the section is already correctly scoped to account/payment/infrastructure.

**Net result:** Only the DPD Section 4.2 table needs the dual-basis update. The other documents are either correctly scoped or delegate to the DPD.

### Finding 7 (P3): DPD Section 10 missing Web Platform account deletion

**File:** `docs/legal/data-protection-disclosure.md`
**Section:** 10. Termination and Data Deletion (lines 273-286)
**Current:** Only covers Plugin removal (10.1) and Docs Site/Repository data (10.2). No mention of Web Platform account deletion.
**Fix:** Add a new subsection `### 10.3 Web Platform Account Deletion` after 10.2, cross-referencing T&C Section 13.1b:

> ### 10.3 Web Platform Account Deletion
>
> Users may delete their Web Platform account at any time via account settings. Upon account deletion:
>
> - **(a)** Account data (email, authentication tokens, session data) is deleted from Supabase.
> - **(b)** Encrypted API keys and workspace data are deleted from Hetzner infrastructure.
> - **(c)** Stripe retains payment records (subscription metadata, invoices) for 10 years per French tax law (Code de commerce Art. L123-22).
> - **(d)** Cloudflare cache entries expire per standard TTL; no persistent user data is stored by Cloudflare.
>
> See the [Terms and Conditions](terms-and-conditions.md) Section 13.1b for the full account termination procedure.

#### Research Insights

**Best Practices:**

- GDPR Article 17 (Right to Erasure) requires clear disclosure of what happens to data upon account deletion. The DPD should mirror the T&C's deletion commitments to avoid contradictions.
- Listing each processor's deletion behavior separately (as done above) provides the transparency required by Article 13(2)(a) regarding retention periods.

**Edge Cases:**

- The Eleventy mirror file link format differs: use `[Terms and Conditions](/pages/legal/terms-and-conditions.html)` instead of `[Terms and Conditions](terms-and-conditions.md)`.
- Verify that T&C Section 13.1b content matches the deletion commitments described here. Cross-check already confirmed alignment: T&C 13.1b lists (a) account data deletion, (b) workspace/API key deletion, (c) Stripe retention per French tax law, (d) Cloudflare cache expiry.

## Acceptance Criteria

- [x] Privacy Policy Section 1 intro enumerates Plugin, Docs Site, and Web Platform
- [x] Privacy Policy Section 11 describes Web Platform security measures (AES-256-GCM, TLS, EU-only hosting, PCI SAQ-A, bcrypt)
- [x] DPD Section 3.1 heading reads "Plugin Architecture (Local-Only)"
- [x] GDPR Policy Section 1 second paragraph includes "Web Platform (app.soleur.ai)" in the scope list
- [x] DPD Section 4.3 table does not contain a Buttondown row
- [x] DPD Section 4.2 Cloudflare row uses dual legal basis (contract performance + legitimate interest)
- [x] DPD Section 10.3 exists with Web Platform account deletion procedure cross-referencing T&C Section 13.1b
- [x] All "Last Updated" dates bumped to today's date with change descriptions
- [x] No cross-document references are broken by the edits
- [x] Eleventy mirror files (`plugins/soleur/docs/pages/legal/`) updated with identical body content changes, adapted for Eleventy link format (`/pages/legal/*.html`)
- [x] Post-edit grep verification passes: zero unaddressed Buttondown rows in Section 4.3, zero "Local-Only Architecture" heading references, Cloudflare legal basis consistent across all documents
- [ ] Legal compliance auditor run confirms no P1/P2 findings remain

## Test Scenarios

- Given a reader of Privacy Policy Section 1, when they read the intro, then the Web Platform is listed as part of the scope
- Given a reader of Privacy Policy Section 11, when they look for Web Platform security measures, then AES-256-GCM, TLS, EU-only hosting, and PCI SAQ-A are described
- Given a reader of DPD Section 3.1, when they see the heading, then it clearly indicates the section covers Plugin architecture only
- Given a reader of GDPR Policy Section 1, when they read the scope, then the Web Platform is enumerated alongside plugin, docs site, and repository
- Given a reader of DPD Section 4.3, when they scan the "Third-Party Services Used by Users" table, then Buttondown does not appear (it is correctly in Section 4.2)
- Given a reader of DPD Section 4.2, when they check Cloudflare's legal basis, then both contract performance and legitimate interest are listed with applicability conditions
- Given a reader of DPD Section 10, when they look for Web Platform account deletion, then Section 10.3 describes the procedure with a cross-reference to T&C Section 13.1b
- Given the Eleventy mirror files, when they are compared to source files, then body content matches (allowing for frontmatter and link format differences)

## Context

- **Parent issue:** #890
- **Origin:** Cross-document audit during #736
- **Related PRs:** #732 (initial legal docs), #736 (Web Platform DPD update), #880 (T&C Web Platform update)
- **Documents affected (source):**
  - `docs/legal/privacy-policy.md` (Findings 1, 2)
  - `docs/legal/data-protection-disclosure.md` (Findings 3, 5, 6, 7)
  - `docs/legal/gdpr-policy.md` (Finding 4)
- **Documents affected (Eleventy mirrors):**
  - `plugins/soleur/docs/pages/legal/privacy-policy.md` (Findings 1, 2)
  - `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Findings 3, 5, 6, 7)
  - `plugins/soleur/docs/pages/legal/gdpr-policy.md` (Finding 4)
- **Total files modified:** 6 (3 source + 3 Eleventy mirrors)

## Institutional Learnings Applied

These learnings from `knowledge-base/project/learnings/` informed the deepened plan:

1. **`2026-03-18-dpd-processor-table-dual-file-sync.md`**: The DPD's dual-file pattern means every change must touch both `docs/legal/` and `plugins/soleur/docs/pages/legal/` in the same PR. Drift is invisible until both files are diffed side by side.

2. **`2026-03-18-legal-cross-document-audit-review-cycle.md`**: Legal edits always surface additional cross-reference gaps. The pattern is: edit all documents -> run compliance auditor -> fix findings -> re-verify. Budget for this cycle.

3. **`2026-03-18-split-legal-basis-cross-section-consistency.md`**: A legal basis change propagates to every section that references that processing activity's data types, legal basis, or retention. Grep for the processor name across all legal docs to find every reference.

4. **`2026-03-20-legal-doc-product-addition-prevention-strategies.md`**: Exhaustive grep before implementation converts "did I miss anything?" into a bounded checklist. Strategy 5 (post-edit structural verification) should be run after all edits.

5. **`2026-03-02-legal-doc-bulk-consistency-fix-pattern.md`**: Key differences between file locations: `docs/legal/` has `type`/`jurisdiction`/`generated-date` frontmatter and `.md` relative links; `plugins/soleur/docs/pages/legal/` has `layout`/`permalink`/`description` frontmatter and `/pages/legal/*.html` absolute links wrapped in `<section>` HTML tags.

6. **`2026-03-18-dpd-sub-processor-contradiction-fix.md`**: Buttondown is a **processor** (not sub-processor) because Jikigai is Controller. Section 4.3 is for user-controlled services; Jikigai-controlled processors belong in Section 4.2.

## MVP

No code changes. All fixes are text edits to existing legal markdown documents. Each finding maps to a single, well-scoped text substitution or addition. The total change set is 6 files (3 source + 3 Eleventy mirrors).

### Implementation Order

1. **Pre-implementation grep inventory** -- Run `grep -n "Local-Only Architecture\|Buttondown" docs/legal/data-protection-disclosure.md` and `grep -n "Cloudflare.*contract\|Cloudflare.*Article 6" docs/legal/*.md` to establish the baseline of all references that will change.

2. **Findings 1, 2** -- Privacy Policy source (`docs/legal/privacy-policy.md`): edit intro scope, add security paragraph.

3. **Findings 3, 5, 6, 7** -- DPD source (`docs/legal/data-protection-disclosure.md`): rename heading, remove Buttondown row from 4.3, fix Cloudflare basis in 4.2, add Section 10.3.

4. **Finding 4** -- GDPR Policy source (`docs/legal/gdpr-policy.md`): add Web Platform to scope enumeration.

5. **Update "Last Updated" dates** on all 3 source documents with change descriptions.

6. **Sync to Eleventy mirrors** -- Apply identical body content changes to `plugins/soleur/docs/pages/legal/` files, converting link formats (`.md` -> `/pages/legal/*.html`). Also update the `<p>` tag in the hero section that contains the "Last Updated" text for the Privacy Policy mirror.

7. **Post-edit verification** (from learning `2026-03-20-legal-doc-product-addition-prevention-strategies.md` Strategy 5):

   ```bash
   # 1. Buttondown removed from DPD 4.3 -- verify not in user-services table
   grep -A 20 "Third-Party Services Used by Users" docs/legal/data-protection-disclosure.md | grep -i "buttondown"
   # Should return nothing

   # 2. Cloudflare legal basis consistency
   grep -n "Cloudflare" docs/legal/data-protection-disclosure.md | grep -i "article 6"
   # Should show dual basis in 4.2

   # 3. Heading rename
   grep "Local-Only Architecture" docs/legal/data-protection-disclosure.md
   # Should return nothing (renamed to "Plugin Architecture (Local-Only)")

   # 4. Cross-reference integrity
   grep -oE 'Section [0-9]+(\.[0-9]+[a-z]?)?' docs/legal/data-protection-disclosure.md | sort -u
   # Verify 10.3 appears and all references resolve

   # 5. Mirror file sync verification
   diff <(sed -n '/^## 1\./,/^---$/p' docs/legal/privacy-policy.md) <(sed -n '/^## 1\./,/^---$/p' plugins/soleur/docs/pages/legal/privacy-policy.md) | head -20
   # Body content should match
   ```

8. **Run legal compliance auditor** -- Run the `legal-compliance-auditor` agent on all 3 source documents to catch any cross-reference gaps introduced by the edits. Budget for one fix-reverify cycle per learning `2026-03-18-legal-cross-document-audit-review-cycle.md`.

9. **File new issues** for any out-of-scope findings discovered during the compliance auditor pass (e.g., GDPR Policy Section 7 missing Web Platform security measures).

## References

- Issue: [#890](https://github.com/jikig-ai/soleur/issues/890)
- PR #732: Initial legal document suite
- PR #736: Web Platform DPD updates
- PR #880: T&C Web Platform update
- T&C Section 13.1b: Web Platform account deletion procedure
- DPD Section 8.1(c): Web Platform security measures (source for Finding 2 fix)
- [Cloudflare GDPR Trust Hub](https://www.cloudflare.com/trust-hub/gdpr/) -- confirms legitimate interest as standard basis for CDN traffic processing
- [Cloudflare Community GDPR Discussion](https://community.cloudflare.com/t/gdpr-and-cloudflare/18736) -- confirms dual-basis approach for authenticated vs unauthenticated traffic
