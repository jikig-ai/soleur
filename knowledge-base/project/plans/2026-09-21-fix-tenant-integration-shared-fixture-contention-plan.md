---
title: "fix: Tenant integration (dev-Supabase) red on main — BYOK delegation-cap tests look like shared-fixture contention"
type: fix
date: 2026-09-21
slug: fix-tenant-integration-shared-fixture-contention
branch: feat-one-shot-7964-tenant-integration-red
issue: 7964
closes: 7964
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: Tenant integration (dev-Supabase) red on main — BYOK delegation-cap tests look like shared-fixture contention

## Enhancement Summary

**Deepened on:** 2026-09-21
**Sections enhanced:** 5 (writer census, mutex mechanism, precedent-diff,
risks, test registration)
**Reviewed-Coverage: sequential-fallback** — deepen-plan halts/gates and
research were executed inline in a single session; no independent review
agents ran.

### Key Improvements

1. Writer census corrected: `scheduled-realtime-probe.yml` is a second CI
   consumer of `dev_scheduled` — a subscribe-only realtime probe, not a
   migration/fixture writer. The serialization claim now names the *writer*
   class precisely.
2. Precedent-diff gate (deepen-plan Phase 4.4) satisfied: side-by-side of
   `tc_acquire` (flock, fd-scoped) vs `pg_advisory_xact_lock`
   (session-scoped), including the #7553 fail-open divergence with its
   justification.
3. Pooler research confirmed the mechanism choice and surfaced the
   session-lock-over-transaction-pooler leak footgun, now pinned as a
   hard coupling in the fallback path.

### New Considerations Discovered

- `pg_advisory_lock` (session-scoped) over the transaction pooler leaks
  locks to unrelated pool renters — the fallback MUST stay paired with
  `DATABASE_URL` direct/session-mode, never `DATABASE_URL_POOLER`.
- A `pg_sleep`-held transaction occupies one pool slot for the job
  duration — capacity note added.

## Overview

