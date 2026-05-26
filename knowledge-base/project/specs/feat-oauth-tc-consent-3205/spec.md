---
title: OAuth T&C Consent — Residual Audit Bundle (R1–R6)
status: specified
issue: 3205
brainstorm: knowledge-base/project/brainstorms/2026-05-15-oauth-tc-consent-residual-audit-brainstorm.md
branch: feat-oauth-tc-consent-3205
pr: 3853
date: 2026-05-15
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
---

# Spec: OAuth T&C Consent — Residual Audit Bundle (R1–R6)

## Problem Statement

Issue #3205 (P1-high, deferred-scope-out, domain/legal, CPO-routed) was filed asserting that server-side T&C consent enforcement was missing at the OAuth callback path. **The premise is stale.** Server-side enforcement shipped on `main` via PR #898 → PR #927 → migrations 005–008 on 2026-03-20. The four-layer defense (callback gate, middleware gate, WS handshake gate, column-level GRANT lockdown) is live today; the "user lands in app with no consent record" path is closed.

A targeted residual-risk audit (CLO + CPO + CTO triad + repo-research) on `main` surfaced six gaps in the SHIPPED implementation, none of which are described in #3205's body:

1. **R1.** `users.tc_accepted_at` and `users.tc_accepted_version` are OVERWRITTEN on every acceptance. After a `TC_VERSION` bump, evidence of the prior version's acceptance is destroyed. GDPR Art. 7(1) requires the controller to "demonstrate that consent was given" — a destroyed prior-version record is a single-user-incident-class GDPR breach if a paid customer disputes a prior-version processing activity.
2. **R2.** `apps/web-platform/middleware.ts:112-117` fails OPEN on Supabase SELECT errors. A flaky DB query lets a non-accepted user reach `/dashboard`.
3. **R3.** `apps/web-platform/server/ws-handler.ts:321-324` checks `tc_accepted_version` only during the WebSocket handshake. Long-lived sockets (a `chat` exchange or running agent stream) continue past a `TC_VERSION` bump until the user disconnects.
4. **R4.** No CI guardrail exists against silent edits to `docs/legal/terms-and-conditions.md` without bumping `TC_VERSION` in `apps/web-platform/lib/legal/tc-version.ts`. Users' stale acceptance silently survives substantive content changes.
5. **R5.** `/accept-terms` checkbox copy must name BOTH "Terms & Conditions and Privacy Policy" with separate linked anchors (GDPR Art. 7(2) "distinguishable" consent for the bundled-acceptance model). Repo-research did not confirm the current copy meets this bar; verify-then-fix-inline.
6. **R6.** Zero end-to-end test coverage of OAuth → `/accept-terms` → `/dashboard`; only vitest unit tests exist. Changes to the enforcement path land without integration-level protection.

Additionally, `apps/web-platform/server/ws-handler.ts:322` uses the literal numeric close code `4004` rather than importing from `WS_CLOSE_CODES.TC_NOT_ACCEPTED` — a drift risk the repo-research surfaced.

## Goals

- **G1.** Ship an append-only `public.tc_acceptances` audit ledger that records each acceptance event (user_id, version, accepted_at, document_sha) with INSERT-only service-role write boundary and SELECT-self-only RLS. GDPR Art. 7(1) demonstrability is the binding requirement.
- **G2.** Capture the T&C document fingerprint at acceptance time via a build-time `TC_DOCUMENT_SHA` constant (SHA-256 of `docs/legal/terms-and-conditions.md`) emitted to `apps/web-platform/lib/legal/tc-version.ts`. The constant is recorded on every `tc_acceptances` row.
- **G3.** Change `middleware.ts:112-117` to fail closed on Supabase SELECT error (redirect to `/accept-terms`) and mirror to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
- **G4.** Add WebSocket mid-session re-check: on every `start_session`/`chat` message handler, compare cached `tc_version_at_handshake` against current `TC_VERSION`; close socket with `WS_CLOSE_CODES.TC_NOT_ACCEPTED` on mismatch.
- **G5.** Replace literal `4004` in `ws-handler.ts:322` with `WS_CLOSE_CODES.TC_NOT_ACCEPTED`, imported from a single shared source consumed by both client and server.
- **G6.** Add CI workflow step that computes SHA-256 of `docs/legal/terms-and-conditions.md` (and the Eleventy mirror at `plugins/soleur/docs/pages/legal/terms-and-conditions.md`), compares against `TC_DOCUMENT_SHA`, and fails the build if mismatched unless `TC_VERSION` was bumped in the same commit.
- **G7.** Verify and (if needed) fix `/accept-terms` and `/signup` checkbox copy to name BOTH "Terms & Conditions" and "Privacy Policy" with separate linked anchors.
- **G8.** Add an end-to-end test (Playwright or vitest with mocked Supabase + mocked OAuth provider; Open Question 3) that drives the OAuth callback → `/accept-terms` redirect → POST `/api/accept-terms` → `/dashboard` happy path AND asserts a `tc_acceptances` row was inserted.
- **G9.** Publish a written `TC_VERSION` bump-policy rubric (material / clarifying / cosmetic) at `knowledge-base/legal/tc-version-bump-policy.md`. CLO sign-off required.
- **G10.** Close GitHub issue #3205 once the PR merges, with a comment linking the shipped surfaces and the audit bundle.

