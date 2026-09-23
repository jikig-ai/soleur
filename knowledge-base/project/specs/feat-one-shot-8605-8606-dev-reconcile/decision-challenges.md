---
feature: feat-one-shot-8605-8606-dev-reconcile
issue: 8605
plan: knowledge-base/project/plans/2026-09-23-fix-dev-ledger-closed-unmerged-reconcile-and-migration-gate-cwd-plan.md
---

# Decision challenges: feat-one-shot-8605-8606-dev-reconcile

These are Taste and User-Challenge findings from plan review (headless one-shot run). They were
recorded here and not applied, so the operator can decide on them at ship time.

## DC-1 (User-Challenge): warning-only `closed` verdict, reconcile by dispatch only

**Source:** code-simplicity review, recommendation 1.

**Plan says:** a closed PR's rows get a `closed` verdict, a warning for 24 h after close and blocking
after. A `pull_request_target: closed` job discards them automatically, and a refusal files an
`action-required` issue.

**Challenge:** keep `closed` a warning (with a Sentry event) forever and drop the close-time job.
Reconcile runs only by dispatch. This removes the new privileged trigger and about 30% of the
workflow and wiring-guard surface.

**Why not applied:** the operator's direction was that closed-PR rows must stop counting as in-flight
with a fail-closed classifier, and it named a close job as the example mechanism. A permanent warning
leaves those rows unowned indefinitely, which is the defect #8605 records (ADR-084: stated direction
is the default).

## DC-2 (Taste): the scheduled probe auto-dispatches the reconcile for `closed` rows

**Source:** CTO devex review, P1 #2.

**Challenge:** have `scheduled-dev-migration-drift.yml` start `dev-ledger-reconcile.yml` for each PR
number in a `closed` line, so rows whose close-time run lost the mutex clear themselves.

**Why not applied:** it needs `actions: write` on a scheduled job. The 600 s mutex wait, the 24 h
grace and the `action-required` issue cover the same failure without a new permission.

## DC-3 (Taste): a separate test suite for the writer

**Source:** CTO devex review, P2 #6.

**Challenge:** create `dev-ledger-reconcile.test.sh` with a shared fixture file, so writer failures
do not read as guard-suite failures in a suite heading toward 150 cases.

**Why not applied:** the existing suite already has the fixture origin, the fakes and the
guard-vacuity-floor promotion; extracting a shared fixture is a refactor of a suite that just
shipped. Revisit if the suite passes about 2,500 lines.

## DC-4 (Taste): `git ls-tree --full-tree` instead of `:(top,literal)`

**Source:** code-simplicity review.

**Challenge:** `--full-tree` resolves from the repo top and prints full names, which removes one
Sharp Edge.

**Why not applied:** `dev-ledger-parity.sh` already reads the same tree with `:(top,literal)`; one
convention across both scripts. Both forms were verified from `apps/web-platform`.

## DC-5 (User-Challenge): degrade a transient PR-state failure to an in-flight warning

**Source:** architecture-strategist, deepen-plan (P1).

**Plan says:** any PR-state lookup the classifier cannot complete exits 2, which the probe reports as
UNCLASSIFIED and which blocks main (after one retry on 5xx/429; 401/403/404 are config errors).

**Challenge:** the lookup can only move a row from in-flight to `closed-grace`, which is itself a
warning for 24 h, so blocking on a failed lookup is stricter than what it measures. A GitHub API
outage or the shared `GITHUB_TOKEN` rate limit would red main while dev holds any open PR's rows.
Map a transient failure to `in-flight pr-state=unverified` (warning, Sentry on the scheduled probe)
and keep config failures closed.

**Why not applied:** the operator's direction was to keep the classifier fail-closed. The trade-off
(an API outage can red main) is recorded in the ADR-061 amendment's Consequences.
