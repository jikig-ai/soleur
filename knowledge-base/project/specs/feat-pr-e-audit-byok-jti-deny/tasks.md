---
title: PR-E — Tasks
date: 2026-05-16
spec: knowledge-base/project/specs/feat-pr-e-audit-byok-jti-deny/spec.md
plan: knowledge-base/project/plans/2026-05-16-feat-pr-e-audit-byok-jti-deny-plan.md
branch: feat-pr-e-audit-byok-jti-deny
worktree: .worktrees/feat-pr-e-audit-byok-jti-deny/
lane: cross-domain
---

# Tasks — PR-E audit_byok_use writer sweep + is_jti_denied consumer

## 1. Phase 0 — Preconditions (verify before TDD)

- [ ] 1.1 Confirm CWD = worktree path.
- [ ] 1.2 Confirm branch = `feat-pr-e-audit-byok-jti-deny`.
- [ ] 1.3 `grep -rn "is_jti_denied" apps/` returns 0 production consumers.
- [ ] 1.4 `grep -rn "persistTurnCost" apps/` returns 2 callers (agent-runner, cc-dispatcher).
- [ ] 1.5 Migration 037 shape matches PR-B plan §1.4 (re-verify per `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`).
- [ ] 1.6 13 existing `*.tenant-isolation.test.ts` files inventoried.

## 2. Phase 2 — Consumer wiring (RED → GREEN → REFACTOR)

### 2.1 RED — write failing integration tests

- [ ] 2.1.1 Create `apps/web-platform/test/server/tenant-jwt-deny.tenant-isolation.test.ts` with Tests A, B, C, D outlined in plan §Test Detail.
- [ ] 2.1.2 Add a test-only export `_peekCachedJti(userId)` (or analogous introspection) in `lib/supabase/tenant.ts` so Test B can read the cached jti without re-decoding the JWT.
- [ ] 2.1.3 Run the new suite under `TENANT_INTEGRATION_TEST=1` → Tests B + C fail (no consumer wired yet). Tests A + D pass (no behavior change for empty deny-list or unrelated jti). Commit RED state.

### 2.2 GREEN — wire the consumer

- [ ] 2.2.1 Widen `MintedJwt` interface (`lib/supabase/tenant.ts:44`) with `jti: string`.
- [ ] 2.2.2 Widen `CacheEntry` interface (`lib/supabase/tenant.ts:202`) with `jti: string`.
- [ ] 2.2.3 In `mintFounderJwt`, surface `row.jti` in the returned `MintedJwt`.
- [ ] 2.2.4 In `getFreshTenantClient` cache-hit branch: after `await inflight`, BEFORE the freshness check, call the deny probe on `entry.jti`. On `true`: evict the cache entry, emit Sentry mirror via `reportSilentFallback(null, { feature: "tenant-jwt", op: "is_jti_denied.deny", extra: { userId, jti: entry.jti } })`, fall through to remint. On `false`: continue.
- [ ] 2.2.5 In `getFreshTenantClient` cache-miss branch: after `minting` resolves, before returning `entry.client`, call the deny probe on `entry.jti`. On `true`: evict from cache, emit Sentry mirror (same shape), throw `new RuntimeAuthError("denied_jti", "Authentication unavailable; retry shortly")`. On `false`: return `entry.client`.
- [ ] 2.2.6 Run the test suite → Tests B + C now pass.

### 2.3 REFACTOR

- [ ] 2.3.1 Extract a private `async function denyProbe(jti: string, userId: UserId): Promise<boolean>` that calls `getServiceClient().rpc("is_jti_denied", { p_jti: jti })` and emits the Sentry mirror on `true`. Both call sites use it; throw at the call site (cache-miss) only.
- [ ] 2.3.2 Add JSDoc to `denyProbe` explaining the cache-hit-vs-cache-miss contract.
- [ ] 2.3.3 Re-run the suite → still green.

## 3. Phase 3 — WORM enforcement tests

- [ ] 3.1 Create `apps/web-platform/test/server/audit-byok-use.tenant-isolation.test.ts` with three tests:
  - 3.1.1 UPDATE raises P0001.
  - 3.1.2 DELETE raises P0001.
  - 3.1.3 Tenant-client SELECT returns only own-founder rows.
- [ ] 3.2 Run under `TENANT_INTEGRATION_TEST=1` → green.

## 4. Phase 4 — Writer-sweep CI lint

