---
title: "Evaluate Analytics Solutions for soleur.ai"
type: feat
date: 2026-02-21
issue: "#198"
related: "#193, #188"
version-bump: PATCH
deepened: 2026-02-21
---

# Evaluate Analytics Solutions for soleur.ai

## Enhancement Summary

**Deepened on:** 2026-02-21
**Research sources:** Plausible docs, GDPR legal assessment, Eleventy patterns, 8 institutional learnings

### Key Improvements
1. Updated script tag to use `async` instead of `defer` (analytics-specific best practice)
2. Added Plausible 2025 script update details (site-specific snippets, `plausible.init()` API)
3. Added GDPR legal basis analysis with Art. 6(1)(f) three-part test and ePrivacy Art. 5(3) exemption
4. Added optional Cloudflare Workers proxy for ad-blocker bypass
5. Incorporated 8 institutional learnings (Eleventy gotchas, dual legal doc patterns, Article 30 requirements)

## Overview

soleur.ai currently has zero analytics. The docs site is a pure static Eleventy site on GitHub Pages with no JavaScript execution, no external dependencies, and no third-party integrations. Legal documents (cookie policy, privacy policy, GDPR policy) explicitly state "no analytics." Adding analytics requires both implementation and coordinated legal document updates across two file locations.

## Problem Statement

