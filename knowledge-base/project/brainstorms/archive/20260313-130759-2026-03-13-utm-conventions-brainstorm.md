# UTM Conventions and Social-Distribute Integration

**Date:** 2026-03-13
**Issue:** #579
**Status:** Captured
**Branch:** feat-utm-conventions

---

## What We're Building

UTM tracking conventions for the content distribution pipeline. Currently all distributed content uses bare URLs with no attribution tracking. Plausible Analytics (the analytics backend) reads UTM parameters natively from URL query strings -- no analytics-side configuration is needed.

The change is purely on the link-generation side: social-distribute will append platform-specific UTM parameters when constructing article URLs during content generation (Phase 3).

## Why This Approach

**Generation-time injection** was chosen over publish-time or dual-layer injection because:

1. **Covers all platforms.** social-distribute generates content for 6 platforms (Discord, X, IndieHackers, Reddit, Hacker News, LinkedIn). content-publisher.sh only automates 2 (Discord, X). Generation-time injection means manual channels (IH, Reddit, HN, LinkedIn) get correct UTMs baked into copy-paste-ready content.

2. **Avoids the channel fork problem.** The X publishing path has two code paths (API + Playwright web UI fallback). Injecting upstream means both paths get consistent tracking without duplicating UTM logic.

3. **Single injection point.** One place to change conventions, one place to debug. The publisher just posts what's in the content file.

## Key Decisions

### UTM Parameter Conventions

| Parameter | Convention | Examples |
|-----------|-----------|----------|
| `utm_source` | Platform name (lowercase) | `discord`, `x`, `indiehackers`, `hackernews`, `reddit`, `linkedin`, `email` |
| `utm_medium` | Channel type | `social` (X, LinkedIn), `community` (Discord, IH, Reddit, HN), `newsletter` (email) |
| `utm_campaign` | Article slug | `caas-pillar`, `operations-management` |

### Platform-Specific Rules

| Platform | UTM Treatment |
|----------|--------------|
| Discord | Full UTMs (source, medium, campaign) |
| X/Twitter | Full UTMs |
| IndieHackers | Full UTMs |
| LinkedIn | Full UTMs |
| Hacker News | Full UTMs |
| Reddit | Minimal: `utm_source=reddit` only. Long marketing-looking URLs risk irreversible domain reputation damage on Reddit. |
| Email | Full UTMs (for future newsletter use) |

### Scope Decisions

- **`utm_content`**: Not used. Skip variant-level tracking for now (YAGNI).
- **`utm_term`**: Not used. No paid search campaigns.
- **Campaign naming**: Just the article slug (e.g., `caas-pillar`), no prefix namespacing. If non-article campaigns arise later, add prefixes then.
- **Sanitization**: UTM values validated with strict alphanumeric + hyphens + underscores to prevent query parameter injection.

### Existing Content

- **4 unpublished files**: Update with UTM-tagged URLs (operations-management, competitive-intelligence, brand-guide-creation, business-validation).
- **2 published files**: Leave as-is (legal-document-generation, why-most-agentic-tools-plateau). URLs are already in the wild -- retroactive changes have no effect on posted links.

### Convention Documentation

Add UTM conventions section to `knowledge-base/marketing/content-strategy.md`, co-located with existing content quality standards.

## Open Questions

- Should content-publisher.sh add a validation warning if it detects URLs without UTM parameters? (Nice-to-have, not blocking.)
- Should HN submissions use shorter UTM params given the URL is the submission link? (HN displays domain only, not full URL, so this is cosmetic.)

## Research Context

- Plausible was chosen over GoatCounter and Cloudflare Web Analytics partly because it supports all 5 UTM parameters natively (see analytics evaluation plan, 2026-02-21).
- Cookie-free analytics legal update pattern confirms UTM parameters are URL metadata, not cookies/device storage -- no additional legal document updates needed.
- X API has two code paths (API + Playwright fallback) -- UTM injection must happen upstream to stay consistent.
- Reddit domain reputation damage is irreversible -- minimal UTMs reduce spam filter risk.
