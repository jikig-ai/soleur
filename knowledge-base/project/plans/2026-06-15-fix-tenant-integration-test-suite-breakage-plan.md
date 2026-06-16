---
title: "fix: tenant-integration test-suite breakage (stale assertion, column-REVOKE reframe, harness determinism)"
type: fix
date: 2026-06-15
lane: cross-domain
semver: patch
requires_cpo_signoff: false
brand_survival_threshold: none
---

# fix: tenant-integration test-suite breakage

## Enhancement Summary

**Deepened on:** 2026-06-15
**Halt gates passed:** 4.6 User-Brand Impact (threshold `none`, sensitive-`.sql`-path scope-out present), 4.7 Observability (skip — test/docs only), 4.8 PAT-shaped var (no match), 4.9 UI-wireframe (no UI surface in Files lists).

### Key Improvements
1. **Fix 3 retry predicate is now grounded against the installed `@supabase/auth-js@2.99.2`** — was the load-bearing unknown. HTTP 429 surfaces as `AuthApiError` with `.status === 429` (the library does NOT auto-retry 429 — only 502/503/504 via `AuthRetryableFetchError`, `node_modules/@supabase/auth-js/dist/module/lib/fetch.js:6-14`), so the wrapper IS required. Canonical detect predicate pinned below.
2. **Precedent-diff (Phase 4.4) confirms Option B (durable column protection) is achievable** — it is the exact mig-006 pattern, proving the arguments' "would be re-clobbered" is imprecise. The recommendation stays Option A (debt marker) on maintenance-cost grounds, but now honestly.
3. **Verify-negative pass confirms Phase 2.1** — no table-level UPDATE revoke exists on `conversations`, so owner direct UPDATE succeeds under RLS (the original test relied solely on the no-op column-REVOKE).

### New Considerations Discovered
- The opaque `"Database error deleting user"` is a 500-class admin error (not a 429); the retry predicate must match it by message too, not only by 429 status.
- mig 075's SECURITY DEFINER RPC grant shape (`REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE … TO authenticated`) is already correct — no RPC change in scope, consistent with "do not touch the RPC".

## Research Insights — grounded findings

### GoTrue retry predicate (Fix 3, auth-js@2.99.2)

Verified against `node_modules/@supabase/auth-js/dist/module/lib/errors.d.ts:13-40` + `error-codes.d.ts:6` + `fetch.js:6-14`:

- `AuthApiError.status` is always a `number` (required ctor arg); `.code` is `string | undefined`.
- HTTP 429 → `AuthApiError` (`.status === 429`), NOT auto-retried by the library.
- Rate-limit `code` enum values: `over_request_rate_limit`, `over_email_send_rate_limit`, `over_sms_send_rate_limit`.
- `createUser`/`deleteUser`/`signInWithPassword` all resolve `{ data, error }` with `error: AuthError | AuthApiError` on failure.

Canonical detect predicate for `withGoTrueRetry`:

```ts
function isRetryableGoTrueError(err: unknown): boolean {
  const e = err as { status?: number; code?: string; message?: string } | null;
  if (!e) return false;
  const RATE_CODES = ["over_request_rate_limit", "over_email_send_rate_limit", "over_sms_send_rate_limit"];
  return (
    e.status === 429 ||
    (e.code != null && RATE_CODES.includes(e.code)) ||
    /rate limit|too many requests/i.test(e.message ?? "") ||
    /database error deleting user/i.test(e.message ?? "") // opaque 500-class transient seen on shared dev
  );
}
```

### Precedent-Diff (Phase 4.4)

