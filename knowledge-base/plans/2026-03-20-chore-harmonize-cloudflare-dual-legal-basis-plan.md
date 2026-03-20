---
title: "chore: harmonize Cloudflare dual legal basis across Privacy Policy and GDPR Policy"
type: fix
date: 2026-03-20
---

# chore: harmonize Cloudflare dual legal basis across Privacy Policy and GDPR Policy

## Overview

DPD Section 4.2 (the authoritative processor table) correctly states a dual legal basis for Cloudflare: contract performance (Article 6(1)(b)) for authenticated users, legitimate interest (Article 6(1)(f)) for unauthenticated traffic. Three companion locations in the DPD, GDPR Policy, and Privacy Policy still use blanket "contract performance" without this qualifier. This is a P3 precision fix -- no false statements exist, but the companion documents should match the processor table.

## Problem Statement

The dual-basis fix applied in #890 (PR #899) to DPD Section 4.2 made the asymmetry visible: three other locations describe Cloudflare-related processing under blanket "contract performance" without acknowledging that unauthenticated CDN/proxy traffic uses legitimate interest.

**Authoritative wording (DPD Section 4.2, line 152):**

> Contract performance (Article 6(1)(b)) for authenticated users; legitimate interest (Article 6(1)(f)) for unauthenticated traffic

## Proposed Solution

Apply 3 targeted edits to propagate the dual legal basis, then sync each change to the corresponding Eleventy mirror file.

### Edit 1: DPD Section 2.1b(d) -- blanket contract performance qualifier

**Source file:** `docs/legal/data-protection-disclosure.md` (line 72)
**Mirror file:** `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (line 81)

**Current (line 72):**

> **(d)** The legal basis for this processing is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the User signed up for.

**Proposed:**

> **(d)** The legal basis for this processing is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the User signed up for. For Cloudflare CDN/proxy processing of unauthenticated traffic (visitors who have not signed up), the legal basis is **legitimate interest** (Article 6(1)(f) GDPR) -- see Section 4.2 for the full dual-basis disclosure.

**Rationale:** Section 2.1b(d) describes legal basis for "this processing" (all Web Platform processing). Adding a qualifier for the Cloudflare edge case aligns it with Section 4.2 without restructuring the paragraph.

### Edit 2: GDPR Policy Section 3.7 -- add CDN/proxy bullet

**Source file:** `docs/legal/gdpr-policy.md` (lines 85-87)
**Mirror file:** `plugins/soleur/docs/pages/legal/gdpr-policy.md` (lines 94-96)

**Current:** Three bullets (account, payment, infrastructure) all under contract performance.

**Proposed:** Add a fourth bullet after the infrastructure bullet:

> - **CDN/proxy processing:** For authenticated users, the lawful basis is **contract performance** (Article 6(1)(b)) -- Cloudflare processes requests as part of delivering the Web Platform service. For unauthenticated traffic (visitors who have not signed up), the lawful basis is **legitimate interest** (Article 6(1)(f)) -- operating CDN and DDoS protection for `app.soleur.ai` is necessary for infrastructure security and service availability. Data processed: IP addresses, request headers, TLS termination data. Processed by Cloudflare (see DPD Section 4.2).

**Rationale:** Section 3.7 enumerates Web Platform processing activities with per-activity legal basis. Adding Cloudflare as a fourth activity matches the structure and eliminates the gap.

### Edit 3: Privacy Policy Section 6 -- add Cloudflare technical data mention

**Source file:** `docs/legal/privacy-policy.md` (line 186)
**Mirror file:** `plugins/soleur/docs/pages/legal/privacy-policy.md` (line 195)

**Current (line 186):**

> For the Web Platform (app.soleur.ai), the legal basis for processing account data, workspace data, and subscription data is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the user signed up for. For payment processing via Stripe, the legal basis is also contract performance -- processing is necessary to fulfill the subscription agreement.

**Proposed:**

> For the Web Platform (app.soleur.ai), the legal basis for processing account data, workspace data, and subscription data is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the user signed up for. For payment processing via Stripe, the legal basis is also contract performance -- processing is necessary to fulfill the subscription agreement. For technical data processed by Cloudflare (IP addresses, request headers -- see Section 5.8), the legal basis is contract performance for authenticated users and **legitimate interest** (Article 6(1)(f) GDPR) for unauthenticated traffic.

**Rationale:** Section 6 scopes legal basis by data category. Account/workspace/subscription data are correctly scoped to contract performance. Adding a sentence for Cloudflare's technical data processing explicitly covers the CDN/proxy edge case and cross-references Section 5.8 (which already describes Cloudflare's data processing).

## Mirror File Sync

Each edit must be applied to both the source file and its Eleventy mirror. The mirror files are in `plugins/soleur/docs/pages/legal/` and have different frontmatter (Eleventy `layout`/`permalink`/`description` vs. `type`/`jurisdiction`/`generated-date`) but identical body content.

**Mirror pairs:**

| Source | Mirror |
|--------|--------|
| `docs/legal/data-protection-disclosure.md` | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` |
| `docs/legal/gdpr-policy.md` | `plugins/soleur/docs/pages/legal/gdpr-policy.md` |
| `docs/legal/privacy-policy.md` | `plugins/soleur/docs/pages/legal/privacy-policy.md` |

## Acceptance Criteria

- [ ] DPD Section 2.1b(d) includes Cloudflare unauthenticated traffic qualifier with cross-reference to Section 4.2
- [ ] GDPR Policy Section 3.7 has a fourth bullet for CDN/proxy processing with dual legal basis
- [ ] Privacy Policy Section 6 mentions Cloudflare technical data processing with dual legal basis and cross-references Section 5.8
- [ ] All three edits are mirrored to `plugins/soleur/docs/pages/legal/` counterparts
- [ ] `grep -c "legitimate interest" docs/legal/data-protection-disclosure.md` count increases by 1
- [ ] `grep -c "legitimate interest" docs/legal/gdpr-policy.md` count increases by 1
- [ ] `grep -c "legitimate interest" docs/legal/privacy-policy.md` count increases by 1
- [ ] No conflict markers in any edited file
- [ ] "Last Updated" dates on DPD frontmatter updated to reflect this change

## Test Scenarios

- Given the DPD Section 4.2 processor table states dual legal basis for Cloudflare, when reading DPD Section 2.1b(d), then it should reference the same dual basis
- Given GDPR Policy Section 3.7 lists Web Platform processing activities, when reading the section, then CDN/proxy processing should appear as a separate bullet with dual basis
- Given Privacy Policy Section 6 describes legal bases by data category, when reading the section, then Cloudflare technical data should be explicitly mentioned with dual basis

## Context

- **Origin:** #912, identified during cross-document review of PR #899 (resolving #890)
- **Severity:** P3 -- the DPD Section 4.2 table is the authoritative processor-level disclosure, so no legal risk
- **Related PRs:** #899 (cross-document audit), #890 (original findings)
- **Related plan:** `2026-03-20-chore-legal-cross-document-audit-findings-plan.md` (Finding 6 in that plan specifically identified this issue)

## References

- DPD Section 4.2 processor table (authoritative dual-basis wording): `docs/legal/data-protection-disclosure.md:152`
- DPD Section 2.1b(d): `docs/legal/data-protection-disclosure.md:72`
- GDPR Policy Section 3.7: `docs/legal/gdpr-policy.md:85-87`
- Privacy Policy Section 6: `docs/legal/privacy-policy.md:186`
- Issue: #912
