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
   - a live `origin` branch whose tip is not an ancestor of main, and whose head commit is dated within the last 30 whole days, holds it among its **top-level** migration files that are **not on main**, by exact name, identical blob, or slug. `gh-readonly-queue/*` refs own nothing. A head dated more than a day in the future, or undated, counts as stale: the committer date is set by whoever pushes.

   **An ownerless row counts as main's**, because no other ref can fix it, so it blocks. So does a row whose only owner is stale, a row whose name is in main's history, and any row that cannot be classified. Content drift always blocks. A row that is on main's tip by the time the classifier fetches (it merged after the probe read main) is reported `merged`, a warning.
   - The blob and slug tiers are load-bearing. Exact-name matching alone would red main for the whole life of a PR that renamed its applied migration.
   - Restricting ownership to files absent from main is also load-bearing. Every branch carries main's files, so without that restriction a merged rename would "own" the never-merged original from every branch. It is also why "not merged" can be read from ancestry: a squash-merged branch that was never deleted still counts as live, but after the squash its files are on main and own nothing.
   - Implemented by `apps/web-platform/scripts/dev-ledger-parity.sh classify-missing`, which `.github/actions/dev-migration-drift-probe/action.yml` calls under `fail-on-ledger-drift`. It uses git only: a bare owner repo and one blobless fetch of origin's heads. No GitHub API, no new permissions.
2. **Policy: a migration applied to shared dev is immutable, merged or not.** A change ships as a new migration file. `dev-ledger-parity.sh check` is the per-ref half. `tenant-integration.yml` runs it before apply; it is the base-ref copy whenever main carries the script (the checkout copy only in the introduction window), extracted and executed in the same step. It fails the owning PR when an unmerged migration was edited (A1), renamed (A2) or deleted (A4) after CI applied it, so the PR's own CI goes red, which this ADR's Decision requires. A row another fresh branch holds by exact name **at the applied blob**, and did not inherit from this PR's history, is treated as that PR's in-flight row instead.
   - **Accepted cost:** fix-up migrations become permanent on prd, and the migration count grows faster.
   - **What the PR-side check cannot see:**
     - A4 reads the blobs reachable in `main..<PR head>` on origin. A force-push that drops the applying commit, or a migration body that existed only inside a merge commit's conflict resolution, leaves no trace to match.
     - An independent fresh branch that holds the row at the applied blob still excuses it. That branch is not in the PR's diff, so this is visible only as a `::warning::` in the check's log.
     - The check is a snapshot before apply. Writes after it (the PR's own runner copy, migration bodies with dev credentials, the mutex failing open, #8049) are outside it; the post-merge probe on main remains the backstop.
   - **The main side is not a history check.** Between the push in which an open PR deletes, or renames and re-slugs, an applied migration, and the push in which it restores it, that row has no owner, so main's probe reds. The PR's own check is red over the same window and names the fix.

### Rejected alternatives (additions)

- **Blocking orphan-migration-drift probe on `push:main`**, the first rejected alternative above, is **superseded in part**. It was right about in-flight rows and wrong about ownerless ones: those have no owning ref, so main must own them.
- **Automatically re-apply an edited unmerged migration.** Rejected. Re-running an edited idempotent body leaves the objects the old body created and the new body does not touch. That is silent residue: #8520's 075 `FOR ALL` policy and 122 index. A non-idempotent body simply fails later and less clearly.
- **Ephemeral throwaway DB per CI run.** The re-evaluation trigger above ("reconsider if shared-dev coupling causes further incidents") fired with #8520. The option was re-evaluated and **still rejected**: the per-ref ledger check reaches the same properties (pre-merge failure of the owning PR, no false-red main) at near-zero cost, and ADR-023 separately rejects Supabase branching.
- **An `applied_by_ref` ledger column.** Rejected. It is a schema change that also lands on prd, for a property that branch heads already give.

### Consequences

- An open PR's applied migrations no longer red main or the scheduled probe, as long as the PR's branch still holds them. Deleting such a branch unmerged, or removing the file from it, turns its rows ownerless, which reds main until the file is restored or dev is reconciled. The annotation says so.
- An abandoned branch stops protecting its rows once its head commit is more than 30 whole days old: the verdict becomes `stale`, blocking, and names the branch. On the scheduled surface each blocking class also emits one Sentry event.
- Repair procedures: `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` §Content drift and Part 1. Self-service reconcile is tracked in #8605.

## Amendment 2026-09-23 (#8605, #8606): closed-PR ownership and a dev reconcile path

**Status:** Accepted. **Issues:** #8605, #8606. Append-only: every section above is unchanged, and
two of its sentences are superseded by name below.

### Context

Under the previous amendment, a branch whose pull request was closed without merging, and whose
branch was never deleted, kept its applied dev rows in-flight forever, because nothing in git records
PR state. The only way to discard an applied-but-unmerged version was a hand-run SQL session with a dev
credential. Separately, `run-migrations.sh` resolved its unmerged-apply pathspec against the current
directory, so from `apps/web-platform` (where `tenant-integration.yml` and `rls-authz-fuzz.yml` run it)
every file read as "not on origin/main" (#8606, fixed by anchoring both pathspecs with
`:(top,literal)`; from the repo root, the prd path, they name the same paths as before).

### Decision

1. **Ownership rule, restated.** A missing-on-main row is an in-flight `::warning::` if and only if the
   conditions of the previous amendment hold AND at least one fresh live holder branch has an open pull
   request, has none, or has a latest closed pull request whose head is not the branch's current tip.
   When every fresh holder's latest pull request closed AT the branch tip, the verdict is `closed-grace`
   (a warning) for `CLOSED_GRACE_H=24` hours after the close, then `closed` (blocking, with a Sentry
   event on the scheduled surface). The evidence is bound to the commit (`head.sha` == branch tip), never
   the branch name, so a re-pushed or recreated branch is not condemned by an old PR. A closed holder is
   decided before the stale tiers run.
2. **The classifier reads PR state.** `classify-missing` calls `GET /repos/{repo}/pulls?head=…` with the
   job's `GITHUB_TOKEN` and `pull-requests: read`, only for fresh owner branches (a probe with no fresh
   candidate makes no call), memoised per run. It stays fail-closed: 401/403/404 exit as `config`
   (naming the status), 429/5xx get one retry and then exit as `transient`, and a malformed body exits
   as `transient`; the probe reports any of these as UNCLASSIFIED (blocking).
