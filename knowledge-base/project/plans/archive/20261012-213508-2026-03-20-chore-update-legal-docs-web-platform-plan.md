---
title: "chore: update legal documents for web platform cloud services"
type: chore
date: 2026-03-20
issues: "#703, #736"
priority: p1-high
deepened: 2026-03-20
---

# chore: Update Legal Documents for Web Platform Cloud Services

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 phases + technical considerations + acceptance criteria + risks
**Research conducted:** GDPR Art. 13 transparency requirements, SaaS T&C best practices (2025-2026), cross-document consistency verification (all 3 docs confirmed in sync), 3 institutional learnings applied, peer T&C pattern analysis (Basecamp/37signals)

### Key Improvements

1. **Issue #703 is already complete:** Verification confirms PR #732 (merged 2026-03-18) fully addressed the Privacy Policy, DPD, and GDPR Policy updates. Source and Eleventy copies are in sync for all three documents. Only the T&C (#736) remains. Closing #703 requires only a verification commit, not new edits.
2. **Section 7.1 already partially scoped:** The T&C Section 7.1 already uses "The Plugin itself does not..." phrasing, but this scoping is undermined by Section 4.1 which uses unscoped "Soleur does not operate cloud servers." Both sections need alignment.
3. **Existing pattern from PR #732:** The Privacy Policy Section 4.1 uses the exact pattern to follow: scope existing text to "The Soleur **Plugin**" and add a cross-reference sentence "This section applies to the Plugin only. For data collected by the Soleur Web Platform (app.soleur.ai), see Section X below."
4. **GDPR Art. 13 transparency applies immediately:** Web research confirms transparency requirements apply at the point of data collection and cannot be deferred for beta status. The T&C false statements create a regulatory risk regardless of user volume.
5. **Beta-appropriate scope:** Peer analysis (Basecamp/37signals) shows SaaS T&C should describe the service and its data practices but need not include comprehensive SLA or uptime commitments at beta stage. Keep new sections minimal.

### New Considerations Discovered

- The T&C Section 1 ("Introduction and Acceptance") references "the Plugin" and "the Service" but does not mention "the Web Platform" -- this needs updating for the new scope
- Section 13.3 lists surviving sections "5.4, 6, 9, 10, 11, 14, and 15" -- new Web Platform sections may need to be added to the survival clause
- The T&C lacks a consent mechanism reference for Web Platform account creation -- the Privacy Policy references "contract performance" (Art. 6(1)(b)) but the T&C should state that account creation constitutes acceptance of data processing
- The DPD Section 8.1(g) already says "Users accept the updated Terms and Conditions when creating a Web Platform account" -- the T&C must match this claim

---

## Overview

Two related GitHub issues require updating Soleur's legal documents to reflect the web platform (app.soleur.ai):

- **#703** -- Update privacy policy, DPD, and GDPR policy for web platform
- **#736** -- Update Terms & Conditions for web platform cloud services

PR #732 (merged 2026-03-18) already addressed the bulk of #703 by adding web platform sections to the Privacy Policy, DPD, and GDPR Policy. However, #703 remains open and may need a final verification pass. Issue #736 is entirely unaddressed -- the T&C still contains blanket "local-only" statements that contradict the web platform.

## Problem Statement

The Terms & Conditions contain false statements about Soleur's architecture:

- **Section 4.1:** "Soleur does not operate cloud servers and does not collect, transmit, or store your data on remote infrastructure controlled by us."
- **Section 7.1:** "The Plugin itself does not collect, transmit, or store personal data on external servers."
- **Section 7.4:** "Because Soleur stores data locally and does not collect personal data on our servers, these rights are inherently satisfied by your local control over the data."

These blanket statements apply to all of Soleur, not just the Plugin. The web platform at app.soleur.ai processes user PII (email, auth tokens, encrypted API keys, subscription data) on Jikigai-operated infrastructure via Supabase, Stripe, Hetzner, and Cloudflare.

This is a potential GDPR Art. 13 transparency violation and blocks the web platform beta launch.

### Research Insights: GDPR Art. 13 Transparency

