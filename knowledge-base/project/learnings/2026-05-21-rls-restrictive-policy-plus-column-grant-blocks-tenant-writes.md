---
date: 2026-05-21
category: security-issues
module: apps/web-platform/server/session-sync.ts
problem_type: silent_write_failure
component: supabase_rls_column_grant
severity: high
tags:
  - rls
  - column-grant
  - security-definer-rpc
  - silent-failure
  - tenant-client
  - kb-sync-history
related_pr: 4226
related_issue: 4224
synced_to: [data-integrity-guardian-issue-4240]
---

# RLS RESTRICTIVE policy + column-level GRANT silently blocks every tenant-client write

## Problem

`#4224` extended `users.kb_sync_history` with a new writer (`appendKbSyncRow`) and a new UI surface (`KbSyncStatus`) that reads the latest row. Multi-agent review surfaced a load-bearing prerequisite: **the tenant client has no UPDATE privilege on `kb_sync_history`**, so every write through `getFreshTenantClient(userId).from("users").update({kb_sync_history: ...})` silently fails. The UI would have shipped permanently stuck at "Workspace ready" (the empty-state fallback) regardless of actual sync activity.

The pre-existing `recordKbSyncHistory` (legacy daily-count sparkline) had the same write path — meaning PR-C §2.1 (#3244) migrated it to the tenant client in good faith, but the actual UPDATE has been failing silently in prod ever since (caught by the function's best-effort `log.warn` — no Sentry mirror existed for that catch site until #4224 added one).

**Root cause:** Two independent Postgres authorization layers, both invisible to mocked tests:

1. **Migration `006_restrict_tc_accepted_at_update.sql`** revokes table-wide UPDATE from `authenticated` and re-grants only `UPDATE (email)`. Any UPDATE statement that mentions `kb_sync_history` is rejected by the column grant before RLS runs.
2. **Migration `017_kb_sync_history.sql`** adds a RESTRICTIVE RLS policy that requires the new column value to equal the old: `kb_sync_history IS NOT DISTINCT FROM (SELECT kb_sync_history FROM public.users WHERE id = auth.uid())`. The migration's own header comment names the intent: *"Only the service role (used by session-sync after syncPush) should write this column."*

`getFreshTenantClient()` mints a JWT with `role=authenticated` (PR-C §2.1 default). Both layers reject the write; supabase-js returns `{error: { code: '42501' /* permission denied */ }}` which the helper absorbs via `reportSilentFallback`.

Tests didn't catch this because every test that exercises the helper mocks `getFreshTenantClient` to a recursive `eqChain.then = (r) => r({error: null})` — the auth boundary is never crossed, so the GRANT/RLS rejection never fires.

## Solution

New migration `053_append_kb_sync_row_rpc.sql` introduces a `SECURITY DEFINER` RPC that the tenant client can call:

```sql
CREATE OR REPLACE FUNCTION public.append_kb_sync_row(
  p_row jsonb,
  p_cap int DEFAULT 100
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'append_kb_sync_row: no auth.uid()';
  END IF;
  UPDATE public.users
     SET kb_sync_history = (
       WITH appended AS (
         SELECT elem, ord FROM jsonb_array_elements(COALESCE(kb_sync_history, '[]'::jsonb)) WITH ORDINALITY t(elem, ord)
         UNION ALL
         SELECT p_row, COALESCE(jsonb_array_length(kb_sync_history), 0) + 1
       ),
       trimmed AS (
         SELECT elem, ord FROM appended ORDER BY ord DESC LIMIT p_cap
       )
       SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb) FROM trimmed
     )
   WHERE id = v_caller;
END;
$$;

REVOKE ALL ON FUNCTION public.append_kb_sync_row(jsonb, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.append_kb_sync_row(jsonb, int) TO authenticated;
```

The `auth.uid()` pin is the tenant-isolation primitive — the function only ever writes the caller's own row, even though it runs with owner privileges. The `search_path` pin matches `cq-pg-security-definer-search-path-pin-pg-temp`.

`appendKbSyncRow` in `server/session-sync.ts` becomes a thin RPC dispatch:

```ts
export async function appendKbSyncRow(userId: string, row: KbSyncRow) {
  try {
    const tenant = await getFreshTenantClient(userId);
    const { error } = await tenant.rpc("append_kb_sync_row", {
      p_row: row,
      p_cap: KB_SYNC_HISTORY_CAP,
    });
    if (error) reportSilentFallback(error, { /* ... */ });
  } catch (err) { /* ... */ }
}
```

## Key Insight

**A tenant-client write that compiles, type-checks, and passes mocked tests can still be 100% rejected in prod because Postgres authorization runs at the wire boundary that mocks short-circuit.** The combination of `cq-pg-security-definer-search-path-pin-pg-temp` rules ALREADY signals when a SECURITY DEFINER RPC is the right shape; the inverse heuristic — *"if you can't write the column with `tenant.from(...).update(...)`, you need an RPC"* — was unwritten.

Two compounding side benefits of the RPC pattern:

1. **Atomic read-modify-write** — the previous JS-side `SELECT … then UPDATE` had no optimistic concurrency. Concurrent webhook + manual reconcile calls could each load the same `existing` array and clobber each other's append. The single-statement UPDATE under `auth.uid()` takes a row-level lock; lost-update is impossible.
2. **Heterogeneous JSONB preservation** — the RPC appends to whatever is there (legacy `{date,count}` + new rich rows) and trims by ordinality. No JS-side discriminator needed, no cap drift between writers.

## Prevention

- **When adding a new column to `public.users`, decide at-migration-time whether it should be tenant-writable.** If yes: add a `GRANT UPDATE (<col>) ON TABLE public.users TO authenticated` line — and if the column needs append/trim semantics, write the RPC at the same time. If no: document it on the column comment AND make sure no helper writes it via the tenant client.
- **Audit every tenant-client `.update({…})` on `public.users` for `cq-write-boundary-sentinel-sweep`** : `git grep -nE 'tenant.*\.from\("users"\)\.update' apps/web-platform/server/` should match only columns the authenticated role can write. The current matches against `kb_sync_history` should be flagged as defects until #053 lands (or as redundant once the RPC replaces them).
- **Mock-based tests need an integration counterpart for the auth boundary.** When a helper writes a column with row/column-level grants, either (a) run one integration test against a real Supabase instance with `TENANT_INTEGRATION_TEST=1`, or (b) add a unit test that asserts the helper calls a SECURITY DEFINER RPC (which is the only tenant-callable write path).
- **The `cq-silent-fallback-must-mirror-to-sentry` rule is doubly load-bearing for tenant-write helpers.** Without the mirror, prod rejections look like "no rows ever land" — which an admin reading the analytics dashboard interprets as "no syncs happened," not "every sync silently dropped." The migration's own intent comment ("Only the service role should write this column") was the only signal that the post-PR-C #3244 state was broken.

## Session Errors

1. **Initial bash invocation in bare repo root** — `pwd && git status` ran in `/home/jean/git-repositories/jikig-ai/soleur/` and errored "this operation must be run in a work tree." **Recovery:** cd into the worktree first. **Prevention:** /soleur:work and /soleur:review skills should detect bare-repo context at Phase 0 and refuse to proceed without an explicit worktree path. (PreToolUse hook on Bash that rejects `git status` / `git diff` in bare-repo roots would also work.)

2. **`timeout` not on PATH after Bash CWD drift** — `cd apps/web-platform && timeout ./node_modules/.bin/vitest ...` worked, but a follow-up bare invocation `timeout ./node_modules/.bin/vitest ...` (without re-cd) failed because the Bash tool's CWD doesn't persist between calls. **Recovery:** prefix every Bash invocation with `cd <abs-path> &&`. **Prevention:** there's an existing learning at `2026-04-19-bash-cwd-no-persist.md` covering this; the pattern recurs because absolute paths are verbose.

3. **`vi.mock` factory referenced top-level constants (3 distinct test files)** — `session-sync-sentry-mirror.test.ts`, `kb-route-helpers.test.ts` second try, `workspace-reconcile-on-push.test.ts` mock update all hit `ReferenceError: Cannot access 'X' before initialization` because vitest hoists `vi.mock` factories above top-level `const` declarations. **Recovery:** wrap spies in `vi.hoisted({ spy: vi.fn() })`. **Prevention:** when writing a new test file that mocks a module + needs to inspect calls, default-template the spy declaration as `const { spy } = vi.hoisted({ spy: vi.fn() })`. The skill `andrew-kane-gem-writer` and `feature-dev:code-architect` could mention this in their test-template guidance.

4. **Stale `user.id` references after rename to `userId`** — extracted a long `POST` body into `handleSync(userId)` and didn't grep all references. Tests failed with 500 because `user.id` was undefined inside the extracted function. **Recovery:** `Edit` with `replace_all: true` for the rename. **Prevention:** use `replace_all` from the start when renaming a parameter that's used throughout the function body.

5. **TypeScript handler-logger type mismatch (Inngest)** — `syncWorkspace` expects pino `Logger`; the Inngest `step.logger` only exposes warn/info/error. Initially fell through with `const log = stepLogger ?? logger` which tsc rejected (`BaseLogger` properties missing). **Recovery:** always use the module-scoped pino `logger` for `syncWorkspace`; mark `stepLogger` as `void stepLogger` since the Inngest event-step logger is only for run-time telemetry. **Prevention:** Inngest peer functions (`cfo-on-payment-failed.ts`, `github-on-event.ts`) already use the module-scoped logger for SDK calls. A skill rule on `soleur:engineering:design:ddd-architect` or a `cq-*` could say: "When an Inngest function calls a helper that expects pino `Logger`, do not pass the step.logger — use the module-scoped logger; the step.logger is only for the Inngest UI panel."

6. **Migration 053 missing REVOKE for anon/authenticated** — first version only revoked PUBLIC. `migration-rpc-grants.test.ts` requires REVOKE from all three roles before GRANT EXECUTE. **Recovery:** change to `REVOKE ALL ... FROM PUBLIC, anon, authenticated`. **Prevention:** the rule `cq-pg-security-definer-search-path-pin-pg-temp` enforces `search_path` but not the REVOKE shape — could extend to a sibling `cq-pg-security-definer-revoke-pattern` that mirrors the `migration-rpc-grants.test.ts` check inline. (Or: the migration template at `plugins/soleur/skills/work/references/`should include the canonical 3-role REVOKE in any RPC scaffolding.)

7. **Mock factory dropping real constants** — `vi.mock("@/server/session-sync", () => ({ appendKbSyncRow: spy }))` clobbered the new constant exports (`WORKSPACE_RECONCILE_REQUESTED_EVENT`, error_class literals). The Inngest function's imports resolved to `undefined`, blowing up its inngest.createFunction call. **Recovery:** spread `await importOriginal()`: `vi.mock("@/server/session-sync", async (importOriginal) => ({ ...(await importOriginal()), appendKbSyncRow: spy }))`. **Prevention:** when a module exports both runtime constants and functions, always use `importOriginal` spread in mocks; a one-line bullet in `soleur:atdd-developer` or the testing skill would prevent recurrence.

## Cross-references

- AGENTS.md hard rule [id: cq-pg-security-definer-search-path-pin-pg-temp] — sibling concept; the `auth.uid()` pin is to function-body semantics what `search_path` pin is to extension-namespace semantics.
- AGENTS.md [id: cq-silent-fallback-must-mirror-to-sentry] — without this, prod write-rejections look like absence-of-activity instead of failure.
- AGENTS.md [id: hr-write-boundary-sentinel-sweep-all-write-sites] — the column-grant/RLS pair IS a write-boundary sentinel, but at the DB layer rather than the TypeScript layer.
- Plan: `knowledge-base/project/plans/2026-05-21-feat-workspace-reconciliation-with-main-plan.md`
- Spec: `knowledge-base/project/specs/feat-workspace-reconciliation-4224/spec.md`
- PR: #4226
