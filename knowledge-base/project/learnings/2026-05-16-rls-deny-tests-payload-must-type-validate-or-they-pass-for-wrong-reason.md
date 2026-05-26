---
title: RLS-deny tests must use schema-correct payloads — Postgres type-validation fires BEFORE RLS, masking real coverage
date: 2026-05-16
category: test-failures
tags:
  - supabase
  - rls
  - tenant-isolation
  - postgres
  - 22p02
  - vitest-blind-class
  - pr-3244
related:
  - "#3244 §2 (PR-C sibling-query migration)"
  - "PR #3854"
  - "Issue #3869 (PR-C deferrals tracker)"
  - 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind
  - 2026-05-07-write-side-primitive-without-read-side-select-is-an-agent-native-parity-gap
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss
---

# Problem

PR-C (#3244 §2) added 11 tenant-isolation integration tests under `apps/web-platform/test/server/*.tenant-isolation.test.ts`. Each test mints a synthetic founder JWT, then asserts a cross-tenant INSERT/UPDATE/SELECT is RLS-denied. The cc-dispatcher suite (`cc-dispatcher.tenant-isolation.test.ts:136-182`) seeded user B's `conversation_id` and asserted user A's tenant client could NOT INSERT a row into `messages` via that FK:

```ts
const { data, error } = await aClient
  .from("messages")
  .insert({
    id: randomBytes(16).toString("hex"),  // ← the bug
    conversation_id: bConvId,
    role: "user",
    content: "spoofed by A",
    ...
  })
  .select("id");
const succeeded = data && data.length > 0;
expect(succeeded).toBeFalsy();
```

Vitest reported `passed` on every iteration. The `data-integrity-guardian` agent caught it during multi-agent review: `messages.id` is type `uuid` (per `001_initial_schema.sql:46`), and `randomBytes(16).toString("hex")` produces a 32-char hex string with no dashes — Postgres rejects it with error code `22P02` (`invalid_text_representation`) **before** RLS evaluates the `with check` policy.

**The RLS deny path was never executed.** The test passed because the row failed type validation. If the migration had accidentally widened the RLS policy to allow cross-tenant writes, this test would still have passed — the type error would have continued masking the missing RLS coverage.

# Root cause

Postgres evaluates a write in a fixed order: parse → type-cast inputs → constraint checks → RLS `with check` → execute. Type validation at step 2 fails fast with `22P02`; RLS at step 4 never runs. A test that asserts "the write did not persist" passes whether the gate at step 2 OR step 4 stopped it — but only step 4 is the gate under test.

This is the same class as the 2026-05-06 vitest-blind learning (`REVOKE EXECUTE` causes `42501` → tests pass without testing the policy) but the trigger is different: there, the test never even compiled against the real grant surface; here, the test compiled but a more-eager validator preempted the policy.

# Solution

Use `randomUUID()` from `node:crypto` for any column typed `uuid`:

```diff
-import { randomBytes } from "node:crypto";
+import { randomBytes, randomUUID } from "node:crypto";
 ...
-    id: randomBytes(16).toString("hex"),
+    id: randomUUID(),
```

Fix committed in `aa22dc9b`. Both `messages.id` insert sites in `cc-dispatcher.tenant-isolation.test.ts` updated; passwords and `session_id` (text columns) still use `randomBytes`.

# Prevention

The general principle: **a deny-test must send a payload that would have SUCCEEDED if the gate under test were removed.** If type-validation, FK-existence, or check-constraint failures preempt the policy, the test passes for the wrong reason and gives no signal when the policy regresses.

Rules of thumb for tenant-isolation / RLS-deny test design:

1. **Payload columns must type-validate against the live schema.** `uuid` → `randomUUID()`. `timestamptz` → `new Date().toISOString()`. `jsonb` → real JSON, not `{}` if a NOT NULL key is required. `text` with a CHECK constraint (e.g., `role IN ('user','assistant')`) → a value the check accepts.

2. **FK targets must exist.** If you're testing RLS on `messages` via FK to `conversations.user_id`, seed user B's `conversations` row with service-role first, then point user A's INSERT at `bConvId`. (PR-C tests already do this.)

3. **Distinguish RLS-deny from row-absent.** `expect(data).toEqual([])` passes whether RLS denied OR the seed row never landed. Add a service-role re-read after the denied write to confirm the row is actually absent — `session-sync.tenant-isolation.test.ts` does this for UPDATE poison-checks; generalize the pattern. (Tracked in #3869.)

4. **For each RLS policy under test, run a positive control.** A test that "user B's tenant client successfully INSERTs into B's own conversation" confirms the payload shape, FK seeding, and policy-evaluation order are correct — if the positive control fails for any reason other than the policy, the negative tests below it are unreliable.

# Session Errors

- **Plan §0.4 destructure-shape drift** — Plan sample used `const { client } = await getFreshTenantClient` but actual signature returns `Promise<SupabaseClient>`. Recovery: adapted per `agent-runner.ts:188` precedent. Prevention: covered by existing learning `2026-05-15-plan-verbatim-code-must-grep-target-file-local-conventions`.

- **Explicit auth-probe broke 12+ consumer test mocks** — Plan §0.4 prescribed `.from("users").maybeSingle()` probe; pulled an extra mock contract through 12 ws-* test files. Recovery: switched ws-handler `tenantFor` and conversation-writer to implicit-mint probe (RuntimeAuthError IS the probe) per `agent-runner.ts:188`. Prevention: plan reviewers should treat probe-mode (explicit vs implicit) as a per-surface decision matrix, not a uniform prescription.

- **`service.rpc is not a function` in cc-dispatcher tests** — Real `getFreshTenantClient` chain pulled `mintFounderJwt` → `service.rpc("precheck_jwt_mint")` through unmocked supabase-js. Recovery: added `vi.mock("@/lib/supabase/tenant", ...)` to short-circuit. Prevention: extract shared `test/helpers/tenant-mocks.ts` (tracked #3869 item 1).

- **byok-lease mock bridge for `KeyInvalidError`** — Hardcoded fake key in lease mock bypassed legacy `mockGetUserApiKey.mockRejectedValueOnce` setup. Recovery: bridged by making `lease.getApiKey()` delegate to legacy mock fn. Prevention: when introducing a new lease-wrapped primitive, ensure mock helpers delegate to existing test surfaces rather than short-circuiting them.

- **vi.hoisted for class decls in vi.mock factory** — `FakeRuntimeAuthError` referenced before declaration (hoisting bug). Recovery: wrapped in `vi.hoisted(() => ({ FakeRuntimeAuthError: class … }))`.

- **CWD reset across Bash calls** — `cd apps/web-platform && tsc` worked once then forgot. Recovery: standardized on absolute-path-chained Bash (`cd /abs/path && ./node_modules/.bin/tsc` in single call).

- **UUID-format bug (this learning's subject)** — caught by review, not by author. Recovery: replaced `randomBytes(16).toString("hex")` with `randomUUID()`. Prevention: this learning.

- **`TENANT_INTEGRATION_TEST=1` silent-skip trap** — 11 integration test files `describe.skipIf`'d with no CI workflow asserting the gate fires. Caught by `test-design-reviewer`. Recovery: filed #3869 item 6 (CI tenant-integration job — needs Doppler dev-Supabase secrets). Prevention: when adding `describe.skipIf`-gated tests, simultaneously open a tracked issue or CI workflow PR — the skip-gate is the trap, not the test logic. Adjacent to the 2026-05-06 vitest-blind class.

# Workflow proposal — feedback into rules

For Phase 1.5 deviation analyst review:

**Proposed addition to `apps/web-platform/AGENTS.md` (test domain section):** "When asserting RLS-deny on an INSERT, the payload must type-validate against the live schema — otherwise Postgres rejects with `22P02` BEFORE RLS evaluates and the test passes for the wrong reason. Use `randomUUID()` for `uuid` columns, real timestamps for `timestamptz`, etc. A positive control (same payload shape, same user's own row, expect success) confirms the payload is policy-reachable."

Enforcement tier: **skill instruction** (test-design-reviewer agent already exists and would catch this if the rule were in its checklist — promote to its reference notes). Hook is impractical (would need schema introspection at lint time).
