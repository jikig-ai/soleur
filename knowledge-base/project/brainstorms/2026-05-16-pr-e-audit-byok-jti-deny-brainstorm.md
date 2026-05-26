---
title: PR-E — audit_byok_use writer sweep + is_jti_denied consumer (#3887)
date: 2026-05-16
status: brainstormed
issue: 3887
umbrella_issue: 3244
predecessor: 3883
branch: feat-pr-e-audit-byok-jti-deny
worktree: .worktrees/feat-pr-e-audit-byok-jti-deny/
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# PR-E — audit_byok_use writer sweep + is_jti_denied consumer

## Why now (carry-forward from PR-C plan §Tracked Deferrals + #3887 body)

> "Sequence audit-writer BEFORE 2nd hosted founder onboards OR GA exposure,
> whichever first. Art. 5(2) accountability — a botched audit-writer
> pollutes WORM ledger irreversibly."

Today (2026-05-16): 1 hosted founder. `is_jti_denied()` reader shipped in
migration 037 but has ZERO consumer call sites in `apps/`. The
`RuntimeAuthError.cause = "denied_jti"` discriminant is declared in
`apps/web-platform/lib/supabase/tenant.ts:65` but no code raises it —
the variant is scaffolding-only. Any leaked or stolen JWT (jti) is
usable for its full 10-min TTL with no in-band kill-switch.

A second hosted founder makes the surface multi-tenant in posture even
when not in data; revocation enforcement must precede that step.

## User-Brand Impact (framing — carries into plan)

**If this lands broken, the user experiences:** a closed-preview founder
sees `RuntimeAuthError(denied_jti)` falsely on a fresh JWT (false-positive
on the deny-list check) and loses access to the runtime mid-session, OR
a BYOK audit row is silently dropped on a path the writer sweep missed
and the founder's billing dashboard under-reports a turn that actually
spent against their key.

**If this leaks, the user's data / money is exposed via:** (a) a runtime
JWT stolen by any vector (XSS in a third-party tool surface, log
exfiltration during a Sentry incident, plaintext in a future deploy
artifact, MITM on a transient HTTP downgrade) remains valid for its
full TTL — the founder's key + tenant data are usable through PostgREST
with no in-band kill-switch even after revocation intent is recorded;
(b) a BYOK SDK call path that bypasses `runWithByokLease`'s
`persistTurnCost` writer charges the founder's Anthropic key but
leaves no row in the WORM ledger — Art. 5(2) "ability to demonstrate"
fails on a DSAR or audit request.

**Brand-survival threshold:** `single-user incident`. Carry-forward from
PR-B and PR-C. The accountability + revocation surface is identical
posture to the Art. 5(2) framing both predecessors carried.

## CLO + CPO + CTO framing (Phase 0 stand-in)

`USER_BRAND_CRITICAL=true` per the threshold. Per brainstorm domain
config, all three leaders weigh in here:

- **CLO (legal/compliance):** Art. 5(2) accountability gap is the
  load-bearing legal driver. The WORM ledger is the controller-side
  evidence of "how the founder's data and key were used." A BYOK call
  path that bypasses `write_byok_audit` does not satisfy Art. 5(2);
  an unrevokable JWT does not satisfy Art. 32 "ability to ensure the
  ongoing confidentiality." PR-D (#3883) was the storage-RLS layer of
  the same accountability surface; PR-E is the audit-writer + JWT-
  revocation layer. Neither expands the personal-data surface; no PA1
  amendment expected. PA2 (Sentry sub-processor) was amended in
  PR-D. The deny-list table records `(jti, founder_id, denied_at,
  reason)` — `founder_id` is already in scope for PA1. Article 30
  register: no new processing activity (revocation enforcement is
  part of the existing "authentication" activity), but the §Active
  Items in `knowledge-base/legal/compliance-posture.md` will close
  the open `Art. 5(2) audit-writer gap` entry post-merge.

- **CPO (product blast-radius):** Closes the last open advisory from
  the PR-B sequencing matrix before the 2nd hosted founder. A
  false-positive `denied_jti` rejection presents identically to a
  rate-limit rejection — same `RuntimeAuthError` class, same
  client-facing "Authentication unavailable; retry shortly" message.
  Recovery is operator-mediated (delete the deny-list row OR rotate
  the founder's session). Acceptable single-user incident class
  because the founder retains email + dashboard access; only the
  runtime is gated. ux-design-lead: not invoked — no new UI surface.

- **CTO (architecture blast-radius):** Two distinct invariants:
  (1) `is_jti_denied(jti)` MUST be called between mint and JWT
  issuance/return on every code path that yields a runtime JWT —
  the canonical site is `mintFounderJwt` in `lib/supabase/tenant.ts`,
  which today is the SOLE mint path. (2) `persistTurnCost`
  (the writer wrapper for `write_byok_audit`) MUST be invoked on
  EVERY BYOK SDK call path inside `runWithByokLease`. Sweep
  enumeration: `agent-runner.ts` (3 sites) + `cc-dispatcher.ts` (1
  site) + `pdf-chapter-router.ts` (1 site, currently NOT calling
  `persistTurnCost` — its cost rolls up to the outer turn's totals).
  CI lint enforcement: a new test file under
  `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`
  source-greps every `runWithByokLease` call site and asserts the
  same file contains a `persistTurnCost` call OR a structured
  comment `// byok-audit-writer-sweep: out-of-scope — <reason>`.
  Patterned after `.service-role-allowlist` enforcement.

## Schema-check decision: writer for the deny-list

`migration 037_audit_byok_use.sql:122-148` declared `denied_jti` as a
service-role-only table with NO writer RPC. The PR-B plan §1.4 line
that motivated this brainstorm reads:

> "`public.denied_jti (jti uuid primary key, founder_id uuid, denied_at
> timestamptz default now())` (RLS-on, zero policies, service-role-only
> insert)."

Three possible writer postures for PR-E. We pick (C) and defer (B):

- **(A) Add a `revoke_jti(p_jti, p_founder_id, p_reason)` RPC + admin
  call-site in PR-E.** Rejected as out-of-scope per #3887: "admin UI
  for jti revocation deferred." No admin UI today; an RPC with no
  caller would be dead code.

- **(B) Insert on logout / session-end / account-delete.** Tempting
  because there's already an `account-delete.ts` boundary. Rejected
  for PR-E because (1) per-logout deny-list inserts at 60/hour mint
  rate could grow the table unboundedly without a TTL sweep; (2)
  semantic gap — the deny-list's job is REVOCATION (compromise
  response) not LIFECYCLE (normal logout). A logged-out JWT just
  expires at TTL (10 min); paying a deny-list row to bring it down
  from 10 min to instant is not load-bearing. Defer to a follow-up
  issue if we ever want session-end-driven revocation. **Filed:**
  to be created at deepen-plan time per `wg-when-deferring-a-capability-create-a`.

- **(C) Read-only consumer in PR-E + manual revocation via DBA / SQL
  console as the documented operator surface.** PR-E ships the
  `is_jti_denied(jti)` check at the mint path so existing INSERTs
  (via SQL Editor / psql / supabase-mcp) take effect. This matches
  the migration 037 author's stated posture ("service-role-only
  insert"; no admin RPC implied). Re-evaluation trigger: when the
  2nd hosted founder onboards OR a real revocation event occurs
  (compromise drill), promote to (A) with a scoped admin RPC.

This decision MUST be explicit in the plan body and PR description so
review-time agents (user-impact-reviewer, security-sentinel) can audit
the "where does a deny-list row come from?" question without re-deriving
the trade-off.

## Writer-sweep enumeration (audit-row coverage)

Producer = the BYOK SDK call path. Audit-row = `write_byok_audit` via
`persistTurnCost` in `apps/web-platform/server/cost-writer.ts:64`.

| # | File | Line | Construct | BYOK? | Audit? | Disposition |
|---|------|------|-----------|-------|--------|-------------|
| 1 | `apps/web-platform/server/agent-runner.ts` | 863 | `runWithByokLease(userId, …) { /* session driver */ }` | Yes | Yes — `persistTurnCost` at `:1876` (inside the lease) | Sweep PASS. |
| 2 | `apps/web-platform/server/agent-runner.ts` | 1607 | `query({...})` inside the lease above | Yes (parent lease) | Yes — parent's `persistTurnCost` | Sweep PASS (covered by parent). |
| 3 | `apps/web-platform/server/agent-runner.ts` | 2363 | `runWithByokLease(userId, …)` for re-dispatch | Yes | Yes — re-entrant `persistTurnCost` | Sweep PASS. |
| 4 | `apps/web-platform/server/cc-dispatcher.ts` | 883 | `runWithByokLease(userId, …) { sdkQuery(...) }` | Yes | Yes — `persistTurnCost` at `:1705` | Sweep PASS. |
| 5 | `apps/web-platform/server/pdf-chapter-router.ts` | 148 | `query({...})` for chapter-router single-turn | Yes (inherits parent lease via ALS) | **No direct call** — `routingCostUsd` rolls into parent `persistTurnCost` | Sweep: TWO sub-options. **(5a) Accept** as out-of-scope, document the rollup so the dashboard's per-turn audit row covers the router pre-roll; **(5b) Emit** a distinct audit row per router turn (`agent_role: "pdf-chapter-router"`) so the WORM ledger preserves the routing decision's cost. Brainstorm picks (5a) for PR-E (single audit row per logical user-turn matches the §3.1 dashboard's grain; the router is a sub-call of the parent agent's turn). Re-evaluate when a per-sub-call dashboard is built. |
| 6 | `apps/web-platform/server/safe-bash.ts` | — | No SDK invocation | No | N/A | Out-of-scope (not a BYOK path). |
| 7 | `apps/web-platform/server/bash-sandbox.ts` | — | No SDK invocation | No | N/A | Out-of-scope (not a BYOK path). |
| 8 | `apps/web-platform/server/ws-handler.ts` | — | No SDK invocation | No | N/A | Out-of-scope (websocket dispatch only). |
| 9 | `apps/web-platform/server/soleur-go-runner.ts` | 42, 692 | Imports SDK types only; runtime SDK call is inside `cc-dispatcher` | No (delegates) | N/A | Out-of-scope (delegates to #4 cc-dispatcher). |

The PR description's writer-sweep section MUST list all 9 rows with
disposition. The CI lint runs over the same enumeration.

## is_jti_denied consumer wiring

Single canonical mint path today: `mintFounderJwt(userId, opts)` in
`apps/web-platform/lib/supabase/tenant.ts:124`. Returns
`MintedJwt { jwt, ttlSec, mintedAt }` to `getFreshTenantClient(userId)`
which caches it. Insertion site for the deny-list probe MUST be
**between mint (sign) and return** so a deny-listed jti never enters
the cache.

Two operator-correct insertion points; brainstorm picks (B):

- **(A) Probe inside `precheck_jwt_mint` RPC** (SQL-side). Atomic with
  jti generation, no race window. Rejected because (1) the SQL RPC
  generates a FRESH `gen_random_uuid()` jti — by definition not yet
  on the deny-list (cardinality of `jti` space is 2^122). Probing a
  freshly-generated jti is pointless. The threat model is REUSE of a
  cached / leaked / replayed JWT, not the first mint.

- **(B) Probe inside `getFreshTenantClient` on cache-hit path AND
  inside `mintFounderJwt` post-sign on cache-miss path.** This is
  the correct architectural placement:
  - Cache-hit path (`getFreshTenantClient:248`): after `await inflight`
    resolves to a cached `CacheEntry`, before returning the cached
    `entry.client`, call `is_jti_denied(decodedJti)`. On true: evict
    cache entry, fall through to remint. On false: return cached
    client.
  - Cache-miss path: after `mintFounderJwt` returns a fresh MintedJwt
    but before installing it in the cache, call `is_jti_denied(jti)`.
    On true: discard, throw `RuntimeAuthError("denied_jti", ...)`.
    On false: install + return.

  This matches the migration 037 header comment:
  > "Auth probe in lib/supabase/tenant.ts checks is_jti_denied(jti)
  >  before accepting a cached JWT in getFreshTenantClient."

  The fresh-mint check is defensive against a race where (i) operator
  inserts a deny-list row, (ii) `precheck_jwt_mint` generates that
  same UUID by collision (probability 0 at 2^122) — the load-bearing
  call is the cache-hit one.

**Decoded-jti extraction:** the JWT signed locally has its claim set
already known in scope (`payload.jti`). Cache the jti alongside the
client in `CacheEntry` (extend struct) so the cache-hit check can
read it without re-decoding the JWT.

**Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`:** on
the deny branch, `reportSilentFallback(null, { feature: "tenant-jwt",
op: "is_jti_denied.deny", extra: { userId, jti } })`. NOTE — `jti` is
a random UUID, not a personal identifier; safe to log raw (`userId`
goes through the pseudonymize-at-Sentry hook already in scope per ADR-
028/029). This is the load-bearing observability for "revocation took
effect."

**Error code:** the PR-B plan §1.4 specifies the `denied_jti` cause
variant on `RuntimeAuthError`. The proposal "JWT_REVOKED" in #3887 is
the user-facing error CODE; the internal discriminant stays as
`cause: "denied_jti"`. The client-facing message remains
"Authentication unavailable; retry shortly" — same as `jwt_mint` /
`rotation` per the sanitization posture in `lib/auth/error-messages.ts`.

## Integration tests (under `TENANT_INTEGRATION_TEST=1`)

Three suites, all in `apps/web-platform/test/server/`:

1. **`tenant-jwt-deny.tenant-isolation.test.ts`** (new)
   - Test A: fresh mint with empty `denied_jti` → success, jti in
     returned MintedJwt, client usable.
   - Test B: insert `(jti, founder_id, now(), 'test-revoke')` into
     `denied_jti` then call `getFreshTenantClient(userId)` (cache-hit
     path, prior mint cached) → throws `RuntimeAuthError(cause:
     "denied_jti")`. Asserts Sentry mirror fired via the test-only
     `_resetSentryEvents` introspection.
   - Test C: deny-list insert BEFORE first mint → fresh mint returns,
     cache-installation deny check fires, throws same error. (Negative
     control for cache-miss path.)
   - Test D (negative): insert an UNRELATED jti → original session
     unaffected.

2. **`audit-byok-use.tenant-isolation.test.ts`** (new)
   - Test A: WORM enforcement. `service.from("audit_byok_use").update(...)`
     raises P0001. Same for `.delete(...)`. Asserts the trigger fires.
   - Test B: `write_byok_audit` RPC writes a row visible to the
     founder's tenant client (SELECT-policy validation).
   - Test C: tenant-client `.rpc("write_byok_audit", ...)` is rejected
     (already partially covered by `agent-runner.tenant-isolation.test.ts:305`;
     this file re-asserts at the audit-writer boundary).

3. **`byok-audit-writer-sweep.test.ts`** (new — source-grep CI lint, NOT
   a tenant-isolation suite; runs in the standard `webplat` vitest pass)
   - Enumerates all `runWithByokLease(` call sites under
     `apps/web-platform/server/` via fs.readFileSync source-grep.
   - For each site's containing file: asserts the file ALSO contains a
     `persistTurnCost(` call OR a structured comment line
     `// byok-audit-writer-sweep: out-of-scope — <one-line reason>`.
   - Maintains a fixture allowlist for the pdf-chapter-router rollup
     case (row 5a above) — exactly one entry, justified inline.

## Article 30 register amendment

Re-checked PR-D's PA2 amendment (Sentry sub-processor) and PR-B's
original PA1 (Supabase processing activity). PR-E's surface:

- `denied_jti` table — already in PA1 scope via the "authentication"
  processing activity (the migration shipped in PR-B, before PR-E).
- `is_jti_denied(jti)` RPC — read-only, same activity, no expansion.
- Sentry deny-event mirror — `userId` pseudonymized; `jti` is random
  UUID (not personal data per Art. 4(1)); PA2's existing scope
  covers.

**Expected outcome:** no PA1/PA2 amendment. The plan body will state
this explicitly and the PR body will carry the `no surface change`
note (per #3887 description requirement). If gdpr-gate at plan Phase
2.7 disagrees, fold its finding in.

## Out of scope (deferrals — tracked at deepen-plan)

Per #3887:
- Admin UI for jti revocation. Deferral issue at deepen-plan time per
  `wg-when-deferring-a-capability-create-a`.
- Token rotation policy / automated revocation triggers.
- Re-issuing tokens after revocation (separate UX flow — currently
  the founder remints by reconnecting; deny-list works as kill-switch
  only).
- Refactoring `write_byok_audit` schema. Schema is fine for the §3.1
  dashboard's grain.

Brainstorm-emergent (file deferral issues at deepen-plan time):
- (B) above: deny-list TTL sweep / logout-driven revocation.
- (5b) above: per-pdf-chapter-router-turn audit row.

## Domain Assessments

- **CLO:** reviewed. No Art. 30 amendment; Art. 5(2) accountability
  gap closes. Compliance-posture.md Active Items entry will close at
  post-merge.
- **CTO:** reviewed. Two invariants enumerated above; CI lint
  prescribed. `cq-pg-security-definer-search-path-pin-pg-temp` not
  triggered (no new SQL functions). `hr-write-boundary-sentinel-sweep-all-write-sites`
  triggers — plan's `Files to Edit` must enumerate all 9 rows of the
  sweep table.
- **CPO:** reviewed. Single-user-incident threshold confirmed;
  CPO sign-off required at plan time (carried into plan frontmatter
  as `requires_cpo_signoff: true`). No new UI surface; no
  ux-design-lead invocation.

## Capability Gaps (specialists outside the standard plan pipeline)

None. user-impact-reviewer at review time (per `review/SKILL.md`
conditional-agent block #15 — auto-fires on `single-user incident`
threshold) is the only review-phase specialist required beyond the
standard data-integrity-guardian + security-sentinel + semgrep-sast +
gdpr-gate (conditional).

## Decisions to lock into plan

1. Deny-list writer is OUT OF SCOPE for PR-E. Read-only consumer +
   manual SQL operator surface as documented kill-switch.
2. Consumer probe site: `lib/supabase/tenant.ts` `getFreshTenantClient`
   (cache-hit) + post-mint installation check (cache-miss). NOT inside
   `precheck_jwt_mint` RPC.
3. Pdf-chapter-router rollup case (5a) — no separate audit row; doc
   the rollup in the writer-sweep table.
4. Three new integration suites under `TENANT_INTEGRATION_TEST=1`
   gate; one regular vitest sweep-lint suite.
5. No Article 30 amendment expected.
6. Brand-survival threshold `single-user incident` carries forward.
