---
title: "Verify GitHub Data Protection Agreement Acceptance"
type: legal
date: 2026-02-21
issue: "#203"
---

# Verify GitHub Data Protection Agreement Acceptance

## Overview

Verify whether Jikigai has accepted GitHub's Data Protection Agreement (DPA) for GDPR Article 28 compliance, given that GitHub Pages hosts soleur.ai and GitHub acts as a data processor.

## Problem Statement

The GDPR Article 30 compliance audit (#187, resolved in #200) identified an outstanding action item: "Verify GitHub DPA -- Confirm Jikigai has accepted GitHub's Data Protection Agreement." The GDPR policy (Section 2.2) already references the GitHub DPA, but this reference has not been validated against reality.

## Research Findings

### Critical Discovery: DPA Scope Limitation

GitHub's formal Data Protection Agreement (DPA) is **only available to corporate accounts** that sign the corporate terms of service:

- **Covered:** GitHub Enterprise Cloud, GitHub Enterprise (Unified), GitHub Teams, GitHub Copilot
- **NOT covered:** Free-tier organizations and individual accounts

**Jikigai's plan:** Free Organization (1 seat). This means the formal GitHub DPA does **not** apply.

### What Free-Plan Users Get Instead

GitHub's Privacy Statement + Terms of Service serve as the data protection framework for free accounts:

- GitHub acknowledges its role as processor when organizations provide accounts (Privacy Statement)
- GitHub is certified under the EU-US Data Privacy Framework (adequacy decision C(2023) 4745)
- GitHub maintains Standard Contractual Clauses as supplementary safeguard
- GitHub uses sub-processors bound by contractual obligations

### Community Confirmation

GitHub Community Discussion #22277 confirms: "GDPR support (including Data Protection Agreement) is available for corporate accounts that sign the corporate terms of service." No viable workaround exists for free-tier users needing formal Article 28 DPA coverage.

### Current GDPR Policy Inaccuracy

The GDPR policy (Section 2.2, line 42) states GitHub's processing is "governed by the GitHub Data Protection Agreement." This is technically inaccurate -- Jikigai on the free plan is not covered by that DPA. The processing is governed by GitHub's Terms of Service and Privacy Statement.

## Proposed Solution

### Phase 1: Document DPA Status

1. Create a DPA verification memo documenting the research findings
2. Record the DPA status in the Article 30 register context

### Phase 2: Update Legal Documents

1. Update GDPR policy Section 2.2 to accurately reflect that:
   - Jikigai is on GitHub's free plan
   - The formal GitHub DPA does not apply
   - GitHub's processing is governed by the GitHub Terms of Service and GitHub Privacy Statement
   - GitHub's Privacy Statement acknowledges processor obligations and GDPR compliance
   - The EU-US Data Privacy Framework provides the international transfer mechanism
2. Sync changes to both legal document locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`)

### Phase 3: Risk Assessment and Recommendation

Document the compliance gap and present options to counsel:

1. **Accept current posture (recommended for now):** GitHub's ToS + Privacy Statement provide substantive GDPR protections even without the formal DPA. The processing is minimal (web server logs for a documentation site). Risk is low.
2. **Upgrade to GitHub Teams ($4/user/month):** Provides access to the formal DPA. Eliminates the compliance gap entirely.
3. **Alternative hosting:** Move docs to a provider with DPA coverage on free plans.

## Acceptance Criteria

- [x] GDPR policy Section 2.2 accurately reflects DPA status for free-plan accounts
- [x] Both legal document locations updated in sync (`docs/legal/` and `plugins/soleur/docs/pages/legal/`)
- [x] DPA verification findings documented for the Article 30 register
- [x] Counsel recommendations clearly stated with risk assessment
- [x] Issue #203 acceptance criteria addressed

## Test Scenarios

- Given the GDPR policy references GitHub's DPA, when a reader checks the referenced DPA, then the policy text accurately describes the applicable terms (not the formal DPA which does not cover free plans)
- Given the legal documents exist in two locations, when changes are made, then both locations are identical
- Given the audit report flagged "Verify GitHub DPA," when this task completes, then the verification result is documented with clear next steps

## Non-Goals

- Upgrading to a paid GitHub plan (decision for counsel, not this task)
- Changing hosting providers
- Rewriting the entire GDPR policy
- Modifying the Article 30 register template (private document)

## References

- Issue #203: https://github.com/jikig-ai/soleur/issues/203
- Prior audit: #187 (resolved in #200, commit db2f89f)
- GitHub DPA: https://github.com/customer-terms/github-data-protection-agreement
- GitHub Privacy Statement: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement
- GitHub Community Discussion #22277: https://github.com/orgs/community/discussions/22277
- Audit report: `knowledge-base/specs/archive/20260221-044654-feat-cnil-article-30/audit-report.md`
- GDPR policy: `docs/legal/gdpr-policy.md`
- Constitution: Legal documents exist in two locations and must be synced