## Non-Goals

- **NG1.** Backfill of historical acceptances into `tc_acceptances`. We do not have IP/UA/SHA for past acceptances; manufacturing rows would re-introduce the PR #898/#927 fabricated-consent class of bug.
- **NG2.** Moving `TC_VERSION` to a DB row (DB-driven version). CTO assessment: introduces deploy/CDN race; the CI guardrail (G6) is the better primitive.
- **NG3.** Populating `tc_acceptances.ip_hash` and `user_agent` columns in the route handler. Schema reserves nullable columns; capture deferred pending Legitimate Interest Assessment per CLO (Open Question 2).
- **NG4.** Separate `privacy_accepted_*` column family / `/api/accept-privacy` endpoint. Today's bundled-consent design is GDPR-defensible IF G7 lands; separation is a follow-on if the LIA or counsel review demands it.
- **NG5.** Finer-grained "material vs. cosmetic" `TC_VERSION` bump UX (banner-not-redirect for clarifying changes). Deferred to a Phase 4.1 onboarding prerequisite per CPO.
- **NG6.** Splitting the bundle across multiple PRs. The bundled-PR scope was explicitly chosen.
- **NG7.** Restructuring the existing `users.tc_accepted_at` / `users.tc_accepted_version` columns. They remain the denormalized latest-acceptance cache for fast middleware reads.

## Functional Requirements

### FR1: `public.tc_acceptances` append-only ledger

A new table `public.tc_acceptances` with columns:

- `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `version text NOT NULL`
- `accepted_at timestamptz NOT NULL DEFAULT now()`
- `document_sha text NOT NULL`
- `ip_hash text NULL`
- `user_agent text NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`

Constraints / policies:

- RLS enabled.
- `SELECT` policy: `auth.uid() = user_id` only. No anon access.
- No `UPDATE` or `DELETE` grants for `authenticated` or `anon` roles. Service role only (via service-key client) can INSERT/SELECT/DELETE for operational reasons; UPDATE is REVOKED across all roles to enforce append-only semantics at the GRANT layer.
- Index on `(user_id, accepted_at DESC)` for "show me this user's acceptance history" queries.

### FR2: `POST /api/accept-terms` writes a ledger row

`apps/web-platform/app/api/accept-terms/route.ts` is modified to:

- Compute or import `TC_DOCUMENT_SHA` (build-time constant from `lib/legal/tc-version.ts`).
- After the successful `users` UPDATE (lines 52–59), INSERT a new row into `public.tc_acceptances` with `(user_id, version, document_sha)` populated; `ip_hash` and `user_agent` left NULL (NG3).
- Idempotency path at lines 47–50 (user already on current version): also no-op the ledger insert.
- If the ledger INSERT fails, the route returns 500 (`Failed to record acceptance`) and the `users` UPDATE remains committed; mirror error to Sentry. Rationale: the `users` row is the fast read-path; ledger failure means partial record but the consent itself is still cached. Operator alerting on Sentry.

Alternative (Open Question 1): wrap both the UPDATE and INSERT in a `SECURITY DEFINER` RPC `public.accept_terms(p_version text, p_doc_sha text, p_ip_hash text, p_user_agent text)` pinned to `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`. Resolve at plan time.

### FR3: `TC_DOCUMENT_SHA` build-time constant

`apps/web-platform/lib/legal/tc-version.ts` exports a new constant `TC_DOCUMENT_SHA: string` alongside `TC_VERSION`. The value is the lowercase hex SHA-256 of `docs/legal/terms-and-conditions.md` at build time.

Implementation: a small build script (`apps/web-platform/scripts/compute-tc-sha.mjs` or inline in `next.config.ts` build phase) computes the SHA at build start and writes it to a generated file `lib/legal/tc-document-sha.generated.ts`, which `tc-version.ts` re-exports. The generated file is `.gitignored`; CI checks the generated value against a pinned `TC_DOCUMENT_SHA` stored elsewhere (FR6).

### FR4: Middleware fail-closed on DB error

`apps/web-platform/middleware.ts:112-117` is changed so that any error from the `tc_accepted_version` SELECT redirects to `/accept-terms` (with `?error=db_unavailable` or similar) instead of letting the request through. Mirror to Sentry via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`.