3. **DC-1: a CI path writes to the shared DEV ledger and schema, never prd.** `dev-ledger-reconcile.yml`
   runs `apps/web-platform/scripts/dev-ledger-reconcile.sh`, a writer kept in its own file (it sources the
   read-only guard as a library, so the guard `tenant-integration.yml` extracts stays write-free). For one
   pull request it discards the rows that PR owns: in one `psql --single-transaction` unit it deletes each
   ledger row by compare-and-set on filename AND `content_sha` (raising unless exactly one row matched) and
   runs the paired `.down.sql` when there is one, newest `applied_at` first, under the dev-suite mutex
   (proceeding only on `DEV_SUITE_MUTEX_ACQUIRED`), with `lock_timeout`/`statement_timeout`. It runs
   automatically when a same-repo PR is closed without merging (`pull_request_target`, base-branch
   workflow, no PR-head code executed) and on `workflow_dispatch` from `main` (dry run by default).
   - **Authorization boundary:** repo write access, the same boundary that already lets a PR's CI apply
     its SQL to dev. Fork PRs are excluded (they never applied anything). An OPEN PR's rows can be
     discarded only by its author (`github.triggering_actor`) and only for rows with a paired `.down.sql`.
   - **Why the PR's own `.down.sql` may run with the dev credential under `pull_request_target`:** it is
     refused on any backslash byte (psql would run a meta-command such as `\!` from a `-f` file), checked
     before any mutex or database contact; on transaction-control and non-transactional statements, matched
     on a view with comments, strings and dollar-quoted bodies stripped; and it runs with `GH_TOKEN` unset.
     A single wrapping `BEGIN`/`COMMIT` pair is normalized away. This is why the path is not a
     `contributor` path in C4: forks are excluded, and same-repo authors already hold the credential
     through PR CI.
   - **Dev only:** the workflow asserts the `dev_scheduled` Doppler config resolves to `environment=dev`
     and holds no `SUPABASE_ACCESS_TOKEN`, and the writer checks `DOPPLER_ENVIRONMENT=dev` in-process
     before any `psql`.
4. **Policy 2, relaxed and bounded.** An applied-but-unmerged version may be discarded (down plus CAS
   delete) instead of restored, only when the PR carries its paired `.down.sql`. The primary fix for an
   edited-after-apply migration stays "restore the applied body and ship a new migration". A CLOSED PR's
   row with no `.down.sql` is discarded ledger-only; its objects stay on dev, and the workflow files an
   `action-required` issue naming the residue.
5. **Later-row safety.** A down body that uses `CASCADE` or redefines shared objects (`CREATE OR
   REPLACE`, policies, grants, `ALTER FUNCTION`/`PROCEDURE`) is refused while the ledger holds any row
   applied at or after this PR's earliest row, because it could drop another branch's objects or revert
   main's later definition. `allow_later_rows` (dispatch only, never the close path) overrides after a dry
   run lists those rows. Residual: detection is by `applied_at`, so an object an out-of-order apply created
   before this PR's row and that depends on it is not seen.

**Superseded sentences** (previous amendment, Decision 1 and Consequences): "It uses git only: a bare
owner repo and one blobless fetch of origin's heads. No GitHub API, no new permissions." (now: git plus
the `pull-requests: read` lookup above) and "Self-service reconcile is tracked in #8605." (now:
`dev-ledger-reconcile.yml`).

### Rejected alternatives (additions)

- **`pull_request: closed` as the trigger.** It runs the workflow copy from the PR's merge ref, i.e.
  PR-controlled YAML with the dev secret.
- **Dispatch with `--ref <branch>`.** It runs the branch's YAML, and branches predating the workflow
  cannot dispatch it.
- **Refuse every closed PR's row that has no `.down.sql`.** Contradicts the operator's direction; the
  residue is disclosed and filed instead.
- **A warning-only `closed` verdict with dispatch-only reconcile.** Leaves closed PRs' rows unowned
  indefinitely.
- **Degrade a transient PR-state failure to an in-flight warning.** Contradicts the fail-closed
  direction; one retry is used instead.
- **An audit table on dev.** A migration that would also land on prd; the PR comment, job summary and
  `action-required` issue carry the audit trail.

### Consequences

- Closing a migration PR unmerged with its branch retained discards its dev rows within minutes. A
  refused or failed close-time run files an `action-required` issue and turns blocking after 24 hours.
- A PR closed by a `GITHUB_TOKEN`-authenticated workflow fires no `pull_request_target` event and relies
  on the grace. A PR closed with "delete branch" reads `orphan` (blocking, no grace) until the close-time
  run lands, as before, now bounded by minutes; the orphan line carries a `gh pr list` lookup hint.
- The detection ceiling for a close-time run that never happened is about 30 hours (the 24-hour grace
  plus the 6-hour probe cadence).
- A GitHub API outage on an authoritative probe can red main while fresh owners exist (fail-closed).
