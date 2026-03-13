---
title: "legal: Clarify email provider DPA for legal@jikigai.com"
type: feat
date: 2026-02-21
issue: "#204"
deepened: 2026-02-21
---

# Clarify Email Provider DPA for legal@jikigai.com

## Enhancement Summary

**Deepened on:** 2026-02-21
**Key improvements:**
1. DNS verification confirmed Proton Mail (MX: mail.protonmail.ch, mailsec.protonmail.ch)
2. Proton DPA verified -- applies to "any business or organization regardless of legal form" (reduces account-tier risk)
3. Proton AG legal entity confirmed: CHE-354.686.492, Route de la Galaise 32, 1228 Plan-les-Ouates, Switzerland
4. Exact file locations and line numbers identified for all replacements

## Overview

Identify the email provider for legal@jikigai.com, verify DPA status under GDPR Article 28, document international transfer mechanisms, and update the Article 30 register (Treatment N.3) with concrete provider details replacing current placeholders.

## Problem Statement

The GDPR Article 30 compliance audit (#187, resolved in #200) identified that Treatment N.3 (legal inquiry handling via legal@jikigai.com) has placeholder values for the email provider. The register currently says "fournisseur email" and "Selon fournisseur email" -- these must be replaced with the actual provider identity, DPA reference, and transfer mechanism.

## Proposed Solution

1. Confirm the email provider via DNS MX lookup (preliminary research indicates Proton Mail / Proton AG, Geneva, Switzerland)
2. Document Proton's DPA terms and data residency
3. Update the Article 30 register template with concrete values
4. Update GDPR policy references from generic "the email provider" to named provider
5. Sync all changes across both legal document locations

## Technical Approach

### Phase 1: Verify Provider

```bash
dig MX jikigai.com +short
dig TXT jikigai.com +short  # Check SPF for provider confirmation
```

**Verified result:**
- MX: `10 mail.protonmail.ch.` and `20 mailsec.protonmail.ch.`
- Provider: Proton Mail (Proton AG, Geneva, Switzerland)
- Legal entity: Proton AG, Route de la Galaise 32, 1228 Plan-les-Ouates, Switzerland (CHE-354.686.492)
- DPA: https://proton.me/legal/dpa -- applies to "any business or organization using the Services, regardless of its legal form"; automatically accepted as part of Proton's Terms and Conditions
- Data residency: Switzerland, EU, and adequacy-decision countries only
- Transfer mechanism: SCCs for any transfers outside CH/EU/adequacy countries
- Switzerland adequacy: Commission Decision 2000/518/EC

### Phase 2: Update Documents

**Task 2.1: Update Article 30 register Treatment N.3**

File: `knowledge-base/specs/archive/20260221-044654-feat-cnil-article-30/article-30-register-template.md`

Replace placeholder values and fill `[DATE]` placeholders with `2026-02-21`:

| Field | Current Value | New Value |
|-------|--------------|-----------|
| Destinataires | "fournisseur email" | "Proton AG (Proton Mail)" |
| Transferts hors UE | "Selon fournisseur email pour legal@jikigai.com" | "Suisse (decision d'adequation CE 2000/518/CE); donnees chiffrees stockees en Suisse et Allemagne" |
| Sous-traitant (if field exists) | N/A | "Proton AG, Route de la Galaise 32, 1228 Plan-les-Ouates, Geneve, Suisse" |

**Task 2.2: Update GDPR policy in both locations**

In Section 11.2 (breach notification scenario) of both `docs/legal/gdpr-policy.md` and `plugins/soleur/docs/pages/legal/gdpr-policy.md`, replace "the email provider handling legal@jikigai.com" with "Proton AG (Proton Mail), the email provider handling legal@jikigai.com". Keep generic phrasing in other sections.

**Task 2.3: Mark audit recommendation as resolved**

File: `knowledge-base/specs/archive/20260221-044654-feat-cnil-article-30/audit-report.md`

Update Recommendation 3 ("Clarify email provider") status to resolved with a reference to this PR.

## Acceptance Criteria

- [ ] Email provider confirmed as Proton Mail (Proton AG) via DNS MX records
- [ ] Proton's DPA terms documented (link to https://proton.me/legal/dpa)
- [ ] Switzerland adequacy decision referenced (2000/518/EC)
- [ ] Article 30 register Treatment N.3 updated with provider details
- [ ] GDPR policy Section 11.2 updated in both locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`)
- [ ] Audit report recommendation 3 marked as resolved

## Non-Goals

- Verifying whether the Proton account is business vs. consumer tier (operational task requiring admin access -- flagged as follow-up if DPA requires business tier)
- Fixing the `data-processing-agreement.md` vs `data-protection-disclosure.md` naming mismatch between sync locations (pre-existing issue, separate scope)

## Dependencies and Risks

- **Risk: Account tier uncertainty (mitigated).** Proton's DPA applies to "any business or organization using the Services, regardless of its legal form" and is automatically accepted as part of the Terms and Conditions. This reduces the risk that a consumer-tier account lacks DPA coverage, though confirming the account type remains good practice.
- **Risk: Worktree conflicts.** Three related worktrees (`feat-legal-email-dpa`, `feat-article-30-register`, `feat-github-dpa-verify`) may touch overlapping files. Mitigation: This branch merges first; others rebase after.
- **Dual-location sync.** Both `docs/legal/` and `plugins/soleur/docs/pages/legal/` must be updated. Use grep to verify consistency post-edit.

## Version Bump

PATCH bump (documentation update to existing legal files under `plugins/soleur/`).

## References

- Issue #204: Clarify email provider DPA for legal@jikigai.com
- Issue #187: CNIL registration check (original audit)
- PR #200: GDPR Article 30 compliance fixes (v2.23.4)
- Proton DPA: https://proton.me/legal/dpa
- EU adequacy decision for Switzerland: Commission Decision 2000/518/EC
- Article 30 register template: `knowledge-base/specs/archive/20260221-044654-feat-cnil-article-30/article-30-register-template.md`
