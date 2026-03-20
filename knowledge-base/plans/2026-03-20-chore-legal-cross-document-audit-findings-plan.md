---
title: "chore: resolve pre-existing legal audit findings from cross-document review"
type: fix
date: 2026-03-20
---

# chore: resolve pre-existing legal audit findings from cross-document review

## Overview

Cross-document audit during #736 identified 6 P2 and 1 P3 finding across the Privacy Policy, Data Protection Disclosure (DPD), and GDPR Policy. All findings are consistency gaps -- scopes, headings, or placements that became stale when the Web Platform was introduced. No false statements exist; the documents simply need alignment with each other and with the T&C (already updated in #880).

## Problem Statement

The Web Platform (app.soleur.ai) was added to the T&C in #880, and prior PRs (#732, #736) updated the DPD and GDPR Policy with Web Platform processor tables, data processing sections, and transfer mechanisms. However, several sections in the Privacy Policy, DPD, and GDPR Policy were not updated to reflect the expanded scope. These consistency gaps could confuse users or raise questions during a regulatory audit.

## Proposed Solution

Apply 7 targeted edits across 3 legal documents. Each edit is a text substitution or addition -- no structural reorganization required.

## Findings and Fixes

### Finding 1 (P2): Privacy Policy Section 1 intro omits Web Platform from scope

**File:** `docs/legal/privacy-policy.md`
**Section:** 1. Introduction (line 15)
**Current:** Scope defined as "the Plugin" and "the Docs Site" only.
**Fix:** Add "and the Soleur Web Platform at app.soleur.ai" to the introductory sentence, after "the Docs Site". The phrase should read:

> ...handles information in connection with the Soleur Company-as-a-Service platform ("the Plugin"), a Claude Code plugin providing agents, skills, commands, and a knowledge base for structured software development workflows, the Soleur documentation website located at soleur.ai ("the Docs Site"), and the Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) ("the Web Platform").

**Note:** Section 4.7 already covers Web Platform data, so the intro just needs the scope addition.

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

### Finding 3 (P2): DPD Section 3.1 heading "Local-Only Architecture" is misleading

**File:** `docs/legal/data-protection-disclosure.md`
**Section:** 3.1 (line 106)
**Current heading:** `### 3.1 Local-Only Architecture`
**Fix:** Rename to `### 3.1 Plugin Architecture (Local-Only)` to clarify this section describes the Plugin only, since the DPD now also describes Web Platform cloud processing in other sections.

### Finding 4 (P2): GDPR Policy Section 1 second paragraph omits Web Platform

**File:** `docs/legal/gdpr-policy.md`
**Section:** 1. Introduction, second paragraph (line 21)
**Current:** "This policy applies to all individuals located in the European Economic Area ('EEA') who use or interact with Soleur, including the plugin software, documentation site, and GitHub repository."
**Fix:** Add "Web Platform (app.soleur.ai)," to the enumeration:

> This policy applies to all individuals located in the European Economic Area ("EEA") who use or interact with Soleur, including the plugin software, Web Platform (app.soleur.ai), documentation site, and GitHub repository.

### Finding 5 (P2): DPD Section 4.3 Buttondown placement error

**File:** `docs/legal/data-protection-disclosure.md`
**Section:** 4.3 Third-Party Services Used by Users (lines 156-167)
**Current:** Buttondown appears in the "Third-Party Services Used by Users" table (Section 4.3) with a description saying it "acts as data processor on behalf of Jikigai." This contradicts its placement -- services in 4.3 are described as "initiated and controlled by the User, not by Soleur."
**Fix:** Remove the Buttondown row from the Section 4.3 table. Buttondown is already correctly listed in Section 4.2 ("Service Processors") in the "Docs Site and Newsletter Processors" table. No content needs to be added elsewhere.

### Finding 6 (P2): Cloudflare legal basis in DPD

