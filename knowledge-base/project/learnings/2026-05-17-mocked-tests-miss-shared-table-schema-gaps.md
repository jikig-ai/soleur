# Mocked unit tests miss shared-table schema gaps; multi-agent review catches them

**Captured:** 2026-05-17
**Source PR:** #3940 (PR-F Inngest trigger layer)
**Source plan:** `knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md`
**Defect class:** mocked-test false-pass against absent DB columns + RLS policy
**Severity:** P1 (would have failed at first prod invocation; auto-merge would have shipped broken code)

## Problem

PR-F shipped a complete-looking Inngest CFO function that INSERT-ed into `messages` with `{user_id, tier, source, owning_domain, draft_preview, urgency, trust_tier, status:'draft'}`, plus a `/api/dashboard/today` route that SELECT-ed the same columns, plus a migration 046 that added a CHECK constraint referencing `tier`. **None of those columns existed on `main`** — the `messages` table only had `(id, conversation_id, role, content, tool_calls, created_at, leader_id, status, usage)`. The existing `status` CHECK from migration 040 admitted only `('complete', 'aborted')` — incompatible with `'draft'`. The existing RLS policy gated inserts on `EXISTS(conversations c WHERE c.id = conversation_id AND c.user_id = auth.uid())` — the CFO insert had no `conversation_id` so the policy would have rejected the write even after the columns existed.

The PR had:
- 3548 passing unit tests
- 994 passing component tests
- 22 passing migration shape tests
- tsc --noEmit clean
- 11-agent multi-agent review was the ONLY signal that surfaced the gap

The plan was reviewed by DHH + Kieran + Code Simplicity at plan-time. Plan §Phase 1 specified migration 046 adds `runtime_paused_at`, `runtime_cost_cap_cents`, `record_byok_use_and_check_cap`, and the `messages_external_tier_status_check` CHECK constraint. It did NOT specify adding the columns the CHECK + the CFO insert + the today route all depend on. The plan **assumed they existed**. Plan-time review didn't catch this either.

## Root cause

Three test surfaces independently failed to exercise the production-DB schema:

1. **CFO function unit tests** mocked `@/lib/supabase/tenant` with `getFreshTenantClientSpy = vi.fn(async () => ({ from: () => ({ insert: insertSpy }) }))`. The mock happily accepted any row shape; `insertSpy.mock.calls[0][0]` returned the row the SUT *tried* to insert, not the row a real DB would have accepted or rejected.

2. **Dashboard today-route unit tests** mocked the entire PostgREST chain (`from → select → eq → eq → eq → order → limit`) with hoisted `vi.fn()` stubs. The mock accepted any column name in `.eq()` and `.select()`; no chain stage said "that column doesn't exist."

3. **Migration shape tests** are file-parse-only (`readFileSync` + regex against the SQL text). They verified the migration **says** the right things (`LANGUAGE plpgsql`, `FOR UPDATE`, `SECURITY DEFINER`, etc.) but never executed the SQL against a real database. The integration-tier `046-runtime-cost-state.atomicity.integration.test.ts` IS the test that would have caught the schema gap — but it was gated on `TENANT_INTEGRATION_TEST=1` and never ran in this `/work` session.

The compounding failure mode: each layer of the test pyramid had a different mocking strategy, and each strategy was internally consistent — but no single test in the suite ever asked PostgreSQL `does this column exist?` for the columns the SUT was about to read or write.

## Solution

**Inline P1 fix in commit `4408d3f0`:** Extended migration 046 with §1.5 (messages external-drafts schema additions) inserted BEFORE the CHECK constraint:
- `ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE, tier text, source text, owning_domain text, draft_preview text, urgency text, trust_tier text` (all NULLABLE so legacy conversation-bound rows remain valid)
- `DROP + ADD CONSTRAINT messages_status_check CHECK (status IN ('complete','aborted','draft','archived'))` to widen the migration-040 enum
- Two new RLS policies (idempotent DROP+CREATE) gating user_id-routed reads/inserts alongside the existing conversation-id policies
- `CREATE INDEX IF NOT EXISTS messages_today_idx ON public.messages (user_id, created_at DESC) WHERE tier IN external_* AND status='draft'` partial covering index
- 5 new shape-test assertions in `046-runtime-cost-state.test.ts` pinning each addition

## Prevention

The cheapest mechanical gate that would have caught this **at /work time** rather than /review time:

**When a plan touches a migration AND a sibling code path writes/reads from the same table, /work Phase 1 MUST run the migration against a real Supabase dev instance and assert the consumer-side columns exist BEFORE writing the consumer code.** The Supabase MCP (via Doppler `DATABASE_URL_POOLER`) is the canonical path per the work skill's "Supabase fallback chain" — applying the migration to dev makes the column existence verifiable in <5 seconds.

Mechanical detection (during /work Phase 1):