| Pattern in plan | Repo precedent | Diff / verdict |
|---|---|---|
| Option B durable column protection (Phase 2.5) | `mig 006_restrict_tc_accepted_at_update.sql`: `REVOKE UPDATE ON TABLE public.users FROM authenticated; GRANT UPDATE (email) … TO authenticated;` | **Identical pattern.** Confirms Option B is durable (Supabase blanket grant runs once at init; later migration REVOKE wins). The arguments' "re-clobbered" claim is wrong; Option A is chosen on maintenance cost, not impossibility. |
| SECURITY DEFINER RPC (NOT being changed) | `mig 075:105-108`: `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE … TO authenticated` | Already canonical (matches `cq-pg-security-definer-search-path-pin-pg-temp` + the 2026-05-06 named-role-revoke learning). No change. |
| SOLEUR-DEBT marker (Phase 2.4) | `knowledge-base/project/learnings/technical-debt/README.md` `// SOLEUR-DEBT: <ceiling>; <upgrade trigger>` | Marker form matches; `harvest-debt` will surface it. |

### Verify-the-Negative pass

- Plan claim "owner CAN update visibility via RLS" (Phase 2.1): **confirmed** — `conversations_owner_update` is `USING (user_id = auth.uid())` and there is NO table-level UPDATE revoke on `conversations` (`git grep "REVOKE.*conversations" supabase/migrations/` returns only the visibility column-REVOKE). Owner direct UPDATE succeeds.
- Plan claim "non-owner/anon write blocked by RLS" (Phase 2.2/2.3): **confirmed** — no PERMISSIVE UPDATE policy admits a non-owner; userB/anon UPDATE matches 0 rows (write deny shape).

## Overview

Running `apps/web-platform` tenant-integration suites against the shared dev Supabase
project surfaced failures. **This is NOT a production-code regression** — the prod + dev
DB cascade machinery (account-delete cascade migs 065/066: `organizations.owner_user_id`
+ `audit_byok_use.founder_id` FK SET NULL, the WORM carve-out, and
`set_conversation_visibility` SECURITY DEFINER) was verified CORRECT and live on both
prd and dev via read-only catalog introspection. **Do NOT touch migs 065/066.**

The failures are test-correctness + test-harness issues in
`test/server/conversation-visibility.tenant-isolation.test.ts` and the shared
synthetic-user harness. Three fixes:

1. **Stale assertion** (clear bug): the non-owner RPC test asserts `P0001`, but mig 075
   raises `insufficient_privilege` (SQLSTATE `42501`). Wrong since day one; hidden because
   the suite is opt-in and never runs in CI.
2. **Column-REVOKE assertion cannot pass on a real Supabase project**: `authenticated`
   actually HAS UPDATE on `conversations.visibility`; the column-REVOKE in mig 075 is a
   silent no-op. Reframe the test to assert the RLS-effective contract (owner-only writes).
3. **Harness determinism**: synthetic-user create/sign-in/delete against the SHARED dev
   project hits GoTrue rate limits non-deterministically. Add rate-limit-aware
   backoff/retry around the create + delete paths and document/gate the behavioral suites
   to target a dedicated freshly-migrated project.

Pure test + docs change. No production code path, no UI surface, no new dependency, no
new infrastructure. The only `.sql` touched is a comment (SOLEUR-DEBT marker) — see the
GDPR-gate note in Domain Review for the conditional case where a durable-fix migration is
chosen instead.

## Research Reconciliation — Argument premises vs. codebase reality

The investigation handed three premises. All three conclusions hold, but two mechanisms
were imprecise and one file target was incomplete. Correcting these at plan time prevents
the implementation from inheriting the imprecise framing.