**GDPR enforcement context (2025-2026):** Over EUR 1.6 billion in fines issued in 2024 alone. GDPR enforcement is intensifying, especially for SaaS platforms handling personal data. Article 13 requires controllers to disclose processing details at the point of data collection -- this cannot be deferred for beta status.

**Article 13 minimum disclosures required in T&C or linked Privacy Policy:**

1. Identity and contact details of the controller
2. Purposes of processing and legal basis for each
3. Recipients or categories of recipients of personal data
4. Transfers to third countries and safeguards applied
5. Retention periods or criteria
6. Data subject rights (access, rectification, erasure, restriction, portability, objection)
7. Right to lodge a complaint with a supervisory authority

**Current state:** Items 1-7 are already covered in the Privacy Policy and GDPR Policy (updated in PR #732). The T&C gap is that it makes affirmative false statements that contradict these disclosures, not that the disclosures are missing. The fix is scoping + cross-referencing, not re-documenting.

## Proposed Solution

### Phase 1: Terms & Conditions Update (Primary Work -- #736)

Update the T&C to scope "local-only" statements to the Plugin and add Web Platform service terms. Apply changes to both file locations:

- `docs/legal/terms-and-conditions.md` (source)
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy template)

Specific sections to modify:

#### Section 1: Introduction and Acceptance

Update the scope definition. Currently references "the Plugin" and "the Service" but not "the Web Platform." Add "and the Soleur Web Platform at app.soleur.ai ("the Web Platform")" to the first paragraph. Update acceptance clause to: "By installing, accessing, or using Soleur (whether the Plugin or the Web Platform), you agree to be bound by these Terms."

#### Section 2: Definitions

Add new definitions:

- **"Web Platform"** -- the Soleur cloud-hosted service at app.soleur.ai, including account management, workspace environments, and subscription services.
- **"Subscription"** -- a paid plan for Web Platform access, managed through Stripe Checkout.
- **"Account Data"** -- email address, authentication tokens, session data, and other information provided during Web Platform registration and use.

**Implementation note:** Insert alphabetically among existing definitions. Keep definitions brief -- detailed data categories are in the Privacy Policy Section 4.7.

#### Section 4.1: Local-First Architecture

**Current text to scope (line 51):**
> The Plugin is installed and operates locally on your machine via the Claude Code CLI. All knowledge-base files, configuration data, and User Content are stored exclusively on your local file system. Soleur does not operate cloud servers and does not collect, transmit, or store your data on remote infrastructure controlled by us.

**Target text:**
> The Plugin is installed and operates locally on your machine via the Claude Code CLI. All knowledge-base files, configuration data, and Plugin-generated User Content are stored exclusively on your local file system. The Plugin does not collect, transmit, or store your data on remote infrastructure controlled by us.
>
> This section applies to the Plugin only. For the Web Platform, see Section 4.3 below.

