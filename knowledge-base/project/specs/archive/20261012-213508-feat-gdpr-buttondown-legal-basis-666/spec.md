# Spec: Clarify Legal Basis for Buttondown Data (#666)

**Date:** 2026-03-18
**Issue:** #666
**Branch:** feat/gdpr-buttondown-legal-basis-666
**Priority:** P1 (High)

## Problem Statement

Privacy Policy Section 4.6, GDPR Policy Section 3.6, and DPA Section 2.3(e) all claim consent (Art 6(1)(a)) as the sole lawful basis for Buttondown newsletter data and state "email address only" as the data collected. Buttondown automatically collects additional data (IP address, referrer URL, subscription timestamp, browser/device metadata) that is neither disclosed nor assigned a correct legal basis.

## Goals

- G1: Disclose all data types collected by Buttondown during newsletter subscription
- G2: Assign correct lawful basis per data type (consent for email, legitimate interest for HTTP metadata)
- G3: Add balancing test for legitimate interest on newsletter metadata
- G4: Add explicit Art 21 right-to-object mention for newsletter metadata in Privacy Policy Section 8.1
- G5: Maintain cross-document consistency across all 5 files

## Non-Goals

- Email open/click tracking disclosure (Buttondown tracking is opt-in, not enabled)
- Buttondown DPA negotiation (separate concern)
- Signup form UI changes (disclosure is in privacy policy, not the form)

## Functional Requirements

- FR1: Privacy Policy Section 4.6 — expand "Data collected" to list all types with collection method; split lawful basis
- FR2: Privacy Policy Section 6 — update newsletter legal basis paragraph to reflect split
- FR3: Privacy Policy Section 8.1 — add Art 21 right-to-object for newsletter metadata
- FR4: GDPR Policy Section 3.6 — update lawful basis with split and add balancing test
- FR5: GDPR Policy Section 4.2 table — update Buttondown row with full data types
- FR6: GDPR Policy Section 10 processing register (activity #6) — update data types and bases
- FR7: DPA Section 2.3(e) — update newsletter processing description with complete data types and split basis
- FR8: Both copies of Privacy Policy and GDPR Policy must be updated identically (docs/legal/ and plugins/soleur/docs/pages/legal/)

## Technical Requirements

- TR1: All 5 files updated in a single commit for atomicity
- TR2: Grep verification across all legal docs for consistency (per learnings pattern)
- TR3: "Last Updated" date changed to 2026-03-18 with "(newsletter legal basis clarification)" note

## Files to Modify

| File | Sections |
|------|----------|
| `docs/legal/privacy-policy.md` | 4.6, 6, 8.1 |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 4.6, 6, 8.1 |
| `docs/legal/gdpr-policy.md` | 3.6, 4.2 table, 10 register |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 3.6, 4.2 table, 10 register |
| `docs/legal/data-protection-disclosure.md` | 2.3(e) |
