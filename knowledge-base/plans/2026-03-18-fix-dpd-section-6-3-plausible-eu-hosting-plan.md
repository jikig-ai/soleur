---
title: "fix: DPD Section 6.3 should mention Plausible Analytics EU-only hosting"
type: fix
date: 2026-03-18
semver: patch
---

# fix: DPD Section 6.3 should mention Plausible Analytics EU-only hosting

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 4 (Proposed Solution, Proposed Text, Acceptance Criteria, Test Scenarios)
**Research sources:** Plausible data policy (plausible.io/data-policy), Plausible DPA (plausible.io/dpa), 2 institutional learnings, cross-document audit of all 5 legal docs

### Key Improvements

1. Verified Plausible hosting claims against live DPA and data policy -- confirmed Hetzner (Germany) and BunnyWay (Slovenia), both EU-owned companies
2. Audited all 5 legal documents for Plausible references -- confirmed Cookie Policy and GDPR Policy need no changes (Cookie Policy has no transfers section; GDPR Policy already handles Plausible correctly)
3. Applied cross-section consistency learning -- verified no additional sections reference Plausible in an international transfer context beyond those already identified

### New Considerations Discovered

- Plausible DPA explicitly states "visitor data never leaves the EU and EU-owned cloud infrastructure" -- stronger than just "hosted in Germany"
- Plausible is incorporated in Estonia (EU) -- relevant for controller jurisdiction but not needed in the transfer disclosure
- Both Plausible sub-processors (Hetzner, BunnyWay) are EU-incorporated companies -- no Schrems II risk at any layer

## Overview

DPD Section 6.3 (International Data Transfers -- Docs Site) mentions GitHub Pages but omits Plausible Analytics. Plausible is EU-hosted (Hetzner, Germany; BunnyWay, Slovenia) with no international data transfers. Adding an explicit statement strengthens transparency without changing any compliance posture.

Related: #700 (this issue), #697 (PR where the gap was discovered), #693 (parent audit PR).

## Problem Statement

Section 6.3 currently reads:

> The Docs Site is hosted on GitHub Pages, which may involve data processing in the United States and other jurisdictions where GitHub operates. GitHub maintains appropriate transfer mechanisms as described in its data processing agreements.

Plausible Analytics is a documented Docs Site processor (Section 4.2) but is not mentioned in the international transfers section. While this is not a compliance violation (no transfer occurs), explicitly stating EU-only hosting is best practice for GDPR Article 44 transparency.

### Research Insights

**Verified hosting claims (2026-03-18):**

- Plausible data policy confirms: "Your website data never leaves the EU"
- Primary hosting: Hetzner Online GmbH (Falkenstein, Germany) -- EU-owned
- CDN and DDoS: BunnyWay d.o.o. (Slovenia) -- EU-owned
- Legal entity: Incorporated in Estonia (EU)
- DPA states: "visitor data never leaves the EU and EU-owned cloud infrastructure"
- SCCs signed with all vendors as supplementary safeguard

**Cross-document audit (all 5 legal docs):**

| Document | Plausible mentioned? | International transfers section? | Change needed? |
|----------|---------------------|--------------------------------|----------------|
| DPD (`data-processing-agreement.md`) | Yes (Section 2.3(a), 4.2) | Yes (Section 6.3) -- missing Plausible | **Yes** |
| Privacy Policy (`privacy-policy.md`) | Yes (Section 4.3, 6) | Yes (Section 10) -- missing Plausible | **Yes** |
| GDPR Policy (`gdpr-policy.md`) | Yes (Section 3.2, 4.3, 8 register) | Yes (Section 6) -- correctly omits Plausible (lists transfers only) | No |
| Cookie Policy (`cookie-policy.md`) | Yes (Section 3.2, 4.2) | No transfers section | No |

## Proposed Solution

Add a sentence to Section 6.3 in both DPD file copies confirming Plausible processes all data within the EU. Also add a corresponding sentence to the Privacy Policy (Section 10) for cross-document consistency. No changes to GDPR Policy or Cookie Policy.

### Files to modify (4 files, dual-file sync)

| File | Section | Change |
|------|---------|--------|
| `docs/legal/data-processing-agreement.md` | 6.3 Docs Site | Add Plausible EU-only hosting sentence |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 6.3 Docs Site | Add Plausible EU-only hosting sentence (identical content) |
| `docs/legal/privacy-policy.md` | 10. International Data Transfers | Add Plausible EU-only paragraph |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 10. International Data Transfers | Add Plausible EU-only paragraph (identical content) |

### Why NOT the GDPR Policy