| Premise (from arguments) | Codebase reality (verified) | Plan response |
|---|---|---|
| Fix 1: test line ~313 asserts `error.code === "P0001"`, mig 075 raises `insufficient_privilege` (42501). | **Exact.** `test:313` = `expect(error!.code).toBe("P0001")`; adjacent comment `:312` = "RPC raises insufficient_privilege". Mig `075:100` = `RAISE EXCEPTION … USING ERRCODE = 'insufficient_privilege'`. | Change `P0001` → `42501`. No reframe needed. |
| Fix 2: `authenticated` has UPDATE on `conversations.visibility` because **Supabase's blanket `GRANT ALL ON ALL TABLES … TO authenticated` clobbers the column REVOKE**. | Conclusion correct (authenticated CAN update visibility), but the precise mechanism is the **table-level UPDATE grant subsumes the column-level REVOKE** (silent no-op) — the exact pathology in learning `2026-03-20-supabase-column-level-grant-override.md`. `075.down.sql:20` re-GRANTs `UPDATE(visibility)`, confirming the column toggle is the only lever. Supabase's `ALTER DEFAULT PRIVILEGES` is the *function*-grant gotcha (learning `2026-05-06-…`); for *tables* it's the table-grant-subsumes-column-revoke rule. | Reframe the test to the RLS-effective contract. **Surface the durable-fix option honestly** (see Fix 2 §): a mig-006-style "REVOKE table-level UPDATE + re-GRANT all-cols-except-visibility" IS durable (not re-clobbered) — the arguments' "would be re-clobbered" claim is the imprecise part. The debt-marker route is still defensible (wide hot table + per-column GRANT maintenance burden); the plan presents BOTH and lets deepen-plan/plan-review weigh. |
| Fix 2: test currently exercises the REVOKE via an `authenticated` client. | The client is **`userAClient` — the OWNER** (`test:241`) updating their OWN private conversation. Under RLS `conversations_owner_update` (`075:67-70`, `user_id = auth.uid()`), the owner IS permitted. The column-REVOKE was the *only* thing the test relied on to produce the deny. | Reframe MUST switch the deny-actor to a **non-owner (userB)** and/or **anon** client. An owner-update assertion now correctly SUCCEEDS (RLS allows it). This is a real test-logic change, not a one-line code swap. |
| Fix 3: add backoff to `test/helpers/tenant-isolation-teardown.ts` (`tearDownTenantUser`). | The **conversation-visibility test does NOT use `tearDownTenantUser`.** It uses `createSharedWorkspaceMembers` + `tearDownSharedWorkspace` (`workspace-members-fixtures.ts`) + 3× `signInWithPassword`. The rate-limit `AuthApiError: Request rate limit reached` fires on the **create + sign-in** path, not teardown. `tearDownTenantUser` is one of TWO delete helpers; `tearDownSharedWorkspace` is the other (12 caller suites). | Backoff must wrap **both** create helpers' `auth.admin.createUser`, both delete helpers' `auth.admin.deleteUser`, AND `signInWithPassword`. Centralize in a shared `withGoTrueRetry` wrapper. Existing mitigation is JWT caching (`mint-once.ts`), not backoff — the new wrapper complements it. |
| Fix 3: suite gated by `TENANT_INTEGRATION_TEST=1`. | The target test gates on **`SUPABASE_DEV_INTEGRATION=1`** (`test:28`). The repo has TWO conventions: `TENANT_INTEGRATION_TEST=1` (~55 files) and `SUPABASE_DEV_INTEGRATION=1` (6 files). No shared `INTEGRATION_ENABLED` module. | Gating/doc work must address both env conventions. Do NOT silently rename the target test's gate (would mask it from any existing CI/operator invocation keyed on `SUPABASE_DEV_INTEGRATION`). Document the dedicated-project requirement in `test/README.md` for both conventions. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is a test-suite
and harness change. The production conversation-visibility behavior (owner-only visibility
writes via RLS + SECURITY DEFINER RPC) is unchanged and already verified live on prd/dev.

**If this leaks, the user's data is exposed via:** N/A — no data-handling code path changes.
The reframed Fix 2 test asserts the SAME effective security contract that already holds in
prod (owner-only writes; non-owner/anon blocked); it does not relax any production grant or
policy. The accepted defense-in-depth gap (column-REVOKE no-op) is pre-existing and is being
*documented*, not introduced.

