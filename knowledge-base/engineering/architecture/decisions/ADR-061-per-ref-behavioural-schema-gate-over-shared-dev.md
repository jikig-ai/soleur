# ADR-061: Per-ref behavioural schema gates over shared dev-Supabase

- **Status:** Accepted
- **Date:** 2026-06-15
- **Issue:** #5372 (auth.users delete-cascade CI failure)
- **Decider:** `/soleur:one-shot` implementation, ratified by multi-agent review (architecture-strategist surfaced the false-red-main flaw)

## Context

The `Tenant integration (dev-Supabase)` workflow runs on both `push:main` and `pull_request` against a **single shared dev project**, applying each PR's in-flight migrations via `ALLOW_UNMERGED_DEV_APPLY=1` and leaving them in place. So the live dev schema at any moment is the union of `main` plus every open migration-PR's applied-but-unmerged objects.

#5372 was caused by one such leave-behind: an orphan `routine_runs` table (open PR #5342) whose STATEMENT-level WORM triggers contradict its `ON DELETE SET NULL` FK to `users`, aborting the GDPR Art-17 account-delete cascade as an opaque GoTrue 500.

The instinctive fix — make the existing orphan-migration-drift probe BLOCKING on `push:main` — is unsafe: dev always carries orphans from open PRs, so a blocking orphan gate would persistently false-red main. The first replacement attempt (a gate scanning the live dev schema for the WORM-vs-cascade contradiction) narrowed the *class* but **inherited the same flaw**: scanning shared mutable state means another PR's leave-behind reds main on `push:main`.

## Decision

A CI gate that asserts a **behavioural schema invariant** (here: Art-17 deletability — no raising UPDATE/DELETE trigger on a table with an `ON DELETE SET NULL/CASCADE` FK to `users`) over **shared dev** MUST be **per-ref-scoped**: it blocks (`::error::` + non-zero exit) only when the offending object is **owned by a migration in the current checkout**; an object that is a leave-behind from another ref is downgraded to `::warning::`.

Ownership is determined cheaply: the offending relation's name appears in `supabase/migrations/*.sql` on the current ref. Net effect:

- the **owning** PR's CI fails (the gate is the enforcement teeth that block the bad migration at its source);
- `main` and unrelated PRs stay green despite the leave-behind on shared dev;
- a genuinely-merged bad migration still errors on `main` (main owns it).

This is implemented in `apps/web-platform/scripts/preflight-worm-cascade-contradiction.sh` (wired into `tenant-integration.yml` after apply, before tests) and is the canonical pattern for any future behavioural schema gate over shared dev.

The gate is a **fail-fast named-relation early-warning, not a proof**: its "raising trigger" detection is a `prosrc` heuristic (`RAISE EXCEPTION`/`ASSERT`), matching the codebase's uniform WORM idiom. The end-to-end minimal-user `deleteAccount` regression test (`account-delete.cascade.integration.test.ts`) is the behavioural backstop that catches any raise idiom the heuristic misses.

## Rejected alternatives

