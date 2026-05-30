---
title: "fix: tenant-integration resolver tests seed acceptance fixture (resolve_byok_delegation returns 0 rows)"
date: 2026-05-30
type: fix
issue: 4660
branch: feat-one-shot-4660-tenant-integration-resolver
lane: cross-domain
detail_level: MORE
brand_survival_threshold: none
---

# 🐛 fix: tenant-integration (dev-Supabase) — resolver tests must seed a current-version acceptance row

## Overview

`tenant-integration.yml` (`Tenant integration (dev-Supabase)`) has failed on **every** main run since 2026-05-29 (≥6 consecutive commits, spanning unrelated PRs #4653/#4649/#4658). It is a non-required check, but a perpetually-red main workflow normalizes breakage and masks future regressions in the tenant-isolation surface.

Two of the 14 integration ACs in `apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts` fail:

- `AC-resolver-delegation: grantee with no own key + active delegation returns (grantor, delegation_id)` — `resolver returns one row: expected +0 to be 1`
- `AC-multi-workspace (DIG F3): explicit p_workspace_id returns only that workspace's delegation` — `expected +0 to be 1`

Both call `grant_byok_delegation` then assert `resolve_byok_key_owner` returns 1 delegation row; the live dev RPC returns 0.

**Root cause (verified, NOT the issue body's "dev seeding/expiry" hypothesis).** The test self-seeds every fixture in `beforeAll` + per-test (synthetic users + fresh grants) — there is no external seed to expire. The real defect is **test-vs-schema drift introduced by PR #4627** (commit `da8b06bd`, 2026-05-29):

- Migration `083_byok_delegation_consent_gate.sql` **redefined** `resolve_byok_key_owner` to add **Gate 1** — the delegation only resolves if a row exists in `byok_delegation_acceptances` matching `(delegation_id, grantee_user_id, side_letter_version = current_byok_side_letter_version())`.
- Migration `084_byok_delegation_withdrawals.sql` redefined it again, **keeping Gate 1** and adding Gate 2 (a `NOT EXISTS` withdrawal clause — satisfied by default, needs no fixture).

The integration test (authored 2026-05-25 in the mig-064 era, commit `eafd9886`) grants a delegation but **never inserts an acceptance row**. After #4627 raised the resolver bar, the two grant→resolve ACs return 0 rows. The sibling `AC-cross-tenant` PASSES because it only asserts the trigger raises `P0001` — it never resolves, so it never hits Gate 1. This is exactly the failure signature in the issue.

PR #4627's plan/work updated the migration-level resolver tests but did not sweep the live-DB integration fixtures for the new acceptance precondition.

**Fix (minimal).** After each `grant_byok_delegation` whose delegation is later resolved, seed a current-version acceptance row via the service-role client (RLS-bypassing, mirrors the canonical insert at `app/api/workspace/delegations/accept/route.ts:65-74`):

```ts
// import at top of test file:
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

async function seedAcceptance(
  service: SupabaseClient,
  delegationId: string,
  granteeUserId: string,
): Promise<void> {
  const { error } = await service
    .from("byok_delegation_acceptances")
    .insert({
      user_id: granteeUserId,
      delegation_id: delegationId,
      side_letter_version: BYOK_SIDE_LETTER_VERSION, // "1.0.0", matches current_byok_side_letter_version()
    });
  expect(error, `seedAcceptance(${delegationId})`).toBeNull();
}
```

`BYOK_SIDE_LETTER_VERSION` (`= "1.0.0"`) is CI-parity-pinned to the SQL `current_byok_side_letter_version()` literal (`test/byok-side-letter-version-parity.test.ts`), so importing the TS const keeps the fixture future-proof against a version bump rather than hardcoding `"1.0.0"`.

Call `seedAcceptance` in exactly the two grant→resolve ACs (3 grants total): `AC-resolver-delegation` (1 grant: alice→bob) and `AC-multi-workspace` (2 grants: alice→dave W_A, carol→dave W_C). The other 12 ACs do not resolve and need no acceptance fixture (verified per-AC below).

This is a **test-only change** — no migration, no application code, no schema, no resolver logic. The resolver behaving as designed (fail-closed without acceptance) is correct; the test fixtures were stale.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Reality (verified) | Plan response |
|---|---|---|
| "Dev-Supabase data/seeding state: the active delegation fixture is absent or expired (seed not applied, `revoked_at`/`expires_at` lapsed, RLS mismatch)" | Test self-seeds all fixtures in `beforeAll`/per-test; no external seed exists to expire. `revoked_at`/`expires_at` are NULL on fresh grants. | Reject the seeding/expiry hypothesis; root cause is the missing acceptance-row fixture vs the mig-083 Gate 1. |
| "Environment/seeding defect, not application logic" | Half-right: not application logic, but also not environment — it is **test-fixture drift** vs a schema change (#4627 mig 083/084). | Fix the test fixtures; do not touch dev-Supabase data or the resolver. |
| "Not introduced by #4658" | Correct — #4658 touched only Sentry emission. The regression was introduced by **#4627** (`da8b06bd`, 2026-05-29), which redefined the resolver. | Cite #4627 as the introducing PR. |
| Suggested alt: "guard the two integration ACs behind a seed-precondition skip" | Would hide a real regression and reduce tenant-isolation coverage. The fixtures are seedable in-test. | Reject the skip-guard; seed the acceptance row instead (full coverage retained). |
| `resolve_byok_delegation` (issue title) | The RPC is named `resolve_byok_key_owner`; `resolve_byok_delegation` does not exist as a symbol. | Use the correct symbol name throughout. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is a CI test-fixture fix for a non-required check. A wrong fix (e.g., weakening the resolver) could re-open the BYOK consent-gate that protects a delegated key from being used without recorded consent.
**If this leaks, the user's data is exposed via:** N/A — test-only change; no new data path, no schema, no production code.
**Brand-survival threshold:** none — test-fixture correction on a non-required workflow. threshold: none, reason: test-only change to dev-Supabase integration fixtures; no production code, schema, or data surface is touched.

## Acceptance Criteria

### Pre-merge (PR)
- [x] AC1: `seedAcceptance(service, delegationId, granteeUserId)` helper added to `byok-delegations.tenant-isolation.test.ts`, inserting into `byok_delegation_acceptances` with `side_letter_version: BYOK_SIDE_LETTER_VERSION` (imported from `@/server/byok-side-letter`, NOT a hardcoded literal). Verify: `grep -n "BYOK_SIDE_LETTER_VERSION" apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts` returns the import line + the insert usage. ✓ import at line 42, insert usage at line 136.
- [x] AC2: `AC-resolver-delegation` calls `seedAcceptance` for the alice→bob grant before `resolve_byok_key_owner(bob)`. ✓ line 284 (`seedAcceptance(service, delegationId, bob.id)`).
- [x] AC3: `AC-multi-workspace` calls `seedAcceptance` for BOTH the alice→dave (W_A, `idA`) and carol→dave (W_C, `idC`) grants before the two resolves. ✓ lines 338–339 (`idA`/dave, `idC`/dave).
- [x] AC4: No other AC gains an acceptance seed (the other 12 do not resolve). `grep -c` returns **5**, not 4: 1 helper def + 3 call sites + 1 `seedAcceptance(${delegationId})` string in the helper's own `expect` message (present in the plan's prescribed snippet). Functional intent satisfied — exactly 3 call sites at lines 284/338/339, all within the two resolving ACs.
- [x] AC5: Live-DB run is green. `doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/byok-delegations.tenant-isolation.test.ts --project unit` → **14/14 passed** (21.5s), including the two previously-failing resolver ACs.
- [x] AC6: Skip-path unchanged: same command WITHOUT `TENANT_INTEGRATION_TEST=1` → **14 skipped** (describe block skipped, no live-DB calls).
- [x] AC7: `./node_modules/.bin/tsc --noEmit` passes (exit 0) — the `@/server/byok-side-letter` import and `seedAcceptance` signature typecheck.
- [x] AC8: No production/schema files modified. `git status` confirms the only tracked modification is `apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts` (+ plan + specs/ artifacts). (The two `worktree-manager.*` files in a two-dot `git diff origin/main` are a sibling branch's merged change the branch is behind on, not part of this diff — `git merge-base..HEAD` is empty for them.)

### Post-merge (operator)
- [ ] AC9: `tenant-integration.yml` is green on the first `push` to main after merge. Automation: `gh run list --workflow=tenant-integration.yml --branch main --limit 1 --json conclusion` — expect `success`. (The merge itself triggers the run via the `supabase/migrations/**`-adjacent path filter; the test file path `apps/web-platform/test/server/**.tenant-isolation.test.ts` is in the push filter, so the merge re-fires it.)
- [ ] AC10: `gh issue close 4660` after AC9 confirms green. Use `Ref #4660` (not `Closes`) in the PR body — this is a normal code-class fix that closes at merge, but the true confirmation is the post-merge green run; `Closes #4660` in the body is acceptable here since the workflow re-fires automatically on merge and no operator prod-write step gates closure. Plan author's choice: `Closes #4660` (standard single-PR fix).

## Test Scenarios

The test FILE is itself the test surface. Confirm the runner + path:
- Runner: `apps/web-platform` package — `npm run test:ci` (vitest). The `--project unit` flag matches `apps/web-platform/vitest.config.ts` node project; the file lives under `test/server/**` which the `include:` glob collects (verify at /work Phase 0: `grep -n "include" apps/web-platform/vitest.config.ts`).
- Gate env: `TENANT_INTEGRATION_TEST=1` flips `describe.skipIf(!INTEGRATION_ENABLED)` to run.
- Secrets: dev-Supabase `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` via `doppler run -p soleur -c dev`.

Per-AC resolve-vs-no-resolve audit (why only 2 ACs need the fixture):

| AC | Calls `resolve_byok_key_owner`? | Needs acceptance seed? |
|---|---|---|
| AC-cross-tenant | no (asserts trigger P0001) | no |
| AC-cap-upper-bound ($1M) | no | no |
| AC-cap-upper-bound (hourly>daily) | no | no |
| AC-resolver-own-key | yes, but caller has own `api_keys` row → Gate 1 short-circuited by own-key precedence (returns before the delegation query) | no |
| **AC-resolver-delegation** | **yes (bob, no own key)** | **YES — 1 seed** |
| **AC-multi-workspace** | **yes (dave, no own key, 2 workspaces)** | **YES — 2 seeds** |
| AC-worm-shape1-attribution | no (asserts revoke 42501) | no |
| AC-worm-shape1-valid | no (reads row directly) | no |
| AC-revoke-reserved-reason | no | no |
| AC-worm-delete | no | no |
| AC-member-departure | no (reads row directly) | no |
| AC-hourly-cap-exceeded | no (calls `check_and_record_byok_delegation_use`, not the resolver) | no |
| AC-worm-shape3 | no (direct UPDATE + read) | no |
| AC-anonymise-active-row-guard | no (reads row directly) | no |

Note AC-resolver-own-key: own-key precedence (`IF EXISTS (api_keys ...) RETURN`) returns before the delegation query, so it never reaches Gate 1 — confirmed unaffected. Verify at /work by reading `084_byok_delegation_withdrawals.sql:288-296`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-fixture correction on a non-required CI workflow. No new user-facing surface, no schema, no application logic. (Engineering/QA only; not a product, legal, marketing, or infra change.)

## Observability

Skip — pure test change, no Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface. The only edited file is a `test/` file. (Per plan Phase 2.9 skip condition: "Plan is pure-docs/test — no Files-to-Edit under code/infra paths.")

## Files to Edit

- `apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts` — add `import { BYOK_SIDE_LETTER_VERSION }`, add `seedAcceptance` helper, call it in `AC-resolver-delegation` (1×) and `AC-multi-workspace` (2×).

## Files to Create

- (none — test edit + plan artifacts only)

## Open Code-Review Overlap

None. (Single test file; verified no open `code-review` issue tracks `byok-delegations.tenant-isolation.test.ts`.)

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Seed acceptance row in `beforeAll` for all delegations | Rejected — only 2 ACs resolve; seeding globally couples unrelated tests and the WORM/anonymise ACs would gain spurious acceptance rows. Seed per-AC at the grant site. |
| Guard the 2 ACs behind a seed-precondition `it.skipIf` (issue body suggestion) | Rejected — hides a real regression, drops tenant-isolation coverage on the resolver happy-path, and the fixtures are trivially seedable in-test. |
| Weaken/revert the resolver Gate 1 | Rejected — Gate 1 is correct, deliberate consent enforcement (#4625/#4627, legal-reviewed). The test was stale, not the schema. |
| Add a `grant_byok_delegation`-time auto-acceptance | Rejected — would change production consent semantics (grant ≠ acceptance by design; acceptance is the grantee's separate consent act). Out of scope and wrong. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with threshold `none` + reason.)
- The `seedAcceptance` insert uses the **service-role** client (RLS-bypassing) like every other write in this test. Do NOT route through the `/api/workspace/delegations/accept` route (it requires an authenticated grantee session the integration harness doesn't establish) — the direct table insert is the canonical test-fixture path and mirrors the route's insert shape exactly.
- `side_letter_version` MUST equal `current_byok_side_letter_version()` (`"1.0.0"`). Import `BYOK_SIDE_LETTER_VERSION` rather than hardcoding — a future version bump (a deliberate legal re-consent act) would otherwise silently re-break this test with the same 0-rows signature.
- The acceptances table has `UNIQUE (user_id, delegation_id)` and a `no_mutate` trigger (insert-only). Each `seedAcceptance` targets a distinct fresh delegation, so no 23505 conflict — but if a test is ever refactored to re-grant the same (grantor, grantee, workspace) tuple, the partial-unique on `byok_delegations` blocks it first.
- The `byok_delegation_acceptances.user_id` FK is `ON DELETE RESTRICT`; like the delegation rows, seeded acceptance rows accumulate as orphans per the closed-preview pattern documented in the test's `afterAll`. No new cleanup burden beyond what already exists (deferred sweeper #3934).
- **Acceptance is keyed on the GRANTEE, not the grantor.** `seedAcceptance` MUST pass the *grantee*'s user_id (`bob.id` / `dave.id`), matching the resolver's Gate 1 clause `a.user_id = bd.grantee_user_id`. Passing the grantor would insert an acceptance the resolver never reads, leaving the 0-rows failure intact. The own-key precedence (`api_keys WHERE user_id = p_caller_user_id`) is also keyed on the *caller* (grantee) — so the grantee must have NO `api_keys` row for the delegation branch to be reached. bob/dave have none; alice's `api_keys` row seeded in `AC-resolver-own-key` is irrelevant because alice is never the caller in the delegation resolves. Do not give the grantee an own key.

## Deepen-Plan Verification (2026-05-30)

Realism passes run inline (deepen-plan Phases 4.45–4.8). All gates pass; findings folded above.

**Premise (multi-clause predicate read — verbatim).** Resolver `resolve_byok_key_owner` at `084_byok_delegation_withdrawals.sql:271-330`. The delegation branch returns a row IFF ALL of:
1. `bd.grantee_user_id = p_caller_user_id` (caller is the grantee)
2. `bd.workspace_id = p_workspace_id`
3. `bd.revoked_at IS NULL` (NULL on fresh grants ✓)
4. `bd.expires_at IS NULL OR bd.expires_at > clock_timestamp()` (tests pass `p_expires_at: null` ✓)
5. **Gate 1 (mig 083):** `EXISTS(acceptances WHERE delegation_id=bd.id AND user_id=bd.grantee_user_id AND side_letter_version = current_byok_side_letter_version())` — **the unsatisfied clause**; the fix seeds exactly this row.
6. **Gate 2 (mig 084):** `NOT EXISTS(withdrawals ...)` — vacuously true (no withdrawal seeded) ✓.

Clauses 1–4 + 6 already hold for the test's fresh grants; only clause 5 fails → 0 rows. Seeding one acceptance row per resolved delegation satisfies clause 5. Verified the conjunction, not just the most-discussed clause (per deepen-plan multi-clause-predicate check).

**Negative-claim verification.**
- "Own-key precedence returns before the delegation query" → CONFIRMED at `084:288-296` (`IF EXISTS(api_keys WHERE user_id=p_caller_user_id) ... RETURN;`). So `AC-resolver-own-key` short-circuits Gate 1.
- "No production/schema files modified" → the sole Files-to-Edit path is `apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts` (test/); confirmed not in the sensitive-path regex.

**Runtime-shape verification.**
- `@/server/byok-side-letter` import resolves: `apps/web-platform/tsconfig.json:17-18` maps `"@/*": ["./*"]`. `byok-side-letter.ts` exports `BYOK_SIDE_LETTER_VERSION = "1.0.0"`.
- `--project unit` collects the file: `apps/web-platform/vitest.config.ts:42-44` unit project `include: ["test/**/*.test.ts", ...]` matches `test/server/byok-delegations.tenant-isolation.test.ts`.

**Side-letter version parity.** `BYOK_SIDE_LETTER_VERSION` (`"1.0.0"`, `server/byok-side-letter.ts:24`) == SQL `current_byok_side_letter_version()` (`"1.0.0"`, `083:55-64`), CI-gated by `test/byok-side-letter-version-parity.test.ts`. Importing the TS const (not hardcoding) keeps the fixture correct across a future version bump.

**Precedent-diff (deepen-plan Phase 4.4).** The canonical acceptance-insert precedent is `app/api/workspace/delegations/accept/route.ts:65-74` — same three columns (`user_id`, `delegation_id`, `side_letter_version: BYOK_SIDE_LETTER_VERSION`), `id`/`accepted_at`/`retention_until`/`created_at` defaulted. `seedAcceptance` mirrors it via the service-role client (test harness has no authenticated grantee session). No novel pattern.

**Issue/PR citations (verified live this session).** #4660 OPEN (the target). #4627 (`da8b06bd`, 2026-05-29) is the introducing PR — `git log` shows it last-touched migrations 083 + 084 (the resolver redefinitions). Test file last-touched by #4290 (`eafd9886`, 2026-05-25, mig-064 era) — predates the consent gate, confirming the drift direction.