GDPR Policy Section 6 already lists only services that perform international transfers (Anthropic, GitHub, Buttondown). Plausible is correctly absent because it does not transfer data internationally. The Article 30 register (Section 8) already states "Plausible Analytics is hosted in the EU." No GDPR Policy change is needed.

### Why NOT the Cookie Policy

The Cookie Policy describes cookie usage and tracking technologies. It has no "International Data Transfers" section. Plausible is already correctly described as cookie-free in Section 3.2 and 4.2. No change needed.

### Proposed text

**DPD Section 6.3** -- append after the existing GitHub Pages paragraph:

> Plausible Analytics, used for privacy-respecting website analytics on the Docs Site (see Section 4.2), processes all data exclusively within the European Union (Hetzner, Germany). No international data transfers occur for analytics data.

**Privacy Policy Section 10** -- append after the Buttondown paragraph:

> Plausible Analytics, used for Docs Site analytics (see Section 4.3), processes all data exclusively within the European Union (Hetzner, Germany). No international data transfers occur for analytics data. See [Plausible's Data Policy](https://plausible.io/data-policy) for details.

### Research Insights on Proposed Text

**Best practices for "no transfer" disclosures:**

- State the processor name and its function (identifies which processing activity)
- Cross-reference the processor table or data collection section (avoids duplication)
- Name the hosting location specifically (not just "EU" -- name the country)
- Explicitly state "no international data transfers" (affirmative negation is clearer than silence)
- Include a link to the processor's own data policy or DPA for verification

**Edge cases considered:**

- BunnyWay (Slovenia) is used for CDN/DDoS but is EU-based -- mentioning only "Hetzner, Germany" is sufficient since both are EU; listing both sub-processors would over-detail Section 6.3 (that detail belongs in Section 4.2)
- Plausible's Estonia incorporation is a corporate detail, not a data processing location -- omitting it from the transfer disclosure is correct
- If Plausible later adds a non-EU sub-processor, Section 6.3 would need updating -- but this is true for any processor disclosure and is Plausible's contractual obligation to notify per their DPA

## Acceptance Criteria

- [ ] DPD Section 6.3 mentions Plausible Analytics EU-only hosting in `docs/legal/data-processing-agreement.md`
- [ ] DPD Section 6.3 mentions Plausible Analytics EU-only hosting in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] Both DPD file copies have identical Section 6.3 content (verify with `diff`)
- [ ] Privacy Policy Section 10 mentions Plausible EU-only hosting in `docs/legal/privacy-policy.md`
- [ ] Privacy Policy Section 10 mentions Plausible EU-only hosting in `plugins/soleur/docs/pages/legal/privacy-policy.md`
- [ ] Both Privacy Policy file copies have identical Section 10 content (verify with `diff`)
- [ ] No changes to GDPR Policy (correct as-is)
- [ ] No changes to Cookie Policy (correct as-is)
- [ ] All markdownlint checks pass
- [ ] DPD "Last Updated" date bumped to current date

## Test Scenarios

- Given the DPD Section 6.3, when a user reads the international transfers disclosure, then Plausible Analytics is listed with its EU-only hosting status and cross-references Section 4.2
- Given both DPD file copies, when compared with `diff` on the body content (excluding frontmatter), then the Section 6.3 content is identical
- Given the Privacy Policy Section 10, when a user reads international transfers, then Plausible is explicitly called out as EU-only with no international transfer and links to Plausible's data policy
- Given both Privacy Policy file copies, when compared with `diff` on the body content, then the Section 10 content is identical
- Given the GDPR Policy Section 6, when reviewed, then it remains unchanged (Plausible correctly absent from international transfer list)
- Given the Cookie Policy, when reviewed, then it remains unchanged (no international transfers section exists)

## Context

- **Severity**: Low -- Plausible's EU hosting means no transfer risk; omission is not a compliance violation
- **Source**: Found by architecture-strategist review agent during PR #697 review
- **Learning**: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md` documents the dual-file sync pattern -- every structural change must touch both file copies in the same PR
- **Learning**: `knowledge-base/project/learnings/2026-02-21-cookie-free-analytics-legal-update-pattern.md` documents the multi-document lockstep update pattern for analytics-related legal changes
- **Learning**: `knowledge-base/project/learnings/2026-03-18-split-legal-basis-cross-section-consistency.md` warns that legal changes propagate to every section referencing the same processing activity -- grep for "Plausible" across all legal docs to verify no section is missed

## References

- Issue: #700
- Parent PR: #697
- Parent audit: #693
- Related closed: #699 (CLA processor table)
- Related open: #701 (DPD link format)
- Plausible DPA: [plausible.io/dpa](https://plausible.io/dpa) -- verified 2026-03-18
- Plausible data policy: [plausible.io/data-policy](https://plausible.io/data-policy) -- verified 2026-03-18
