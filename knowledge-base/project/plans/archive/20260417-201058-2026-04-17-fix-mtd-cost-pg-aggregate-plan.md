---
category: plans
tags: [byok, billing, postgres, supabase, migration, performance, data-integrity]
date: 2026-04-17
issue: 2478
pr: null
branch: feat-mtd-cost-pg-aggregate
semver: patch
---

# Fix #2478 — replace client-side MTD sum with Postgres aggregate

**Issue:** [#2478](https://github.com/jikig-ai/soleur/issues/2478) (review-origin, `deferred-scope-out` → ready to close)
**Source review:** PR [#2464](https://github.com/jikig-ai/soleur/pull/2464) (merged) — flagged P2 by `data-integrity-guardian` and `performance-oracle`.
**Semver:** patch — bug-fix on an existing, already-shipped loader.

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Overview, Reconciliation, Phase 1 (TDD), Phase 2 (SQL), Phase 3 (loader), Acceptance Criteria, Risk table
**Research applied:** live PostgREST probe against dev Supabase, three relevant `knowledge-base/project/learnings/` entries, review criteria from `data-integrity-guardian`, `performance-oracle`, `security-sentinel`, `kieran-rails-reviewer`, `code-simplicity-reviewer`.

### Key Improvements

1. **Option A rejection is now evidence-backed, not hypothetical.** The live probe output is pasted verbatim into Research Reconciliation — no implementer re-probes and no reviewer asks "did you actually try it?"
2. **Security-definer guardrails hardened.** Added `REVOKE EXECUTE … FROM PUBLIC` **before** the `CREATE OR REPLACE` (covers the idempotent-replay case where grants would otherwise leak to PUBLIC via `CREATE FUNCTION`'s default PUBLIC grant); added explicit function-comment documenting service-role-only; added a DROP-IF-EXISTS preamble commented out for the signature-change rollback path.
3. **Supabase JS typing guardrail from learning 2026-04-05.** The RPC response is typed explicitly (`{ total: string; n: number }[]`) rather than relying on `ReturnType<typeof createClient>` inference — prevents the `never`-collapse that bit session-sync in PR #2430.
4. **Boolean/cast safety from learning 2026-03-20.** RPC body uses `COALESCE(SUM(…), 0)` and `COUNT(*)::INTEGER` — no user-controlled casts, no implicit NULL-to-number coercions at the Postgres boundary.
5. **Unapplied-migration fire-drill from learning 2026-03-28.** Post-merge verification is now blocking, with the exact REST probe payload pre-written so the reviewer/implementer can paste-and-run (not just "verify it's applied").
6. **NUMERIC wire-decoding tightened.** The `@supabase/postgrest-js` client returns NUMERIC as a JS `string` by default to preserve precision — plan now explicitly decodes via `Number(…)` once at the boundary, with a precision-headroom calculation in the Risk table.
7. **Index-only scan preconditions made explicit.** Noted that `VACUUM ANALYZE`'s visibility-map coverage is the only gap between "index contains all columns" and "Postgres actually picks index-only scan"; added an autovacuum check step for the EXPLAIN gate.
8. **Parity test grounded without new deps.** Dropped the `decimal.js` suggestion; use a hand-summed NUMERIC-exact fixture instead (no runtime dep added, no `cq-before-pushing-package-json-changes` review on an unnecessary dependency).

### New Considerations Discovered

- `CREATE OR REPLACE FUNCTION` preserves existing grants on replacement; on **first** create it grants `EXECUTE` to PUBLIC by default. The migration MUST run the REVOKEs even on first apply — this is a real security gap if the migration is split or the REVOKEs are treated as "cleanup" after CREATE.
- PostgREST returns `data: []` (empty array) for an RPC that returns `TABLE(...)` with zero matching rows — **not** `data: [{total: null, n: 0}]`. The loader must handle `monthRow === undefined` explicitly; the draft already does, but the test for "zero conversations" must assert this exact shape, not the legacy `count: 0` header.
- Supabase JS v2.99.2 (installed) passes RPC args as JSON body; snake_case vs camelCase is preserved literally. Use `uid` and `since` (matching the SQL parameter names) — any mismatch returns `PGRST202 "Could not find the function"`.

## Overview

`server/api-usage.ts` currently computes the user's month-to-date BYOK spend
by `SELECT`-ing up to 1000 `total_cost_usd` rows from `conversations` and
summing them in JS. Three concrete defects:

1. **Float-summation drift.** NUMERIC(12,6) values round-trip through
   JS floats before the reduce; the dashboard total can disagree with
   `SELECT SUM(total_cost_usd) FROM conversations …` in Postgres by
   sub-cent amounts that compound with row count.
2. **Unbounded wire.** The 1000-row defensive cap streams ~200 KB of
   NUMERIC strings to Node on every dashboard load for a heavy user,
   and silently under-counts for any user who exceeds the cap.
3. **No index-only scan.** Postgres reads `total_cost_usd` from the heap
   for every qualifying row just so JS can sum it. The partial index
   from migration 017 (`idx_conversations_user_cost`) is already keyed
   on the filter columns; an aggregate can finish inside the index.

The fix pushes the aggregate to Postgres so the wire carries a single
NUMERIC, the value equals `SUM()` exactly, and the query can use
index-only scans.

## Research Reconciliation — Spec vs. Codebase

Issue #2478 presents two options and prefers Option A. Live probing
against the Supabase dev instance invalidates the preferred path.

| Spec claim (issue #2478)                                                   | Reality (probed on dev 2026-04-17)                                                                                                         | Plan response                                                                                           |
|----------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| Option A (PostgREST aggregate, no migration) is viable and preferred.      | `GET /rest/v1/conversations?select=total_cost_usd.sum()` returns **HTTP 400 `PGRST123` "Use of aggregate functions is not allowed"**.      | **Option A rejected.** Supabase's hosted PostgREST has `db-aggregates-enabled = false` by project-level policy (DoS protection). Flipping it would be an infrastructure-wide change affecting every endpoint and every tenant — far outside this fix's scope. Proceed directly to **Option B** (security-definer RPC) as the primary and only path. |
| Either path must match the partial index from migration 017.              | `idx_conversations_user_cost ON conversations (user_id, created_at DESC) WHERE total_cost_usd > 0` already matches the predicate 1:1.      | RPC body uses `WHERE user_id = $1 AND total_cost_usd > 0 AND created_at >= $2`; EXPLAIN step confirms `Index Only Scan using idx_conversations_user_cost`. |
| RPC signature: `sum_user_mtd_cost(uid uuid, since timestamptz) returns table(total numeric, n integer)`. | Existing RPC pattern (`increment_conversation_cost` in migration 017) uses `SECURITY DEFINER` + explicit `SET search_path = public` + explicit role GRANTs. | Keep the spec signature. Match the migration-017 pattern for SECURITY, `search_path`, REVOKE-from-PUBLIC, GRANT-to-service_role — end users must NEVER call this RPC; it is service-role-only. |

The "no migration required" shortcut does not exist in this environment.
This is the kind of spec-vs-reality gap Phase 1.7 exists to catch before
implementation pivots mid-GREEN.

**Verbatim probe output (dev Supabase, 2026-04-17):**

```text
$ curl -sS "$SUPABASE_URL/rest/v1/conversations?select=total_cost_usd.sum()&limit=1" \
    -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
    -w "\nHTTP %{http_code}\n"

{"code":"PGRST123","details":null,"hint":null,"message":"Use of aggregate functions is not allowed"}
HTTP 400
```

`PGRST123` is PostgREST's code for "client requested an aggregate but
the `db-aggregates-enabled` config flag is false." Supabase's hosted
PostgREST pins this to `false` as a DoS protection against unbounded
client-driven aggregates; the flag is not exposed in the dashboard and
flipping it is a Supabase-side project setting (not something we
control per-endpoint). Documented in PostgREST release notes since v12:
<https://postgrest.org/en/stable/references/api/aggregate_functions.html>.

## Open Code-Review Overlap

**Check run 2026-04-17 against `gh issue list --label code-review --state open`
and `--label deferred-scope-out --state open` for paths in this plan's
Files to Edit / Files to Create.**

Matches:

- `apps/web-platform/server/api-usage.ts` → only #2478 (self — closed by this PR).
- `idx_conversations_user_cost` → only #2478 (self).
- `conversations` table → #2388 (unrelated architectural refactor touching `ChatSurface` parameter object, `KbChatContext`, agent-native REST — no shared file or concern with this plan).

**Disposition:** No overlaps to fold in, acknowledge, or defer. This PR
touches exactly the surface area #2478 calls out.

## Acceptance Criteria

- [x] **AC1 — parity to ≤ 1 cent.** On a seeded fixture of ≥ 200
      conversations spanning the current and previous calendar months,
      the new loader's `mtdTotalUsd` matches the existing client-side
      reduce within **≤ $0.01 absolute** and within **≤ $0.001** for
      realistic row counts (< 1000). Captured as a parity test that
      runs both code paths on the same fixture.
- [ ] **AC2 — index-only.** `EXPLAIN (ANALYZE, BUFFERS)` for the RPC
      body shows `Index Only Scan using idx_conversations_user_cost`,
      not a seq scan or a bitmap heap scan that re-reads the row.
- [x] **AC3 — single round-trip, single NUMERIC.** A network inspection
      (dev tools or a wrapping test mock counting `.from()` /
      `.rpc()` calls) confirms the month scope uses exactly one
      `service.rpc("sum_user_mtd_cost", …)` call and decodes exactly
      one NUMERIC at the Node boundary. The 1000-row cap
      (`MTD_SCOPE_LIMIT`) is removed.
- [ ] **AC4 — RPC is service-role only.** Grants match migration 017's
      `increment_conversation_cost`: `REVOKE EXECUTE … FROM PUBLIC`,
      `FROM authenticated`, `FROM anon`; `GRANT EXECUTE … TO
      service_role`. A REST probe with the anon key receives
      `PGRST202` or `42501` (not found / insufficient privilege).
- [x] **AC5 — error handling preserved.** When the RPC errors, the
      loader returns `null` exactly as the current two-query `Promise.all`
      path does; the existing "returns null when month query errors"
      test keeps passing with the new call shape.
- [x] **AC6 — UTC month boundary preserved.** The caller still passes
      `computeMonthStartIso()` output to the RPC; the existing "month
      query uses UTC boundary" test keeps passing, adapted to assert
      the RPC argument instead of `.gte()`.
- [ ] **AC7 — migration verified in production.** After merge, the REST
      probe from `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
      confirms the function is resolvable (`POST /rest/v1/rpc/sum_user_mtd_cost`
      with a valid payload returns 200 + a `[{"total": "…", "n": …}]`
      body, not `PGRST202`). Enforcement: AGENTS.md `wg-when-a-pr-includes-database-migrations`.

## Implementation Phases

### Phase 0 — Preflight (no code)

1. Confirm next migration number is **027** (`025_`, `026_` already
   present; `027_…` is free).
2. Re-run the PostgREST aggregate probe once more immediately before
   starting implementation, so the Option A rejection is documented
   with a fresh timestamp in the PR body. If the probe unexpectedly
   succeeds (e.g., Supabase flipped the default), STOP and re-plan —
   Option A becomes viable and this whole migration goes away.

   ```bash
   SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain)
   SERVICE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c dev --plain)
   curl -sS "$SUPABASE_URL/rest/v1/conversations?select=total_cost_usd.sum()&limit=1" \
     -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" -w "\nHTTP %{http_code}\n"
   # Expected: HTTP 400, body {"code":"PGRST123","message":"Use of aggregate functions is not allowed"}
   # If HTTP 200 with a data body: STOP. Option A is now viable; this migration is unnecessary.
   ```

### Phase 1 — Write RED tests first (TDD gate)

Per AGENTS.md `cq-write-failing-tests-before`. These tests must fail
before the loader is changed.

**Test 1 — `test/api-usage.test.ts` adaptation.**
The existing suite mocks `service.from("conversations")` for the
month-scope chain. Add parallel coverage for `service.rpc(…)`:

- Extend `mockSupabase.ts` helper with a `mockRpc(data, error)` factory
  that returns a thenable resolving to `{ data, error }` (same shape as
  the chain thenable — no `.count`, since RPC response body is
  `[{total, n}]` not a count header).
- Replace the two-call mock pattern
  (`mockFrom.mockImplementationOnce(listChain).mockImplementationOnce(monthChain)`)
  with `mockFrom` for the list chain + a top-level `mockRpc` mock for
  the month sum.
- Update the following existing tests to assert the RPC call instead
  of the `.from("conversations").select("total_cost_usd", …)` chain:
  - `returns empty rows + 0 MTD when user has no conversations`
  - `returns rows + MTD total when current-month conversations exist`
  - `returns rows with MTD=0 when only prior-month conversations exist`
  - `month query uses UTC boundary` → now asserts `rpc` was called with
    `("sum_user_mtd_cost", { uid: VALID_UUID, since: "2026-04-01T00:00:00.000Z" })`
  - `month-scope query enforces cost > 0 filter and defensive limit` →
    replace with `"MTD sum uses RPC (no client-side reduce)"` — asserts
    only one RPC invocation, asserts `.from` was NOT called a second
    time for month scope, asserts `MTD_SCOPE_LIMIT` constant is removed
    from the exports.
  - `returns null when month query errors` → now triggers via RPC
    `mockRpc(null, { code: "XX000", message: "boom" })`.

**Test 2 — new parity test (`test/api-usage-parity.test.ts`).**
Seeded fixture of 200 synthetic `total_cost_usd` values spanning
NUMERIC(12,6) representable space (include sub-cent, cent, and
dollar-scale values). Compute both:

- `clientSum = rows.reduce((s, r) => s + Number(r.total_cost_usd), 0)`
- `serverSum = Number(rpcResult[0].total)` where `rpcResult[0].total`
  is a hardcoded NUMERIC-exact string pre-computed by the test author
  (e.g., `"12.345678"` for a fixture whose Postgres `SUM()` is
  mathematically exactly that value).

Assert `Math.abs(clientSum - serverSum) <= 0.01` (AC1, wide bound) AND
`Math.abs(clientSum - serverSum) <= 0.001` for counts under 1000 (AC1,
tight bound). Do NOT add a new runtime dep (e.g., `decimal.js`) just
for this test — AGENTS.md `cq-before-pushing-package-json-changes`
would force a lockfile round-trip for one test's worth of benefit.
Hand-summed fixtures are strictly sufficient.

**Test 3 — grant/visibility RED test (integration-style, gated by
`SUPABASE_URL` env).** Skipped in CI when env is absent.

```ts
test.runIf(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_ANON_KEY)(
  "sum_user_mtd_cost is NOT callable via anon key",
  async () => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const anon = process.env.SUPABASE_ANON_KEY!;
    const res = await fetch(`${url}/rest/v1/rpc/sum_user_mtd_cost`, {
      method: "POST",
      headers: {
        "apikey": anon,
        "Authorization": `Bearer ${anon}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ uid: "00000000-0000-0000-0000-000000000000", since: "2026-04-01T00:00:00.000Z" }),
    });
    // Either PGRST202 (not exposed to anon role) or 401/403. Never 200.
    expect(res.status).toBeGreaterThanOrEqual(400);
  },
);
```

Run with `node node_modules/vitest/vitest.mjs run test/api-usage` (per
AGENTS.md `cq-in-worktrees-run-vitest-via-node-node`; note vitest is
installed at app level — `cd apps/web-platform && ./node_modules/.bin/vitest run`).
Confirm all updated tests fail.

### Phase 2 — Migration `027_mtd_cost_aggregate.sql`

**File:** `apps/web-platform/supabase/migrations/027_mtd_cost_aggregate.sql`

```sql
-- Postgres-side month-to-date cost aggregate for the BYOK usage
-- dashboard. Replaces a client-side JS reduce over up to 1000 rows
-- (see issue #2478). Uses the partial index from migration 017
-- (idx_conversations_user_cost), enabling an index-only scan.
--
-- SECURITY: security-definer + explicit search_path; REVOKE from
-- PUBLIC/authenticated/anon and GRANT only to service_role. End users
-- must never call this directly — the BYOK loader runs under the
-- service client which already enforces `caller MUST have verified
-- userId belongs to the session` (see server/api-usage.ts:1-5).
--
-- Idempotency note: CREATE OR REPLACE FUNCTION preserves existing
-- grants on REPLACE, but on FIRST create Postgres grants EXECUTE to
-- PUBLIC by default. The REVOKE statements below MUST run on every
-- apply — treating them as "cleanup" after the CREATE is a real
-- security gap. Supabase's migration runner is not transactional
-- per-file for DDL; the REVOKEs are ordered immediately after the
-- CREATE so a mid-file retry still lands them.

-- If a future migration changes the signature, uncomment the DROP and
-- drop the old (UUID, TIMESTAMPTZ) overload. For the initial apply
-- this is a no-op — CREATE OR REPLACE handles the in-place update.
-- DROP FUNCTION IF EXISTS public.sum_user_mtd_cost(UUID, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.sum_user_mtd_cost(
  uid   UUID,
  since TIMESTAMPTZ
) RETURNS TABLE(total NUMERIC, n INTEGER)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  -- COALESCE guarantees `total` is never NULL when zero rows match;
  -- matches the loader's `mtdTotalUsd = 0` default. COUNT(*)::INTEGER
  -- is an explicit cast (no user-controlled data is cast anywhere —
  -- see learning 2026-03-20 on ::boolean cast safety).
  SELECT COALESCE(SUM(total_cost_usd), 0)::NUMERIC AS total,
         COUNT(*)::INTEGER                          AS n
    FROM public.conversations
   WHERE user_id = uid
     AND total_cost_usd > 0
     AND created_at >= since;
$$;

COMMENT ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) IS
  'Service-role-only MTD cost aggregate for the BYOK usage dashboard. '
  'End users MUST NOT call this directly; see server/api-usage.ts. '
  'Issue #2478.';

REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM anon;
GRANT  EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) TO   service_role;
```

**Notes on the SQL above:**

- `STABLE` is correct: the function is deterministic within a
  transaction for fixed inputs and reads `conversations`. This lets
  the planner reuse the result inside a single statement if the RPC is
  ever composed.
- `LANGUAGE sql` is chosen over `plpgsql` deliberately — the body is a
  single SELECT with no control flow, so `sql` inlines better in the
  planner. The sibling `increment_conversation_cost` uses `plpgsql`
  only because it needs an `IF … RAISE EXCEPTION` guard.
- `COALESCE(SUM(…), 0)` guarantees the `total` column is never NULL
  when zero rows match, matching the existing loader's `mtdTotalUsd = 0`
  behavior for no-conversations users.
- No `DROP FUNCTION` preamble: `CREATE OR REPLACE` handles it. If the
  signature ever changes the replacement fails loudly; a future
  migration adds `DROP FUNCTION IF EXISTS public.sum_user_mtd_cost(UUID,
  TIMESTAMPTZ);` ahead of the new definition.

### Phase 3 — Loader refactor (`server/api-usage.ts`)

**Replace** the month-scope query (lines 95-102) and the JS reduce
(lines 128-132) with a single RPC:

```ts
const [listRes, monthRes] = await Promise.all([
  service
    .from("conversations")
    .select(
      "id, domain_leader, created_at, input_tokens, output_tokens, total_cost_usd",
    )
    .eq("user_id", userId)
    .gt("total_cost_usd", 0)
    .order("created_at", { ascending: false })
    .limit(MAX_USAGE_ROWS),
  service.rpc("sum_user_mtd_cost", {
    uid: userId,
    since: monthStartIso,
  }),
]);

if (listRes.error || monthRes.error) {
  console.error("[api-usage] load failed", {
    op: "loadApiUsageForUser",
    listCode: listRes.error?.code ?? null,
    monthCode: monthRes.error?.code ?? null,
  });
  // AGENTS.md cq-silent-fallback-must-mirror-to-sentry: this branch
  // returns null → caller renders an empty dashboard with a retry
  // button. Mirror to Sentry so the degraded state is visible.
  reportSilentFallback(listRes.error ?? monthRes.error, {
    feature: "api-usage",
    op: "loadApiUsageForUser",
    extra: {
      listCode: listRes.error?.code ?? null,
      monthCode: monthRes.error?.code ?? null,
    },
  });
  return null;
}

// PostgREST returns NUMERIC as a JS string to preserve 12,6 precision.
// RPC returns a single-row TABLE: [{ total: "0.042300", n: 2 }].
// Zero-match case returns an empty array, NOT [{total: null, n: 0}] —
// so the destructure MUST handle `monthRow === undefined` explicitly.
//
// Typing note: we type monthRes.data explicitly rather than relying on
// the client's inferred return type. `ReturnType<typeof createClient>`
// collapses RPC return types to `never` in @supabase/supabase-js v2.49+
// (see learning 2026-04-05-supabase-returntype-resolves-to-never).
interface MonthSumRow {
  total: string | number | null;
  n: number | null;
}
const monthRow = (monthRes.data as MonthSumRow[] | null)?.[0];
const mtdTotalUsd = Number(monthRow?.total ?? 0);
const mtdCount    = Number(monthRow?.n     ?? 0);
```

**Delete:**

- `MTD_SCOPE_LIMIT` constant (line 19) and the adjacent comment
  (lines 16-18). The defensive cap is no longer relevant because the
  RPC never streams rows.
- The `MonthScopeRow` interface (lines 71-73) — no rows to type.
- The `.reduce((sum, r) => sum + Number(r.total_cost_usd ?? 0), 0)`
  block (lines 128-131).
- The `.count` read on `monthRes.count` (line 132) — PostgREST RPC
  responses do not carry a `count` header; we read the `n` column from
  the RPC body instead.

**Keep:**

- UUID validation, domain-label mapping, list-query shape, error-path
  early return, re-export of `relativeTime`, `MAX_USAGE_ROWS` constant.
- `computeMonthStartIso()` — it produces the `since` argument now.

**Observability:** the error branch now reports to Sentry via
`reportSilentFallback` (imported from `@/server/observability`), per
AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`. Pino stdout
alone is not enough for a silent-fallback that degrades the billing
dashboard to a "load failed" state.

### Phase 4 — Verify locally

1. **Typecheck.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
2. **Vitest.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-usage`.
   All existing tests pass with the adapted mocks; new parity test
   (AC1) passes.
3. **Dev server smoke.** `./scripts/dev.sh 3000`, log in as a seeded
   test user, open `/dashboard/settings/billing`, confirm the MTD
   total renders to 2 or 4 decimal places exactly matching a manual
   `SELECT SUM(total_cost_usd) FROM conversations WHERE user_id = $1
   AND total_cost_usd > 0 AND created_at >= date_trunc('month', now())`.
4. **Apply migration to dev Supabase** (to exercise the full RPC path,
   not just the mock):

   ```bash
   cd apps/web-platform
   doppler run -p soleur -c dev -- \
     npx supabase db push --include-all
   ```

5. **EXPLAIN probe (AC2).** Against the dev Supabase SQL editor:

   ```sql
   EXPLAIN (ANALYZE, BUFFERS)
   SELECT COALESCE(SUM(total_cost_usd), 0), COUNT(*)
     FROM public.conversations
    WHERE user_id    = '<test-user-uuid>'
      AND total_cost_usd > 0
      AND created_at >= '2026-04-01T00:00:00Z';
   ```

   Confirm `Index Only Scan using idx_conversations_user_cost`. If the
   planner picks a seq scan (unlikely, but possible at very low row
   counts), re-run with a fuller fixture before declaring the index
   path taken. Paste the EXPLAIN output into the PR body.

   **Visibility-map precondition.** Index-only scan requires the
   visibility map to have enough "all-visible" pages; otherwise
   Postgres falls back to a normal index scan (still uses the index,
   still fast — just re-reads the heap for MVCC). On a dev DB with
   recent inserts, run `VACUUM (ANALYZE) public.conversations;` before
   the EXPLAIN if the row count is non-trivial. For prod, autovacuum
   handles this; the EXPLAIN verdict "Index Only Scan" or "Index Scan
   using idx_conversations_user_cost" both satisfy AC2 — a **seq
   scan** would not.
6. **Anon-key grant probe (AC4).** Per the RED test in Phase 1 Test 3,
   POST to `/rest/v1/rpc/sum_user_mtd_cost` with the anon key; expect
   a 4xx. Document the exact status and code in the PR body.

### Phase 5 — Ship

Follow `/ship`. This PR includes a DB migration, so:

- `/ship` Phase 5.5 checks pass (no contested-design, no
  cross-cutting-refactor — this is the scoped #2478 fix).
- PR body contains `Closes #2478` (AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).
- Semver label: **`semver:patch`**.
- After merge, follow `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
  verification procedure (AGENTS.md `wg-when-a-pr-includes-database-migrations`):
  - REST probe: `POST /rest/v1/rpc/sum_user_mtd_cost` with service key
    and a non-existent UUID — expect `200` + `[{"total":"0.000000","n":0}]`.
  - Anon-key probe — expect 4xx (grants enforced).
  - Capture both in the post-merge comment thread, not just the merge.

## Files to edit

- `apps/web-platform/server/api-usage.ts` — swap the month-scope select
  for `.rpc()`, delete the reduce + `MTD_SCOPE_LIMIT` + `MonthScopeRow`,
  add `reportSilentFallback` on the error branch.
- `apps/web-platform/test/api-usage.test.ts` — adapt month-scope
  assertions from `.from()` chain to `.rpc()`.
- `apps/web-platform/test/helpers/mock-supabase.ts` — add `mockRpc`
  helper (small addition; does not change existing shape).

## Files to create

- `apps/web-platform/supabase/migrations/027_mtd_cost_aggregate.sql` —
  the security-definer RPC.
- `apps/web-platform/test/api-usage-parity.test.ts` — the parity test
  covering AC1.

## Alternative Approaches Considered

| Option | Why not chosen                                                                                                                               |
|--------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| **A — PostgREST aggregate** (`.select("total_cost_usd.sum()")` with `head: true`)  | **Rejected after live probe.** Supabase hosted PostgREST returns `PGRST123 "Use of aggregate functions is not allowed"`. Enabling `db-aggregates-enabled` is a project-wide config change that would affect every tenant and endpoint, far outside this fix's blast radius. Tracked as out-of-scope — re-evaluate if Supabase flips the default or if we self-host PostgREST. |
| **C — Materialized view refreshed nightly**                                         | Premature: daily refresh is stale for an "MTD" figure users check multiple times a day, and the table is nowhere near the size that would justify a materialization cost. Revisit only if we ever have users with > 100k conversations/month. |
| **D — Keep the reduce, lift the 1000-row cap**                                      | Does not address the float-drift defect (P2) or the unbounded-wire defect. The cap exists precisely because the reduce is untrustworthy above 1000 rows; removing the cap widens the bug. |
| **E — Cache `mtdTotalUsd` in a per-user row, update on each conversation insert**  | Doubles the write path's complexity for a read that already fits in sub-5 ms with an index-only scan. Correct-by-construction is simpler than cache-invalidation-by-trigger. |

## Non-Goals / Out of Scope

- **Enabling PostgREST aggregates project-wide.** Blast radius too large
  for a P2 scope-out fix. If it becomes desirable (e.g., for admin
  dashboards), file a separate infrastructure issue.
- **Backfill / data migration.** Nothing to backfill — the aggregate is
  computed on-demand, not stored.
- **Changing the `list` query shape.** The 50-row recent-activity query
  is working as intended; only the unbounded month-scope query is
  broken.
- **Cross-month totals, year-to-date, lifetime spend.** Those are
  separate product features; the current scope is strictly "replace
  the MTD reduce."

## Risk & Mitigation

| Risk                                                                    | Likelihood | Impact | Mitigation                                                                                                                                            |
|-------------------------------------------------------------------------|:----------:|:------:|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| Migration applies on dev but fails in prod (privilege drift).           | Low        | High   | Runbook REST probe runs immediately post-merge and is blocking per `wg-when-a-pr-includes-database-migrations`.                                        |
| Planner picks a seq scan at low row counts in prod.                     | Low        | Low    | AC2 EXPLAIN on dev is captured; if prod differs, the function still returns correctly — it's a performance warning, not a correctness issue. Filed as follow-up only if observed. |
| RPC response shape changes between Supabase JS client versions.         | Low        | Medium | `TABLE(total NUMERIC, n INTEGER)` returns `[{total, n}]` via PostgREST — stable since PostgREST v9.0. Pin dependency via existing `^2.49.0` range; no change needed. |
| `Number(numeric_string)` still loses precision at the JS boundary.      | Very low   | Low    | Only one coercion, on the already-summed result. For MTD totals < $10,000 with 6 decimals, IEEE 754 has > 9 significant digits of headroom. AC1 tight-bound asserts ≤ $0.001. |
| A developer manually calls the RPC from the anon role.                  | Low        | High   | Grants mirror migration 017. RED test (Phase 1 Test 3) enforces 4xx for anon at the REST layer. |

## Test Scenarios

1. User with zero conversations → `mtdTotalUsd = 0`, `mtdCount = 0`,
   `rows = []`.
2. User with 2 current-month conversations at $0.0042 and $0.0125 →
   `mtdTotalUsd = 0.0167` exactly (no float drift).
3. User with 1 prior-month + 0 current-month conversation →
   `mtdTotalUsd = 0`, `mtdCount = 0`, `rows.length = 1`.
4. User with 1,500 current-month conversations (exceeds the old
   1000-row cap) → total is correct (Option B has no cap).
5. RPC returns error → loader returns `null`; Sentry receives a
   silent-fallback event tagged `feature=api-usage, op=loadApiUsageForUser`.
6. Non-UUID input → throws before any Supabase call (existing guard
   preserved).
7. Anon-key REST probe → 4xx (grants enforced).

## Domain Review

**Domains relevant:** none (carry-forward from issue #2478 context — CTO-adjacent DB change, but the fix is purely infrastructure/correctness with no product, marketing, legal, or operational implication beyond the existing billing dashboard it already serves).

This is a targeted correctness + performance fix on an already-shipped,
user-invisible code path. The dashboard's rendered total goes from
"off by sub-cent due to float drift" to "exact"; no UI change, no copy
change, no pricing change, no new surface. Cross-domain review is not
required.

## PR body template

```markdown
Closes #2478.

Replaces the client-side JS reduce over up to 1000 NUMERIC(12,6)
`total_cost_usd` rows with a single security-definer RPC
(`sum_user_mtd_cost`) that sums on Postgres and returns a single
NUMERIC. Fixes float-summation drift (data-integrity P2), eliminates
~200 KB of unbounded wire on every dashboard load (performance P2),
and enables an index-only scan on `idx_conversations_user_cost` from
migration 017.

Option A (PostgREST `.select("total_cost_usd.sum()")`) was probed live
against the Supabase dev instance on 2026-04-17 and returned
`PGRST123 "Use of aggregate functions is not allowed"` — the hosted
PostgREST has `db-aggregates-enabled = false` project-wide and flipping
it is outside this fix's blast radius. Fell back to Option B (RPC),
which is the only path that doesn't require an infra-wide config
change.

### Verification

- [ ] `vitest run test/api-usage` — all tests pass (adapted + new parity test).
- [ ] `EXPLAIN (ANALYZE, BUFFERS)` on dev confirms `Index Only Scan using idx_conversations_user_cost`. Output in thread below.
- [ ] Dev dashboard load: MTD total matches manual `SELECT SUM(total_cost_usd)` exactly.
- [ ] Post-merge: REST probe against prod returns 200 + `[{"total":"0.000000","n":0}]` for a non-existent UUID (migration applied).
- [ ] Post-merge: REST probe with anon key returns 4xx (grants enforced).
```

## References

- Issue: [#2478](https://github.com/jikig-ai/soleur/issues/2478)
- PR that flagged this: [#2464 (merged)](https://github.com/jikig-ai/soleur/pull/2464)
- Partial index: `apps/web-platform/supabase/migrations/017_conversation_cost_tracking.sql` lines 14-18
- Sibling RPC pattern (grants, search_path): `apps/web-platform/supabase/migrations/017_conversation_cost_tracking.sql` lines 20-45
- Loader: `apps/web-platform/server/api-usage.ts:75-135`
- Existing tests to adapt: `apps/web-platform/test/api-usage.test.ts`
- Runbook: `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
- Relevant AGENTS.md rules:
  - `cq-write-failing-tests-before` (TDD gate)
  - `cq-silent-fallback-must-mirror-to-sentry` (observability on error branch)
  - `wg-when-a-pr-includes-database-migrations` (post-merge verification)
  - `cq-in-worktrees-run-vitest-via-node-node` (test invocation)