- [ ] 4.1 Create `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` per plan §Phase 3 code block.
- [ ] 4.2 Sweep MUST cover (NARROW FILTER per deepen-plan 2026-05-16):
  - Every `.ts` file under `apps/web-platform/server/**` (excluding `**/*.test.ts` and `byok-lease.ts` itself).
  - That contains `runWithByokLease\s*\(` (the BYOK-lease opening call).
  - Asserts the file ALSO contains `persistTurnCost(` OR the structured marker `// byok-audit-writer-sweep: out-of-scope`.
- [ ] 4.3 Do NOT widen the sweep to grep `query(` / `sdkQuery(` from `@anthropic-ai/claude-agent-sdk` — narrow filter already covers all 4 BYOK SDK paths via the parent lease (verified deepen-plan 2026-05-16). Do NOT assert an `OUT_OF_SCOPE_MARKER` count guard — see plan §Phase 3 design lock.
- [ ] 4.4 (Optional, documentation-only.) Add the marker comment line above `query({` at `apps/web-platform/server/pdf-chapter-router.ts:148` to make the cost-rollup posture explicit for future readers: `// byok-audit-writer-sweep: out-of-scope — cost rolls up via routingCostUsd into parent persistTurnCost at agent-runner.ts:1876 (plan rev-2026-05-16 row 5a)`. Not load-bearing for the sweep test under the narrow filter.
- [ ] 4.5 Run the sweep test → green.
- [ ] 4.6 Verify the sweep test catches a regression: temporarily add a `runWithByokLease(...)` block to a fresh file under `server/` with no `persistTurnCost`; sweep must fail. Revert.

## 5. Phase 5 — Verification

- [ ] 5.1 Run the tenant-isolation pass:
  ```
  cd apps/web-platform && \
    doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 \
      ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts --reporter=verbose
  ```
  Expected: 13 existing + 2 new = 15 suites green.
- [ ] 5.2 Run the sweep standalone:
  ```
  cd apps/web-platform && \
    ./node_modules/.bin/vitest run test/server/byok-audit-writer-sweep.test.ts --reporter=verbose
  ```
  Expected: green.
- [ ] 5.3 Run the full webplat group:
  ```
  bash scripts/test-all.sh
  ```
  Expected: no pre-existing regression.
- [ ] 5.4 Run `.service-role-allowlist` enforcement (CI gate) → pass.
- [ ] 5.5 Run plan-review skill (DHH + Kieran + code-simplicity) → apply or document responses.

## 6. Phase 6 — PR + reviewer pipeline

- [ ] 6.1 Push branch.
- [ ] 6.2 Open PR with title `feat(runtime): PR-E audit_byok_use writer sweep + is_jti_denied consumer (#3887)`.
- [ ] 6.3 PR body must include:
  - `Closes #3887` (body, not title).
  - Brand-survival vector context: closes Art. 5(2) accountability gap before 2nd hosted founder or GA exposure.
  - Per-suite re-run tally: 13 existing tenant-isolation + 2 new tenant-isolation + 1 new sweep-lint = 16 green.
  - Article 30 amendment: "no PA1/PA2 surface change."
  - Writer-sweep enumeration: 9-row table from brainstorm verbatim.
  - Operator post-merge: NONE (no migration); after merge, run `gh issue close 3887` + update `knowledge-base/legal/compliance-posture.md` Active Items row "Art. 5(2) audit-writer gap" to closed with PR # and date.
- [ ] 6.4 Invoke `/soleur:review`. Mandatory agents: `user-impact-reviewer`, `data-integrity-guardian`, `security-sentinel`, `semgrep-sast`, `gdpr-gate` (conditional fires per brand-survival threshold + auth-domain code).
- [ ] 6.5 After green CI + reviews: `gh pr merge --squash --auto`.

## 7. Phase 7 — Post-merge

- [ ] 7.1 Verify production health: no new Sentry events with `op: "is_jti_denied.deny"` (sanity — should be zero at runtime; only test inserts fire it on dev).
- [ ] 7.2 Update `knowledge-base/legal/compliance-posture.md` Active Items: close `Art. 5(2) audit-writer gap` row with new entry `| <today> | art-5-2-audit-writer | PR #<N> | Resolved by PR-E audit writer sweep + jti-deny consumer | jean.deruelle |`.
- [ ] 7.3 `gh issue close 3887 --comment "Closed by PR #<N>"`.
- [ ] 7.4 File deferral issues per plan §Tracked Deferrals (3 issues with labels `deferred-scope-out`, `domain/engineering`, `priority/p3-low`).

## 8. Compound capture (post-merge)

- [ ] 8.1 If any session learning emerged (e.g., a sweep-test grep refinement, a tenant.ts boundary subtlety), capture via `/soleur:compound`. File under `knowledge-base/project/learnings/`.