The redirect target itself (`/accept-terms`) is a TC-exempt path, so the user is not infinite-looped; they see the accept-terms page which can render a "service unavailable, please try again" state, OR the accept-terms page itself can succeed and proceed normally.

### FR5: WebSocket mid-session re-check

`apps/web-platform/server/ws-handler.ts` is modified:

- On handshake (line 304), record `session.tcVersionAtHandshake = TC_VERSION`.
- On every inbound message of type `start_session`, `chat`, `tool_use`, or any agent-bound type, before processing: re-read `users.tc_accepted_version` for this user. If `!== TC_VERSION`, close socket with `WS_CLOSE_CODES.TC_NOT_ACCEPTED` and emit a Sentry breadcrumb.
- The re-read is cached in-process for 30 seconds per session to avoid a DB query per message; on cache miss, query.

### FR6: CI guardrail for T&C edit drift

A new GitHub Actions job (or step in an existing workflow) runs on every PR:

- Computes SHA-256 of `docs/legal/terms-and-conditions.md` AND `plugins/soleur/docs/pages/legal/terms-and-conditions.md`.
- Compares against a pinned value in `apps/web-platform/lib/legal/tc-version.ts` (a `TC_DOCUMENT_SHA` const literal that developers manually update when bumping `TC_VERSION`).
- Fails the build if any SHA mismatches the pinned value AND the diff in this PR does NOT bump `TC_VERSION`.
- Also fails if the two T&C document copies (in `docs/` and `plugins/soleur/docs/pages/`) drift from each other (must remain byte-identical).

### FR7: `/accept-terms` and `/signup` checkbox copy verify

Read `apps/web-platform/app/(auth)/accept-terms/page.tsx` and `apps/web-platform/app/(auth)/signup/page.tsx`. The checkbox label MUST contain the literal phrase "Terms & Conditions" AND the literal phrase "Privacy Policy" AND both must be wrapped in `<a>` anchors pointing at distinct URLs (`/pages/legal/terms-and-conditions.html` and `/pages/legal/privacy-policy.html`). If either fails, fix copy inline in this PR.

### FR8: End-to-end test

Add `apps/web-platform/test/e2e/oauth-tc-consent.test.ts` (or `tests/e2e/...` per existing convention; verify at plan time). The test:

- Mocks the Supabase auth callback to simulate successful OAuth code exchange.
- Drives a synthetic GET on `/auth/callback?code=...`.
- Asserts redirect to `/accept-terms` when `users.tc_accepted_version` is NULL.
- POSTs to `/api/accept-terms` with valid CSRF.
- Asserts `users.tc_accepted_version` is updated AND a row exists in `public.tc_acceptances` with matching `version` + `document_sha`.
- Asserts redirect chain proceeds to `/setup-key` (or `/dashboard`).

### FR9: Bump-policy rubric doc

Create `knowledge-base/legal/tc-version-bump-policy.md` documenting the 3-tier change classification:

- **Substantive** (new processing purpose, new processor, changed legal basis, expanded data category, changed retention) → bump major/minor; force re-acceptance.
- **Clarifying** (rewording without semantic change, broken-link fix, added examples) → bump patch; force re-acceptance (current behavior, accept consent fatigue trade-off).
- **Cosmetic** (CSS, markdown formatting, typo) → no bump; document the edit in PR description; CI guardrail (FR6) enforces explicit operator acknowledgment.

CLO sign-off required on this doc before PR Ready-for-review.

### FR10: Close issue #3205

PR body includes `Closes #3205` and a comment summarizing: (a) the shipped surfaces that resolve the original premise (callback gate, middleware gate, WS handshake gate, GRANT lockdown — already on `main`), (b) the audit-bundle gaps R1–R6 addressed by this PR.

## Technical Requirements

### TR1: Migration

- New migration `apps/web-platform/supabase/migrations/009_add_tc_acceptances_ledger.sql` (or the next available `00N_` number — verify at plan time).
- Idempotent (uses `CREATE TABLE IF NOT EXISTS`, `CREATE POLICY IF NOT EXISTS` where supported, or guarded `DO $$` blocks).
- Includes table create, RLS enable, SELECT policy, REVOKE UPDATE on all roles, GRANT INSERT/SELECT to service role only.
- Includes comment on every column with the GDPR purpose.
- Per AGENTS.md `hr-dev-prd-distinct-supabase-projects`: migration MUST be applied to both dev and prd Supabase projects in the ship phase. Document the project IDs in `knowledge-base/project/specs/feat-oauth-tc-consent-3205/migration-checklist.md` (created during work phase).

### TR2: Route handler changes

- `apps/web-platform/app/api/accept-terms/route.ts`: insert ledger row after `users` UPDATE; preserve idempotency at lines 47–50 (no ledger insert if already on current version).
- Keep `validateOrigin` + `rejectCsrf` (lines 25–28) unchanged.
- Sentry mirror on ledger INSERT failure.

### TR3: Middleware change

- `apps/web-platform/middleware.ts`: change fail-open at lines 112–117 to fail-closed. Mirror to Sentry per `cq-silent-fallback-must-mirror-to-sentry`. Add a unit test covering the DB-error branch.

### TR4: WS handler change

- `apps/web-platform/server/ws-handler.ts`: add `tcVersionAtHandshake` session field; add re-check on inbound `start_session`/`chat`/`tool_use` messages with 30-second in-process cache; replace literal `4004` with `WS_CLOSE_CODES.TC_NOT_ACCEPTED`.
- `WS_CLOSE_CODES.TC_NOT_ACCEPTED` is added (or surfaced if already exists) in `apps/web-platform/lib/ws-codes.ts` (verify location at plan time per repo-research finding) and imported by both client (`lib/ws-client.ts`) and server (`server/ws-handler.ts`).

### TR5: Build-time SHA

- `apps/web-platform/scripts/compute-tc-sha.mjs` (or equivalent) reads `docs/legal/terms-and-conditions.md`, computes SHA-256, writes to `apps/web-platform/lib/legal/tc-document-sha.generated.ts`. Added to `next.config.ts` build phase or `package.json` `prebuild` script.
- The generated file is `.gitignored`. `tc-version.ts` re-exports from it.

### TR6: CI workflow

- New file or extension of existing `.github/workflows/web-platform-ci.yml` (or equivalent — verify at plan time).
- Job runs on every PR touching `docs/legal/**`, `plugins/soleur/docs/pages/legal/**`, or `apps/web-platform/lib/legal/**`.
- Computes SHAs; compares to pinned constant; fails on mismatch unless same commit bumps `TC_VERSION`.
- Compares the two T&C copies (canonical and Eleventy mirror) byte-identical.

### TR7: Test stack

- E2E test framework: TBD per Open Question 3. Plan-time options: (a) introduce Playwright (new dep); (b) extend existing vitest with Supabase + Auth mocks. Defaults to (b) unless plan reveals (a) is materially better.

### TR8: Documentation

- `knowledge-base/legal/tc-version-bump-policy.md` — FR9 deliverable.
- Update `knowledge-base/project/learnings/2026-03-20-tc-version-enforcement-surface-parity.md` with a reference to this PR's WS mid-session fix as the third enforcement-surface gap caught by the same rule.

### TR9: Hard-rule applicability

- `hr-write-boundary-sentinel-sweep-all-write-sites`: applies — sweep all write sites of `users.tc_accepted_at` / `users.tc_accepted_version`. Plan must enumerate every site (currently: `POST /api/accept-terms`, `handle_new_user()` trigger via migration 008, callback fallback via `ensureWorkspaceProvisioned` migration). New writes from the RPC (if FR2 alternative chosen) must be added to the sweep.
- `hr-gdpr-gate-on-regulated-data-surfaces`: applies — schemas + auth + API routes touching regulated data. Plan Phase 2.7 and work Phase 2 exit MUST invoke `/soleur:gdpr-gate`.
- `cq-pg-security-definer-search-path-pin-pg-temp`: applies if the RPC alternative is chosen for FR2.
- `cq-silent-fallback-must-mirror-to-sentry`: applies to FR4 and FR5 error paths.
- `cq-nextjs-route-files-http-only-exports`: applies to `app/api/accept-terms/route.ts` modifications (already conformant; preserve).
- `wg-after-merging-a-pr-that-adds-or-modifies` (DB migrations): plan must include the dev + prd migration application checklist.

## User-Brand Impact

(Carry-forward from brainstorm `## User-Brand Impact` section per Phase 0.1 framing — "all of them" selected.)

- **Artifact:** Consent record on `users.tc_accepted_at` / `users.tc_accepted_version` (today) plus new `public.tc_acceptances` ledger.
- **Vector:** First paid customer, counsel, or regulator asks Soleur to demonstrate when, to which version, and how a user accepted Terms.
- **Threshold:** **Single-user incident.** A single missing or fabricated consent record is a GDPR Art. 7(1) breach and breaks the trust-before-revenue commitment in roadmap T2.
- **Worst outcomes:**
  - **Legal dispute, no consent record** — destroyed prior-version evidence after `TC_VERSION` bump (R1). Closed by FR1+FR2.
  - **Trust breach / PII leak via fail-open** — Supabase incident lets a non-accepted user reach `/dashboard` (R2). Closed by FR4.
  - **Stale-consent agent stream** — long-lived WS session keeps streaming after `TC_VERSION` bump (R3). Closed by FR5.

`user-impact-reviewer` MUST run at PR review time per `hr-weigh-every-decision-against-target-user-impact`.

## Domain Review (carry-forward)

### CLO

R1 is must-close before paid-customer-#1; gates Phase 4.10 Stripe live. Git/build SHA fingerprint is sufficient evidence vs. full content-hash. IP/UA capture deferred pending LIA. Bundled-consent design defensible IF FR7 lands. Bump-policy rubric (FR9) is must-tighten. CLO sign-off required before PR Ready-for-review on (a) FR1 schema (SELECT policy, RLS, GRANT shape), (b) FR9 rubric content, (c) FR7 verify outcome.

### CPO

Close #3205 as resolved-on-main; the bundled PR is the new tracking surface. R1 is a Phase 4 prerequisite (gates 4.10 Stripe live, NOT a Phase 2 reopen). 0 beta users today means retrofitting the ledger produces consistent records going forward. Finer-grained bump UX deferred to Phase 4.1. CPO sign-off required at brand-survival re-check.

### CTO

Premise stale; bundle correct. SECURITY DEFINER RPC option preferred for FR2 atomicity (resolve at plan). Build-time SHA is the right contract vs. request-time. Keep `TC_VERSION` as code constant. Replace literal `4004` with imported `WS_CLOSE_CODES.TC_NOT_ACCEPTED`. Recommend running `/soleur:architecture create` if FR1 + FR3 are accepted (they together constitute an architectural decision on "how we discharge ICO/GDPR consent records of evidence").

## Open Questions (carry-forward from brainstorm)

1. **RPC vs. multi-statement route handler for FR2.** Resolve at plan.
2. **IP/UA capture today (nullable columns populated) vs. nullable-now-decide-later.** CLO to gate at plan or PR review.
3. **E2E stack: Playwright vs. vitest + mocks.** Plan-time decision.
4. **Privacy Policy as separate column family.** Out of scope this PR; reconsider if FR7 verify fails AND CLO opts for separation.

## Acceptance Criteria

- All FR1–FR10 implemented.
- All TR1–TR9 satisfied.
- `/soleur:gdpr-gate` clean at plan Phase 2.7 and work Phase 2 exit.
- `user-impact-reviewer` runs at PR review with no must-close findings.
- CLO sign-off recorded on FR1 schema + FR9 rubric + FR7 verify outcome.
- CPO sign-off recorded on brand-survival re-check.
- Migration applied to both dev and prd Supabase projects per `hr-dev-prd-distinct-supabase-projects`; checklist artifact in this spec directory.
- PR #3853 body declares `Closes #3205` with comment summary.
