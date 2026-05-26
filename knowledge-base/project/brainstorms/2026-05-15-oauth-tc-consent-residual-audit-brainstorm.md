---
name: 2026-05-15-oauth-tc-consent-residual-audit-brainstorm
date: 2026-05-15
topic: server-side T&C consent enforcement on OAuth signup path — residual-risk audit
status: complete
issue: "#3205"
branch: feat-oauth-tc-consent-3205
pr: "#3853"
lane: cross-domain
brand_survival_threshold: single-user incident
related:
  - https://github.com/jikig-ai/soleur/issues/3205
  - https://github.com/jikig-ai/soleur/pull/3199
  - https://github.com/jikig-ai/soleur/pull/898
  - https://github.com/jikig-ai/soleur/pull/927
---

# Brainstorm: OAuth T&C Consent — Residual-Risk Audit

## TL;DR

Issue #3205 was filed assuming server-side T&C consent enforcement was **missing** at the OAuth callback path. That premise is **stale**. Enforcement shipped via PR #898 → #927 → migrations 005–008 on 2026-03-20:

1. OAuth callback (`apps/web-platform/app/(auth)/callback/route.ts:206-210`) redirects to `/accept-terms` when `tc_accepted_version != TC_VERSION`.
2. Middleware (`apps/web-platform/middleware.ts:125-141`) re-checks consent on every authenticated request to a non-exempt path.
3. WebSocket handshake (`apps/web-platform/server/ws-handler.ts:321-324`) closes the socket with code `4004` on mismatch.
4. Column-level GRANT lockdown (migration `006_restrict_tc_accepted_at_update.sql`) — `tc_accepted_at` / `tc_accepted_version` are service-role-write-only; client cannot self-set.
5. Single write path (`POST /api/accept-terms`) — CSRF-validated, service-role, idempotent.

The "user flips React state, clicks OAuth, lands in app with no server-side consent record" path described in #3205 is closed today on `main`. The brainstorm pivoted to **audit residual GDPR Art. 7(1) / ICO demonstrability gaps** in the shipped implementation. Six gaps surfaced (R1–R6). Decision: ship all six in this worktree's bundled PR (#3853) and close #3205.

## What We're Building

A residual-risk fix-up that closes six gaps in the existing T&C consent recording surface:

- **R1. Append-only `tc_acceptances` ledger + build-time `TC_DOCUMENT_SHA`** — `users.tc_accepted_at` is overwritten on `TC_VERSION` bump, destroying prior-version evidence. Add an INSERT-only audit table that records each acceptance event (`user_id, version, accepted_at, document_sha`). `POST /api/accept-terms` writes the row after the `users` UPDATE succeeds (CTO recommends wrapping both in a `SECURITY DEFINER` RPC pinned to `search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`). Existing `users.tc_accepted_*` columns become the denormalized "latest" cache. Build-time SHA-256 of `docs/legal/terms-and-conditions.md` is emitted to `apps/web-platform/lib/legal/tc-version.ts` as `TC_DOCUMENT_SHA` and persisted with each acceptance.
- **R2. Middleware fail-closed on DB error** — `middleware.ts:112-117` currently fails open if the Supabase SELECT errors. Change to redirect to `/accept-terms` on DB error (fail-closed). Mirror to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
- **R3. WebSocket mid-session re-check** — Today `ws-handler.ts:321-324` checks `tc_accepted_version` only at handshake; long-lived sockets keep streaming after a `TC_VERSION` bump until disconnect. On each `start_session` / `chat` entry point, re-check `tc_accepted_version` (cache as `tc_version_at_handshake` per session, only re-query DB on agent-bound message types). Close with `4004` if stale.
- **R4. CI guardrail against silent T&C edit drift** — Add CI job that computes SHA-256 of `docs/legal/terms-and-conditions.md` (and the Eleventy mirror `plugins/soleur/docs/pages/legal/terms-and-conditions.md`) and compares against `TC_DOCUMENT_SHA` recorded in `lib/legal/tc-version.ts`. Mismatch fails the build unless the same commit bumps `TC_VERSION`. Dovetails with R1.
- **R5. Bundled-consent UI verify** — Confirm `/accept-terms` page checkbox and `/signup` checkbox copy name BOTH "Terms & Conditions and Privacy Policy" with separate linked anchors (GDPR Art. 7(2) "distinguishable" consent for a bundled-acceptance model). Fix copy if mismatched. This is a verify-then-fix-inline task, not a separate sub-feature.
- **R6. End-to-end coverage of OAuth → /accept-terms → /dashboard** — No current e2e test exercises this path (only vitest unit tests). Add a Playwright (or vitest with mocked Supabase + mocked OAuth provider) test that drives: OAuth callback → `/accept-terms` redirect → POST `/api/accept-terms` → `/dashboard`. Also exercises the new `tc_acceptances` row insert.

