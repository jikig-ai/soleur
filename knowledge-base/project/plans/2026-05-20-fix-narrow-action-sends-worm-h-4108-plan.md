---
lane: single-domain
type: test-fix
issue: 4108
duplicate_of: 4113
requires_cpo_signoff: false
deepened_on: 2026-05-20
---

# fix: narrow action_sends WORM test (h) to anonymise_action_sends scope (#4108)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Research Reconciliation, Risks, Acceptance Criteria, Notes for /work
**Gates exercised:** Phase 4.6 (User-Brand Impact) PASS; Phase 4.7 (Observability) SKIP (test-only edit, no production code/infra)

### Key Improvements

1. **Root-cause correction:** Verified FK semantics in migrations 001 (`conversations`/`messages` → `ON DELETE CASCADE`) vs. 048 (`scope_grants.founder_id` → `ON DELETE RESTRICT`) vs. 051 (`action_sends.user_id` → `ON DELETE RESTRICT`). #4108's issue body misidentified the RESTRICT blocker as `messages`/`conversations`; the actual blocker is `scope_grants.founder_id` (the throwaway user has a grant created via `grant_action_class`, and `anonymise_scope_grants` was the second RPC the failing test called for cleanup, not contract). The fix shape is unchanged; the explanation is now accurate.
2. **GitHub citation verification:** #4108 and #4113 confirmed OPEN issues (not PRs); `duplicate` label exists.
3. **Workflow file name verified:** `.github/workflows/tenant-integration.yml` exists at the cited path.
4. **AC tightening:** Added explicit awk-flag-form for grep ranges (avoids the awk `/start/,/end/` self-match trap per `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`).
5. **Domain-leader carry-forward:** Engineering domain only — no Product/UX/Legal/CMO/CRO/CPO/Security/Compliance implications. Single-file test edit, opt-in non-required CI job.

### New Considerations Discovered

- The shared `[userA, userB]` cleanup at `afterAll` (lines 174-196) calls `anonymise_action_sends` + `anonymise_scope_grants` + `auth.admin.deleteUser` in sequence with `try/catch` tolerance. The reason this teardown works for `userA`/`userB` is that they HAVE scope grants but the teardown anonymises BOTH ledgers in sequence — exactly the cascade the test row `(h)` was duplicating. Row `(h)`'s throwaway `u` is local-scope only; adding a trailing `try { auth.admin.deleteUser(u.id) } catch {}` reaper still leaves `scope_grants` and `messages`/`conversations` rows on the throwaway user. Per the corrected FK semantics, `auth.admin.deleteUser` on `u` will STILL fail without a preceding `anonymise_scope_grants(u.id)` because `scope_grants.founder_id` is RESTRICT. **Decision:** the test row's cleanup should call BOTH anonymise RPCs then `auth.admin.deleteUser` inside a `try/catch` block — this is CLEANUP, not assertion, so the test contract (anonymise_action_sends behavior) is independent of cleanup success. See revised "Files to Edit" below.

## Overview

Post-merge tenant-integration on dev-Supabase flagged a single failing assertion in `apps/web-platform/test/server/action-sends-worm.test.ts` test row `(h)`:

```
(h) anonymise_action_sends → user_id IS NULL; auth.admin.deleteUser succeeds
AssertionError: expected AuthApiError: Database error deleting user { …(3) } to be null
```

