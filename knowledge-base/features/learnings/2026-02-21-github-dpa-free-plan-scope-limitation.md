---
title: "GitHub DPA Only Covers Paid Plans"
category: integration-issues
module: legal-agents
severity: medium
tags: [gdpr, dpa, github-pages, article-28, legal-compliance]
date: 2026-02-21
---

# Learning: GitHub DPA Only Covers Paid Plans

## Problem

The GDPR Article 30 compliance audit (#187, resolved in #200) added a reference to the GitHub Data Protection Agreement (DPA) in the GDPR policy, assuming it governed GitHub's processing of data for GitHub Pages hosting. The audit flagged "Verify GitHub DPA acceptance" as an outstanding action item.

## Investigation

1. Fetched the GitHub DPA page at `github.com/customer-terms/github-data-protection-agreement` -- the DPA is a PDF download, not inline text
2. Checked GitHub customer-terms page -- DPA listed under "Additional Terms" for Enterprise Cloud, Teams, and Copilot only
3. Found GitHub Community Discussion #22277 confirming: "GDPR support (including Data Protection Agreement) is available for corporate accounts that sign the corporate terms of service"
4. Verified Jikigai's plan via `gh api /orgs/jikig-ai` -- free Organization plan (1 seat)
5. Reviewed GitHub's Privacy Statement -- it acknowledges processor obligations and GDPR compliance for all accounts

## Root Cause

GitHub's formal DPA is only available to paid plans (Enterprise Cloud, Enterprise Unified, Teams, Copilot). Free-tier organizations are not covered. The GDPR policy incorrectly referenced the DPA as governing GitHub's processing.

## Solution

Updated GDPR policy Section 2.2 to accurately describe that:
- GitHub's processing is governed by the GitHub Terms of Service and GitHub Privacy Statement (not the formal DPA)
- The formal DPA applies to paid plans only
- GitHub's standard terms acknowledge processor obligations and maintain EU-US DPF certification and SCCs

Both legal document locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`) were updated in sync.

## Key Insight

When referencing third-party data protection agreements in legal documents, verify the scope of applicability for your specific plan tier. GitHub's DPA ecosystem has a clear tier boundary: free plans get ToS + Privacy Statement; paid plans get the formal DPA. This distinction matters for Article 28 compliance because the formal DPA contains explicit processor obligations that the Privacy Statement covers more generally.

## Prevention

- Before referencing a third-party DPA in legal documents, verify the organization's plan tier covers it
- Check community forums and official documentation for plan-specific limitations
- When the legal-compliance-auditor flags "verify DPA," treat it as a research task requiring plan-tier verification, not just a link check

## Session Errors

- WebFetch for `livingaide.com` article returned 404 (dead link from search results)
- GitHub DPA page content not extractable via WebFetch (PDF download behind a link page)
- GitHub privacy policies docs page returned an index, not the actual privacy statement (needed to navigate to the specific sub-page)
- First `worktree-manager.sh` invocation output was suppressed; required retry

## References

- Issue: #203
- Prior audit: #187 (resolved in #200)
- GitHub DPA: https://github.com/customer-terms/github-data-protection-agreement
- GitHub Community Discussion: https://github.com/orgs/community/discussions/22277
- GitHub Privacy Statement: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement
