---
title: "chore: update legal documents for web platform cloud services"
type: chore
date: 2026-03-20
issues: "#703, #736"
priority: p1-high
---

# chore: Update Legal Documents for Web Platform Cloud Services

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

## Proposed Solution

### Phase 1: Terms & Conditions Update (Primary Work -- #736)

Update the T&C to scope "local-only" statements to the Plugin and add Web Platform service terms. Apply changes to both file locations:

- `docs/legal/terms-and-conditions.md` (source)
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy template)

Specific sections to modify:

#### Section 2: Definitions

Add new definitions:
- **"Web Platform"** -- the Soleur cloud-hosted service at app.soleur.ai
- **"Subscription"** -- a paid plan for Web Platform access

#### Section 4.1: Local-First Architecture

Scope the existing text to the Plugin only. Add a new subsection:

**4.1b Web Platform Architecture**

The Soleur Web Platform at app.soleur.ai is a cloud-hosted service operated by Jikigai. Unlike the Plugin, the Web Platform processes data on Jikigai-operated infrastructure. By creating a Web Platform account, you acknowledge that your data will be processed as described in the Privacy Policy Section 4.7.

#### Section 4: Add Section 4.3 -- Web Platform Service

Add new section covering:
- Account registration and management
- Subscription and billing (via Stripe Checkout)
- Workspace provisioning
- BYOK (bring your own key) encrypted API key storage
- Service availability and uptime (no SLA for beta)

#### Section 7: Data Practices and Privacy

**Section 7.1:** Scope to Plugin only ("The Plugin itself does not..."). Add cross-reference to Privacy Policy Section 4.7 for Web Platform data practices.

**Add Section 7.1b:** Web Platform Data Practices -- reference Privacy Policy for full details, summarize key points:
- Account data (email, auth tokens) processed by Supabase
- Payment data processed by Stripe (PCI SAQ-A)
- Workspace data hosted on Hetzner (EU-only)
- CDN/proxy via Cloudflare

**Section 7.4:** Fix the blanket GDPR statement. Scope local-data rights to Plugin, add Web Platform rights exercisable against Jikigai via legal@jikigai.com. Reference GDPR Policy for full details.

#### Section 9: Disclaimer of Warranties

**Section 9.1:** Extend to cover Web Platform ("THE PLUGIN AND WEB PLATFORM ARE PROVIDED AS IS...").

#### Section 10: Limitation of Liability

Ensure the existing limitation language covers both Plugin and Web Platform usage.

#### Section 13: Termination

**Add Section 13.1b:** Termination of Web Platform account -- how account deletion works, data retention per Privacy Policy.

**Section 13.3:** Update effect of termination to include Web Platform data deletion (account data deleted, payment records retained per French tax law).

#### Section 15.1: Entire Agreement

Update to reference that these Terms govern both the Plugin and the Web Platform.

#### Frontmatter and Header

Update `Last Updated` date to March 20, 2026 with change description.

### Phase 2: Verification of Privacy Policy, DPD, GDPR Policy (#703)

PR #732 already updated these documents. Run a verification pass to confirm:

1. **Privacy Policy** (`docs/legal/privacy-policy.md`) -- Section 4.7 (web platform data), Sections 5.5-5.8 (processors), international transfers, data retention all present and accurate.
2. **DPD** (`docs/legal/data-protection-disclosure.md`) -- Section 2.1b (web platform processing), processor table in 4.2, Section 8 transition status fulfilled.
3. **GDPR Policy** (`docs/legal/gdpr-policy.md`) -- Section 3.7 (web platform legal basis), Section 4.2 (data categories), international transfers, DPIA evaluation, Article 30 register entries 7-9.

Verify source and Eleventy copies are consistent for all three documents.

If any gaps are found, fix them as part of this PR. If all three are complete, close #703.

### Phase 3: Cross-Document Consistency Audit

Run the legal-compliance-auditor agent after all edits to check:

1. Cross-document consistency between T&C, Privacy Policy, DPD, and GDPR Policy
2. Source vs Eleventy copy sync for all four documents
3. No remaining blanket "local-only" statements that apply to all of Soleur
4. Section numbering integrity
5. All sub-processor references consistent

Per the learning `2026-03-18-legal-cross-document-audit-review-cycle.md`, budget for an audit-fix-reverify cycle.

### Phase 4: grep Verification

