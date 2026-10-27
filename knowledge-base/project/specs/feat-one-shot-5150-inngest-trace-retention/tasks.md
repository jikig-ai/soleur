# Tasks: infra Inngest trace retention

Plan: `knowledge-base/project/plans/2026-10-27-infra-inngest-trace-retention-plan.md`

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Phase 1: Failing tests

- [ ] 1.1 Write `apps/web-platform/infra/inngest-trace-retention.test.sh` before the runner. Seed a temporary SQLite file with five situations: a finished run older than the window, a finished run newer than the window, an in-flight run older than the window, an old event that in-flight run still references, and an old event with no unfinished run.
- [ ] 1.2 Assert only the safe set is deleted and that children go before anchors. The fixture fails if the safe delete count is zero. A `traces` row with a null `run_id` remains. Assert the Postgres text and the SQLite text name the same status set `(50, 300, 400, 500, 600)` and the same unfinished-run guard.
- [ ] 1.3 Assert no delete names `apps`, `functions`, `worker_connections`, `migrations`, `goose_db_version`, `queue_snapshot_chunks`, or Redis, and that neither file deletes `events` or `history` by age alone.
- [ ] 1.4 Run the test. It fails because the runner does not exist yet. The probe's external binaries are `bash` and `python3`. Do not call `date -d`, `timeout`, `flock`, or `stat -c` from the probe.

## Phase 2: Runner

- [ ] 2.1 Write `apps/web-platform/infra/inngest-trace-retention.sql` and `apps/web-platform/infra/inngest-trace-retention.sqlite.sql`. Pipeline A deletes `spans`, `traces`, `event_batches`, then `trace_runs`. Pipeline B deletes `history`, `function_runs`, then `function_finishes`. Pipeline C deletes an old `events` row only when no unfinished run still references it.
- [ ] 2.2 Write `apps/web-platform/infra/inngest-trace-retention.sh`. Postgres runs when `INNGEST_POSTGRES_URI` is set. SQLite runs when `/var/lib/inngest/main.db` exists. Both can run. The URI stays in the environment. Exit 78 when shell tracing is on. Log counts and the outcome marker only.
- [ ] 2.3 Batch with a cap. Stop when `pg_database_size` grows past the invocation budget. Never issue `VACUUM FULL`. Refuse a sequential scan on `spans`, `traces`, `events`, or `history` and then delete nothing.
- [ ] 2.4 `--ensure-indexes` creates `soleur_trace_runs_status_ended_at`, `soleur_function_finishes_created_at`, and `soleur_traces_run_id` with `CREATE INDEX CONCURRENTLY IF NOT EXISTS` on the session pooler. The unit test never calls it. A traces index that cannot be built for space leaves the explain guard refusing deletes.

## Phase 3: Host wiring

- [ ] 3.1 In `apps/web-platform/infra/inngest-bootstrap.sh`, render `inngest-trace-retention.service` and its timer the same way the heartbeat timer is rendered. `OnCalendar=daily`, `Persistent=false`, `RandomizedDelaySec` bounded. Call `--ensure-indexes` and only then install the timer.
- [ ] 3.2 The service takes `flock -n` on `/run/lock/inngest-trace-retention.lock`. After a successful pass it writes the UTC-date marker through a temp file in the same directory and renames it onto the marker path. A partial temp file is not the marker. Do not add `fdatasync`.
- [ ] 3.3 Add `inngest-trace-retention.service` to both `include_units` and `exclude_units` in `apps/web-platform/infra/vector.toml`. Update the exact pin in `apps/web-platform/test/infra/vector-admission.test.sh`.
- [ ] 3.4 Extend `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` so a missing unit fails the render test. Success logs are priority info. A non-zero exit logs `INNGEST_TRACE_RETENTION_OUTCOME=error` at priority err.

## Phase 4: Docs, ADR, C4, disclosures

- [ ] 4.1 Amend ADR-030. Finished trace and log history is bounded. Redis is not age-deleted. Do not open a new ADR.
- [ ] 4.2 Amend the `inngestPostgres` description in `knowledge-base/engineering/architecture/diagrams/model.c4`. No new element and no new edge. Re-run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 4.3 Rewrite the runbook section `## SQLite event-store retention` in `knowledge-base/engineering/operations/runbooks/inngest-server.md` so it describes the status-gated job and the fail-safe file.
- [ ] 4.4 In the same commit as the mechanism, apply the CLO clause from decision-challenges item T2 (7 days; a host not yet replaced is not yet pruning; Redis is not age-deleted; not Art. 15 or Art. 17) in `docs/legal/data-protection-disclosure.md` §2.3(o) and §2.3(aa), `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, the three mirrors under `plugins/soleur/docs/pages/legal/`, `knowledge-base/legal/article-30-register.md` PA-13 (f) / PA-21 (f) / PA-22 (f) / PA-27 (f) / PA-31 (f), and `knowledge-base/legal/compliance-posture.md` item (iv). Do not move Last Updated. Do not close #10848. If PR #11283 has landed, keep its Supabase recipient words. `scripts/lint-legal-mirror-drift-baseline.sh` must pass.

## Phase 5: Follow-through

- [ ] 5.1 Write `apps/web-platform/infra/inngest-trace-retention-probe.sh`. `--self-test` runs the purge on a temporary SQLite fixture and prints `INNGEST_TRACE_RETENTION_OUTCOME=ok` with no network.
- [ ] 5.2 Write `scripts/followthroughs/inngest-trace-retention-5150.sh` and `scripts/followthroughs/inngest-trace-retention-5150.test.sh`. Exit 2 until a stubbed or live row contains the success marker. Exit 0 only then. A missing credential or a query failure is exit 2. Do not use a colon-question unset check.
- [ ] 5.3 The mechanism PR body starts with the sentence that merging this diff does not mutate the live store, contains `Ref #5150`, and does not contain `Closes #5150`. No package version bump. No Inngest CLI pin bump.
