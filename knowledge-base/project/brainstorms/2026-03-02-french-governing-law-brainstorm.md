# Brainstorm: Change Governing Law from Delaware to France

**Date:** 2026-03-02
**Status:** Complete
**Branch:** feat-french-governing-law

## What We're Building

Replacing all Delaware governing law references in Soleur's legal documents with French law / Paris courts jurisdiction, aligning the entire legal suite with the company's actual incorporation in France.

## Why This Approach

- Jikigai is incorporated in France (25 rue de Ponthieu, 75008 Paris)
- CLAs already use French law / Paris courts -- T&Cs and Disclaimer are the outliers
- Delaware governing law was inherited from a US-centric template (Stripe Atlas benchmark mismatch)
- French law is the natural jurisdiction where CNIL enforcement occurs and where the Article 30 register is maintained
- Standard SaaS practice: service provider's jurisdiction governs (Stripe uses Ireland, GitHub uses California)

## Key Decisions

1. **Uniform French law for all users worldwide** -- no tiered US/EU/Other structure. A mandatory-law savings clause preserves EU consumers' local protections automatically (Rome I Art. 6, Brussels I Recast Art. 18).

2. **Courts of Paris** (Tribunal judiciaire de Paris) as the dispute venue -- matches registered address and CLA precedent.

3. **30-day amicable resolution period** before court proceedings -- standard in French commercial contracts.

4. **Mandatory-law savings clause** -- "Nothing in these Terms deprives you of the protection afforded by mandatory provisions of the law of your country of habitual residence."

## Scope of Changes

### Documents requiring changes (Delaware -> France):

| Document | Sections | Files (x2 locations) |
|----------|----------|---------------------|
| Terms & Conditions | 14.1 (US Users), 14.3 (Other Users) | `docs/legal/terms-and-conditions.md` + `plugins/soleur/docs/pages/legal/terms-and-conditions.md` |
| Disclaimer | 8.2 (US Users), 8.3 (Other Users) | `docs/legal/disclaimer.md` + `plugins/soleur/docs/pages/legal/disclaimer.md` |

### Documents already aligned (no change needed):

- Individual CLA (Section 7a): France / Paris courts
- Corporate CLA (Section 7a): France / Paris courts
- Data Processing Disclosure (Section 11): EU Member State law (GDPR-mandated)

### Documents to review for consistency:

- Privacy Policy, GDPR Policy, Cookie Policy, Acceptable Use Policy (no explicit governing law sections)

## CLO Assessment Notes

- French unfair terms doctrine (Code civil Art. 1171) is stricter than Delaware -- existing blanket warranty exclusion (Section 9), liability cap (Section 10), and indemnification (Section 11) should be reviewed for enforceability
- CNIL becomes unambiguously the lead supervisory authority (already effectively the case)
- Practical litigation risk is low for a free product
- Existing user transition: follow Section 12 procedure (post changes to GitHub, 30 days advance notice for EU/EEA)

## Open Questions

1. Should governing law clauses be added to Privacy Policy, GDPR Policy, Cookie Policy, and AUP for completeness?
2. Should existing clauses (Sections 9, 10, 11 of T&Cs) be reviewed for enforceability under French consumer law in this same pass or as a follow-up?
3. User notification plan for the material change (Section 12 compliance)
