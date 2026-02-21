---
title: "Cookie-Free Analytics Legal Update Pattern"
category: implementation-patterns
tags: [plausible, analytics, gdpr, eprivacy, legal-docs, cookie-free]
module: docs-site
symptom: "Adding analytics to a site with legal docs claiming 'no analytics'"
root_cause: "Legal documents must be updated in lockstep with technical changes"
---

# Cookie-Free Analytics Legal Update Pattern

## Problem

Adding analytics to a site where legal documents explicitly state "no analytics" requires updating multiple documents simultaneously. Missing any document creates contradictions that a regulator or careful user will catch.

## Solution

When adding cookie-free analytics (Plausible, Umami, GoatCounter), update all of these in lockstep:

### Documents to update

1. **Cookie Policy** -- Section on analytics (disclose cookie-free nature), Section on Do Not Track (remove "no analytics" claim)
2. **Privacy Policy** -- Data collection section (what Plausible collects), Legal basis section (add Art. 6(1)(f) paragraph)
3. **GDPR Policy** -- Lawful basis section (add analytics paragraph with ePrivacy exemption), Data categories (remove "no analytics" from NOT collected list, add analytics data section), Article 30 register (increment count, add processing activity)
4. **Data Protection Disclosure** -- Limited processing section (add analytics to hosting description)

### Key GDPR arguments for cookie-free analytics

- **Legal basis:** Legitimate interest Art. 6(1)(f) with three-part test: (1) purpose is legitimate, (2) cookie-free is least intrusive means, (3) no identifying data collected
- **ePrivacy exemption:** Art. 5(3) does not apply because no information is stored on or accessed from the user's device
- **No consent banner needed:** Cookie-free analytics that don't store device data are exempt from both GDPR consent and ePrivacy consent requirements

### Script tag choice

Use `async` not `defer` for analytics scripts. If the analytics provider is down, `async` fails silently while `defer` can block first paint until HTML parsing completes.

## Gotcha: Dual file locations

If legal docs exist in two locations (e.g., Eleventy source + root copies), both must be updated. The Eleventy source has layout/permalink frontmatter; root copies have type/jurisdiction frontmatter. Body content should match.

## Gotcha: Article 30 private register

The public GDPR policy references a processing activity count. If a private Article 30 register exists, it must also be updated out-of-band to match. Otherwise the register contradicts the public policy during a CNIL inspection.