**Brand-survival threshold:** none — test-correctness + test-harness change; no production
behavior, schema, or grant is modified (the durable-fix migration option, if chosen, would
*strengthen* defense-in-depth, never weaken it). The sensitive-path note: the SOLEUR-DEBT
marker lives in a `.sql` comment; if Implementation chooses Option B (durable migration)
the GDPR-gate fires (see Domain Review) — but Option A (default) touches only a comment.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1. Confirm the three cited line anchors still hold (paraphrase-without-verification gate):
   - `git grep -n 'toBe("P0001")' test/server/conversation-visibility.tenant-isolation.test.ts` → expect 1 hit (~`:313`).
   - `git grep -n "ERRCODE = 'insufficient_privilege'" supabase/migrations/075_conversation_visibility.sql` → expect 1 hit (`:100`).
   - `git grep -n "REVOKE UPDATE(visibility)" supabase/migrations/075_conversation_visibility.sql` → expect 1 hit (`:38`).
0.2. Enumerate every GoTrue rate-limit-prone call site to size Fix 3 (do not trust this plan's count):
   - `git grep -n "auth.admin.createUser" test/helpers/` and `git grep -rn "auth.admin.createUser" test/server/*.tenant-isolation.test.ts` (inline loops).
   - `git grep -n "auth.admin.deleteUser" test/helpers/`.
   - `git grep -n "signInWithPassword" test/`.
0.3. Read the existing JWT-cache helper `test/helpers/mint-once.ts` to confirm the new retry
   wrapper composes with (does not duplicate) the cache, and to match its rate-limit-budget
   commentary style.

### Phase 1 — Fix 1: stale assertion (RED→GREEN trivial)

`test/server/conversation-visibility.tenant-isolation.test.ts`, the "Non-owner cannot toggle
visibility via RPC" test (~`:302-322`):
- Change `expect(error!.code).toBe("P0001");` → `expect(error!.code).toBe("42501");`
- The adjacent comment `// RPC raises insufficient_privilege` is now consistent with the
  assertion (it already said so — the assertion was the lie).
- Mig 075 raises with `USING ERRCODE = 'insufficient_privilege'` → PostgREST surfaces SQLSTATE
  `42501`. Confirm supabase-js maps this to `error.code === "42501"` (the SELECT-deny tests at
  `:178` and `:231` already assert `42501` for the same mapping — consistent precedent in this
  very file).

### Phase 2 — Fix 2: reframe the column-REVOKE test to RLS-effective contract

Rename/rewrite the "Client UPDATE on visibility column is rejected" test (~`:240-257`). The
current test uses the OWNER (`userAClient`) and relies on the no-op column-REVOKE. Replace
with assertions on the contract that actually holds in prod:

2.1. **Owner CAN update own visibility via RLS direct UPDATE** (new positive control —
   documents that the column-REVOKE is a no-op and RLS governs):
   - `userAClient.from("conversations").update({ visibility: "workspace" }).eq("id", privateConvId)`
   - Expect `error` to be null (RLS `conversations_owner_update` allows `user_id = auth.uid()`).
   - Restore to `private` afterward (or use a throwaway conversation id) so later tests'
     fixtures are not disturbed — verify ordering against the RPC toggle test at `:262`.
2.2. **Non-owner (userB) UPDATE on another user's conversation is blocked by RLS** (the real
   security contract — workspace member cannot mutate owner's row):
   - `userBClient.from("conversations").update({ visibility: "private" }).eq("id", sharedConvId)`
   - Dual-shape deny (TR5 precedent in this file, `:177-181`): either `error.code === "42501"`
     OR `data === []` / zero rows affected (PostgREST UPDATE matching 0 rows is not an error).
     Assert: row unchanged via service-role read-back (`sharedConvId` still `"workspace"`).
2.3. **anon UPDATE matches 0 rows** (anon has the grant but no RLS-passing rows):
   - A fresh anon client (`createClient(supabaseUrl, anonKey)`, no sign-in) UPDATE on any conv id
     affects 0 rows; assert row unchanged via service-role read-back.
2.4. **SOLEUR-DEBT marker** documenting the accepted defense-in-depth gap. Place it in
   `supabase/migrations/075_conversation_visibility.sql` adjacent to the REVOKE at `:38`
   (the marker must live where the no-op defense lives, so `harvest-debt` surfaces it next to
   the code). Canonical form (ceiling before `;`, trigger after — per
   `knowledge-base/project/learnings/technical-debt/README.md`):
   ```sql
   -- SOLEUR-DEBT: column-level REVOKE UPDATE(visibility) is a silent no-op — the table-level
   -- UPDATE grant on conversations subsumes it (see learning 2026-03-20-supabase-column-level-grant-override),
   -- so authenticated/anon retain raw UPDATE on this column; effective protection is RLS
   -- (conversations_owner_update, user_id = auth.uid()) + the SECURITY DEFINER RPC, both verified live.
   -- Upgrade trigger: if a non-owner write path to conversations is ever added, OR if defense-in-depth
   -- column protection becomes required, invert to "REVOKE UPDATE ON public.conversations FROM authenticated;
   -- GRANT UPDATE(<all columns except visibility>) ... TO authenticated" (mig-006 pattern) in a new migration.
   REVOKE UPDATE(visibility) ON public.conversations FROM authenticated;
   ```
   - Update the comment block at `075:31-38` ("Column-level REVOKE is the correct defense") which
     is now factually wrong — it should say the REVOKE is retained as documentation-of-intent but
     is a no-op, with RLS as the effective control.
   - **Do NOT add a new migration** rewriting history (`075` is shipped/applied on prd+dev). The
     marker + corrected comment is Option A (default).

2.5. **Option B (durable migration) — present but do NOT implement by default.** A mig-006-style
   inversion (`REVOKE UPDATE ON public.conversations FROM authenticated; GRANT UPDATE(<safe cols>)
   …`) in a NEW migration (e.g. `086_*`) IS durable — Supabase's blanket grant runs once at
   project init; a later migration's REVOKE wins (proven by mig 006 on `public.users`). Trade-off:
   `conversations` is a wide, hot, frequently-extended table; every future column add must be added
   to the GRANT allowlist or it becomes silently read-only for tenants (the exact failure mode in
   learning `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes`). Given the
   RLS owner-only policy already enforces the effective contract, the marginal defense-in-depth value
   is low against a real maintenance/regression cost. **Recommendation: Option A.** If plan-review or
   deepen-plan (data-integrity-guardian) argues Option B, it requires: a new forward migration + `.down.sql`,
   a file-parse contract test, the GDPR-gate (new `.sql`), and enumerating every current `conversations`
   column into the re-GRANT. Escalate via AskUserQuestion before implementing Option B.

### Phase 3 — Fix 3: harness determinism

3.1. **Shared GoTrue retry wrapper.** Add `withGoTrueRetry<T>(label, fn)` to a shared helper
   (new `test/helpers/gotrue-retry.ts`, or extend `mint-once.ts` to keep rate-limit logic in one
   place — decide at Phase 0.3 after reading `mint-once.ts`). Behavior:
   - Retries on rate-limit signals using the **grounded predicate from Research Insights**
     (`isRetryableGoTrueError`): `err.status === 429`, OR `err.code ∈ {over_request_rate_limit,
     over_email_send_rate_limit, over_sms_send_rate_limit}`, OR message matching
     `/rate limit|too many requests/i`, OR the opaque `/database error deleting user/i` 500-class
     transient. Verified against `@supabase/auth-js@2.99.2` (`errors.d.ts:13-40`, `error-codes.d.ts:6`).
   - Exponential backoff with jitter, bounded (e.g. base 500ms, factor 2, max ~5 attempts, cap ~8s),
     under the existing `hookTimeout: 20_000` ceiling (vitest.config.ts:37) — the total backoff
     budget MUST stay under hookTimeout or the fixture times out instead of recovering.
   - Non-rate-limit errors rethrow immediately (do not mask real failures — preserves the
     `cq-silent-fallback-must-mirror-to-sentry` spirit already honored in `tearDownTenantUser`).
3.2. **Wrap the create + sign-in + delete call sites:**
   - `workspace-members-fixtures.ts:80` (`createUser` in `createSharedWorkspaceMembers`).
   - `workspace-members-fixtures.ts:173` (`deleteUser` in `tearDownSharedWorkspace`).
   - `tenant-isolation-teardown.ts:94` (`deleteUser` in `tearDownTenantUser`).
   - The 3× `signInWithPassword` in the target test (`:129/:138/:147`) — wrap, OR migrate to the
     `mint-once.ts` JWT-cache path if it covers password sign-in (check at Phase 0.3).
   - Inline `createUser` loops in `*.tenant-isolation.test.ts` suites are out of scope for the
     wrapper unless trivial; the target failing suite uses the shared helpers, which is the
     load-bearing path. Note the broader inline-loop migration as a follow-up SOLEUR-DEBT marker
     if not folded in (per `wg-defer-only-after-inline-triage`).
3.3. **Document + gate the dedicated-project requirement.** Update `test/README.md`:
   - State that behavioral tenant-integration suites (both `TENANT_INTEGRATION_TEST=1` and
     `SUPABASE_DEV_INTEGRATION=1` conventions) MUST target a DEDICATED freshly-migrated dev
     Supabase project — NEVER the shared dev pre-merge — mirroring the
     `079-workspace-rls-isolation.test.ts:30-32` header guidance and `hr-dev-prd-distinct-supabase-projects`.
   - Add the `conversation-visibility.tenant-isolation.test.ts` row + run command to the
     integration-tests table (currently missing).
   - Cross-reference the rate-limit budget: the retry wrapper recovers from transient throttle,
     but the durable answer is project isolation; backoff is the seatbelt, not the fix.

### Phase 4 — Verify

4.1. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`).
4.2. Default (no env flag) run stays green via `describe.skipIf` — confirm the suite still
   skips cleanly without `SUPABASE_DEV_INTEGRATION=1`:
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/conversation-visibility.tenant-isolation.test.ts`
   (expect "skipped", not failures).
4.3. Behavioral run against a dedicated dev project (operator/automation step — see Domain
   Review / IaC note): the conversation-visibility suite passes deterministically across ≥2
   consecutive runs (failure count must be 0, not swing 7↔16).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `git grep -c 'toBe("P0001")' test/server/conversation-visibility.tenant-isolation.test.ts` returns `0`; `git grep -c 'toBe("42501")'` on the non-owner RPC test region returns ≥1.
- [ ] The reframed Fix 2 test exercises a **non-owner (userB) and/or anon** actor for the deny assertion, and asserts the row is unchanged via a service-role read-back. (Verify: the deny-path client in the test is NOT `userAClient`.)
- [ ] A `SOLEUR-DEBT:` marker with a `;`-delimited upgrade trigger exists adjacent to the `REVOKE UPDATE(visibility)` in `supabase/migrations/075_conversation_visibility.sql`; the stale "Column-level REVOKE is the correct defense" comment is corrected. (Verify: `git grep -n "SOLEUR-DEBT:" supabase/migrations/075_conversation_visibility.sql` returns 1 hit containing a `;`.)
- [ ] No new migration file is added (Option A) UNLESS Option B was explicitly approved via AskUserQuestion. (Verify: `git status --porcelain supabase/migrations/` shows no new `.sql` file under default Option A.)
- [ ] A `withGoTrueRetry` (or equivalently named) wrapper exists and wraps `createUser` in `createSharedWorkspaceMembers`, `deleteUser` in both `tearDownSharedWorkspace` and `tearDownTenantUser`, and the target test's `signInWithPassword` calls. (Verify: `git grep -n "withGoTrueRetry" test/` covers ≥4 distinct call sites + the definition.)
- [ ] The retry wrapper rethrows non-rate-limit errors (does not mask real failures). (Verify by reading the wrapper: a non-429/non-throttle error is not swallowed.)
- [ ] Total retry backoff budget is bounded under `hookTimeout` (20_000ms). (Verify: max attempts × max delay < 20s.)
- [ ] `test/README.md` documents the dedicated-project requirement for behavioral suites (both env conventions) and adds the `conversation-visibility.tenant-isolation.test.ts` row + run command.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] Default `vitest run` of the target file with NO env flag skips cleanly (no failures).

