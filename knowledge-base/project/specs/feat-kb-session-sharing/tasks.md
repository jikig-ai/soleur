# Tasks: KB Document Sharing (#1745)

## Phase 1: Database & Auth Foundation

- [ ] 1.1 Create migration `017_kb_share_links.sql` (table with CASCADE FK, relative document_path, RLS policies, indexes)
- [ ] 1.2 Add `/shared` to `PUBLIC_PATHS` in `lib/routes.ts` (exact-or-slash matching)
- [ ] 1.3 Add HTTP rate limiting middleware for `/api/shared/` routes (reuse `SlidingWindowCounter`, `cf-connecting-ip`)

## Phase 2: Core Sharing API

- [ ] 2.1 Create `POST /api/kb/share` — generate share link (one-per-document, revoke is permanent, CSRF protected)
- [ ] 2.2 Create `GET /api/kb/share` — list user's shares (authenticated)
- [ ] 2.3 Create `DELETE /api/kb/share/[token]` — revoke share link (permanent, CSRF protected)
- [ ] 2.4 Create `GET /api/shared/[token]` — public document access (service-role client, XSS sanitization, nofollow links, rate-limited, handle disconnected workspace)

## Phase 3: UI — Share Button & Shared Viewer

- [ ] 3.1 Add Share button to KB viewer header (next to "Chat about this")
- [ ] 3.2 Create share popover component (generate/copy/revoke states, revoke confirmation dialog)
- [ ] 3.3 Create shared document viewer page at `/shared/[token]` (standalone, noindex, error states including disconnected workspace)
- [ ] 3.4 Create CTA banner component (single mode: "Create your account" + signup link, non-blocking)

## Phase 4: Sharing Dashboard — DEFERRED

Share popover handles per-document management. Dashboard deferred until user demand emerges.

## Phase 5: Legal & Compliance

- [ ] 5.1 Update Privacy Policy (sharing processing activity)
- [ ] 5.2 Update Terms & Conditions (shared content liability, revocation)
- [ ] 5.3 Update GDPR Policy (processing activity for shared content)
- [ ] 5.4 Update AUP (shared content rules)
- [ ] 5.5 Run legal-compliance-auditor after all edits

## Phase 6: Analytics & Testing

- [ ] 6.1 Add feature usage analytics events (share_created, share_revoked, shared_page_viewed)
- [ ] 6.2 Write integration tests (creation, access, revocation, invalid token, path traversal, rate limiting, CSRF, XSS sanitization, disconnected workspace)
- [ ] 6.3 Update CSRF coverage test (add POST/DELETE routes, fix GET exemption logic)
- [ ] 6.4 Post-merge: verify migration applied to production via REST API