```bash
# 1. From the plan's Phase 1 migration files, extract the target tables:
TABLES=$(grep -oE 'ALTER TABLE\s+(public\.)?(\w+)|CREATE TABLE\s+(public\.)?(\w+)' \
  <migration-files> | awk '{print $NF}' | sort -u)

# 2. For each table, grep the diff for consumer-side .insert({...}) and .select(...):
for table in $TABLES; do
  git diff main...HEAD -- apps/web-platform/ | \
    grep -E "\.from\(\"$table\"\)\.(insert|select)" | head
done

# 3. Cross-reference the consumer-side column names against the migration's
#    ADD COLUMN list and the existing schema (last 5 migrations grep).
```

If a consumer-side column name does NOT appear in:
(a) the new migration's `ADD COLUMN`, OR
(b) the cumulative schema from all prior migrations,
then the consumer code is referencing a non-existent column. Halt /work Phase 1 and either add the column to the migration or pause for plan refinement.

**Secondary gate (cheap second net):** for any table referenced by both a migration AND a consumer in the same PR, require an integration test that runs against a real Supabase dev instance (Doppler-mediated). The TENANT_INTEGRATION_TEST flag should fire automatically when this combination is detected — not require a separate env-var-set CI job.

## Session Errors

1. **Inngest version `^3.45.4` chosen without verification** — `^3.45.4` doesn't exist (npm only has `^3.45.0`, `^3.45.1`). Corrected by `npm view inngest versions --json` → pinned `^3.54.2`. **Recovery:** queried npm registry. **Prevention:** before pinning a new npm dep, query `npm view <pkg> versions --json | tail -50` to confirm the target version exists.

2. **Bash CWD shift surprise** — first `cd apps/web-platform &&` worked, second failed with "No such file or directory" because CWD had already shifted into `apps/web-platform`. **Recovery:** dropped the `cd` from subsequent commands. **Prevention:** the Bash tool's CWD persists across calls — use absolute paths or expect prior `cd` effects to compound.

3. **Source-grep regex missed multiline method chain** — `/stripe\.charges\.retrieve\(/` didn't match `stripe.charges\n      .retrieve(...)`. **Recovery:** allowed whitespace: `/stripe\.charges\s*\.\s*retrieve\s*\(/`. **Prevention:** when grepping source for method-chain calls, allow `\s*\.\s*` between identifier and method.

4. **Positive HMAC signature test failed** — attempted to forge an Inngest signature by stripping `signkey-` prefix and HMAC'ing `<timestamp><body>`. SDK's internal signing format is more complex (canonical serialization, key derivation). **Recovery:** replaced with mode-flip discriminator (set `INNGEST_DEV=1` so SDK skips validateSignature, prove same bad-sig request returns NOT 401). **Prevention:** don't reverse-engineer SDK signing protocols for tests; use the SDK's mode-flip or expose a test-mode bypass instead.

5. **Schema-gap P1 escaped /work** — see "Root cause" + "Prevention" sections above. **Recovery:** multi-agent /review caught it; inline-fixed in commit 4408d3f0 with schema migration + RLS + index + 5 new shape-test assertions. **Prevention:** /work Phase 1 must apply migrations against a real Supabase dev instance and cross-reference consumer-side column names BEFORE writing the consumer code (see "Prevention" above for the mechanical gate).

6. **NODE_ENV readonly mutation TS2540** — `process.env.NODE_ENV = "production"` in a test file fails tsc (NODE_ENV is typed `readonly string`). **Recovery:** cast via `(process.env as Record<string, string | undefined>)[key]` + `@ts-expect-error` for the direct assignment. **Prevention:** always use the `as Record<string, string | undefined>` cast when restoring env vars typed as readonly; never assign directly.

7. **Lockfile diff much larger than expected** — `npm install --package-lock-only` after adding inngest produced 2850-line lockfile diff (transitive OpenTelemetry instrumentation packages). Not actually an error, but caused brief alarm. **Recovery:** verified by inspecting `node_modules/inngest/package.json` transitive deps. **Prevention:** when adding a dep with heavy transitive baggage (Inngest, Next.js, Sentry), expect lockfile churn proportional to the dep's instrumentation surface; no action needed if `bun install --frozen-lockfile` validates cleanly.

## Related learnings

- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — sibling pattern
- `knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — TS↔SQL parity verification before migration commit
- `knowledge-base/project/learnings/2026-05-04-plan-precedent-search-must-include-lib-helpers.md` — plan precondition verification

## Tags

category: integration-issues
module: apps/web-platform/supabase + apps/web-platform/server + apps/web-platform/app/api
defect-class: mocked-test-false-pass-against-absent-schema
captured-by: multi-agent-review-after-mocked-unit-tests-passed
gate-proposed: /work-phase-1-real-db-cross-reference
