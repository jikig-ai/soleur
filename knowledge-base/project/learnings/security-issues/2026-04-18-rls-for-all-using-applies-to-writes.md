---
module: web-platform/auth
date: 2026-04-18
problem_type: security_issue
component: database
symptoms:
  - "Test comment claiming 'WITH CHECK falls back to USING' on a FOR ALL policy"
  - "Redundant public.users upsert in test masks trigger regression"
root_cause: misunderstood_rls_semantics
resolution_type: documentation_and_test_restructure
severity: medium
tags: [rls, supabase, postgres, tenant-isolation, byok, test-design]
synced_to: [work]
---

# RLS `FOR ALL USING` (no `WITH CHECK`) applies to writes too — and how to keep trigger invariants canaried in tests

## Problem

Two non-obvious pitfalls surfaced while writing the BYOK per-tenant isolation integration test (#1449, PR #2598):

1. **The USING expression on a `FOR ALL` policy with no explicit `WITH CHECK` governs write row-validity too** — not via some "WITH CHECK falls back to USING" fallback. The plan and the initial test comment both framed the behavior as a fallback. The security-sentinel review agent caught the framing: the policy is just `FOR ALL USING (auth.uid() = user_id)` (migration 001:40-42); Postgres evaluates the USING expression against each candidate row for INSERT/UPDATE/DELETE too, which is why a spoofed INSERT claiming another tenant's `user_id` is rejected. Same observed behavior, different mental model — and the wrong mental model would let a future maintainer add `WITH CHECK (true)` "to be explicit," which would defeat the invariant. The correct framing matters for future review.

2. **A redundant `upsert` into `public.users` in the test's `beforeAll` masked a potential regression in the `on_auth_user_created` trigger** (migration 001:115). The trigger already auto-creates `public.users` rows from `auth.users` inserts. An `upsert` with `onConflict: "id"` succeeds whether the trigger ran or not — so if someone ever drops or breaks the trigger, production signup silently breaks, and this test happily passes. data-integrity-guardian flagged it during review.

## Investigation

**Pitfall 1** — While researching the plan, I wrote: "The RLS policy is `FOR ALL USING` with no explicit `WITH CHECK`. Per Postgres semantics, `WITH CHECK` falls back to `USING` when omitted." Shipped the comment verbatim into the test. security-sentinel reviewed and replied:

> The behavior is correct but the comment's stated mechanism is wrong; a future maintainer adding an explicit `WITH CHECK (true)` (a real footgun pattern) would defeat this invariant and the comment would mislead the review.

Re-reading the Postgres docs confirms: `FOR ALL` with only `USING` **applies that USING expression to the row visibility of the operation**, which for writes means the target row must satisfy USING. There is no "fallback" — there is a single expression doing both jobs, and that framing is what survives a future `WITH CHECK (true)` drive-by edit.

**Pitfall 2** — The original test's `beforeAll` ran `service.from("users").upsert({id: user.id, email: user.email}, {onConflict: "id"})` for both users. I thought I needed to seed `public.users` for the FK from `api_keys.user_id` to resolve. data-integrity-guardian pointed at migration 001:101-116:

```sql
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, workspace_path)
  values (new.id, new.email, '/workspaces/' || new.id::text);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

The trigger does the work. The upsert was redundant *and* defensively hiding its absence.

## Root Cause

1. A comment written from a "fallback" mental model vs. the actual single-expression semantics. The wrong framing opens the door to a future refactor that silently weakens the invariant.

2. An "integration test must set up its own fixtures" instinct applied without checking what the DB already does on its own. The instinct conflicts with the test's job of *verifying* production invariants — setup steps that paper over trigger-level invariants mask the very regressions the test should catch.

## Solution

**For pitfall 1** — Fix the comment to reflect single-expression semantics:

```ts
// The api_keys RLS policy is `FOR ALL USING (auth.uid() = user_id)` with
// no WITH CHECK clause (001_initial_schema.sql:40-42). Postgres evaluates
// the USING expression against each candidate row for write operations
// too, so an INSERT claiming a foreign user_id fails because
// auth.uid() = userA.id is false when the session is user B.
```

**For pitfall 2** — Replace the upsert with a SELECT assertion that turns the test into a trigger-regression canary:

```ts
// Trigger-regression canary: on_auth_user_created (migrations 001:115)
// auto-creates the public.users row. A silent trigger regression would
// break production signup; this SELECT catches it here instead.
const { data: profile, error: profileError } = await service
  .from("users")
  .select("id, email")
  .eq("id", user.id)
  .single();
expect(profileError, `public.users row missing for ${user.email}`).toBeNull();
expect(profile?.email).toBe(user.email);
```

## Prevention

When writing or reviewing RLS-related tests and comments:

- **Don't frame `FOR ALL USING` behavior as "WITH CHECK falls back to USING."** Frame it as "the USING expression applies to write row validity too." The difference is whether someone could "fix" the implicitness by adding `WITH CHECK (true)` — they can't; that would actually break the invariant.
- **Before writing a fixture setup step that mutates a table with an `ON INSERT` trigger on its parent, check whether the trigger already provides the fixture.** If it does, replace the mutation with an assertion that the trigger ran. This turns every integration test into a canary for the trigger's continued existence.
- **When a review agent disagrees with an explanation of security semantics, treat the disagreement as a correction-until-proven-otherwise.** The agent's reply is cheap; a wrong comment stays in the codebase for years.

## Session Errors

- **Bash tool CWD reset mid-sequence** — Recovery: switched to absolute paths for subsequent calls (`./node_modules/.bin/vitest` from worktree root). Prevention: when running a multi-step local command sequence, prefer a single Bash call with `cd <abs> && <cmd>` per `cq-for-local-verification-of-apps-doppler`, or use absolute paths everywhere. Neither rule flex is new — this session just drifted from the guidance mid-flow.
- **Plan test-count drift during deepen-pass** (forwarded from session-state.md) — Recovery: caught before finalizing; all 3 spots fixed pre-commit. Prevention: when a deepen-pass adds a test, grep the plan for the old count (`rg -n '4 tests'`) before committing — automatable as a markdownlint custom rule if it recurs.

## Cross-references

- **PR #2598** — BYOK per-tenant isolation verification (this session's work).
- **Issue #1449** — sec: verify BYOK encryption is per-tenant isolated (Multi-User Readiness MU2).
- **Issue #2612** — follow-up: master-key envelope encryption.
- **Issue #2613** — follow-up: wire BYOK integration test into nightly CI.
- **Issue #2614** — follow-up: periodic subprocess-env audit.
- **Related learning** — `knowledge-base/project/learnings/security-issues/rls-column-takeover-github-username-20260407.md` (permissive `UPDATE` policies also grant access to new columns — complementary RLS gotcha).
- **Related learning** — `knowledge-base/project/learnings/2026-04-12-silent-rls-failures-in-team-names.md` (silent RLS failures in read paths).
- **Related learning** — `knowledge-base/project/learnings/integration-issues/2026-04-07-supabase-postgrest-anon-key-schema-listing-401.md` (PostgREST returns 200 with `[]` for RLS-filtered table queries, not 401 — referenced in the BYOK test's SELECT assertion).
- **Related brainstorm** — `knowledge-base/project/brainstorms/2026-03-20-byok-key-storage-evaluation-brainstorm.md` (Supabase Vault rejected for per-user keys; HKDF chosen).
