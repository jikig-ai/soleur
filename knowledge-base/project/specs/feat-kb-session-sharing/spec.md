# KB Document Sharing Spec

**Issue:** [#1745](https://github.com/jikig-ai/soleur/issues/1745)
**Brainstorm:** [2026-04-10-kb-document-sharing-brainstorm.md](../../brainstorms/2026-04-10-kb-document-sharing-brainstorm.md)
**Branch:** kb-session-sharing

## Problem Statement

Soleur users produce high-value knowledge base artifacts (brand guides, competitive analyses, roadmaps) but have no way to share them externally. This limits organic discovery and prevents the product-led growth loop where shared artifacts demonstrate Soleur's value to potential users.

## Goals

- G1: Users can share individual KB documents via link with anyone (no login required to view)
- G2: Shared pages display full document content with a non-blocking signup/waitlist CTA
- G3: Users can revoke shared access at any time
- G4: Sharing complies with GDPR and existing legal framework (legal docs updated pre-ship)
- G5: Feature usage is tracked (who shares, how often)

## Non-Goals

- Full KB sharing (deferred -- validate single-doc pattern first)
- Session/conversation sharing (deferred -- requires content sanitization)
- SEO indexability for shared pages (deferred -- privacy-first)
- Per-share view analytics (deferred -- feature usage analytics suffices)
- Custom branding on shared pages (deferred -- Soleur branding for growth)

## Functional Requirements

| # | Requirement | Priority |
|---|-------------|----------|
| FR1 | User can generate a share link for any KB document from the KB viewer | P1 |
| FR2 | Anyone with the share link can view the full document content without authentication | P1 |
| FR3 | Shared page displays a non-blocking CTA banner (create account or join waitlist, adapts to product state) | P1 |
| FR4 | User can revoke a share link (immediately disables access) | P1 |
| FR5 | User can view and manage all active shares from a dedicated sharing dashboard | P1 |
| FR6 | Share links use database tokens stored in a `shared_links` table | P1 |
| FR7 | Shared pages include `noindex` meta tag | P1 |
| FR8 | Share links do not expire automatically (manual revoke only) | P1 |
| FR9 | Shared pages carry Soleur branding | P2 |
| FR10 | Feature usage events tracked (share created, share revoked, shared page viewed) | P2 |

## Technical Requirements

| # | Requirement | Priority |
|---|-------------|----------|
| TR1 | New `shared_links` DB table with RLS policies for token-based anonymous access | P1 |
| TR2 | Public API route for shared content that bypasses auth middleware | P1 |
| TR3 | Path traversal protection scoped to the shared document (not full workspace) | P1 |
| TR4 | Rate limiting on public share endpoints (separate from authenticated endpoints) | P1 |
| TR5 | CSRF protection on share creation/revocation endpoints | P1 |
| TR6 | Legal document updates: Privacy Policy, T&C, GDPR Policy, AUP | P1 |
| TR7 | Cookie Policy update if shared pages set cookies for unauthenticated visitors | P2 |

## Acceptance Criteria

- [ ] User generates a share link from the KB viewer via a "Share" button
- [ ] External viewer accesses the link and sees the full document without login
- [ ] CTA banner is visible but does not block content
- [ ] CTA shows "Create account" when signups are open, "Join waitlist" when not
- [ ] User revokes the link and external viewer immediately gets an error/expired page
- [ ] Sharing dashboard lists all active shares with revoke controls
- [ ] Shared page has `<meta name="robots" content="noindex">` in HTML head
- [ ] Privacy Policy, T&C, GDPR Policy, and AUP updated for sharing
- [ ] Feature usage events fire for share creation, revocation, and page views