The required `Tenant integration (dev-Supabase)` check went red on `main` on
2026-09-08 with counter-shaped BYOK delegation-cap assertion failures
(`expected 10 to be 5`, `expected null not to be null`) while the sibling
branch `feat-one-shot-7829-byok-cap-audit-ledger` was running against the
same shared dev Supabase project (#7964). The check is currently green —
14 consecutive successful `push` runs on `main` across 2026-09-20/21 — with
no code change, which satisfies the issue's own settling criterion
("re-run at a moment when no BYOK-cap branch is running").

Planning-phase verification found that the remedy the issue proposed is
already in force: every test mints fresh users/workspaces/delegations
(`randomBytes(8)`/`randomUUID`, cap meter keyed by `delegation_id`), so a
shared *row-level* counter cannot explain `expected 10 to be 5`. The residual
hazard is at the schema-global layer: every isolation-surface run applies its
own branch's unmerged migrations to the one shared dev project
(`ALLOW_UNMERGED_DEV_APPLY=1`), and the `dev-supabase-<ref>` job mutex is
per-ref — two runs on *different* refs can interleave a
`CREATE OR REPLACE FUNCTION` over a live cap RPC mid-suite, or leave drifted
function bodies behind for the next run. This plan serializes the dev-touching
critical section at the resource (a DB-scoped suite mutex) and makes residual
drift fail fast with a named cause on authoritative (non-PR) runs, so the
next occurrence is prevented or self-diagnosing rather than a mystery red.

## Problem Statement / Motivation

`tenant-integration-required` is a REQUIRED status check
(`infra/github/ruleset-ci-required.tf`), so a red on `main` is inherited by
every subsequent PR. The 2026-09-08 failures were diagnosed as
"shared-fixture contention" on inference alone; the deciding datum — which
state on dev the suite actually saw — was never captured. Three gaps remain
on `origin/main` today:

1. **No cross-ref serialization of the dev-touching critical section.** The
   job-level `concurrency: dev-supabase-${{ github.ref }}` group serializes a
   ref against itself only. A repo-wide group was tried in #7986 and measured
   as queue-starving (~22 arrivals/h vs >= 4 runs/h capacity), reverted by
   #8048. The cross-ref gap — the exact configuration observed on 2026-09-08 —
   is open.
2. **Drift detection runs warning-only inside this workflow.** The
   dev-migration-drift-probe composite already detects both ledger drift
   (`_schema_migrations` rows missing from `origin/main`) and live RPC
   body-marker drift (including `check_and_record_byok_delegation_use`'s
   `FOR UPDATE` and cap-reason markers), but in `tenant-integration.yml` it is
   invoked with defaults — `::warning::` severity, `exit 0` — so a drifted
   dev project proceeds into a 15-minute suite and surfaces as counter-shaped
   test failures instead of a named-drift failure.
3. **A contended or drifted run is not self-announced.** There is no
   banner/probe naming a concurrent sibling run (the ADR-133
   `SIBLING_RUN_DETECTED` pattern exists for local `test-all.sh` but has no
   CI/dev-Supabase counterpart), and the verdict script's eviction arm covers
   `cancelled` but not contention-shaped `failure`.

The exact mechanism of the 2026-09-08 failure is **UNKNOWN** — the deciding
datum (which schema-global state dev actually served mid-run) was never
captured and cannot be reconstructed. The plan therefore does not claim a
confirmed root cause; it closes the *verified open* gap (cross-ref
serialization is absent — provable from the workflow file today) and makes
the next occurrence self-attributing rather than re-diagnosed.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verified state |
|---|---|
| Issue #7964 open, p1, `type/bug` | Confirmed OPEN; no closing PR |
| `Tenant integration (dev-Supabase)` red on main | **Stale** — green streak: 14 consecutive `success` push runs 2026-09-20/21 (`gh run list --workflow tenant-integration.yml --branch main`) |
| Test files exist | `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts` (1271 lines) and `byok-delegations.tenant-isolation.test.ts` (745 lines) present on `origin/main` |
| Tests lack per-run isolation ("shared counter") | **Refuted** — per-run `randomBytes(8)` emails / fresh users / workspaces / delegations; cap SUM keyed by `delegation_id` (atomicity test, `auditRowsFor`). #7986 measured the same at `37dc09e6` |
| "A serializing lock" is missing | Partially — per-ref `dev-supabase-<ref>` job mutex exists (#8048); the cross-ref gap and the `run-migrations.sh` apply race (#8049, OPEN) are real |
| Related closed issues | #7055 closed by #7986 (partitioned assertions + live-body `diagBanner` self-diagnosis in-test); #7963/#7958 closed by #7914 (migration 137 — a *real* RPC drift fixed, not contention); #5916/#5917 earlier same-class flakes |

### Property List (Phase 0.6b — what the ask is actually for)

- **P1 — Attribution:** a red caused by sibling-run interference or residual
  dev drift must be distinguishable from a real regression at read-time.
- **P2 — Prevention (concurrent):** two runs on different refs must not
  interleave apply+test against the one dev project.
- **P3 — Prevention (residual):** drifted schema-global state left by an
  unmerged apply must be caught before a main/authoritative run burns the
  suite on it.

### Cut List (Phase 0.6b — mechanisms proposed but already covered or measured infeasible)

| Proposed mechanism | Property | Why cut |
|---|---|---|
| Per-run unique tenant/team id | P2 (row-level) | Already in force — `randomBytes(8)`/`randomUUID` fixtures, `delegation_id`-keyed meter; implementing would be a no-op presented as a fix (#7986's own correction to #7055) |
| Repo-wide GitHub `concurrency` mutex | P2 | Measured infeasible in #7986/#8048 — 15 arrivals/40 min vs ~4 runs/h capacity; eviction is the steady state and fails the required check closed |
| Per-run Postgres schema / Supabase branch | P2 | Migrations hardcode `public.` qualifiers (`public._schema_migrations`, `public.worktree_write_lease`, …) — schema isolation requires rewriting the migration corpus; Supabase branching is new infra+vendor spend for a CI flake |
| Auto-revert of drifted objects on main runs | P3 | Unbounded DDL — a generic "undo an arbitrary unmerged migration" cannot know safe DROP order; the existing revert procedure (`apps/web-platform/scripts/revert-dev-routine-runs-drift.sql` precedent + drift-probe runbook pointer) stays the remedy |
| `run-migrations.sh` internal txn lock | P2 (apply sub-window) | Already tracked as #8049 (OPEN) — complementary, covers non-CI/manual applies; this plan does not duplicate it |

### Relevant prior art

- `scripts/tenant-integration-gate-verdict.sh` — fail-closed verdict, has the
  eviction arm; contention-shaped `failure` falls to the generic arm.
- `.github/actions/dev-migration-drift-probe/action.yml` — ledger probe +
  `rpc-body` marker probe; `fail-on-rpc-body-drift` input exists but is
  unwired in `tenant-integration.yml` (defaults `"false"`); no
  `fail-on-ledger-drift` input exists.
- `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts`
  — `fetchLiveDelegationRpcBody`/`diagBanner` (#5938/#7829) already fetches
  the live `pg_get_functiondef` body into the failure message.
- ADR-133 — advisory-lock precedent: instrument-first banners
  (`SIBLING_RUN_DETECTED`), proceed-with-announcement on timeout, kernel
  release on holder death (no stale-holder code).
- `apps/web-platform/supabase/migrations/116_worktree_write_lease.sql` —
  lease precedent (rejected here — a lease needs heartbeat/TTL machinery the
  advisory transaction lock gets free from session lifetime).
- `knowledge-base/project/learnings/2026-06-15-tenant-integration-breakage-is-shared-dev-grant-drift-not-code-regression.md`,
  `knowledge-base/engineering/operations/post-mortems/tenant-integration-routine-runs-worm-cascade-postmortem.md`
  (orphan unmerged `104_routine_runs.sql` applied via `ALLOW_UNMERGED_DEV_APPLY=1`
  reded main ~4h — the persistent-drift class),
  `knowledge-base/project/learnings/workflow-patterns/2026-07-03-dev-apply-during-work-broke-shared-tenant-integration-and-sibling-collision.md`.
- Writer census for the shared dev project (verify-the-negative pass,
  deepen 2026-09-21): `tenant-integration.yml` is the ONLY CI writer that
  applies migrations and fixture rows to hosted dev. Two other workflows
  consume `dev_scheduled`: `scheduled-realtime-probe.yml` — a subscribe-only
  realtime probe (`realtime-probe.mjs`, no migration apply, no fixture
  writes) — and `rls-authz-fuzz.yml`, which targets a local disposable
  Supabase-CLI stack (header comment: "this job NEVER touches a hosted
  project"). `web-platform-release.yml` migrates prd only via
  `doppler run -c prd`. Non-CI applies are #8049's scope.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "shared counter" produces `expected 10 to be 5` | Rows are per-run isolated; the shared mutable surface is schema-global objects (functions/triggers/policies) mutated by cross-ref `ALLOW_UNMERGED_DEV_APPLY=1` applies — mid-run (concurrent) or post-run (residual drift) | Prevent concurrent interleave (suite mutex); fail fast on residual drift before the suite |
| "tests need per-run isolation or a serializing lock" | Per-run isolation exists; the only lock is per-ref; repo-wide GitHub mutex measured infeasible | DB-scoped advisory mutex at the resource — serializes at ~5%-of-PRs arrival rate inside the job's own 15-min budget, no pending-entry eviction |
| Check is red on main | Green x14 on main as of 2026-09-21; the flake is conditional on sibling overlap | Ship prevention + attribution; close #7964 on merge with the evidence table |

## Proposed Solution

Two mechanisms, each mapped to a property:

**M1 — Dev-suite mutex at the resource (P1 partial, P2).** A new
`scripts/dev-suite-mutex.sh` (acquire/release/probe) wired into
`tenant-integration.yml` so the critical section — drift probe through the
test step — is serialized across ALL refs at the Postgres layer, not at the
GitHub-concurrency layer. Shape: a background `psql` opens an explicit
transaction, takes `pg_advisory_xact_lock(hashtextextended('tenant_integration_dev_suite', 0))`,
then keeps the transaction (and lock) alive on a column of `pg_sleep(10)`
statements — NOT one `pg_sleep(<hold>)`, because a parked backend never
touches the client socket mid-statement and a killed holder would leave the
lock granted until the sleep ended; chunked sleeps force a result write
every ~10s so a dead client aborts the transaction at the next boundary.
The acquire
step polls the holder's stdout for a post-lock marker and prints
`DEV_SUITE_MUTEX_ACQUIRED wait_ms=<N>` or, past budget,
`DEV_SUITE_MUTEX_CONTENDED_PROCEEDING` with the holder's `application_name`
resolved via `pg_locks` ⨝ `pg_stat_activity` (identity is re-asserted
server-side via `SET LOCAL application_name` — Supavisor masks the
startup-packet `PGAPPNAME` — e.g. `ti-<run_id>-<ref_name>`, run-id first
because `application_name` truncates tail-first; charset-normalized before
echoing — it is DB-returned data flowing into
a GitHub annotation surface). Advisory semantics per
ADR-133: on budget expiry the suite proceeds with the banner — never aborts;
a dead holder's lock releases when the next chunked result write hits the
dead socket (~10-20s, no stale-holder code). Release is
an `if: always()` step that kills the holder PID; job teardown is the
backstop.

- Acquire placement: after the Doppler environment assertions, before
  `Detect dev-vs-main migration drift` — the probe and preflights also read
  live dev state and #8049 documents them racing a sibling's half-applied
  ledger.
- `detect-changes`' anchor grep gains `scripts/dev-suite-mutex\.sh` so a
  mutex change itself runs the suite.
- `PGAPPNAME`/`DATABASE_URL_POOLER` arrive via the existing `doppler run`
  wrapper; ref/run identity via `env:` — no `github.event.*` interpolation.

**M2 — Fail-closed drift on authoritative events (P1, P3).**
`.github/actions/dev-migration-drift-probe/action.yml` gains a
`fail-on-ledger-drift` input mirroring `fail-on-rpc-body-drift`
(`::warning::`/`exit 0` → `::error::`/`exit 1` when drift is seen).
`tenant-integration.yml` passes both flags as
`${{ github.event_name != 'pull_request' }}` — on `push`/`merge_group`-adjacent
`push`/`workflow_dispatch` runs there is no legitimate unmerged-migration
state, so drift = the #5372 orphan-apply class and fails fast naming the file
or function + revert pointer; on `pull_request` the PR's own unmerged
migrations legitimately drift, so both stay warning-only (the mutex is what
protects PR runs from each other).

## Technical Considerations

- **Pooler semantics are the load-bearing verification.** The workflow
  connects via `DATABASE_URL_POOLER` (transaction-mode pooling). Vendor docs
  and pooling literature confirm the shape: `pg_advisory_xact_lock` inside an
  explicit transaction pins one backend for the transaction's duration and
  releases at COMMIT/ROLLBACK, leaving the backend clean for the next pool
  renter — the lifecycle transaction pooling assumes. Two cautions the
  research surfaced: (a) session-scoped `pg_advisory_lock` over the
  transaction pooler is a documented leak class — the lock survives COMMIT
  on the pooled backend and ghost-serializes unrelated renters, so the
  fallback pairing is `DATABASE_URL` (direct/session-mode) +
  `pg_advisory_lock`, NEVER `DATABASE_URL_POOLER` + `pg_advisory_lock`;
  (b) the `pg_sleep`-held transaction occupies one pool slot for the job's
  duration — acceptable at this arrival rate but noted for pool-size
  capacity. If live verification shows pinning does not hold, take the
  fallback above, and only then a lease-row table (last resort —
  heartbeat/TTL machinery + a migration on the prd path). This is Task
  1.1's positive control, not an assumption.
- **Budgets.** `timeout-minutes: 15` bounds the job; the lock-hold `pg_sleep`
  is sized ~1.3x that (dies with the job regardless); the wait budget is
  inside it — shipped as `DEV_SUITE_MUTEX_WAIT_S=180` (not the ~8 min first
  estimated here) so a full-budget wait still leaves ~8-10min for the 5-9min
  section after pre-acquire setup.
- **ADR-133 addendum caution applies:** its capacity verdict was measured on
  a different machine/resource; the transfer here is *method* (banner-first,
  measured wait) not conclusion.
- **No new persistent store, no new connection, no schema change** —
  Encryption Posture and GDPR surfaces are not engaged (the suite's synthetic
  users are pre-existing).
- **Architecture decision (recorded inline, no new ADR):** serializing CI
  runs at the DB resource is the same decision class ADR-133 already covers
  (advisory lock + banner-first + fail-open); this plan applies that pattern
  to the hosted-dev resource rather than the local tmpfs. C4 is unaffected —
  dev Supabase is already modeled in
  `knowledge-base/engineering/architecture/diagrams/model.c4` and no new
  external actor/system/store is introduced. If the /work phase lands on
  the lease-row fallback instead, THAT is a new durable store and requires a
  C4 touch + ADR addendum before merge.
- **Lock-pattern precedent for deepen-plan Phase 4.4:**
  `scripts/lib/test-contention.sh` (ADR-133 local advisory lock + banner)
  and the `acquire_lock` shape in session-state scripts are the in-repo
  precedents to diff the new script against.
- **Byte budget.** ADR-231: mechanism rationale lives in the script's header
  + this plan, not in new workflow comment blocks; the workflow diff is
  wiring-only (the file is ~20 KB vs the 490 KB gate).

## User-Brand Impact

- **If this lands broken, the user experiences:** a required CI check that
  either wedges red (fail-closed direction — merges blocked, operator-visible)
  or proceeds un-serialized (the status quo ante — no new failure mode).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure — the mutex touches only CI orchestration over an already
  dev-scoped Doppler path; holder identity (`PGAPPNAME`) carries ref name and
  run id only.
- **Brand-survival threshold:** `none`
  - `threshold: none, reason: CI orchestration on the shared dev project only — no user data, no production runtime, and every failure mode degrades toward red-with-banner rather than silent-green`

## Observability

```yaml
liveness_signal:
  what: "tenant-integration-required check status on main push runs; DEV_SUITE_MUTEX_* banners in the job log"
  cadence: "per push to main / per isolation-surface PR"
  alert_target: "red required check on the commit; ::error:: annotations for drift"
  configured_in: ".github/workflows/tenant-integration.yml + scripts/dev-suite-mutex.sh"
error_reporting:
  destination: "GitHub Actions annotations (::error::/::warning::); existing Sentry path on the scheduled drift surface is unchanged"
  fail_loud: "DEV_SUITE_MUTEX_CONTENDED_PROCEEDING + ::error::dev-migration-drift lines; gate verdict script error on failure"
failure_modes:
  - mode: "sibling run holds the dev critical section"
    detection: "wait banner + holder application_name from pg_locks/pg_stat_activity"
    alert_route: "job log annotation; red only if the suite then fails"
  - mode: "residual drifted migration/RPC on dev before an authoritative run"
    detection: "fail-closed drift probe (::error:: + exit 1) on non-pull_request events"
    alert_route: "failed check naming the drifted file/function + revert pointer"
  - mode: "mutex holder dies mid-suite"
    detection: "lock releases at the next chunked pg_sleep result write to the dead socket (~10-20s); next run's acquire succeeds"
    alert_route: "release emits DEV_SUITE_MUTEX_HOLDER_LOST if the section is still running"
logs:
  where: "GitHub Actions job log (steps: acquire/release + drift probe)"
  retention: "GitHub default run-log retention"
discoverability_test:
  command: "bash scripts/dev-suite-mutex.sh --help"
  expected_output: "dev-suite-mutex"
```

## Guard Contract

### Guard 1 — dev-suite mutex acquire

**Property.** A `tenant-integration` run that enters the dev-touching critical
section while another run holds it is either serialized behind the holder or
proceeds with a `DEV_SUITE_MUTEX_CONTENDED_PROCEEDING` banner — never silent.

**Assembly.** One chokepoint: the `acquire` subcommand of
`scripts/dev-suite-mutex.sh`, invoked from the single `Acquire dev-suite
mutex` step in `.github/workflows/tenant-integration.yml` — the only CI path
that writes to hosted dev. (Non-CI `run-migrations.sh` applies are outside
this assembly by design and tracked at #8049; stating that boundary is part
of the property.)

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `pg_advisory_xact_lock` statement from the holder SQL | RED — contended-second-run fixture must observe the wait or the banner |
| 2 | Make `acquire` exit 0 without emitting/observing the post-lock marker | RED — the suite's own-dispatch row: a mutex that reports acquired without acquiring is vacuous |
| 3 | Two acquires run concurrently (second member after a compliant first) | second emits `DEV_SUITE_MUTEX_WAITING` then `ACQUIRED` or `CONTENDED_PROCEEDING` — never bare `ACQUIRED after 0ms` |
| 4 | Harness: stub `psql` that never prints the marker | suite RED — wait budget exhausted path must be exercised, not unreachable |
| 5 | Must-pass non-canonical input: acquire on a different ref/run-id while lock is free | PASS — identity strings vary; green must not depend on one fixture's ref name |

**Anchor.** The stub `psql` lives in `tests/scripts/test-dev-suite-mutex.sh`
and is committed in the same PR as the guard; weakening the guard requires
editing both the script and its fixture in one diff — the fixture asserts the
SQL text, so no independent anchor is needed beyond the commit itself.

## Implementation Phases

### Phase 1 — Mutex primitive + positive control

- Write `scripts/dev-suite-mutex.sh` (`acquire|release` subcommands, banner
  vocabulary `DEV_SUITE_MUTEX_{WAITING,ACQUIRED,CONTENDED_PROCEEDING,RELEASED}`,
  holder identity via `PGAPPNAME`, wait budget, fail-open on budget).
- Write `tests/scripts/test-dev-suite-mutex.sh` covering the matrix rows
  (stub `psql` on `PATH`; no live DB needed).
- **Positive control (live):** two concurrent `psql` sessions against dev —
  verify the second blocks on `pg_advisory_xact_lock` through the pooler
  before wiring the workflow. If pinning fails, take the documented fallback
  (`DATABASE_URL` direct + session lock) before proceeding.

### Phase 2 — Workflow + action wiring

- `tenant-integration.yml`: insert `Acquire dev-suite mutex` before the drift
  probe and `Release dev-suite mutex` (`if: always()`) at job end; pass
  `fail-on-rpc-body-drift` and `fail-on-ledger-drift` as
  `${{ github.event_name != 'pull_request' }}`; add
  `scripts/dev-suite-mutex\.sh` to the detect-changes anchor grep.
- `dev-migration-drift-probe/action.yml`: add `fail-on-ledger-drift` input +
  error/exit-1 arm in the ledger step, mirroring the `rpc-body` step's
  severity switch. Validation: `action.yml` is a composite action, NOT a
  workflow — do not run `actionlint` on it (spurious schema errors);
  validate embedded `run:` shell with `bash -c '<extracted snippet>'`
  (sharp-edge #134). `actionlint` applies to the edited
  `tenant-integration.yml` only.

### Phase 3 — Disposition of #7964

- PR body cites the green streak + this mechanism; on merge, post the
  evidence comment on #7964 (per `wg-after-merging-a-pr-that-adds-or-modifies`
  the check is verified on main post-merge; the issue closes via `Closes
  #7964`).
- #8049 remains open and complementary (txn-scoped lock inside
  `run-migrations.sh` covers the non-CI apply path this mutex does not
  reach). Note in the PR body.

## Acceptance Criteria

- [ ] `scripts/dev-suite-mutex.sh` exists with `acquire`/`release`, emits the
      four `DEV_SUITE_MUTEX_*` tokens, fails open with the contended banner at
      wait budget, and never aborts the suite on lock-path failure.
- [ ] `tests/scripts/test-dev-suite-mutex.sh` covers Guard-1 matrix rows
      1–5 and is registered via `run_suite` in `scripts/test-all.sh` (the
      registration point precedent: `test-tenant-integration-gate-verdict.sh`
      at `test-all.sh`'s suite list).
- [ ] `.github/workflows/tenant-integration.yml` acquires the mutex before
      `Detect dev-vs-main migration drift`, releases it under `if: always()`,
      and anchors `scripts/dev-suite-mutex\.sh` in detect-changes.
- [ ] `dev-migration-drift-probe/action.yml` accepts `fail-on-ledger-drift`;
      on `push`/`workflow_dispatch` both drift classes fail the job with
      `::error::` naming the drifted filename or function + marker; on
      `pull_request` behavior is byte-identical to today (warnings only).
- [ ] Positive-control evidence (two-session advisory-lock block over the
      pooler) is pasted into the PR body or `specs/<branch>/` session notes.
- [ ] Post-merge: a `push` run of `Tenant integration (dev-Supabase)` on the
      merge commit is green and shows `DEV_SUITE_MUTEX_ACQUIRED` in the
      acquire step's log.
- [ ] #7964 carries the evidence comment and is closed by the PR.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change
confined to CI orchestration over the dev-Supabase test surface. No
user-facing surface, no product/marketing/legal/finance touchpoints; the
Product/UX mechanical override did not fire (no `components/**/*.tsx`,
`app/**/page.tsx`, or UI-surface paths in Files to Edit/Create). Engineering
domain assessment is inline: the change follows the repo's established
script-extraction + advisory-lock + fail-closed-gate conventions.

## Test Scenarios

- Given the dev mutex is free, when `acquire` runs, then it emits
  `DEV_SUITE_MUTEX_ACQUIRED` and a second concurrent `acquire` emits
  `DEV_SUITE_MUTEX_WAITING` before acquiring or proceeding-with-banner.
- Given the wait budget is exceeded, when a second acquire is still blocked,
  then it emits `DEV_SUITE_MUTEX_CONTENDED_PROCEEDING` and exits 0 (suite
  proceeds — fail-open, never a new red source).
- Given the holder is killed mid-hold, when `release` runs, then it is
  idempotent and the lock is gone (kernel release).
- Given dev carries a `_schema_migrations` row absent from `origin/main`,
  when a `push` run reaches the drift probe, then the job fails fast with
  `::error::` naming the file before migrations/tests run.
- Given the same drift, when a `pull_request` run reaches the probe, then it
  warns and proceeds (PR's own migrations legitimately drift).
- Live verification commands (operator/dev-Supabase via Doppler, run during
  `work` phase — NOT a third concurrent writer; the mutex makes this safe
  once wired):
  - **Lock blocks:** two `psql` sessions, second
    `SELECT pg_advisory_xact_lock(hashtext('tenant_integration_dev_suite'))`
    blocks until the first commits — proves pooler transaction pinning.
  - **Attribution:** `SELECT application_name FROM pg_stat_activity` shows
    the holder's `PGAPPNAME` identity.

## Open Code-Review Overlap

None for the planned file set. `#3364` (run-migrations.sh postgres-role
ownership guard) is adjacent — this plan deliberately does not edit
`run-migrations.sh` (#8049's scope); no action needed.

## Success Metrics

- Zero contention-shaped reds (`expected N to be K` counter failures with no
  code change) on `main` after merge; any red carries a named cause
  (drift file/function, or contended banner).
- A contended run is self-identifying in its own log — no post-hoc GH-run
  archaeology like the 2026-09-08 investigation.

## Dependencies & Risks

- **Precedent-diff (deepen-plan Phase 4.4) — lock/mutex pattern.**
  In-repo precedent is `scripts/lib/test-contention.sh` `tc_acquire` +
  `session-state.sh` `acquire_lock`: **flock** on a repo-local fd —
  kernel-managed release, deliberately no stale-holder code, banner-first
  (`SIBLING_RUN_DETECTED` / `LOW_TMP_HEADROOM`). This plan's mutex uses
  **`pg_advisory_xact_lock`** — same lifetime-semantics-from-the-kernel
  property (session death = release, no stale-holder code), different
  substrate (database session vs filesystem fd) because the shared resource
  is remote, not local. One intentional divergence: #7553 hardened the local
  banner into a full-gate *refusal* (`test-all.sh` refuses when
  `TC_SIBLING_RUN_COUNT > 0`) — fail-closed. This plan keeps the CI mutex
  **fail-open on wait-budget expiry** by design: a hard refusal would make
  the required check red whenever two isolation-surface runs overlap past
  ~8 min — the same queue-starvation shape measured infeasible in
  #7986/#8048, moved one layer down. Proceed-with-banner preserves the
  status-quo-ante failure mode but announces it, and the fail-closed drift
  probe (M2) is the second net that converts residual drift into a named
  red on authoritative runs.
- **Pooler transaction pinning** is the one unverified mechanism assumption —
  Phase 1.1 positive control gates the wiring; fallback path is documented
  and is coupled (`DATABASE_URL` direct + session lock — the pooler +
  session-lock combination is a known leak class).
- **Fail-closed drift on `push` can red main** if dev is already drifted at
  merge time — intended (named cause, revert pointer), but the PR must verify
  dev is clean before merge or the first post-merge run goes red by design.
- **Waiting costs CI minutes** only when actually contended (~5% of PRs
  touch the surface at all).
- `wg-when-a-workflow-concludes-with-an`: the release step is `if: always()`
  and the holder also dies with the job — no wedge path.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Repo-wide GitHub `concurrency` mutex | Measured infeasible (#7986/#8048): ~22 arrivals/h vs ~4 runs/h, pending-entry eviction reddens the required check |
| Per-run tenant/workspace isolation | Already in force — a no-op presented as a fix |
| Per-run schema / Supabase branch | Migrations hardcode `public.`; new vendor infra for a CI flake |
| Lease-row table (`_ci_suite_lease`) | Needs heartbeat+TTL machinery; advisory-xact lock gets lifetime semantics free from the session; kept as documented fallback |
| Auto-revert drifted objects | Unbounded arbitrary-DDL undo; manual revert per runbook stays the remedy |
| Migrate the suite to a local Supabase-CLI stack (rls-fuzz pattern) | Larger refactor of a suite built for hosted GoTrue/service-role semantics; out of proportion to the observed failure |
| Do nothing — check is green | The cross-ref writer gap is real and timed-proven (2026-09-08); the next overlap re-creates the mystery red |

## References & Research

- Issue: #7964 (this plan); residual apply-race: #8049 (OPEN)
- Prior incidents/fixes: #7055 → PR #7986; #7963/#7958 → PR #7914;
  #5916/#5917; mutex revert #8048; required-check shim #5585
- Post-mortem: `knowledge-base/engineering/operations/post-mortems/tenant-integration-routine-runs-worm-cascade-postmortem.md`
- Learnings: `2026-06-15-tenant-integration-breakage-is-shared-dev-grant-drift-not-code-regression.md`,
  `workflow-patterns/2026-07-03-dev-apply-during-work-broke-shared-tenant-integration-and-sibling-collision.md`
- ADR-133 (advisory-lock + banner philosophy; capacity verdict is
  machine-scoped — method transfers, conclusion does not)
- Files: `.github/workflows/tenant-integration.yml`,
  `.github/actions/dev-migration-drift-probe/action.yml`,
  `scripts/tenant-integration-gate-verdict.sh`,
  `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts`,
  `apps/web-platform/test/supabase-migrations/byok-rpc-markers.json`

## Files to Create

- `scripts/dev-suite-mutex.sh`
- `tests/scripts/test-dev-suite-mutex.sh`

## Files to Edit

- `.github/workflows/tenant-integration.yml`
- `.github/actions/dev-migration-drift-probe/action.yml`
