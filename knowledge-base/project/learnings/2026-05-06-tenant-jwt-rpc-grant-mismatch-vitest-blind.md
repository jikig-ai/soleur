---
title: Tenant-JWT migration must verify RPC `EXECUTE` grants — vitest mocks can't catch GRANT mismatches
date: 2026-05-06
category: integration-issues
tags:
  - supabase
  - rls
  - rpc
  - vitest
  - tenant-isolation
  - pr-3244
related:
  - "#3244 (PR-B agent-runtime-platform)"
  - knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md
  - "Migration 033: migrate_api_key_to_v2"
  - "Migration 017: increment_conversation_cost"
  - learning 2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper
  - learning 2026-04-15-multi-agent-review-catches-bugs-tests-miss
---

# Problem

PR-B (#3244 §1.5) migrated 9 user-scoped Supabase queries in `apps/web-platform/server/agent-runner.ts` from a service-role singleton (`supabase()`) to per-tenant JWT clients (`getFreshTenantClient(userId)`). Two of those 9 sites were SECURITY DEFINER **RPC calls** — not table reads:

- `migrate_api_key_to_v2` (lazy v1→v2 BYOK key migration, called from `getUserApiKey` and `getUserServiceTokens`)
- `increment_conversation_cost` (per-turn cost RPC fired after each `result` SDK message, fire-and-forget)

Both RPCs are explicitly `REVOKE EXECUTE FROM authenticated; GRANT EXECUTE TO service_role` (migration 033:54 / 017:43). The tenant client mints JWTs with `role: "authenticated"`. **Result: every RPC call from the tenant client would have failed with PostgreSQL error code `42501` (insufficient_privilege) in production.** Vitest didn't catch it because the test suite mocks the entire `@supabase/supabase-js` chain — `supabase().rpc(...)` resolves to a `vi.fn()` that asserts it was *called*, but never executes against a real database.

The bug was caught by `data-integrity-guardian` during multi-agent review. Without that review, PR-B would have shipped:

- Cost tracking silently disabled (fire-and-forget pattern wraps the error in `reportSilentFallback` to Sentry — invisible to the founder dashboard until the monthly reconciliation drift was noticed).
- Lazy v1→v2 BYOK migration silently failing — every founder still on `key_version=1` would have continued decrypting via `decryptKeyLegacy` on every request, paying the lazy-migration cost forever.

# Solution

For PR-B's scope, the fix was to **revert the two RPC calls back to `supabase().rpc()`** (service-role) while keeping the surrounding SELECT/INSERT queries on the tenant client. Both RPC sites added `// SERVICE-ROLE: <RPC name> is REVOKEd from authenticated` comments documenting why, and `agent-runner.ts` is allowlisted in `apps/web-platform/.service-role-allowlist`.

Why service-role is safe at these specific sites:

1. **`migrate_api_key_to_v2`**: the tenant SELECT immediately above already verified the founder owns the row (`tenant.from("api_keys").eq("user_id", userId)` filters to the founder's rows under RLS). The RPC's predicate-locked UPDATE keyed on `(id, user_id, provider, key_version=1)` then mutates only that row.
2. **`increment_conversation_cost`**: keyed on `conv_id`. The conversation's ownership was verified earlier in the session (the JWT-validated session start in `startAgentSession`, or the tenant probe in `sendUserMessage`).

The longer-term fix (deferred to a follow-up; tracked in #3392) is to add a migration that:

- Adds `auth.uid() = user_id` (or `auth.uid() = conversation.user_id`) guards inside the RPC bodies.
- `GRANT EXECUTE TO authenticated`.
- Migrates the call sites back to tenant client.

# Key Insight

**Migrating Supabase calls from service-role to tenant JWT requires verifying `EXECUTE` grants on every RPC, not just RLS policies on every table.** The two are different access-control surfaces:

- **RLS** governs `SELECT`/`INSERT`/`UPDATE`/`DELETE` against tables. Migrating a query means verifying the policy permits the operation under the tenant role.
- **`EXECUTE`** grants govern RPC invocations. Migrating an `.rpc()` call means verifying the function is `GRANT EXECUTE`d to the tenant role. SECURITY DEFINER functions still need an `EXECUTE` grant on the *outer* invocation; the DEFINER privilege only governs what the body can do once running.

**The vitest mock topology hides this class of bug entirely.** Tests that mock `@supabase/supabase-js.createClient` so `.rpc()` returns a `vi.fn()` will pass regardless of what GRANTs the real RPC has. This isn't a flaw in the mocks — it's the correct boundary for unit tests — but it means **integration coverage is the only mechanism that can catch RPC GRANT mismatches**, and PR-B's integration test (`agent-runner.tenant-isolation.test.ts`) only asserted negative cases (cross-tenant denial). Adding **positive RPC tests** under tenant JWT would have caught the bug:

```ts
test("migrate_api_key_to_v2 under tenant client succeeds for own row", async () => {
  // Seed v1 key for A; aClient.rpc(...) under A's JWT.
  // Asserts error is null. Today this would 42501.
});
```

The general rule: **for every RPC migrated to tenant JWT, add an integration test that calls it under tenant JWT and asserts success.** The cost is one test per RPC; the alternative is shipping silent production failures that surface as monthly billing reconciliation puzzles.

## Detection Pattern

Before migrating any `supabase().rpc("foo", ...)` to `tenant.rpc("foo", ...)`, grep:

```bash
grep -rn "REVOKE EXECUTE.*FROM authenticated\|GRANT EXECUTE.*TO authenticated" \
  apps/web-platform/supabase/migrations/ | grep "<rpc-name>"
```

If the RPC is REVOKEd from authenticated, the migration is incompatible without:

- Adding `GRANT EXECUTE TO authenticated` (and `auth.uid()` guards in the body), OR
- Keeping the call on service-role with a `// SERVICE-ROLE: <rationale>` comment + allowlist entry.

## Bigger Pattern: vitest mocks + multi-agent review

This is a concrete instance of the broader pattern in
`knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`:
**the test environment shapes what classes of bug the test suite can catch.**
Vitest's `vi.mock("@supabase/supabase-js", ...)` is correct for unit tests
but its envelope is "the call chain returns the shape we tell it to." It
can't know about RPC privileges, RLS policies, FK constraints, trigger
side-effects, or any other database invariant. Multi-agent review with a
data-integrity-aware agent (data-integrity-guardian) reads the migrations
directly and matches them against the call sites — exactly the gap vitest
cannot close.

# Session Errors

- **Migrated RPCs to tenant client without GRANT-verification.** Recovery: data-integrity-guardian flagged it during review; reverted both call sites to `supabase().rpc()`. **Prevention:** add a pre-edit grep for `REVOKE EXECUTE.*FROM authenticated` against the RPC name before any `tenant.rpc()` migration. Encode in the relevant skill (work or plan) Sharp Edges.

- **vitest mocks gave a false-green test signal.** Recovery: see above (multi-agent review caught it). **Prevention:** PR-B's tenant-isolation integration test asserted negative cases only; add positive RPC-under-tenant-JWT tests when migrating any `.rpc()` call. Filed as part of the #3392 follow-up.

- **Python batch edit script produced invalid TS** in 3 test files (typeof-checks against undefined `mockRpc`, untyped class params). Recovery: hand-repaired each file. **Prevention:** when scripting test-mock fan-out edits, use the Edit tool per file instead of `python3 -c "with open(p) as fh: ..."`. Per-file Edit is slower but catches typos at edit time vs batch-typecheck time.

- **Pattern-recognition agent false-positive H1**: claimed `abort-all-sessions.test.ts` would CI-fail. Recovery: ran the test, confirmed it passed, dismissed. **Prevention:** when an agent claims a test will fail, run the test before acting. The cost is one bash call vs hours of unwarranted refactoring.

- **Initial CI gate scope was too wide** — scanned `app/api/**` which is PR-C scope (28 false positives). Recovery: tightened the gate's `git ls-files` glob to `server/**` + `lib/**` only. **Prevention:** when implementing a CI gate, run it locally before committing to verify its scope matches the spec.

- **Plan line numbers drifted** from spec authoring to implementation. Recovery: delegated site mapping to an Explore subagent. **Prevention:** plans referencing line numbers in evolving files should grep for unique anchor text instead of pinning lines, OR be regenerated against current state right before `/work`.

# Tags

category: integration-issues
module: agent-runner / supabase-tenant-jwt