Without analytics, there is no visibility into site traffic, content effectiveness, or user behavior. The marketing audit (#193) identified this gap but deferred implementation pending a proper evaluation of privacy-respecting solutions.

## Proposed Solution

**Recommendation: Plausible Analytics ($9/mo)**

Plausible is the best fit for soleur.ai because it offers the richest feature set at the lowest script cost (~1 KB), is fully GDPR-compliant without cookies or consent banners, works with GitHub Pages via a single `<script>` tag, and provides all required metrics (page views, referrers, geo, devices) plus UTM tracking, goals, funnels, and Google Search Console integration.

**Budget alternative: Umami Cloud (Free up to 1M events/month)**

If $9/mo is not justified for current traffic levels, Umami Cloud's free tier covers most small docs sites comfortably. It provides the same core metrics, UTM tracking, and custom events with a ~2 KB script. The trade-off is a less polished dashboard and no funnel/goal tracking comparable to Plausible.

## Comparison Matrix

| Feature | Plausible | Umami Cloud | GoatCounter | Cloudflare WA |
|---|---|---|---|---|
| **Price** | $9/mo | Free (1M events) | $5/mo (commercial) | Free |
| **Script size** | ~1 KB | ~2 KB | ~3.5 KB | ~4.3 KB |
| **Cookies** | None | None | None | None |
| **Consent banner** | Not needed | Not needed | Not needed | Not needed |
| **Open source** | Yes (AGPL) | Yes (MIT) | Yes (ISC) | No |
| **Page views** | Yes | Yes | Yes | Yes |
| **Referrers** | Yes | Yes | Yes | Top 15 only |
| **Geo** | Country + region + city | Country + region + city | Country only | Country only |
| **Devices/Browser/OS** | Yes + versions | Yes | Yes | Yes |
| **UTM tracking** | All 5 params | Yes | Limited | No |
| **Goals/Events** | Yes + funnels | Yes | No | No |
| **Data retention** | Indefinite | Indefinite | Indefinite | ~7 days |
| **GitHub Pages** | Yes | Yes | Yes | Yes |

**Why not the others:**
- **Fathom** ($15/mo): More expensive than Plausible with fewer features (no funnels, no city-level geo, no Search Console integration).
- **Simple Analytics** ($19/mo monthly, $9/mo annual): Highest entry price, similar features to Plausible at higher cost.

## Technical Approach

### Architecture

The implementation is minimal: a single `<script>` tag in the Eleventy base layout (`plugins/soleur/docs/_includes/base.njk`). The site currently has zero JavaScript execution, so this adds a single ~1 KB external script.

No build changes, no bundling, no configuration files. The analytics provider handles all data collection, storage, and dashboarding.

### Implementation

#### Step 1: Analytics Integration

1. Sign up for Plausible and configure the site (soleur.ai)
2. Copy the site-specific script snippet from Plausible dashboard (Site Installation > General)
3. Add `<script>` tag to `plugins/soleur/docs/_includes/base.njk` in the `<head>` section (before `</head>` at line ~66)
4. Verify script loads correctly on local dev (`npm run docs:dev`) -- run `npm install` first in the worktree (dependencies are not shared across worktrees)

**Script insertion point in `base.njk`:**
```html
<!-- Analytics: Plausible (cookie-free, GDPR-compliant) -->
<script async src="https://plausible.io/js/script.js" data-domain="soleur.ai"></script>
```

Use `async` not `defer` for analytics scripts. With `defer`, if a user navigates away before the browser finishes parsing the HTML document, the script will not execute at all -- missing that pageview. With `async`, the script downloads in parallel and executes as soon as available.

**Note on Plausible 2025 script update:** Plausible now provides site-specific personalized snippets. The exact `src` URL may include a unique identifier (e.g., `pa-XXXXX`). Copy the exact snippet from the Plausible dashboard rather than using the generic URL above. If advanced configuration is needed later (custom properties, file downloads, hash-based routing), use the `plausible.init()` API instead of data attributes.

If Umami is chosen instead:
```html
<script async src="https://cloud.umami.is/script.js" data-website-id="YOUR_WEBSITE_ID"></script>
```

#### Step 2: Legal Document Updates

Update legal documents in BOTH locations. These are independent files with different frontmatter -- the Eleventy source has `layout`/`permalink`/`description` frontmatter and HTML wrapper sections, while root copies have `type`/`jurisdiction`/`generated-date` frontmatter with plain markdown. Mirror only the markdown body content, not the structural framing.

- `plugins/soleur/docs/pages/legal/` (Eleventy source, builds to website)
- `docs/legal/` (root copies)

Update the "Last Updated" / date header in every modified legal document.

After updating all documents, verify cross-document consistency: entity name ("Jikigai, incorporated in France"), contact info (legal@jikigai.com), jurisdiction ("EU, US"), and dates must match across all documents.

**Cookie Policy** (`cookie-policy.md`):
- Section 3.2: Update from "We do not deploy any first-party analytics" to disclose the analytics service and confirm it is cookie-free
- Section 4.2: Update from "We do not currently use any analytics cookies" to state the analytics provider name, confirm no cookies are set, and describe what data is collected

**Privacy Policy** (`privacy-policy.md`):
- Section 4.3: Update from "We do not add analytics, tracking pixels, or cookies" to disclose the analytics service, confirm cookie-free operation, and list collected data points (page views, referrer, country, device type, browser)

Note: Section 12 ("Soleur does not add any first-party cookies to the Docs Site") remains factually correct -- Plausible/Umami are third-party scripts that set zero cookies. No change needed.

**GDPR Policy** (`gdpr-policy.md`):
- Section 4.1: Move "Usage analytics or telemetry" from "Data NOT Collected" to a new Section 4.3 "Website Analytics Data" describing the analytics data collected and its legal basis

  Legal basis justification (Art. 6(1)(f) three-part test):
  1. **Purpose test**: Understanding website traffic patterns to improve documentation is a legitimate interest of the website operator
  2. **Necessity test**: Cookie-free analytics is the least intrusive means -- no personal data stored, no cross-site tracking, no device fingerprinting
  3. **Balancing test**: Users' rights are not overridden because no identifying information is collected or stored; IP addresses are discarded after country-level geolocation

  ePrivacy Directive Art. 5(3) does not apply because Plausible does not use cookies or store information on the user's device. No consent mechanism is required.

- Section 10: Add a fourth processing activity to the Article 30 register and update the activity count from "three" to "four":
  - Purpose: Website analytics
  - Legal basis: Art. 6(1)(f) legitimate interest
  - Data categories: Page URLs, referrer URLs, country (from IP, not stored), device type, browser type
  - Recipients: Plausible Analytics (EU-hosted)
  - Retention: Per provider policy (indefinite during subscription)
  - Safeguards: No personal data collected, no cookies, IP addresses not stored

**Data Protection Disclosure** (`data-protection-disclosure.md` / root: `data-processing-agreement.md`):
- Section 2.3(a): Update "Limited Processing by Soleur" to disclose the analytics provider alongside GitHub Pages as a processor of Docs Site data
- Section 3.1(c): No change needed -- refers to the plugin, not the website

Note: The Eleventy source is named `data-protection-disclosure.md` while the root copy is `data-processing-agreement.md`. Both refer to the same document.

### Files to Modify

| File | Change |
|---|---|
| `plugins/soleur/docs/_includes/base.njk` | Add analytics `<script>` tag in `<head>` |
| `plugins/soleur/docs/pages/legal/cookie-policy.md` | Update sections 3.2, 4.2 + date |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | Update section 4.3 + date |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | Update sections 4.1, 10 + date |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Update section 2.3(a) + date |
| `docs/legal/cookie-policy.md` | Mirror body content changes + date |
| `docs/legal/privacy-policy.md` | Mirror body content changes + date |
| `docs/legal/gdpr-policy.md` | Mirror body content changes + date |
| `docs/legal/data-processing-agreement.md` | Mirror body content changes + date |

## Acceptance Criteria

- [x] At least 3 analytics options compared on price, privacy, features, and GitHub Pages compatibility
- [x] Solution recommended with rationale
- [x] Analytics script added to base layout template
- [x] Legal documents updated in both locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`)
- [x] GDPR Article 30 register updated with analytics processing activity (count updated to four)
- [x] Site verified with `agent-browser` that analytics script loads correctly
- [ ] Post-merge: Close issue #188 with rationale (cookie-free analytics removes consent banner need)

## Test Scenarios

- Given the docs site is built, when a user visits any page, then the analytics script loads without errors (verify in browser console)
- Given the cookie policy is updated, when reading section 4.2, then it accurately describes the analytics service and confirms no cookies
- Given the GDPR policy is updated, when reading section 10, then the Article 30 register includes four processing activities
- Given both legal document locations are updated, when diffing corresponding files, then the analytics-related body content is identical

## Non-Goals

- Self-hosting analytics (adds operational complexity not justified for a docs site)
- Custom event tracking beyond basic page views (can be added later)
- A/B testing or conversion optimization
- Cookie consent banner implementation (cookie-free analytics avoids this)
- Dashboard customization or embedding
- Cloudflare Workers proxy (optional future enhancement for ad-blocker bypass -- Plausible docs describe a Cloudflare Workers proxy that maps first-party URLs to Plausible's CDN, covering 100K free requests/day; consider if undercounting becomes an issue)

## Dependencies and Risks

- **Provider account setup**: Need to create a Plausible account and configure soleur.ai before implementation
- **Ad blocker interference**: Privacy-focused analytics scripts are less commonly blocked than Google Analytics, but some ad blockers still block them. Accept undercounting as a trade-off. A Cloudflare Workers proxy can mitigate this later if needed.
- **Dual legal doc locations**: `docs/legal/` and `plugins/soleur/docs/pages/legal/` are independent files with different frontmatter. This is pre-existing tech debt -- mirror body content only, not structural framing

## Rollback Plan

Remove the `<script>` tag from `base.njk` and revert legal document changes.

## References

### Internal
- Issue #198: Evaluate analytics solutions
- Issue #193: Marketing audit (deferred analytics)
- Issue #188: Cookie consent banner
- `plugins/soleur/docs/_includes/base.njk`: Base layout (script insertion point)
- `knowledge-base/learnings/2026-02-21-gdpr-article-30-compliance-audit-pattern.md`: Article 30 requirements
- `knowledge-base/learnings/2026-02-21-marketing-audit-brand-violation-cascade.md`: Legal-analytics conflict awareness
- `knowledge-base/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md`: Eleventy template gotchas

### External
- [Plausible Analytics](https://plausible.io/)
- [Plausible GDPR Legal Assessment](https://plausible.io/blog/legal-assessment-gdpr-eprivacy)
- [Plausible Script Update Guide](https://plausible.io/docs/script-update-guide)
- [Plausible Cloudflare Proxy Guide](https://plausible.io/docs/proxy/guides/cloudflare)
- [Umami Analytics](https://umami.is/)
- [GoatCounter](https://www.goatcounter.com/)
- [Cloudflare Web Analytics](https://www.cloudflare.com/web-analytics/)
- [EDPB Guidelines 1/2024 on Legitimate Interest](https://www.edpb.europa.eu/system/files/2024-10/edpb_guidelines_202401_legitimateinterest_en.pdf)
