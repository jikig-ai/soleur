# KB Document Sharing Brainstorm

**Date:** 2026-04-10
**Issue:** [#1745](https://github.com/jikig-ai/soleur/issues/1745)
**Branch:** kb-session-sharing
**Status:** Decisions captured, ready for planning

## What We're Building

Read-only sharing of individual knowledge base documents with external users via link-based access. Shared pages display the full document content with a non-blocking CTA banner that adapts to the product state (create account if open signups, join waitlist if not). Owners can revoke shared access at any time via an inline share button or a central sharing dashboard.

## Why This Approach

Sharing is a product-led growth lever: every shared link is a branded touchpoint that demonstrates real Soleur output to potential users before asking for commitment. The CMO identified this as a viral acquisition loop -- recipients see real value (a brand guide, a competitive analysis, a roadmap) before encountering the signup CTA.

Starting with single-document sharing validates the pattern with minimal scope. Full KB and session sharing introduce distinct security and UX challenges (path traversal scoping for subtrees, content sanitization for sessions) that don't need to be solved for the initial validation.

## Key Decisions

| # | Decision | Choice | Alternatives considered |
|---|----------|--------|------------------------|
| 1 | Initial sharing scope | Single KB document only | Full KB, session, all three at once |
| 2 | Access model | Link-based (anyone with link) | Email-invite, link + optional email gate |
| 3 | Content visibility | Full content + soft CTA (non-blocking banner) | Preview + hard gate, contextual CTAs |
| 4 | Token model | Database token (`shared_links` table) | Signed URL + denylist, DB token + CDN cache |
| 5 | SEO | Not indexable (`noindex`) | Owner-controlled toggle, defer decision |
| 6 | Link expiration | Manual revoke only (no auto-expiry) | Default expiry + manual, never expire |
| 7 | CTA action | Adaptive (create account or join waitlist) | Waitlist only, create account only |
| 8 | Management UI | Inline share button + dedicated sharing dashboard | Inline only, dashboard only |
| 9 | Legal updates | Included in feature scope (ship together) | Separate follow-up issue |
| 10 | Analytics | Feature usage analytics (who shares, how often) | Per-share view analytics, referral tracking |

## Deferred to Later

| Item | Why deferred | Re-evaluation criteria |
|------|-------------|----------------------|
| Full KB sharing | Introduces subtree path-scoping complexity. Validate single-doc pattern first. | After single-doc sharing has usage data from beta users. |
| Session sharing | Sessions contain API keys, tool call internals, and PII. Requires content sanitization spec. | After content sanitization rules are defined and security-reviewed. |
| SEO indexability | Shared content is permanently discoverable even after revocation. Privacy-first for now. | When user demand for public content surfaces during P4 validation. |
| Per-share view analytics | Adds tracking complexity for unauthenticated visitors. Feature usage analytics suffices for validation. | When founders request view counts on their shared links. |
| Custom branding on shared pages | Shared pages carry Soleur branding for growth/awareness. White-labeling deferred. | When enterprise/team features are explored (post-MVP). |

## Open Questions

1. **URL format:** `/s/<token>` vs `/share/<token>` vs subdomain `share.app.soleur.ai/<token>`? Needs product + CTO input during planning.
2. **Rate limiting:** Public share endpoints need separate rate limiting from authenticated endpoints (CTO flagged). How aggressive?
3. **Content freshness:** Does the shared view show the document at the time of sharing (snapshot) or the current version (live)? Live is simpler but the owner might edit after sharing.
4. **Soleur branding level:** Prominent Soleur header + CTA, or subtle footer? CMO recommends conversion-optimizer and ux-design-lead for layout before implementation.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Ship link-based document sharing first (smallest scope, highest signal). KB prerequisites are done (API, viewer, inbox all shipped). Revocation mechanics need proper spec before implementation. Three sharing granularities is scope creep -- validate one first.

### Marketing (CMO)

**Summary:** Viral acquisition loop -- every shared link is a branded touchpoint with embedded CTAs creating free impressions with a warm audience. Key tension: how much content to show before the gate. Recommends delegating shared-page layout to conversion-optimizer and ux-design-lead before implementation.

### Engineering (CTO)

**Summary:** First-ever unauthenticated access to user-owned data -- fundamental auth boundary change. HIGH risk areas: auth bypass for public routes (all KB APIs gate on `auth.uid()`), content leakage (path traversal), and session data sensitivity. Database token model recommended for clean revocation. Suggests ADR to capture the sharing auth model decision.

### Legal (CLO)

**Summary:** No existing legal documents cover sharing. P0 updates needed: add sharing processing activity to Privacy Policy, Data Protection Disclosure, and GDPR Policy. Add shared-content and revocation clauses to T&C. Add acceptable use rules for shared content to AUP. Cookie Policy may need update if shared pages set cookies for unauthenticated visitors.