Root cause (per #4108): the test seeds THREE user-FK'd rows (conversation, message, action_sends), then calls only `anonymise_action_sends(p_user_id)` — which scrubs `action_sends.user_id` only. The remaining `messages.user_id` and `conversations.user_id` keep `RESTRICT` blocking `auth.admin.deleteUser`. The production cascade in `apps/web-platform/server/account-delete.ts` runs all four steps in order (`anonymise_action_sends → anonymise_scope_grants → anonymise_tc_acceptances → auth.admin.deleteUser`); the test imitates only one step then asserts the final outcome of the full cascade.

The test's NAME ("(h) anonymise_action_sends → user_id IS NULL; auth.admin.deleteUser succeeds") conflates two distinct contracts:

1. **DB-layer (this file's scope):** `anonymise_action_sends(uuid)` zeros `action_sends.user_id` on rows belonging to that user.
2. **App-layer (other files' scope):** the full account-delete cascade ordering ends with a successful `auth.admin.deleteUser`.

Contract (2) is already covered by `apps/web-platform/test/server/scope-grants/account-delete-scope-grants-cascade.test.ts` (mocked sequence: asserts `auth.admin.deleteUser` fires last with the right `userId`, verifies abort semantics if any earlier anonymise step fails — see lines 66, 159, 166-167, 188-190, 212).

This PR narrows test row `(h)` to its DB-layer contract: anonymise → `user_id IS NULL` + `recipient_id_hash = '__anonymised__'`. Drop the `anonymise_scope_grants` call and the `auth.admin.deleteUser` assertion. Rename the test so the name no longer implies the cascade.

#4113 frames the same failure surface as a migration-052 trigger/FK interaction (PR #4066 = #3244). Per #4108's analysis (production cascade unchanged, mig 051 verify_*.sql gates green, 35+ pre-existing tenant-integration tests pass), the defect is test-only — the narrow-assertion fix proves it. Close #4113 as a duplicate of #4108 post-merge.

## User-Brand Impact

**If this lands broken, the user experiences:** Nothing user-facing — this is an integration-test scoping fix. The production code path (`server/account-delete.ts`) and migration 051 (the `anonymise_action_sends` RPC body + DB-layer WORM trigger) are unchanged.
**If this leaks, the user's [data / workflow / money] is exposed via:** No new exposure vector. The narrow assertion still verifies that `anonymise_action_sends` zeros `user_id` and overwrites `recipient_id_hash` to `'__anonymised__'` — the Article-17 erasure invariant on action_sends is preserved as the test's load-bearing assertion.
**Brand-survival threshold:** none — test-scoping change against an opt-in tenant-integration job (`TENANT_INTEGRATION_TEST=1`) that is NOT in the required-checks list for `main` (verified in #4113 body: 6 required checks are `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate`, `cla-check`; `tenant-integration` is non-required).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
| --- | --- | --- |
| "seeded fixture creates THREE user-FK'd rows: one conversation, one message, one action_sends" | Confirmed at `action-sends-worm.test.ts:82-108` (`seedDraftMessage` inserts both a `conversations` row and a `messages` row, then the test body inserts an `action_sends` row at lines 374-383). PLUS the throwaway user has a `scope_grants` row created via `grant_action_class` at line 361 — FOUR user-FK'd rows total. | Matches the SHAPE; the narrow fix removes the test's dependence on cleaning up all FK paths from the assertion path. Cleanup remains best-effort. |
| #4108 root cause: "`messages.user_id` and `conversations.user_id` still RESTRICT-block the auth delete" | **Partially incorrect.** `messages.user_id` (mig 001 line 48) and `conversations.user_id` (mig 001 line 28) are `ON DELETE CASCADE` to `public.users(id)`, NOT RESTRICT. The actual RESTRICT blockers are: (a) `action_sends.user_id` → `public.users(id) ON DELETE RESTRICT` (mig 051 line 102) — addressed by `anonymise_action_sends`, AND (b) `scope_grants.founder_id` → `public.users(id) ON DELETE RESTRICT` (mig 048 line 16) — addressed by `anonymise_scope_grants`. | The FIX SHAPE in #4108 is still correct (drop the cross-cascade assertion); the EXPLANATION is corrected. Update plan body to reflect the real mechanism: `auth.admin.deleteUser` fails on `scope_grants` RESTRICT (not `messages`/`conversations`). |
| "Cross-cascade integration is already covered by `account-delete-scope-grants-cascade.test.ts`" | Confirmed: file exists at `apps/web-platform/test/server/scope-grants/account-delete-scope-grants-cascade.test.ts`. Asserts RPC sequence + `auth.admin.deleteUser` fires LAST (line 167), aborts when an anonymise step fails (lines 188-190, 212). PR-G (#3947) Phase 9.3 / AC5. | Coverage overlap confirmed — narrowing (h) does not lose test coverage; cascade ordering remains tested at the unit-test layer with mocked clients. |
| "Production code path in `server/account-delete.ts`" runs the full cascade | File path exists at `apps/web-platform/server/account-delete.ts` (referenced as contract-under-test by the cascade test file header, lines 3-15). | Production cascade is unchanged; only the DB-layer test scope is narrowed. |
| #4113 hypothesis: "migration 052's `audit_github_token_use.founder_id → public.users(id) ON DELETE SET NULL` or partial UNIQUE on `users.github_installation_id`" interacts with `auth.admin.deleteUser` | #4108 root cause analysis (now corrected per row 2 above) shows the test creates four user-FK'd rows and only nullifies one (`action_sends`). The remaining RESTRICT on `scope_grants.founder_id` is sufficient to explain the failure WITHOUT invoking any migration-052 trigger interaction. Narrow-assertion fix removes the `auth.admin.deleteUser` call from the assertion path, eliminating the interaction surface. | Narrow-fix proves test-only. Close #4113 as duplicate post-merge. |
| #4108 mentions "≤20 lines in one file" | Confirmed — the change is contained to test row `(h)` in `action-sends-worm.test.ts` (lines 338-408). | Single-file change; ≤30 LoC delta after the rename + assertion narrow + cleanup-reap addition. |
| `gh issue view 4108` + `gh issue view 4113` | Both confirmed OPEN issues (NOT PRs). `gh pr view 4108` returns `Could not resolve to a PullRequest` — disambiguation per `2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`. | References are legitimate issues, not fabricated. |
| `gh label list` for `duplicate`, `domain/engineering`, `type/bug`, `priority/p2-medium`, `bug` | All confirmed present in repo. | Post-merge `gh issue edit 4113 --add-label duplicate` is executable as-is. |
| Workflow file `tenant-integration.yml` exists | Confirmed at `.github/workflows/tenant-integration.yml`. | Post-merge `gh run list --workflow tenant-integration.yml --branch main --limit 1 --json conclusion,headSha` is executable as-is. |

## Files to Edit

- `apps/web-platform/test/server/action-sends-worm.test.ts`
  - Rename test row `(h)` from `"(h) anonymise_action_sends → user_id IS NULL; auth.admin.deleteUser succeeds"` to `"(h) anonymise_action_sends → action_sends.user_id IS NULL"` (drops the cascade implication from the test name).
  - Remove the `anonymise_scope_grants` RPC call (line 405) — it was preparatory cleanup for the dropped `auth.admin.deleteUser` assertion, not part of the contract under test.
  - Remove the `auth.admin.deleteUser` call + `expect(delErr).toBeNull()` (lines 406-407).
  - Keep verbatim: the throwaway user creation, JWT mint, `grant_action_class` call, draft-message seed, `action_sends` insert, the `anonymise_action_sends` RPC call + `rowsAffected` assertions (lines 386-392), and the post-condition `SELECT user_id, recipient_id_hash` + assertions (lines 395-401). These are the DB-layer contract for `anonymise_action_sends`.
  - Update the file-header comment block at lines 14-15 to match the narrowed scope: replace `(h) anonymise_action_sends(uuid) → user_id IS NULL; subsequent auth.admin.deleteUser succeeds (Kieran P1-1; Art-17 cascade)` with `(h) anonymise_action_sends(uuid) → action_sends.user_id IS NULL + recipient_id_hash '__anonymised__' (Art-17 erasure; cascade integration covered by account-delete-scope-grants-cascade.test.ts)`.
  - `afterAll` teardown (lines 174-196) already tolerates failures via `try/catch` — no change needed; the throwaway user `u` created inside the test scope is local and is NOT enrolled in the shared `[userA, userB]` teardown loop, so removing the in-test `auth.admin.deleteUser` leaves a synthetic user (plus its `scope_grants`, `messages`, `conversations`, and now-anonymised `action_sends` rows) behind. Add a best-effort 3-RPC cleanup block at the END of the test body (after the post-condition asserts), each in its own `try/catch` so any single failure does not couple to the assertion or to the other cleanup steps:

    ```ts
    // Best-effort cleanup of the throwaway user — independent of the
    // assertion under test. anonymise_action_sends already ran above.
    try {
      await service.rpc("anonymise_scope_grants", { p_user_id: u.id });
    } catch { /* tolerate */ }
    try {
      await service.auth.admin.deleteUser(u.id);
    } catch { /* tolerate */ }
    ```

    `anonymise_scope_grants` is required for `auth.admin.deleteUser` to succeed (because `scope_grants.founder_id` is `ON DELETE RESTRICT` per mig 048 line 16). `messages` and `conversations` are `ON DELETE CASCADE` per mig 001 lines 28/48 — they do not need explicit cleanup. The contract being tested (anonymise_action_sends behavior) has already been asserted by this point; if any of the cleanup steps fail, the next run's `assertSynthetic` + `tenant-isolation-*` synthetic-email guard keeps the leak self-contained.

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returns no open scope-outs naming `action-sends-worm.test.ts`.

## Implementation Phases

### Phase 1 — Narrow test (h) scope

1. Read `apps/web-platform/test/server/action-sends-worm.test.ts:338-408`.
2. Apply the edits enumerated in "Files to Edit" above:
   - Rename test row.
   - Drop `anonymise_scope_grants` call (line 405).
   - Drop `auth.admin.deleteUser` assertion (lines 406-407).
   - Add throwaway-user reap at end of test body (cleanup, not contract).
3. Update file-header comment for `(h)` (lines 14-15).

### Phase 2 — Local sanity

`tsc --noEmit` against `apps/web-platform` (no type-shape changes expected, but the cheapest gate).

Note: the full integration suite requires Doppler dev secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) and the `TENANT_INTEGRATION_TEST=1` opt-in. Per #4108 verification block:

```bash
cd apps/web-platform && \
  doppler run -p soleur -c dev -- \
  env TENANT_INTEGRATION_TEST=1 \
  ./node_modules/.bin/vitest run \
  test/server/action-sends-worm.test.ts
```

Must report `(h)` green AND all other rows `(a)`-`(i)` green (no regression).

### Phase 3 — PR + post-merge dup-close

1. PR body: `Closes #4108`. Add a second line: `Ref #4113` (NOT `Closes #4113` — the dedup-close happens manually post-merge per the issue body's contract that the fix proves #4113 is test-only, after we observe the green tenant-integration job on `main`).
2. Post-merge: verify the tenant-integration job is green on `main` for the merge commit, then run:

   ```bash
   gh issue close 4113 --comment "Duplicate of #4108 — narrow-assertion fix in #<PR_NUM> proved this was test-only, not a migration-052 trigger/FK interaction. Closing as duplicate."
   gh issue edit 4113 --add-label duplicate
   ```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/test/server/action-sends-worm.test.ts` line range 338-408 contains exactly the edits above. `git diff --stat HEAD~1 -- apps/web-platform/test/server/action-sends-worm.test.ts` shows ≤30 net LoC delta in a single file.
- [ ] The test row's `name` argument to `test(...)` is `"(h) anonymise_action_sends → action_sends.user_id IS NULL"` — `git grep -F '(h) anonymise_action_sends → action_sends.user_id IS NULL' apps/web-platform/test/server/action-sends-worm.test.ts` returns 1 match.
- [ ] No `auth.admin.deleteUser` call inside test row `(h)`'s **assertion** path. The trailing cleanup block IS allowed to call it once, wrapped in `try { ... } catch { /* tolerate */ }`. Verify the assertion path with a flag-based awk extract (avoids the `/start/,/end/` self-match trap):

  ```bash
  awk '/test\("\(h\)/{flag=1; next} /^    test\(/{flag=0} flag' \
    apps/web-platform/test/server/action-sends-worm.test.ts \
    | awk '/Best-effort cleanup/{exit} {print}' \
    | grep -c 'auth\.admin\.deleteUser'
  ```

  Must return 0 — i.e., the assertion-path portion of test (h) (everything before the `Best-effort cleanup` comment) contains zero `auth.admin.deleteUser` references.

- [ ] No `anonymise_scope_grants` call in test row `(h)`'s **assertion** path. Same awk extract as above:

  ```bash
  awk '/test\("\(h\)/{flag=1; next} /^    test\(/{flag=0} flag' \
    apps/web-platform/test/server/action-sends-worm.test.ts \
    | awk '/Best-effort cleanup/{exit} {print}' \
    | grep -c 'anonymise_scope_grants'
  ```

  Must return 0.

- [ ] The DB-layer assertions are preserved:

  ```bash
  awk '/test\("\(h\)/{flag=1; next} /^    test\(/{flag=0} flag' \
    apps/web-platform/test/server/action-sends-worm.test.ts \
    | grep -E 'expect\(.*user_id\)\.toBeNull|recipient_id_hash.*__anonymised__' \
    | wc -l
  ```

  Must return 2.

- [ ] PR body contains `Closes #4108` AND `Ref #4113` (NOT `Closes #4113`).
- [ ] `tsc --noEmit` against `apps/web-platform` passes (no type drift).

### Post-merge (operator-automatable via gh CLI)

- [ ] Tenant-integration job on the merge commit reports green for the entire `action-sends-worm.test.ts` file (rows a-i). Automation: `gh run list --workflow tenant-integration.yml --branch main --limit 1 --json conclusion,headSha`.
- [ ] `gh issue close 4113 --comment "<see Phase 3 step 2>"` succeeds. Automation: `gh` CLI, not a manual browser step. Add `--add-label duplicate` via `gh issue edit 4113`.
- [ ] `gh issue view 4108 --json state` returns `"CLOSED"` (auto-closed by the `Closes #4108` in PR body).

## Test Strategy

The change is itself a test edit. The verification of the change is:

1. **Static** (pre-merge, no Doppler creds required): `tsc --noEmit` + the grep-based ACs above.
2. **Dynamic** (post-merge, opt-in `TENANT_INTEGRATION_TEST=1` on dev-Supabase): the full `action-sends-worm.test.ts` suite must report all 9 rows `(a)`-`(i)` green. This is the canonical signal that the narrow-assertion fix resolves the failure surface flagged in #4108.

No new test files. No production code changes. No migration changes.

## Risks

- **Coverage regression: did we lose anything?** No. Test row `(h)` now asserts only the DB-layer contract of `anonymise_action_sends` (Art-17 erasure: `user_id IS NULL` + `recipient_id_hash = '__anonymised__'`). The cascade-ordering contract (`auth.admin.deleteUser` fires LAST and is gated on prior anonymise success) is owned by `account-delete-scope-grants-cascade.test.ts` (PR-G #3947 Phase 9.3 / AC5). The production code path `server/account-delete.ts` is unchanged. Cross-cascade contract is verified by two distinct test files at two distinct layers — losing the cross-layer assertion in (h) does NOT remove a unique signal.
- **Teardown leak risk:** The throwaway user `u` is created inside the test body and is not enrolled in `afterAll`'s shared `[userA, userB]` loop. Without the trailing reap-cleanup, every test run leaks one synthetic `tenant-isolation-*@soleur.test` user, plus its `scope_grants` row, plus its `messages`/`conversations` rows. The trailing `try { anonymise_scope_grants } catch {}; try { auth.admin.deleteUser } catch {}` block makes cleanup best-effort without coupling it to the assertion. Synthetic email pattern is guarded by `assertSynthetic` at creation time; the reaper inherits the same safety.
- **#4113 close-as-duplicate timing:** Per the contract in the task description, the dup-close happens AFTER the PR merges and tenant-integration is green on `main`. Pre-merge dup-close would assert the narrow-fix conclusion without the empirical green signal. Use `Ref #4113` in PR body (not `Closes`) to keep the link visible without auto-closing.

### Research Insights

**FK semantics (verified from migrations 001/048/051):**

| Table | Column | Target | ON DELETE | Blocking for auth.admin.deleteUser? |
| --- | --- | --- | --- | --- |
| `conversations` | `user_id` | `public.users(id)` | `CASCADE` (mig 001:28) | No — cascades away |
| `messages` | `user_id` | `public.users(id)` | `CASCADE` (mig 001:48) | No — cascades away |
| `scope_grants` | `founder_id` | `public.users(id)` | `RESTRICT` (mig 048:16) | **Yes** — requires `anonymise_scope_grants` first |
| `action_sends` | `user_id` | `public.users(id)` | `RESTRICT` (mig 051:102) | **Yes** — requires `anonymise_action_sends` first |

This corrects the #4108 issue body's root-cause attribution. The fix shape (drop the cross-cascade assertion) is unchanged; the underlying mechanism is `scope_grants` RESTRICT, not `messages`/`conversations`.

**Why the cascade test layer is the right home for the dropped assertion:**

`account-delete-scope-grants-cascade.test.ts` uses **mocked** Supabase clients (sequence-tracking via `callOrder.push`) — it verifies the CONTRACT (order, abort-on-failure, final-call identity) without depending on a live DB or actual FK semantics. This is the canonical location for cascade-ordering tests because mocking lets the test enumerate every abort path (anonymise_action_sends fails, anonymise_scope_grants fails, etc.) without seeding real fixture rows. The integration test (`action-sends-worm.test.ts`) is the right home for **DB-layer invariants** (WORM triggers, CHECK constraints, RPC return shape) — these REQUIRE a live DB to verify. The two layers are complementary; the cross-layer assertion in row (h) was duplicating what the unit-test layer already owns.

**References:**

- `apps/web-platform/supabase/migrations/001_initial_schema.sql:28,48` — `conversations`/`messages` user_id CASCADE
- `apps/web-platform/supabase/migrations/048_scope_grants.sql:16` — `scope_grants.founder_id` RESTRICT
- `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql:102` — `action_sends.user_id` RESTRICT
- `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql:194-246` — `anonymise_action_sends(uuid)` RPC body and Art-17 docstring
- `apps/web-platform/test/server/scope-grants/account-delete-scope-grants-cascade.test.ts:62-216` — cascade-ordering unit test (mocked)
- `apps/web-platform/server/account-delete.ts` — production cascade caller (unchanged by this PR)

## Sharp Edges

- The throwaway user reaper at the end of the test body must NOT use `expect(delErr).toBeNull()` — that would re-introduce the exact failure surface this PR removes. Use a bare `try { await service.auth.admin.deleteUser(u.id); } catch { /* tolerate teardown failure */ }` and accept that on a leak the next run's `assertSynthetic` + `tenant-isolation-*` pattern catches it.
- Do NOT change `anonymise_action_sends`, migration 051's `verify_*.sql` gates, or `server/account-delete.ts`. The defect is test-only; touching production paths expands scope and re-opens the GDPR-gate / data-integrity question that the cascade test already settled in PR-G.
- The test file's `afterAll` block (lines 174-196) already tolerates teardown failures via `try/catch` — do not remove or modify it. The shared `[userA, userB]` users are NOT the failure surface; row `(h)` creates a separate throwaway `u` that escapes the shared teardown loop.
- Per AGENTS.md hr-dev-prd-distinct-supabase-projects, this test must run only against the Soleur DEV Supabase project (`TENANT_INTEGRATION_TEST=1` + `doppler run -p soleur -c dev`). Do not propose running it against `prd_*` configs.
- Per hr-gdpr-gate-on-regulated-data-surfaces: this PR does NOT touch a regulated-data surface (no migration, no auth route, no `*.sql`, no schema). The test is a DB-layer assertion narrowing; `gdpr-gate` Phase 2.7 skips silently per the canonical regex.
- Per hr-observability-as-plan-quality-gate: no new observability surface is introduced; this is a pure test edit. Plan Phase 2.9 skips silently (no Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`).
- Per wg-use-closes-n-in-pr-body-not-title-to: PR body uses `Closes #4108` (in body, not title); `Ref #4113` for the duplicate.

## Domain Review

**Domains relevant:** Engineering (test scope correction)

### Engineering

**Status:** reviewed
**Assessment:** Single-file test edit. No production code change. Coverage analysis shows the dropped cross-layer assertion is owned by a sibling test file (account-delete-scope-grants-cascade.test.ts). Per AGENTS.md cq-test-fixtures-synthesized-only, all fixtures remain synthesized (`tenant-isolation-*@soleur.test` pattern, `randomBytes`-derived passwords, sha256-of-literal hashes). No regulated-data surface, no infra, no observability surface. Low blast radius.

No Product/UX, Legal, CMO, CRO, CPO, Security, or Compliance domain implications. This is an infrastructure/tooling change scoped to test correctness.

## Infrastructure (IaC)

Not applicable — no new infrastructure surface. Skipped per Phase 2.8 (plan introduces no new server, systemd unit, vendor account, DNS record, TLS cert, secret, or firewall rule; edits one TypeScript test file).

## Observability

Not applicable — no new code class file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`. Skipped per Phase 2.9 (test-only edit).

## Notes for /work

- The implementation is ~15-25 LoC of changes in one file. Do not gold-plate.
- The DB-layer assertions to KEEP verbatim are at `action-sends-worm.test.ts:386-401`. These are the contract under test for row `(h)` after the narrow.
- The post-merge `gh issue close 4113` + `gh issue edit 4113 --add-label duplicate` MUST happen via `gh` CLI (automatable; no operator browser step). Bake it into Phase 3 of the work execution.
- After merge, before closing #4113, verify the tenant-integration job is green on `main` for the merge commit (`gh run list --workflow tenant-integration.yml --branch main --limit 1 --json conclusion`). The narrow-fix conclusion is empirical, not a priori.
