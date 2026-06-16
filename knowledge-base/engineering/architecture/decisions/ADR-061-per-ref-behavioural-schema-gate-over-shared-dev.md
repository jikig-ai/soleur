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
