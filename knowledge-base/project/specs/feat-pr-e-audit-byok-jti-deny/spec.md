---
title: PR-E — audit_byok_use writer sweep + is_jti_denied consumer
date: 2026-05-16
status: ready-for-plan
issue: 3887
umbrella_issue: 3244
brainstorm: knowledge-base/project/brainstorms/2026-05-16-pr-e-audit-byok-jti-deny-brainstorm.md
branch: feat-pr-e-audit-byok-jti-deny
worktree: .worktrees/feat-pr-e-audit-byok-jti-deny/
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# Spec — PR-E audit_byok_use writer sweep + is_jti_denied consumer

## Problem

Migration `037_audit_byok_use.sql` (shipped in PR-B #3395) declared three
DB-resident primitives — `audit_byok_use` WORM table + `write_byok_audit`
SECURITY DEFINER RPC, `denied_jti` revocation table + `is_jti_denied`
SECURITY DEFINER reader, and `mint_rate_window` + `precheck_jwt_mint`.
PR-B and PR-C wired the writer (`write_byok_audit` via `persistTurnCost`
in `cost-writer.ts:115`) and the rate-limit gate (`precheck_jwt_mint`
inside `mintFounderJwt`). The third primitive — the deny-list reader
`is_jti_denied` — has **ZERO consumer call sites in `apps/`** today
(verified via `grep -rn "is_jti_denied" apps/` at plan time: only
test + migration references).

Consequences:

1. **Art. 5(2) accountability gap on BYOK paths.** The writer
   (`write_byok_audit`) is invoked from a single site
   (`cost-writer.ts:115`) used by 2 of 5 BYOK SDK call paths
   (`agent-runner.ts:1876`, `cc-dispatcher.ts:1705`). The third path
   (`pdf-chapter-router.ts:148`) emits cost via parent rollup —
   acceptable but undocumented. No CI guard prevents a new BYOK call
   path from landing without an audit row.

2. **Art. 32 confidentiality gap on stolen JWTs.** Any runtime JWT
   stolen for any reason (XSS in tool surface, log exfiltration,
   transient MITM, future deploy-artifact leak) remains usable for its
   full 10-min TTL with no in-band kill-switch. The deny-list reader
   exists; the consumer does not. `RuntimeAuthError.cause = "denied_jti"`
   is declared in `lib/supabase/tenant.ts:65` but no code raises it.

3. **CLO advisory carry-forward (PR-C plan §Tracked Deferrals).**
   "Sequence audit-writer BEFORE 2nd hosted founder onboards OR GA
   exposure, whichever first." Today: 1 hosted founder. Closing the
   gap before the 2nd founder onboards is the load-bearing sequencing
   constraint.

## User-Brand Impact

**If this lands broken, the user experiences:** a closed-preview founder
sees `RuntimeAuthError(denied_jti)` falsely on a fresh JWT (false-
positive on the deny-list check) and loses access to the runtime
mid-session, OR a BYOK audit row is silently dropped on a path the
writer sweep missed and the founder's billing dashboard under-reports
a turn that actually spent against their key.

**If this leaks, the user's data / money is exposed via:** a stolen
runtime JWT remains valid for its full TTL (no in-band kill-switch),
OR a BYOK SDK call that bypasses the audit writer charges the
founder's Anthropic key without forensic evidence — Art. 5(2)
"ability to demonstrate" fails on a DSAR or audit request.

**Brand-survival threshold:** `single-user incident`. CPO sign-off
required at plan time per `hr-weigh-every-decision-against-target-user-impact`.
`user-impact-reviewer` MUST run at review time per
`plugins/soleur/skills/review/SKILL.md` conditional-agent block #15.

## Acceptance Criteria

### Pre-merge (PR — verified in CI + reviewer ack)

AC1 — `is_jti_denied` consumer wired at the canonical JWT path. After
the patch, `grep -rn "is_jti_denied" apps/web-platform/lib/supabase/`
returns at least one production call site (not test, not migration
header) inside `tenant.ts`. The consumer call is reachable from
`getFreshTenantClient` on both the cache-hit and cache-miss paths.

AC2 — Cache-hit deny check. When `getFreshTenantClient(userId)` finds
a cached `CacheEntry`, it calls `is_jti_denied(entry.jti)` before
returning the cached client. On `true`: evicts the cache entry, falls
through to remint. On `false`: returns the cached client unchanged.
Asserted by integration test
`tenant-jwt-deny.tenant-isolation.test.ts::Test B`.

AC3 — Cache-miss deny check. When `mintFounderJwt` returns a fresh
`MintedJwt`, `getFreshTenantClient` calls `is_jti_denied(jti)` before
installing in the cache. On `true`: discards, throws
`RuntimeAuthError("denied_jti", "Authentication unavailable; retry shortly")`.
On `false`: installs + returns. Asserted by
`tenant-jwt-deny.tenant-isolation.test.ts::Test C`.

AC4 — Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`.
On the deny branch (either path), `reportSilentFallback(null, { feature:
"tenant-jwt", op: "is_jti_denied.deny", extra: { userId, jti } })`
fires. `userId` is pseudonymized at the helper boundary per existing
ADR-028/029; `jti` is a random UUID (not personal data). Asserted by
`tenant-jwt-deny.tenant-isolation.test.ts::Test B` via `_resetSentryEvents`
introspection.

AC5 — `RuntimeAuthError.cause = "denied_jti"` reachable. After the
patch, the declared discriminant in `tenant.ts:65` has at least one
`throw new RuntimeAuthError("denied_jti", ...)` site in the same
module. The user-facing error message remains
`"Authentication unavailable; retry shortly"` (same as `jwt_mint` /
`rotation` per sanitization posture).

AC6 — CacheEntry struct widened to carry jti. The `CacheEntry`
interface in `tenant.ts:202` gains a `jti: string` field so the
cache-hit deny check can probe without re-decoding the JWT.

AC7 — WORM enforcement test. New file
`apps/web-platform/test/server/audit-byok-use.tenant-isolation.test.ts`
asserts that `service.from("audit_byok_use").update(...)` raises
P0001 and `.delete(...)` raises P0001, exercising the
`audit_byok_use_no_mutate` triggers from migration 037 lines 50-70.

AC8 — `write_byok_audit` writer sweep CI lint passes. New file
`apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`
enumerates every `runWithByokLease(` call site under
`apps/web-platform/server/` via `fs.readFileSync` source-grep. For
each site's containing file, asserts the file ALSO contains a
`persistTurnCost(` call OR a structured comment line
`// byok-audit-writer-sweep: out-of-scope — <one-line reason>`.
The test maintains a fixture allowlist for
`pdf-chapter-router.ts` (rollup case) with exactly one entry.

AC9 — Writer-sweep table in PR body. The PR description carries the
9-row writer-sweep table from the brainstorm (one row per enumerated
file) with the gate-status disposition for each. Reviewer acks the
table is consistent with the codebase at HEAD.

AC10 — Deny-list integration suite green. New file
`apps/web-platform/test/server/tenant-jwt-deny.tenant-isolation.test.ts`
has 4 tests (A: fresh empty deny, B: cache-hit deny, C: cache-miss
deny, D: unrelated-jti negative) and all pass under
`TENANT_INTEGRATION_TEST=1` against dev Doppler.

AC11 — Webplat full suite remains green. `bash scripts/test-all.sh`
TEST_GROUP=webplat returns 0; no pre-existing tenant-isolation suite
regresses. Tally: 13 existing suites + 3 new (2 tenant-isolation + 1
sweep-lint) = 16 suites, all green.

AC12 — `.service-role-allowlist` enforcement gate passes unchanged.
PR-E adds no new service-role imports.

AC13 — `cq-pg-security-definer-search-path-pin-pg-temp` not
triggered. PR-E adds no new SECURITY DEFINER functions. (Migration
037's existing functions already comply.)

AC14 — No Article 30 register amendment. PR-E does not expand the
personal-data surface (deny-list table already in PA1 scope via the
"authentication" processing activity from PR-B; `jti` is random UUID
not personal data; Sentry mirror covered by PA2 from PR-D). PR body
carries the explicit "no PA1/PA2 surface change" note.

AC15 — `gdpr-gate` at plan Phase 2.7 runs and any Critical findings
are folded in OR scoped-out with rationale. (Trigger: brand-survival
`single-user incident` + auth-domain code touched, both fire the gate.)

AC16 — Brainstorm-recommended deferrals filed. Two follow-up issues
at deepen-plan time: (1) deny-list TTL sweep / logout-driven
revocation, (2) per-pdf-chapter-router-turn audit row. Both labeled
`deferred-scope-out` + `domain/engineering` + `priority/p3-low`. AC
discharged when issue numbers are present in plan §Tracked Deferrals.

### Post-merge (operator)

AC17 — Production migration NOT required. Migration 037 shipped in
PR-B (`#3395`); the DB-resident primitives are already live. No
`doppler run -p soleur -c prd -- bash apps/web-platform/scripts/run-migrations.sh`
needed. PR body explicitly notes "no migration in PR-E."

AC18 — `compliance-posture.md` Active Items entry "Art. 5(2)
audit-writer gap" closes. Single-line update post-merge:
`| <date> | art-5-2-audit-writer | PR #<N> | Resolved by PR-E audit
writer sweep + jti-deny consumer | jean.deruelle |`. Operator runs:
`gh issue close 3887 --comment "Closed by PR #<N>"`.

## Non-Goals (deferred via tracked follow-up issues)

- Admin UI for jti revocation (#3887 explicit).
- Token rotation policy / automated revocation triggers (#3887 explicit).
- Re-issuing tokens after revocation — separate UX flow (#3887 explicit).
- Refactoring `write_byok_audit` schema or extending columns
  (#3887 explicit).
- Deny-list TTL sweep / logout-driven revocation (brainstorm-emergent
  — defer to follow-up issue at deepen-plan).
- Per-pdf-chapter-router-turn audit row (brainstorm-emergent — defer
  to follow-up issue at deepen-plan).
- New revocation-list writer RPC (`revoke_jti(...)`) — operator
  revokes via direct SQL today; promote to RPC when 2nd founder
  onboards OR a real compromise drill occurs.

## Test Scenarios (Gherkin)

```gherkin
Feature: Runtime JWT revocation enforcement

  Scenario: Stolen JWT becomes unusable after deny-list insert
    Given a founder has a cached runtime JWT with jti X
    And X was leaked or stolen
    When operator inserts (X, founder_id, now(), 'compromise') into denied_jti
    And the founder's next ws frame triggers getFreshTenantClient(userId)
    Then is_jti_denied(X) returns true
    And the cache entry is evicted
    And the next call remints a fresh jti Y
    And Y is usable; X cannot be re-presented as a Bearer token

  Scenario: Fresh mint races with deny-list insert
    Given mintFounderJwt(userId) generates fresh jti Z via precheck_jwt_mint
    And concurrently operator inserts (Z, founder_id, now(), 'drill') into denied_jti
    When getFreshTenantClient installs the fresh CacheEntry
    Then the post-mint is_jti_denied(Z) check fires
    And RuntimeAuthError(cause: "denied_jti") is thrown
    And the cache is not poisoned with Z
    And Sentry receives a tenant-jwt.is_jti_denied.deny event

Feature: BYOK audit-row coverage

  Scenario: Every BYOK SDK call path emits an audit row
    Given the codebase at HEAD has N runWithByokLease( call sites under apps/web-platform/server/
    When the byok-audit-writer-sweep test runs
    Then for each site's containing file, the file contains a persistTurnCost( call
    Or a structured comment "// byok-audit-writer-sweep: out-of-scope — <reason>"
    And the test passes

  Scenario: WORM enforcement on audit_byok_use
    Given a row exists in public.audit_byok_use
    When service-role attempts UPDATE on that row
    Then SQLSTATE P0001 is raised with message "audit_byok_use is append-only (WORM)"
    And the row is unchanged
    And the same applies to DELETE
```

## References

- Issue: #3887 (CLO context, scope split from PR-D)
- Migration: `apps/web-platform/supabase/migrations/037_audit_byok_use.sql`
- PR-B plan: `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md`
  §1.4 (jti-deny revocation-list design intent)
- PR-C plan: `knowledge-base/project/plans/2026-05-15-feat-pr-c-sibling-query-migration-plan.md`
  §Tracked Deferrals (CLO advisory carry-forward)
- PR-D PR: #3883 (sibling — attachments-storage tenant RLS; same brand-survival
  posture)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-16-pr-e-audit-byok-jti-deny-brainstorm.md`
- Constitution: `knowledge-base/overview/constitution.md` (WORM + audit-trail conventions)
- Hard rules: `hr-menu-option-ack-not-prod-write-auth`,
  `cq-pg-security-definer-search-path-pin-pg-temp`,
  `cq-silent-fallback-must-mirror-to-sentry`,
  `hr-write-boundary-sentinel-sweep-all-write-sites`,
  `hr-gdpr-gate-on-regulated-data-surfaces`
- Learnings:
  `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`
  (re-verified migration 037 shape against HEAD at plan time; no drift)