**File:** `docs/legal/data-protection-disclosure.md`
**Section:** 4.2 Service Processors, Web Platform Processors table (line 152)
**Current:** Cloudflare's legal basis is listed as "Contract performance (Article 6(1)(b))" in the Web Platform Processors table.
**Problem:** For unauthenticated visitors hitting the Cloudflare CDN/proxy, there is no contract in place. Contract performance only applies to authenticated Web Platform users who accepted the T&C.
**Fix:** Change Cloudflare's legal basis to "Contract performance (Article 6(1)(b)) for authenticated users; legitimate interest (Article 6(1)(f)) for unauthenticated traffic". This mirrors the dual-basis approach already used for GitHub Pages in the Docs Site processors table. The GDPR Policy Section 2.1 already mentions Cloudflare under Web Platform context, so a matching update there is not needed (the GDPR Policy references the DPD processor table).

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

## Acceptance Criteria

- [ ] Privacy Policy Section 1 intro enumerates Plugin, Docs Site, and Web Platform
- [ ] Privacy Policy Section 11 describes Web Platform security measures (AES-256-GCM, TLS, EU-only hosting, PCI SAQ-A, bcrypt)
- [ ] DPD Section 3.1 heading reads "Plugin Architecture (Local-Only)"
- [ ] GDPR Policy Section 1 second paragraph includes "Web Platform (app.soleur.ai)" in the scope list
- [ ] DPD Section 4.3 table does not contain a Buttondown row
- [ ] DPD Section 4.2 Cloudflare row uses dual legal basis (contract performance + legitimate interest)
- [ ] DPD Section 10.3 exists with Web Platform account deletion procedure cross-referencing T&C Section 13.1b
- [ ] All "Last Updated" dates bumped to today's date with change descriptions
- [ ] No cross-document references are broken by the edits
- [ ] `docs/` page copies match source (if the site pages are separate files)

## Test Scenarios

- Given a reader of Privacy Policy Section 1, when they read the intro, then the Web Platform is listed as part of the scope
- Given a reader of Privacy Policy Section 11, when they look for Web Platform security measures, then AES-256-GCM, TLS, EU-only hosting, and PCI SAQ-A are described
- Given a reader of DPD Section 3.1, when they see the heading, then it clearly indicates the section covers Plugin architecture only
- Given a reader of GDPR Policy Section 1, when they read the scope, then the Web Platform is enumerated alongside plugin, docs site, and repository
- Given a reader of DPD Section 4.3, when they scan the "Third-Party Services Used by Users" table, then Buttondown does not appear (it is correctly in Section 4.2)
- Given a reader of DPD Section 4.2, when they check Cloudflare's legal basis, then both contract performance and legitimate interest are listed with applicability conditions
- Given a reader of DPD Section 10, when they look for Web Platform account deletion, then Section 10.3 describes the procedure with a cross-reference to T&C Section 13.1b

## Context

- **Parent issue:** #890
- **Origin:** Cross-document audit during #736
- **Related PRs:** #732 (initial legal docs), #736 (Web Platform DPD update), #880 (T&C Web Platform update)
- **Documents affected:**
  - `docs/legal/privacy-policy.md` (Findings 1, 2)
  - `docs/legal/data-protection-disclosure.md` (Findings 3, 5, 6, 7)
  - `docs/legal/gdpr-policy.md` (Finding 4)
- **Mirror files:** Check if `plugins/soleur/docs/pages/legal/` contains copies that also need updating

## MVP

No code changes. All fixes are text edits to existing legal markdown documents. Each finding maps to a single, well-scoped text substitution or addition.

### Implementation Order

1. Findings 1, 2 -- Privacy Policy (edit intro, add security paragraph)
2. Findings 3, 5, 6, 7 -- DPD (rename heading, remove Buttondown row, fix Cloudflare basis, add Section 10.3)
3. Finding 4 -- GDPR Policy (add Web Platform to scope)
4. Update "Last Updated" dates on all 3 documents
5. Sync mirror files in `plugins/soleur/docs/pages/legal/` if they differ from `docs/legal/`

## References

- Issue: #890
- PR #732: Initial legal document suite
- PR #736: Web Platform DPD updates
- PR #880: T&C Web Platform update
- T&C Section 13.1b: Web Platform account deletion procedure
- DPD Section 8.1(c): Web Platform security measures (source for Finding 2 fix)
