---
title: "fix: DPD Section 6.3 should mention Plausible Analytics EU-only hosting"
type: fix
date: 2026-03-18
semver: patch
---

# fix: DPD Section 6.3 should mention Plausible Analytics EU-only hosting

## Overview

DPD Section 6.3 (International Data Transfers -- Docs Site) mentions GitHub Pages but omits Plausible Analytics. Plausible is EU-hosted (Hetzner, Germany; BunnyWay, Slovenia) with no international data transfers. Adding an explicit statement strengthens transparency without changing any compliance posture.

Related: #700 (this issue), #697 (PR where the gap was discovered), #693 (parent audit PR).

## Problem Statement

Section 6.3 currently reads:

> The Docs Site is hosted on GitHub Pages, which may involve data processing in the United States and other jurisdictions where GitHub operates. GitHub maintains appropriate transfer mechanisms as described in its data processing agreements.

Plausible Analytics is a documented Docs Site processor (Section 4.2) but is not mentioned in the international transfers section. While this is not a compliance violation (no transfer occurs), explicitly stating EU-only hosting is best practice for GDPR Article 44 transparency.

## Proposed Solution

Add a sentence to Section 6.3 in both DPD file copies confirming Plausible processes all data within the EU. Also add a corresponding sentence to the Privacy Policy (Section 10) and GDPR Policy (Section 6) for cross-document consistency.

### Files to modify (4 files, dual-file sync)

| File | Section | Change |
|------|---------|--------|
| `docs/legal/data-processing-agreement.md` | 6.3 Docs Site | Add Plausible EU-only hosting sentence |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 6.3 Docs Site | Add Plausible EU-only hosting sentence (identical content) |
| `docs/legal/privacy-policy.md` | 10. International Data Transfers | Add Plausible EU-only paragraph |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 10. International Data Transfers | Add Plausible EU-only paragraph (identical content) |

### Why NOT the GDPR Policy

GDPR Policy Section 6 already lists only services that perform international transfers (Anthropic, GitHub, Buttondown). Plausible is correctly absent because it does not transfer data internationally. The Article 30 register (Section 8) already states "Plausible Analytics is hosted in the EU." No GDPR Policy change is needed.

### Proposed text

**DPD Section 6.3** -- append after the existing GitHub Pages paragraph:

> Plausible Analytics, used for privacy-respecting website analytics on the Docs Site (see Section 4.2), processes all data exclusively within the European Union (Hetzner, Germany). No international data transfers occur for analytics data.

**Privacy Policy Section 10** -- append after the Buttondown paragraph:

> Plausible Analytics, used for Docs Site analytics (see Section 4.3), processes all data exclusively within the European Union (Hetzner, Germany). No international data transfers occur for analytics data. See [Plausible's Data Policy](https://plausible.io/data-policy) for details.

## Acceptance Criteria

- [ ] DPD Section 6.3 mentions Plausible Analytics EU-only hosting in `docs/legal/data-processing-agreement.md`
- [ ] DPD Section 6.3 mentions Plausible Analytics EU-only hosting in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] Both DPD file copies have identical Section 6.3 content
- [ ] Privacy Policy Section 10 mentions Plausible EU-only hosting in both file copies
- [ ] Both Privacy Policy file copies have identical Section 10 content
- [ ] No changes to GDPR Policy (correct as-is)
- [ ] All markdownlint checks pass

## Test Scenarios

- Given the DPD Section 6.3, when a user reads the international transfers disclosure, then Plausible Analytics is listed with its EU-only hosting status
- Given both DPD file copies, when compared with `diff`, then the Section 6.3 content is identical
- Given the Privacy Policy Section 10, when a user reads international transfers, then Plausible is explicitly called out as EU-only with no international transfer
- Given the GDPR Policy Section 6, when reviewed, then it remains unchanged (Plausible correctly absent from international transfer list)

## Context

- **Severity**: Low -- Plausible's EU hosting means no transfer risk; omission is not a compliance violation
- **Source**: Found by architecture-strategist review agent during PR #697 review
- **Learning**: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md` documents the dual-file sync pattern
- **Learning**: `knowledge-base/project/learnings/2026-02-21-cookie-free-analytics-legal-update-pattern.md` documents the multi-document lockstep update pattern

## References

- Issue: #700
- Parent PR: #697
- Parent audit: #693
- Related closed: #699 (CLA processor table)
- Related open: #701 (DPD link format)
- Plausible DPA: [plausible.io/dpa](https://plausible.io/dpa)
- Plausible data policy: [plausible.io/data-policy](https://plausible.io/data-policy)