### Post-merge (operator / automation)
- [ ] Behavioral run of `conversation-visibility.tenant-isolation.test.ts` against a DEDICATED freshly-migrated dev Supabase project passes deterministically across ≥2 consecutive runs (0 failures both runs). Automation: gated by Supabase project provisioning; if a dedicated project is not yet stood up, this is the genuine operator step — but the migrate+run is `doppler run … vitest run …`, scriptable once the project exists (not a dashboard click).

## Domain Review

**Domains relevant:** Engineering (test-correctness), Legal/compliance (conditional — only if Option B migration touches grants).

### Engineering
**Status:** reviewed
**Assessment:** Pure test + docs change. No production code path, route, or schema is modified
under Option A. The reframed Fix 2 test asserts the SAME effective security contract that
already holds in prod (verified live), so it strengthens the suite's fidelity without changing
behavior. The harness retry wrapper is a determinism seatbelt; the durable fix is dedicated-project
isolation (documented). Precedent-diff for the RLS/column-grant pattern is fully covered by the
three cited learnings (2026-03-20, 2026-05-06, 2026-05-21) — no novel DB pattern introduced.

### GDPR / Compliance Gate (conditional)
**Status:** not invoked under Option A (default). Option A touches only a `.sql` *comment* (SOLEUR-DEBT
marker) + corrected prose — no schema, grant, or policy change. If Implementation escalates to
**Option B** (new durable migration altering `conversations` grants), `/soleur:gdpr-gate` MUST be
invoked at that point (new `.sql` + grant surface crosses the `hr-gdpr-gate-on-regulated-data-surfaces`
regex). Recorded here so the gate is not silently skipped if the option flips.