- **Blocking orphan-migration-drift probe on `push:main`** (the plan's original Phase 2). Rejected: dev accumulates benign orphans from every open migration-PR; blocking would false-red main continuously. `ALLOW_UNMERGED_DEV_APPLY` exists precisely to tolerate unmerged state — a gate must not punish it.
- **Live-dev behavioural scan with no per-ref scoping** (the first replacement). Rejected: scanning shared mutable state couples the verdict to objects owned by other PRs — the exact false-red-main class the deviation set out to eliminate. The narrower predicate reduced frequency, not the failure class.
- **Ephemeral throwaway DB per CI run** (apply current-ref migrations to a fresh database, scan that). The cleanest decoupling, but heavyweight relative to the per-ref-ownership check, which achieves the same correctness against the existing shared-dev substrate at near-zero cost. Reconsider if shared-dev coupling causes further incidents.
- **Push the source fix onto PR #5342's branch.** Rejected: #5342 is another author's active branch; mutating it risks clobbering unpushed WIP. The fix is specified as a blocking review comment and enforced by this gate (its CI fails until #5342 fixes its migration: row-level triggers + worm-bypass carve-out + `anonymise_routine_runs` step in `account-delete.ts`, or RESTRICT + pre-anonymise).

## Consequences

- The dev-only revert of the existing `routine_runs` orphan (`scripts/revert-dev-routine-runs-drift.sql`) is point-in-time: #5342's next CI run re-applies it to shared dev. That is acceptable — the per-ref gate keeps main/other PRs green regardless, and the durable fix lands when #5342 merges its corrected migration.
- Future authors adding a schema gate over shared dev must apply the per-ref ownership pattern, or the gate will regress to false-redding main.

## Amendment 2026-09-23 (#8520, #8521): ledger gates are per-ref too

**Status:** Accepted. **Issues:** #8520, #8521. The sections above are unchanged; this amendment extends the per-ref rule from behavioural schema gates to the `_schema_migrations` ledger probe and adds a policy.

### Context

The #7964 work made the ledger drift probe BLOCKING on push to main, the alternative rejected above. Its plan (`knowledge-base/project/plans/2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md` §M2) assumed "on push … there is no legitimate unmerged-migration state". This ADR's own Context says the opposite: dev is the union of main plus every open PR's applied-but-unmerged migrations. The rejected alternative's prediction came true on 2026-09-22. Runs 35732801080 and 35736906203 failed every push to main on `Missing-on-main: 139_openai_api_key_provider.sql`, a row an open PR had legitimately applied, until that PR merged.

Separately, content drift accumulated for months: 26 rows on 2026-09-21. The cause was PRs editing a migration after their CI had applied it. The runner never re-applies a ledgered filename, so dev kept the old body.

### Decision

1. **Ownership on the authoritative ledger probe** (push to main, main dispatch, the scheduled probe). A missing-on-main row is an in-flight `::warning::` if and only if:
   - its filename never appeared in main's history;
   - a live `origin` branch that is not merged into main, with a commit in the last 30 days, holds it among its files that are **not on main**, by exact name, identical blob, or slug.

   **An ownerless row counts as main's**, because no other ref can fix it, so it blocks. So does a row whose only owner is stale (more than 30 days), a row whose name is in main's history, and any row that cannot be classified. Content drift always blocks.
   - The blob and slug tiers are load-bearing. Exact-name matching alone would red main for the whole life of a PR that renamed its applied migration.
   - Restricting ownership to files absent from main is also load-bearing. Every branch carries main's files, so without that restriction a merged rename would "own" the never-merged original from every branch.
   - Implemented by `apps/web-platform/scripts/dev-ledger-parity.sh classify-missing`, which `.github/actions/dev-migration-drift-probe/action.yml` calls under `fail-on-ledger-drift`. It uses git only: a throwaway bare repo and one blobless fetch of origin's heads. No GitHub API, no new permissions.
2. **Policy: a migration applied to shared dev is immutable, merged or not.** A change ships as a new migration file. `dev-ledger-parity.sh check`, run by `tenant-integration.yml` before apply as the base-ref copy, is the per-ref half. It fails the owning PR when an unmerged migration was edited (A1), renamed (A2) or deleted (A4) after CI applied it, so the PR's own CI goes red, which this ADR's Decision requires.
   - **Accepted cost:** fix-up migrations become permanent on prd, and the migration count grows faster.

### Rejected alternatives (additions)

- **Blocking orphan-migration-drift probe on `push:main`**, the first rejected alternative above, is **superseded in part**. It was right about in-flight rows and wrong about ownerless ones: those have no owning ref, so main must own them.
- **Automatically re-apply an edited unmerged migration.** Rejected. Re-running an edited idempotent body leaves the objects the old body created and the new body does not touch. That is silent residue: #8520's 075 `FOR ALL` policy and 122 index. A non-idempotent body simply fails later and less clearly.
- **Ephemeral throwaway DB per CI run.** The re-evaluation trigger above ("reconsider if shared-dev coupling causes further incidents") fired with #8520. The option was re-evaluated and **still rejected**: the per-ref ledger check reaches the same properties (pre-merge failure of the owning PR, no false-red main) at near-zero cost, and ADR-023 separately rejects Supabase branching.
- **An `applied_by_ref` ledger column.** Rejected. It is a schema change that also lands on prd, for a property that branch heads already give.

### Consequences

- An open PR's applied migrations no longer red main or the scheduled probe. Deleting such a branch unmerged turns its rows ownerless, which reds main until a dev reconcile. The annotation says so.
- An abandoned branch stops protecting its rows 30 days after its last commit: the verdict becomes `stale`, blocking, and names the branch.
- Repair procedures: `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` §Content drift and Part 1. Self-service reconcile is tracked in #8605.