**Pattern source:** This follows the exact scoping pattern used in Privacy Policy Section 4.1 (PR #732): scope the statement, then add a cross-reference sentence.

#### Section 4: Add Section 4.3 -- Web Platform Service

Add new section between 4.2 and the current Section 5:

```markdown
### 4.3 Web Platform Service

The Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) is a cloud-hosted service operated by Jikigai. Unlike the Plugin (Section 4.1), the Web Platform processes data on Jikigai-operated infrastructure.

When you create a Web Platform account:

- You provide an email address and create authentication credentials managed by Supabase.
- You may store encrypted API keys (BYOK -- bring your own key) in your workspace.
- If you subscribe to a paid plan, payment is processed by Stripe via Stripe Checkout. Card data is handled exclusively by Stripe and never reaches Jikigai servers.

The Web Platform is hosted on Hetzner servers in Helsinki, Finland (EU) and uses Cloudflare as a CDN/proxy. Full data processing details are described in the [Privacy Policy](privacy-policy.md) Section 4.7.

By creating a Web Platform account, you accept these Terms and acknowledge that your data will be processed as described in the Privacy Policy.
```

**Edge case: beta disclaimer.** Do NOT include "beta" language in T&C terms. Beta status is a marketing descriptor, not a legal category. If service limitations exist, state them directly (e.g., "no uptime guarantee") rather than using "beta" as a catch-all disclaimer.

#### Section 7: Data Practices and Privacy

**Section 7.1 (line 112):** Already says "The Plugin itself does not collect, transmit, or store personal data on external servers." This scoping is correct. Add a cross-reference:

> This section applies to the Plugin only. For Web Platform data practices, see Section 7.3 and the [Privacy Policy](privacy-policy.md) Section 4.7.

**Add Section 7.1b (new):** Web Platform Data Practices

```markdown
### 7.1b Web Platform Data Practices

The Soleur Web Platform collects and processes personal data as necessary to provide the service. This includes:

- **Account data** (email, authentication tokens) processed by Supabase (EU-hosted, AWS eu-west-1, Ireland).
- **Payment data** processed by Stripe (PCI SAQ-A -- card data handled exclusively by Stripe).
- **Workspace data** (encrypted API keys, workspace configurations) hosted on Hetzner (Helsinki, Finland, EU).
- **Technical data** (IP addresses, request headers) processed by Cloudflare CDN/proxy.

For comprehensive data processing details, legal bases, retention periods, and your rights, see the [Privacy Policy](privacy-policy.md) and [GDPR Policy](gdpr-policy.md).
```

**Section 7.4 (line 124):** Replace the blanket GDPR statement:

**Current text:**
> If you are located in the EU/EEA, you have rights under the GDPR including the right of access, rectification, erasure, restriction of processing, data portability, and objection. Because Soleur stores data locally and does not collect personal data on our servers, these rights are inherently satisfied by your local control over the data.

**Target text:**
> If you are located in the EU/EEA, you have rights under the GDPR including the right of access, rectification, erasure, restriction of processing, data portability, and objection.
>
> For the Plugin, these rights are inherently satisfied by your local control over Plugin-generated data.
>
> For the Web Platform, you may exercise these rights against Jikigai by contacting <legal@jikigai.com>. See the [GDPR Policy](gdpr-policy.md) Section 5 for full details on how to exercise each right.
>
> For any GDPR-related inquiries concerning the documentation site or third-party integrations, please contact us through the channels listed in Section 16.

#### Section 9: Disclaimer of Warranties

**Section 9.1 (line 142):** The current text uses "THE PLUGIN" in all-caps. Update to:
> THE PLUGIN AND THE WEB PLATFORM ARE PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND...

**Section 9.2:** Update to reference both Plugin and Web Platform:
> We do not warrant that the Plugin or the Web Platform will be uninterrupted, error-free, secure, or free of harmful components.

#### Section 10: Limitation of Liability

**Section 10.1 (line 156):** Currently says "YOUR USE OF THE PLUGIN." Update to:
> ...ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE PLUGIN OR THE WEB PLATFORM.

**Section 10.2 (line 160):** Update aggregate liability cap to:
> ...ARISING OUT OF OR RELATING TO THESE TERMS OR YOUR USE OF THE PLUGIN OR THE WEB PLATFORM SHALL NOT EXCEED THE GREATER OF (A) THE AMOUNT YOU PAID US (IF ANY) IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM, OR (B) ONE HUNDRED EUROS (EUR 100).

**Research insight:** For free-tier users, a "zero paid" liability cap is problematic under EU consumer law. Adding a floor amount (EUR 100) provides a minimal but non-zero cap that is more defensible. This is a common pattern in EU SaaS T&C.

#### Section 13: Termination

**Add Section 13.1b (new):** Web Platform Account Termination

```markdown
### 13.1b Termination of Web Platform Account

You may delete your Web Platform account at any time. Upon account deletion:

- Account data (email, authentication tokens) is deleted from Supabase.
- Workspace data and encrypted API keys are deleted from Hetzner.
- Payment records (subscription metadata, invoices) are retained for 10 years per French tax law (Code de commerce Art. L123-22).

For details on data retention after account deletion, see the [Privacy Policy](privacy-policy.md) Section 7.
```

**Section 13.3 (line 204):** Update effect of termination:

**Current text:**
> Upon termination, your license to use the Plugin ceases. Because all data is stored locally on your machine, termination does not affect your User Content -- you retain full control of your local files.

**Target text:**
> Upon termination, your license to use the Plugin ceases. Plugin-generated User Content remains on your local machine under your control. For the Web Platform, account termination triggers data deletion as described in Section 13.1b.

**Surviving sections (line 204):** Review whether new Web Platform sections (4.3, 7.1b) need to survive termination. They do not -- they describe active service terms. Keep the existing survival clause as-is.

#### Section 15.1: Entire Agreement

Update to:
> These Terms, together with any referenced policies (including our Privacy Policy and Acceptable Use Policy), constitute the entire agreement between you and us regarding your use of the Plugin and the Web Platform.

#### Frontmatter and Header

Update `Last Updated` date to March 20, 2026 with change description: "added Web Platform service terms, scoped local-only statements to Plugin, updated data practices and GDPR rights sections for Web Platform."

### Phase 2: Verification of Privacy Policy, DPD, GDPR Policy (#703)

**Status: COMPLETE (verified during deepening)**

PR #732 already updated these documents. Verification during plan deepening confirms:

1. **Privacy Policy** (`docs/legal/privacy-policy.md`) -- Section 4.7 (web platform data) present. Sections 5.5-5.8 (Supabase, Stripe, Hetzner, Cloudflare) present. International transfers in Section 10 cover all processors. Data retention in Section 7 includes Web Platform. Source and Eleventy copies are in sync (only differences: frontmatter, HTML wrapper, template variables, link paths).
2. **DPD** (`docs/legal/data-protection-disclosure.md`) -- Section 2.1b (web platform processing) present. Section 4.2 processor table includes all 4 Web Platform vendors plus existing processors. Section 8 transition status shows all 7 commitments fulfilled. Source and Eleventy copies are in sync (only difference: HTML wrapper).
3. **GDPR Policy** (`docs/legal/gdpr-policy.md`) -- Section 3.7 (web platform legal basis) present with contract performance (Art. 6(1)(b)) for all three processing activities. Section 4.2 data categories table includes all Web Platform data types. Section 6 international transfers cover all processors. Section 9 DPIA evaluation concluded (not required). Section 10 Article 30 register entries 7-9 present with correct legal bases. Source and Eleventy copies are in sync.

**Action:** Close #703 when the PR is merged. No further edits needed to these three documents.

### Phase 3: Cross-Document Consistency Audit

Run the legal-compliance-auditor agent after all T&C edits to check:

1. Cross-document consistency between T&C, Privacy Policy, DPD, and GDPR Policy
2. Source vs Eleventy copy sync for all four documents
3. No remaining blanket "local-only" statements that apply to all of Soleur
4. Section numbering integrity (new sections 4.3, 7.1b, 13.1b do not break references)
5. All sub-processor references consistent
6. **NEW:** T&C acceptance clause matches DPD Section 8.1(g) claim about account creation
7. **NEW:** T&C liability cap language consistent with any Privacy Policy or GDPR Policy claims

Per the learning `2026-03-18-legal-cross-document-audit-review-cycle.md`, budget for an audit-fix-reverify cycle. Legal documents have a cross-reference graph that is invisible in a section-by-section plan. The auditor reads all documents holistically and catches gaps that targeted edits miss.

### Phase 4: grep Verification

Run targeted grep to confirm no blanket "does not collect/operate/store" statements remain unscoped:

```bash
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/terms-and-conditions.md
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/privacy-policy.md
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/data-protection-disclosure.md
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/gdpr-policy.md
```

All matches must be scoped to "the Plugin" or "Plugin itself" (not blanket "Soleur").

**Additional grep checks (from learning):**

```bash
# Check for stale conditional language about cloud features
grep -n "if cloud features\|when cloud\|future cloud" docs/legal/terms-and-conditions.md
# Check for remaining "Soleur does not" blanket statements
grep -n "Soleur does not" docs/legal/terms-and-conditions.md
```

## Technical Considerations

- **Dual-file sync:** Every change to `docs/legal/*.md` must be mirrored to `plugins/soleur/docs/pages/legal/*.md` with Eleventy-specific differences (frontmatter, HTML wrapper, link paths, template variables for counts). The learning `2026-03-19-dpa-vendor-response-verification-lifecycle.md` documents a case where one source file was missed -- enumerate ALL files before editing.
- **Legal agent workflow:** Use `legal-document-generator` to draft the T&C updates, then `legal-compliance-auditor` to audit. The pattern is: edit all documents, then run auditor, then fix findings, then re-verify. Per the learning, the auditor must run as a post-edit verification, not a pre-edit check.
- **No model/schema changes:** This is purely a documentation update.
- **Cross-reference graph:** T&C Section 7 references the Privacy Policy. Privacy Policy Section 4.1 references "this section applies to the Plugin only." DPD Section 8.1(g) references "users accept the updated Terms and Conditions when creating a Web Platform account." All cross-references must remain accurate after edits.
- **Eleventy link differences:** Source files use relative `.md` links (e.g., `privacy-policy.md`). Eleventy copies use absolute HTML paths (e.g., `/pages/legal/privacy-policy.html`). When syncing new cross-references in the T&C, convert link formats.
- **Section numbering strategy:** Use subsection numbering (4.1b, 7.1b, 13.1b) rather than renumbering existing sections. This preserves backward compatibility with any external references to section numbers and matches the pattern used in Privacy Policy (Section 4.1 scoped, Section 4.7 added) and DPD (Section 2.1b added).

### Implementation Order

1. Edit `docs/legal/terms-and-conditions.md` (source) -- all section changes
2. Sync to `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy) -- same content, different links/frontmatter
3. Run legal-compliance-auditor on all 4 source documents
4. Fix any findings in both locations
5. Run grep verification
6. Commit

## Acceptance Criteria

- [x] T&C Section 1 references "the Web Platform" in scope definition
- [x] T&C Section 2 defines "Web Platform," "Subscription," and "Account Data"
- [x] T&C Section 4.1 scoped to Plugin only, with cross-reference to Section 4.3
- [x] T&C Section 4.3 describes Web Platform service (account, payment, workspace, BYOK)
- [x] T&C Section 7.1 retains Plugin scoping, adds cross-reference to Section 7.1b
- [x] T&C Section 7.1b describes Web Platform data practices with processor summary
- [x] T&C Section 7.4 split into Plugin (local control) and Web Platform (exercisable via <legal@jikigai.com>) GDPR rights
- [x] T&C Section 9.1 covers both Plugin and Web Platform
- [x] T&C Section 10 liability language covers both Plugin and Web Platform
- [x] T&C Section 10.2 has EUR 100 floor for liability cap
- [x] T&C Section 13.1b covers Web Platform account termination and data deletion
- [x] T&C Section 13.3 updated for Web Platform data
- [x] T&C Section 15.1 references both Plugin and Web Platform
- [x] All "does not collect/operate/store" statements in T&C scoped to "the Plugin"
- [x] No "Soleur does not" blanket statements remain
- [x] Source and Eleventy copies consistent for T&C (link format differences only)
- [x] Privacy Policy, DPD, GDPR Policy verified complete (confirmed during deepening)
- [x] Source and Eleventy copies consistent for Privacy Policy, DPD, GDPR Policy (confirmed during deepening)
- [x] legal-compliance-auditor finds zero P1/P2 findings in T&C (pre-existing P1s in other docs tracked in #888, #889)
- [x] grep verification shows no unscoped blanket statements across all four documents
- [x] `Last Updated` date reflects March 20, 2026 with change description
- [x] DPD Section 8.1(g) claim about T&C acceptance is satisfied by new Section 4.3

## Test Scenarios

- Given the T&C at `docs/legal/terms-and-conditions.md`, when grep for "does not collect", then all matches contain "Plugin" or "Plugin itself" qualifier
- Given the T&C, when grep for "Soleur does not", then zero matches found (all scoped to "The Plugin does not")
- Given the T&C, when searching for "Web Platform", then Sections 1, 2, 4.3, 7.1b, 7.4, 9, 10, 13.1b, 13.3, 15.1 contain Web Platform references
- Given both T&C file locations, when diffing content (ignoring frontmatter/HTML wrapper/link format differences), then content is identical
- Given all four legal documents, when running legal-compliance-auditor, then zero P1/P2 cross-document consistency findings
- Given the T&C Section 4.3, when checking against DPD Section 8.1(g), then account creation acceptance clause matches

## Dependencies and Risks

- **Dependency:** PR #732 (merged) provides the foundation. This PR builds on that work.
- **Risk: Scope creep.** Other legal documents (AUP, Cookie Policy, Disclaimer) should NOT be modified unless the auditor flags a direct inconsistency. The AUP may need a "Web Platform" reference eventually but is not a blocking issue.
- **Risk: Over-engineering.** Keep new sections minimal. This is correcting false statements and adding minimum viable Web Platform terms, not writing comprehensive SaaS terms. Full SaaS terms can evolve as the product matures.
- **Risk: Section numbering confusion.** Using subsection numbers (4.3, 7.1b, 13.1b) instead of renumbering avoids breaking external references. But verify the auditor does not flag numbering gaps (e.g., "no Section 4.2" when 4.2 already exists for Third-Party API Interactions).
- **Risk: EUR 100 liability floor.** This is a new element not present in other documents. Ensure it does not conflict with the Privacy Policy or GDPR Policy liability statements. If uncertain, omit and keep the existing "amount paid" cap.

### Mitigations

- Run legal-compliance-auditor in benchmark mode to get GDPR Art. 13 checklist verification
- Budget for one audit-fix-reverify cycle (learning: legal cross-document audit review cycle)
- Enumerate all 8 files (4 source + 4 Eleventy) before starting edits (learning: DPA vendor response verification lifecycle)

## References and Research

### Internal References

- PR #732: `chore(ops+legal): record new services from web platform deployment` (merged 2026-03-18)
- Issue #670: `ops+legal: record new services from web platform deployment` (closed)
- Issue #703: `legal: update privacy policy, DPD, and GDPR policy for web platform` (open)
- Issue #736: `legal: update Terms & Conditions for web platform cloud services` (open)
- Learning: `knowledge-base/project/learnings/2026-03-18-legal-cross-document-audit-review-cycle.md`
- Learning: `knowledge-base/project/learnings/2026-03-19-dpa-vendor-response-verification-lifecycle.md`
- Learning: `knowledge-base/project/learnings/2026-03-11-third-party-dpa-gap-analysis-pattern.md`
- Plan: `knowledge-base/project/plans/2026-03-18-chore-vendor-ops-legal-web-platform-services-plan.md`

### External References

- [GDPR Article 13 - GDPRhub](https://gdprhub.eu/Article_13_GDPR) -- Article 13 full text and case law
- [GDPR Compliance for SaaS: 2026 Action Plan](https://www.feroot.com/blog/gdpr-saas-compliance-2025/) -- Enforcement trends
- [SaaS Terms of Service Template (2025)](https://promise.legal/templates/terms-of-service) -- Template structure reference
- [Basecamp Terms of Service](https://basecamp.com/about/policies/terms) -- Peer SaaS T&C pattern (37signals)
- [Article 29 WP Transparency Guidelines](https://iapp.org/news/a/transparency-and-the-gdpr-practical-guidance-and-interpretive-assistance-from-the-article-29-working-party) -- Practical guidance on transparency obligations

### Files to Modify

- `docs/legal/terms-and-conditions.md` (primary target)
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy sync)

### Files to Verify (read-only -- confirmed in sync during deepening)

- `docs/legal/privacy-policy.md` -- confirmed complete
- `docs/legal/data-protection-disclosure.md` -- confirmed complete
- `docs/legal/gdpr-policy.md` -- confirmed complete
- `plugins/soleur/docs/pages/legal/privacy-policy.md` -- confirmed in sync
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- confirmed in sync
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` -- confirmed in sync

### Agents

- `legal-document-generator` -- draft T&C updates
- `legal-compliance-auditor` -- post-edit cross-document audit (benchmark mode recommended)
- `clo` -- orchestration if needed