### Product/UX Gate
**Tier:** N/A — no UI surface. No file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`
is created or edited (Files lists below are test/`.sql`-comment/`.md` only). Mechanical UI-surface
override does not fire.

## Observability

Skipped — this is a test-suite + docs change. No Files-to-Edit under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`; no new infrastructure surface. The
suite's own failure signal IS the observability (a red vitest run); the retry wrapper preserves
real-failure visibility by rethrowing non-rate-limit errors (per `cq-silent-fallback-must-mirror-to-sentry`,
the existing `tearDownTenantUser` console.warn-on-anonymise-error pattern is retained).

## Infrastructure (IaC)

Skipped — no new server, service, cron, secret, vendor, or persistent runtime process. The
"dedicated dev Supabase project" referenced in Fix 3 is a documentation/gating requirement for
*running* behavioral suites, not a resource this PR provisions. If/when a dedicated test project
is provisioned, that is its own infra change governed by `hr-all-infrastructure-provisioning-servers`
and out of scope here.

## Files to Edit

- `apps/web-platform/test/server/conversation-visibility.tenant-isolation.test.ts` — Fix 1 (P0001→42501); Fix 2 reframe (owner-CAN positive control + non-owner/anon deny); wrap `signInWithPassword` (Fix 3).
- `apps/web-platform/supabase/migrations/075_conversation_visibility.sql` — SOLEUR-DEBT marker + correct the stale "column-level REVOKE is the correct defense" comment (Fix 2). **Comment-only edit; no DDL change.**
- `apps/web-platform/test/helpers/workspace-members-fixtures.ts` — wrap `createUser` (`:80`) + `deleteUser` (`:173`) in `withGoTrueRetry` (Fix 3).
- `apps/web-platform/test/helpers/tenant-isolation-teardown.ts` — wrap `deleteUser` (`:94`) in `withGoTrueRetry` (Fix 3).
- `apps/web-platform/test/README.md` — dedicated-project gating doc + new suite row (Fix 3).

