---
title: "GDPR Article 30: Email Provider Documentation Pattern"
category: integration-issues
tags: [gdpr, article-30, dpa, email-provider, proton-mail, legal-compliance]
module: legal-agents
problem_type: documentation-gap
date: 2026-02-21
---

# GDPR Article 30: Email Provider Documentation Pattern

## Problem

The Article 30 register had placeholder values ("fournisseur email") for the email provider handling GDPR inquiries. Updating required identifying the provider, verifying DPA status, and propagating changes across multiple legal documents that must stay in sync.

## Solution

1. **Identify provider via DNS**: `dig MX jikigai.com +short` confirmed Proton Mail (mail.protonmail.ch).
2. **Verify DPA**: Proton's DPA at proton.me/legal/dpa applies to "any business or organization regardless of legal form" and is automatically accepted via Terms and Conditions.
3. **Document transfer mechanism**: Switzerland has EU adequacy decision (Commission Decision 2000/518/CE). Germany (where Proton also stores data) is EU -- does NOT belong in "Transferts hors UE".
4. **Update all locations**: Article 30 register, GDPR policy (both sync locations), audit report.

## Key Insights

### EU vs non-EU transfer distinction matters

When documenting data storage in the Article 30 register's "Transferts hors UE" field, only list countries that are actually outside the EU/EEA. Switzerland requires a transfer justification (adequacy decision). Germany does not -- it is an EU member state. Listing EU countries in the non-EU transfer field is structurally incoherent under Article 46 GDPR.

Correct pattern: "Suisse (decision d'adequation CE 2000/518/CE); donnees stockees en Suisse et dans l'UE (Allemagne)"

### Cross-document consistency requires checking ALL sections

When naming a new processor in legal documents, check ALL sections that reference it -- not just the section you're primarily updating. In this case, adding Proton to the breach notification section (11.2) also required adding it to the third-party data table (Section 4.2). Review agents caught this; manual editing would have missed it.

### Proton DPA applies broadly

Proton's DPA is not limited to business/enterprise accounts. It applies to "any business or organization using the Services, regardless of its legal form" and is incorporated by reference into the standard Terms and Conditions. This reduces the risk assessment for account-tier uncertainty.

## Session Errors

- Edit tool requires reading files before editing -- attempted an edit without prior read
- "Transferts hors UE" field initially included Germany (EU member) -- structural legal error caught by review
- Third-party data table in GDPR policy Section 4.2 was missed in initial implementation -- caught by code-simplicity-reviewer

## Prevention

- When updating Article 30 registers, grep for ALL references to the entity being documented across all legal files
- Use review agents even for documentation-only changes -- they catch cross-document consistency gaps
- For "Transferts hors UE" fields, explicitly verify whether each country is EU/EEA before listing

## References

- Issue #204
- PR #200 (GDPR Article 30 compliance fixes)
- Proton DPA: https://proton.me/legal/dpa
- EU adequacy decision for Switzerland: Commission Decision 2000/518/EC