Bundled as one PR on `feat-oauth-tc-consent-3205` (PR #3853). Closes #3205.

## Why This Approach

- **Single PR ships brand-survival + hygiene together.** Bundling vs. splitting was the chosen scope. Trade-off: larger blast radius for review, but the surface area is narrow (T&C consent recording only) and the gaps share migration / route / middleware files. Splitting would create N rebasing dependencies across PRs that touch overlapping files.
- **CLO + CPO + CTO triad consensus.** All three agents concur that R1 is the only brand-survival-threshold gap (gates Phase 4.10 Stripe live activation per `roadmap.md:324`). R2–R6 are single-user-incident class but cheap. Bundle is rational.
- **Past remediation history (PR #898/#927 + migration 007) shows the team has lived through an Art. 7(1) fabricated-consent incident.** The append-only ledger closes the loop on that remediation — without it, a future similar incident has no audit trail to remediate against.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Issue #3205 disposition | Close once #3853 merges (PR will reference `Closes #3205` in body) | Premise is stale; shipped surfaces + bundled audit fix supersedes the original scope |
| Schema for audit ledger | New table `public.tc_acceptances` (INSERT-only via service-role; `SELECT` self-only via RLS); keep `users.tc_accepted_*` columns as denormalized latest cache | Append-only ledger is the GDPR-demonstrable record; column cache stays for fast read-path in middleware/callback (avoid join overhead) |
| Existing users / backfill | No backfill of historical acceptances into the new ledger; existing `users.tc_accepted_at` rows are the only record of the current acceptance and remain valid. Going forward, every acceptance writes a new ledger row | Backfill would fabricate evidence (we don't have IP/UA/SHA for past acceptances). Same lesson as PR #898/#927 — never fabricate consent metadata |
| `/accept-terms` interaction | Unchanged — existing single path serves both OAuth and OTP signups; consent recording becomes "UPDATE `users` row + INSERT `tc_acceptances` row in one RPC" | Existing flow is correct per all three agents; only the record-keeping changes |
| Document fingerprint | Build-time `TC_DOCUMENT_SHA` constant emitted alongside `TC_VERSION`; computed from `docs/legal/terms-and-conditions.md` | CDN race window if computed at request time; build-time pin is the contract. Matches CLO's "git SHA fingerprint" recommendation cheaply |
| `TC_VERSION` source | Keep as code constant in `lib/legal/tc-version.ts` (NOT moved to DB) | DB-driven version introduces doc-build / app-deploy race; CI guardrail (R4) is the better primitive |
| IP / user-agent capture at acceptance | **Deferred** — ledger schema includes nullable `ip_hash` and `user_agent` columns, but the route does NOT populate them yet. Capture remains an Open Question pending LIA | CLO: raw IP is itself personal data; requires Legitimate Interest Assessment before logging. Acceptable for pre-revenue / B2C signups; required for first enterprise contract |
| `TC_VERSION` bump policy rubric | Ship a 3-tier written policy in `knowledge-base/legal/tc-version-bump-policy.md` (material / clarifying / cosmetic) | CLO action; cheap; the existing inline comment in `tc-version.ts` is insufficient at scale |
| Bump-on-clarifying-edit UX | Out of scope for this PR (CPO flagged finer-grained UX for Phase 4.1); current "force re-acceptance on any bump" is correct for 0-beta-user state | Defer to a follow-on issue when first external user onboards |
| WS close code source | Replace literal `4004` in `ws-handler.ts:322` with imported `WS_CLOSE_CODES.TC_NOT_ACCEPTED` from shared client/server constants | Repo-research surfaced the drift risk; trivial fix; bundle with R3 |

## Open Questions

1. **RPC vs. multi-statement route handler for R1.** CTO recommends a `SECURITY DEFINER` RPC `accept_terms(version, sha, ip_hash, ua)` pinned to `search_path = public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`). Alternative: keep two service-role statements in the route handler. RPC is more atomic and centralizes write boundary; route-handler is simpler. **Resolve at plan time.**
2. **IP / UA capture today vs. nullable-now.** Two options: (a) ship nullable columns now, leave route NOT populating them, decide at first enterprise deal; (b) drop columns from initial schema and add later when LIA done. (a) is sticky-but-cheap. **CLO to gate at plan or PR review.**
3. **E2E test stack choice.** No Playwright config exists in the web-platform today (repo-research). Options: (a) add Playwright to web-platform (introduces new dependency, ~50 MB CI image growth); (b) vitest with mocked Supabase + mocked OAuth provider (in-tree pattern, less realistic). **CTO/CPO to gate at plan.**
4. **Privacy Policy as separate column family.** CLO/research agree that today's bundled-consent design is GDPR-defensible IF `/accept-terms` checkbox names both documents with separate links. If R5 verify finds the copy is mismatched AND CLO later decides separate columns are needed, that's a follow-on issue (scope out of this PR).

## User-Brand Impact

- **Artifact:** Consent record on `users.tc_accepted_at` / `users.tc_accepted_version` (and new `tc_acceptances` ledger).
- **Vector:** First paid customer or counsel/regulator asks Soleur to demonstrate when, to which version, and how a user accepted Terms.
- **Threshold:** **Single-user incident** — a single missing or fabricated consent record exposes Soleur to GDPR Art. 7(1) breach and breaks the trust-before-revenue commitment in roadmap T2 ("Secure Before Beta").
- **Worst outcomes (per Phase 0.1 framing "all of them"):**
  - **Legal dispute, no consent record** — already partly mitigated by `tc_accepted_version`+`tc_accepted_at` columns, but overwrite-on-bump destroys multi-version history; R1 closes this.
  - **Trust breach / cross-tenant or PII leak** — middleware fail-open on DB error (R2) is the live single-user vector today; on Supabase incident, a non-accepted user could reach `/dashboard` and see workspace state.
  - **Auth bypass / session hijack** — WS mid-session no re-check (R3) means a `TC_VERSION` bump doesn't force re-consent for live sockets; for a long-running agent stream, output continues against stale consent.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

User-brand-critical triad mandatory per Phase 0.1; other domains did not match Assessment Questions.

### Engineering (CTO)

**Summary:** Premise stale. Confirmed three single-user-incident class gaps not in #3205 body — middleware fail-open (R2), WS mid-session (R3), no CI guardrail for doc drift (R4). Recommended build-time `TC_DOCUMENT_SHA` constant, kept `TC_VERSION` as code constant (DB-source introduces deploy/CDN race). `SECURITY DEFINER` RPC pinned `search_path` for the ledger write.

### Legal (CLO)

**Summary:** Append-only `tc_acceptances` ledger is the single must-close-before-paid-customer-#1 gap (GDPR Art. 7(1) demonstrability). Git/build SHA is sufficient evidence; full content-hash is overkill. IP/UA capture requires Legitimate Interest Assessment first. Verify `/accept-terms` checkbox names BOTH T&C and Privacy Policy (bundled-consent under Art. 7(2) "distinguishable"). Written `TC_VERSION` bump-policy rubric (material/clarifying/cosmetic) is must-tighten.

### Product (CPO)

**Summary:** Issue #3205 should close as resolved-on-main; the audit-ledger gap (R1) gates roadmap Phase 4.10 (Stripe live activation), not Phase 2 ("Secure Before Beta"). 0 beta users today; retrofitting the ledger before recruitment (4.1) produces consistent records. Finer-grained "material vs. cosmetic" bump UX deferred to a separate Phase 4.1 prerequisite. Recommend bundling IP/UA + fingerprint into R1 PR; drop WS close-code-rename as a standalone item.

## Capability Gaps

None new. All work is within existing surfaces: Postgres migrations + Next.js route handler + Next.js middleware + WS handler + CI workflow + Eleventy doc — all of which have established patterns in this repo (verified by repo-research-analyst against `apps/web-platform/supabase/migrations/`, `app/api/`, `middleware.ts`, `server/ws-handler.ts`, `.github/workflows/`).

## Next Steps

- Run `skill: soleur:plan` from inside `.worktrees/feat-oauth-tc-consent-3205/` to break R1–R6 into tasks.
- Tag PR #3853 body with `Closes #3205` once ready.
- CLO sign-off required on (a) IP/UA Open Question 2 resolution and (b) the bump-policy rubric doc before PR Ready-for-review.