Run targeted grep to confirm no blanket "does not collect/operate/store" statements remain unscoped:

```bash
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/terms-and-conditions.md
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/privacy-policy.md
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/data-protection-disclosure.md
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/gdpr-policy.md
```

All matches must be scoped to "the Plugin" (not blanket "Soleur").

## Technical Considerations

- **Dual-file sync:** Every change to `docs/legal/*.md` must be mirrored to `plugins/soleur/docs/pages/legal/*.md` with Eleventy-specific differences (frontmatter, HTML wrapper, link paths, template variables for counts).
- **Legal agent workflow:** Use `legal-document-generator` to draft the T&C updates, then `legal-compliance-auditor` to audit. The CLO agent can orchestrate.
- **No model/schema changes:** This is purely a documentation update.
- **Cross-reference graph:** T&C Section 7 references the Privacy Policy. Privacy Policy Section 4.1 references "this section applies to the Plugin only." DPD Section 8.1(g) references "users accept the updated Terms and Conditions." All cross-references must remain accurate after edits.

## Acceptance Criteria

- [ ] T&C Section 4.1 scoped to Plugin only, with new Section 4.1b for Web Platform (`docs/legal/terms-and-conditions.md`)
- [ ] T&C Section 7.1 scoped to Plugin only, with new Section 7.1b for Web Platform data practices
- [ ] T&C Section 7.4 updated with Web Platform GDPR rights
- [ ] T&C definitions include "Web Platform" and "Subscription"
- [ ] T&C termination section covers Web Platform account deletion
- [ ] T&C warranty/liability sections cover both Plugin and Web Platform
- [ ] All "does not collect/operate/store" statements in T&C scoped to "the Plugin"
- [ ] Source and Eleventy copies consistent for T&C
- [ ] Privacy Policy, DPD, GDPR Policy verified complete (PR #732 work confirmed)
- [ ] Source and Eleventy copies consistent for Privacy Policy, DPD, GDPR Policy
- [ ] legal-compliance-auditor finds zero P1/P2 findings
- [ ] grep verification shows no unscoped blanket statements across all four documents
- [ ] `Last Updated` dates reflect March 20, 2026

## Test Scenarios

- Given the T&C at `docs/legal/terms-and-conditions.md`, when grep for "does not collect", then all matches contain "Plugin" or "Plugin itself" qualifier
- Given the T&C, when searching for "Web Platform", then Sections 4.1b, 4.3, 7.1b, 7.4, 13 contain Web Platform terms
- Given both T&C file locations, when diffing content (ignoring frontmatter/HTML wrapper differences), then content is identical
- Given all four legal documents, when running legal-compliance-auditor, then zero P1/P2 cross-document consistency findings

## Dependencies and Risks

- **Dependency:** PR #732 (merged) provides the foundation. This PR builds on that work.
- **Risk:** Scope creep into other legal documents (AUP, Cookie Policy, Disclaimer). These should NOT be modified unless the auditor flags a direct inconsistency.
- **Risk:** Over-engineering the Web Platform T&C sections. Keep minimal -- this is a beta with terms that will evolve. Focus on correcting false statements, not writing comprehensive SaaS terms.

## References and Research

### Internal References

- PR #732: `chore(ops+legal): record new services from web platform deployment` (merged 2026-03-18)
- Issue #670: `ops+legal: record new services from web platform deployment` (closed)
- Issue #703: `legal: update privacy policy, DPD, and GDPR policy for web platform` (open)
- Issue #736: `legal: update Terms & Conditions for web platform cloud services` (open)
- Learning: `knowledge-base/learnings/2026-03-18-legal-cross-document-audit-review-cycle.md`
- Plan: `knowledge-base/plans/2026-03-18-chore-vendor-ops-legal-web-platform-services-plan.md`

### Files to Modify

- `docs/legal/terms-and-conditions.md` (primary target)
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy sync)

### Files to Verify (read-only unless issues found)

- `docs/legal/privacy-policy.md`
- `docs/legal/data-protection-disclosure.md`
- `docs/legal/gdpr-policy.md`
- `plugins/soleur/docs/pages/legal/privacy-policy.md`
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- `plugins/soleur/docs/pages/legal/gdpr-policy.md`

### Agents

- `legal-document-generator` -- draft T&C updates
- `legal-compliance-auditor` -- post-edit cross-document audit
- `clo` -- orchestration if needed