## Files to Create

- `apps/web-platform/test/helpers/gotrue-retry.ts` — `withGoTrueRetry` wrapper (OR fold into `mint-once.ts` per Phase 0.3 decision; if folded, this create entry drops).

## Open Code-Review Overlap

None — to be confirmed at /work via `gh issue list --label code-review --state open` against the
Files-to-Edit paths (run the two-stage `--json` + standalone `jq --arg` form, not single-stage
`gh --jq`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Present and filled: threshold `none`, with sensitive-`.sql`-path reason recorded.)
- **Fix 2 is NOT a one-line swap.** The current test uses the OWNER client and relies on the no-op column-REVOKE. The reframe must change the deny-actor to non-owner/anon, or it asserts the wrong thing. A naive "expect 42501 → expect no error on owner" without adding the non-owner deny path silently drops the security assertion the test exists to make.
- **PostgREST UPDATE matching 0 rows is NOT an error.** The non-owner/anon deny assertions must read the row back via service-role to prove it is unchanged — `error === null` with 0 rows affected is the RLS-deny shape for writes (mirrors the dual-shape SELECT-deny precedent at `:177-181`), not a test failure.
- **Two env-var conventions exist** (`TENANT_INTEGRATION_TEST=1` vs `SUPABASE_DEV_INTEGRATION=1`). Do NOT rename the target test's `SUPABASE_DEV_INTEGRATION` gate — an existing operator/CI invocation may key on it. Document both; rename neither.
- **The arguments named only `tenant-isolation-teardown.ts` for Fix 3**, but the failing suite's rate-limit hits are on `createSharedWorkspaceMembers` + `signInWithPassword` in `workspace-members-fixtures.ts` and the target test. Wrapping only the named teardown helper would leave the actual failure path (create/sign-in throttle) unprotected.
- **Retry backoff budget must fit under `hookTimeout: 20_000`** (vitest.config.ts:37). An unbounded or too-generous backoff converts a recoverable throttle into a hook timeout — a worse failure mode.
- **The column-REVOKE durable fix (Option B) IS achievable** (mig-006 pattern on `public.users` proves Supabase's blanket grant does not re-clobber a later migration's table-level REVOKE). The arguments' "would be re-clobbered" is imprecise. Option A (debt marker) is recommended on maintenance-cost grounds, not impossibility — present the trade-off honestly; escalate Option B via AskUserQuestion rather than silently choosing.
- **Do NOT touch migs 065/066** (account-delete cascade) — verified correct and live; out of scope.

## Test Scenarios

1. **Fix 1**: non-owner RPC call → `error.code === "42501"` (was P0001).
2. **Fix 2a**: owner direct UPDATE of own conversation visibility → succeeds (RLS allows).
3. **Fix 2b**: non-owner (userB) UPDATE of owner's shared conversation → blocked (42501 OR 0 rows); row unchanged on service-role read-back.
4. **Fix 2c**: anon UPDATE → 0 rows; row unchanged.
5. **Fix 3**: simulate/observe a GoTrue 429 during create or sign-in → wrapper retries with backoff and the fixture succeeds (no AuthApiError surfaced to the test). Non-429 errors still propagate.
6. **Skip path**: with no env flag, the whole `describe` skips cleanly (CI stays green).
