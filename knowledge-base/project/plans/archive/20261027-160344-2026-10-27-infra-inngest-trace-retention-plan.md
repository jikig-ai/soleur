---
title: "infra: self-hosted Inngest event store has no retention bound (PII persists until manual maintenance)"
type: chore
date: 2026-10-27
slug: infra-inngest-trace-retention
branch: feat-one-shot-5150-inngest-trace-retention
issue: 5150
closes: 5150
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# infra: self-hosted Inngest event store has no retention bound (PII persists until manual maintenance)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-27
**Sections enhanced:** 4 (Proposed Solution, Dependencies & Risks, Acceptance Criteria, tasks)
**Research agents used:** none spawned (no subagent tool). In-process: baseline SQL read, mint workflow read, `gh issue view` 5150 / 7465 / 6911, `gh pr view` 11311, `gh api repos/inngest/inngest/pulls/4357`, and the learnings named below.

### Key Improvements

1. The UTC-date marker is written through a temp file and a same-directory rename, so a crash mid-write cannot look like a finished pass.
2. Column types below are taken from the v1.45.1 baseline, including nullable `traces.run_id`. Those rows are not age-deleted.
3. A fixture success must delete at least one row. A live night that deletes zero after catch-up is still success. The close stays on the marker.

### New Considerations Discovered

- The v1.45.1 baseline has no trigger and no policy. The app-database WORM learning does not apply to this project.
- `inngest/inngest` pull 4357 is merged (2026-07-17) and is the retention guide. Mint on this repo publishes an image and does not replace the host. Issue #5150, #7465, and #6911 are open. Draft PR #11311 is open.

## Overview

Finished Inngest trace and log history on Soleur's dedicated store has no expiry. The server pinned in this repo does not delete those rows, and the public legal text says so. This plan ships a status-gated retention job, the same shape Inngest documents for self-hosted Postgres, on a short window aligned with Inngest Cloud's Pro trace-and-log history, for the hosted store every Soleur workspace shares and for the host setup a deployment of this infra follows. Rows an in-flight run still needs stay. Production enablement stays behind the existing host-replace ack. The mechanism PR does not itself prune the live database.

## Problem Statement / Motivation

Issue #5150 is open. Its body still describes SQLite at `/var/lib/inngest` and a bootstrap with no retention flag. That description of the durable path is stale. When `INNGEST_POSTGRES_URI` is set, Inngest v1.45.1 opens Postgres (`pkg/devserver/devserver.go` opens `dbpostgres` when `PostgresURI` is non-empty and opens SQLite only otherwise). `apps/web-platform/infra/inngest-bootstrap.sh` keeps that URI only on the durable arm (`REDIS_READY=1`), whose sentinel is `--postgres-max-open-conns`. The fail-safe arm unsets the URI, and then SQLite at `--sqlite-dir /var/lib/inngest` is the store and can accumulate traces. A leftover `main.db` from a past fail-safe can still hold payloads after the durable arm is back. Redis AOF on the dedicated host is the queue and in-flight run state, not trace history.

There is no `--history-retention` flag in `inngest start` at the pinned CLI (v1.45.1, `apps/web-platform/infra/inngest-cli.provenance.md`). [Inngest's self-host page](https://www.inngest.com/docs/platform-and-operations/self-host-inngest) says Postgres rows for events, runs, and traces are not removed automatically. [Inngest's Postgres retention guide](https://github.com/inngest/inngest/blob/main/docs/POSTGRES_RETENTION.md) (shipped with v1.38.0) is a status-gated SQL runbook, not a server flag. Its worked example uses 30 days. Inngest Cloud's "Trace and log history" is 24 hours (Free), 7 days (Pro), 14 days (Business), up to 365 days (Enterprise) ([limits](https://www.inngest.com/docs/durable-execution/limits)). The brief asks for a few days and the same practice as Inngest Cloud.

Parent-measured, read-only, 2026-10-27, project `soleur-inngest-prd` ref `pigsfuxruiopinouvjwy` (eu-west-1, Postgres 17, Micro, disk 12 GB after an automatic 8 to 12 GB expansion). Not re-queried in this planning pass. Database `postgres` is 9.7 GB. WAL is 0.25 GB. `pg_replication_slots` is empty. `auth.users` has 0 rows. `public.spans` 4.4 GB / 1.74M rows; `public.traces` 2.3 GB / 901k; `public.events` 1.4 GB / 196k (toast is almost all of that); `public.history` 1.3 GB / 1.01M. Rows span 2026-06-18 through 2026-10-27. October 2026 alone is 812k spans. The app project `soleur-web-platform` (`ifsccnjhymdmidffkzhl`) disk is still 8 GB. This work is the Inngest backing project. The only named app is `soleur-runtime`. Two other apps have blank names. Retention is global to the store. Those blank names are not a filter.

Legal text still says the store does not self-expire: Data Protection Disclosure §2.3(o) ("THREE stores, none of which self-expires"), the privacy-policy sentence that the store "performs no automatic deletion", the gdpr-policy "Recipient addresses and routing configuration (ADR-269)" sentence ("no automatic deletion"), Article 30 PA-13 (f) and PA-27 (f), and compliance-posture PA-27 Active Items (iv). #5150 requires those statements to name the concrete bound. PA-13 already retracted a "30-day rolling window via `inngest start --history-retention`" because that flag is set nowhere.

## Proposed Solution

One oneshot on the dedicated Inngest host, rendered by `inngest-bootstrap.sh` the same way `inngest-heartbeat.timer` and `inngest-server-probe.timer` are rendered, runs three status-gated delete pipelines. If `INNGEST_POSTGRES_URI` is set, it runs them against Postgres through that environment variable, never through argv. If `/var/lib/inngest/main.db` exists, it runs the same predicates in SQLite dialect against that file. It does not unlink the SQLite file. It does not touch Redis.

The window is `INNGEST_TRACE_RETENTION_DAYS`, default 7, ruled by the CTO on 2026-10-27 in `knowledge-base/project/specs/feat-one-shot-5150-inngest-trace-retention/decision-challenges.md` (item T1). Seven days is the only Inngest Cloud trace-and-log window that is a few days. It is shorter than the upstream guide's 30-day example and equal to Inngest's `MaxDebouncePeriod` of 7 days. Pipeline A keys off `ended_at`, which is the finish time, so a debounce that ran for 7 days keeps its finished trace for 7 days after it finishes. The debounce payload is copied onto the Redis debounce item, which this job does not delete. Status-gating still keeps the in-flight run. Do not delete traces on start time or `received_at`. Soleur's own `step.sleep` sites are short (`cron-email-ingress-probe` sleeps `15m`; `cron-gh-pages-cert-reissue` polls at `DNS_GATE_INTERVAL_MS` / `POLL_INTERVAL_MS`; `agent-on-spawn-requested` sleeps `SETTLE_GRACE` of `2m`). `event-scheduled-reminder.ts` states it does not use `step.sleepUntil`. Cloud's max function length (30 or 90 days) is why events and history are not deleted by age alone.

Merging this diff does not mutate the live Inngest store. That sentence is the mechanism PR body's first line. `mint-inngest-bootstrap-tag.yml` path-filters `apps/web-platform/infra/inngest*` and `apps/web-platform/infra/vector.*` on push to `main` and publishes an image. It does not replace the live host. `build-inngest-bootstrap-image.yml` publishes only an existing tag, and only on `workflow_dispatch`. The timer, the Vector unit pair, and the first index build reach production only through the existing `apply_target=inngest-host-replace` ack. This plan ships that mechanism. The PR body uses `Ref #5150` and does not use a closing keyword. `scripts/followthroughs/inngest-trace-retention-5150.sh` closes the issue when a Better Stack row shows the success marker after that replace.

Coordination signals, one consumer each. The UTC-date marker is written only by the runner, and only after a successful pass. The write uses a temp file in the same directory and a rename onto the marker path, matching the bootstrap's `mktemp` plus `install` replace pattern. A partial temp file is not the marker. `inngest-bootstrap.sh` has no `fdatasync` call, so this plan does not add one. A later start the same UTC date reads the marker and skips the delete. A start with no marker, or a marker from another date, runs the delete. `flock -n` on `/run/lock/inngest-trace-retention.lock` refuses an overlapping start. It carries no date and drops when the process exits. `INNGEST_POSTGRES_URI` presence means run the Postgres pipelines. The durable arm of `inngest-bootstrap.sh` (`REDIS_READY=1`) is what leaves the variable set. The runner does not decide durability. `/var/lib/inngest/main.db` presence means run the SQLite pipelines against that file. The fail-safe arm is what creates the file. Absence of the file does not mean the durable store is healthy. When both are present, both pipelines run.

### Safe tables and predicates

Terminal `trace_runs.status` integers, from the upstream guide: 50 Overflowed, 300 Completed, 400 Failed, 500 Cancelled, 600 Skipped. Non-terminal: 100 Scheduled, 200 Running. `function_finishes.status` is `varchar`. A finishes row exists only when a run finishes. Do not filter finishes by the integer set. `function_runs.run_id` and `function_finishes.run_id` and `history.run_id` and `events.internal_id` are `bytea`. `trace_runs.run_id`, `traces.run_id`, and `event_batches.run_id` are `char(26)`. `spans.run_id` is `text`. Joins cast to a common text or compare `bytea` to `bytea`. The fixture must use those encodings.

Age alone is not a safe predicate. Children are deleted before their anchor. Deleting the anchor first orphans `spans`, `traces`, and `event_batches`.

Pipeline A, anchor `trace_runs`. Children first, then the anchor: `spans`, `traces`, `event_batches`, then `trace_runs`. A child row is eligible only when its run's `trace_runs` row has `status` in `(50, 300, 400, 500, 600)`, `ended_at` is not null, and `ended_at` is older than the window in unix milliseconds (`ended_at < floor(extract(epoch from clock_timestamp()) * 1000) - days * 86400000`).

Pipeline B, anchor `function_finishes`. Children first, then the anchor: `history`, `function_runs`, then `function_finishes`. Eligible when `function_finishes.created_at` is older than the window (`created_at < clock_timestamp() - make_interval(days => :days)`). A `function_runs` row with no matching `function_finishes` row is still executing and is never deleted. Its `history` rows are never deleted.

Pipeline C, `events`. Eligible when `events.received_at` is older than the window and there is no unfinished `function_runs` row for that event (`function_runs.event_id = events.internal_id` and no `function_finishes` row for that `function_runs.run_id`). One event can fan out to many runs. The event stays while any of those runs is unfinished.

Not deleted, by name, in any statement: `apps`, `functions`, `worker_connections`, `migrations`, `goose_db_version`, `queue_snapshot_chunks`, and anything in Redis. No statement deletes from `events` or `history` using only a timestamp.

SQLite uses the same three pipelines and the same status set and the same unfinished-run guard. The SQL is not a copy of the Postgres text: SQLite has no `make_interval`, and its column affinities come from the v1.45.1 SQLite migrations, which the test reads before it freezes the dialect. Time comparisons use the affinity the fixture just proved.

Each delete is `DELETE FROM <table> WHERE ctid IN (SELECT ctid FROM <eligible> LIMIT :batch)` on Postgres, and an equivalent `rowid` limit on SQLite. One invocation caps the number of batches per statement. A statement that still has eligible rows after that cap holds back only its anchor: capped `spans`, `traces`, or `event_batches` skips `trace_runs`, and capped `history` or `function_runs` skips `function_finishes`. The other statements still run, including `history` and `events`, and the SQLite file still runs. The pass exits non-zero with `reason=batch_cap` and does not write the marker. It records `pg_database_size` at start. If that size grows past a byte budget versus the start, it stops and exits non-zero. Dead tuples from a first catch-up of months of spans can fill a 12 GB volume that already holds a 9.7 GB database before autovacuum reclaims them. The job does not run `VACUUM FULL` and does not resize the disk. Steady state after catch-up is much smaller than the current history. The first catch-up takes many nights because of the batch cap.

Before any delete, the Postgres arm explains the anchor select. A sequential scan on `spans`, `traces`, `events`, or `history` is a non-zero exit and zero deletes. The indexes that make those plans index scans are not in goose migration `000010` (that migration indexes list columns, not `(status, ended_at)`). They are created idempotently, outside goose, with `CREATE INDEX CONCURRENTLY IF NOT EXISTS`, on the session pooler (`:5432`, not `:6543`), only when the ack-gated enable runs. Names: `soleur_trace_runs_status_ended_at` on `(status, ended_at)`, `soleur_function_finishes_created_at` on `(created_at)`, `soleur_traces_run_id` on `(run_id)` when `idx_traces_run_id` is absent, and `soleur_events_received_at` on `events (received_at)`. Existing `idx_spans_run_id`, `idx_function_finishes_run_id`, `idx_function_runs_event_id`, and `idx_history_run_id_created` stay. Concurrent index builds cannot run inside a transaction. They are not added under `apps/web-platform/supabase/migrations/` (wrong database).

### What the disclosures will say

Ruled by the CLO on 2026-10-27 (decision-challenges item T2). The published clause, true on merge day and after the later host-replace, is: finished trace and log history in the dedicated Postgres event store, and in the SQLite file when that file is the store, is removed after 7 days by a status-gated job that leaves in-flight runs in place, but a host that has not yet been replaced onto an image containing that job is not yet pruning. Redis queue and in-flight run state are not deleted by age. This removal is not account deletion and is not a response to an access or erasure request. Do not print "Inngest Cloud Pro" in a public sentence. Do not claim the live host is already pruning. Do not revive `--history-retention`. Do not contradict the §2.3(o) clause that customer email is hashed at the webhook boundary. Do not say account deletion or a DSAR reaches this store (#10848 stays open). If PR #11283 has landed, keep its Supabase Inc / eu-west-1 recipient words and substitute only the retention words. Last Updated does not move (#7465). The public docs and `plugins/soleur/docs/pages/legal/` change in the same commit (`scripts/lint-legal-mirror-drift-baseline.sh`).

### Research Insights

**Best Practices:**

- Children before anchors, status-gated, batched. That is the merged upstream guide (`inngest/inngest` pull 4357, merged 2026-07-17, title "docs: Add guidance on Postgres retention for self-hosting").
- The image build does not deploy. Learning `knowledge-base/project/learnings/workflow-patterns/2026-06-18-inngest-bootstrap-release-tag-then-dispatch-deploy.md` records that split. Its tag-push step is not the current path: `mint-inngest-bootstrap-tag.yml` mints on a `main` push that matches the path filter, and `build-inngest-bootstrap-image.yml` is `workflow_dispatch` of an existing tag. Verified in this pass. Neither file replaces the host.

**Implementation Details:**

The v1.45.1 baseline (`000001_baseline.sql`, read this pass) declares `trace_runs.run_id CHAR(26)`, `trace_runs.ended_at BIGINT NOT NULL`, `trace_runs.status INT NOT NULL`, `spans.run_id TEXT NOT NULL`, `traces.run_id CHAR(26)` with no NOT NULL, `event_batches.run_id CHAR(26) NOT NULL`, `function_finishes.status VARCHAR NOT NULL`, `function_finishes.created_at TIMESTAMP NOT NULL`, `function_finishes.run_id BYTEA`, `function_runs.run_id BYTEA NOT NULL`, `function_runs.event_id BYTEA NOT NULL`, `history.run_id BYTEA NOT NULL`, `events.internal_id BYTEA` (indexed by `idx_events_internal_id`), `events.received_at TIMESTAMP NOT NULL`, `events.event_data VARCHAR`. The same file creates `idx_spans_run_id`, `idx_function_finishes_run_id`, `idx_function_runs_event_id`, `idx_function_runs_run_id`, and `idx_history_run_id_created`. It does not create an index on `trace_runs (status, ended_at)`, `function_finishes (created_at)`, or `traces (run_id)`. It contains no trigger and no policy.

`ended_at` is already NOT NULL, so the `IS NOT NULL` arm is redundant on this baseline and stays, in case a later migration relaxes the column. `traces.run_id` can be null. Those rows do not match the join. Do not age-delete them. A null run id can be a trace still being written.

**Edge Cases:**

- A live night that deletes zero rows after catch-up is success. Learning `knowledge-base/project/learnings/database-issues/2026-06-14-pg-cron-retention-window-exceeding-table-age-is-silent-unbounded-growth.md` is the opposite failure: a window longer than the oldest row reports success and deletes nothing while the table grows. The fixture must contain a row older than the window and must fail if that row survives. The follow-through does not fail a live zero count.
- Learning `knowledge-base/project/learnings/2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` applies to the app database's WORM triggers. This project's baseline has none. Do not add a bypass role for a trigger that is not there.

**References:**

- [POSTGRES_RETENTION.md](https://github.com/inngest/inngest/blob/main/docs/POSTGRES_RETENTION.md)
- `apps/web-platform/infra/inngest-cli.provenance.md` pinned version v1.45.1. The launch line is `exec /usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest "$@"`. No retention flag is on that line.

Surfaces: `docs/legal/data-protection-disclosure.md` §2.3(o) and §2.3(aa); `docs/legal/privacy-policy.md` (the "performs no automatic deletion" sentence); `docs/legal/gdpr-policy.md` (the ADR-269 recipient-address sentence); `knowledge-base/legal/article-30-register.md` PA-13 (f), PA-21 (f), PA-22 (f), PA-27 (f), and PA-31 (f); `knowledge-base/legal/compliance-posture.md` PA-27 Active Items (iv); the three plugin legal mirrors.

## Technical Considerations

- Architecture: amend ADR-030. The substrate decision already records self-hosted Postgres plus Redis and records no automatic deletion. The amendment records that finished trace and log history is now status-gated and bounded, and that Redis is still not age-deleted. Do not open a new ADR. The ADR corpus rejects Inngest Cloud as the substrate, not a self-hosted purge.
- C4: read of `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, and `spec.c4`. External human actors unchanged. External systems unchanged. Containers `inngest`, `inngestPostgres`, and `inngestRedis` already exist. `views.c4` already includes all three. `spec.c4` defines element kinds and has no `inngest` element of its own. The only edit is the `inngestPostgres` description, which today says "Inngest config + run history" with no bound. Add that finished trace and history rows are removed by the status-gated job on the existing host. No new element and no new edge. Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` in the work phase.
- Performance: first catch-up is batch-capped because a 9.7 GB database on a 12 GB disk can run out of space on dead tuples. October 2026 alone was 812k spans, so a 7-day steady state is a fraction of the current table.
- Security: the URI stays in the environment. The script exits 78 when shell tracing is on, matching the follow-through `EX_CONFIG` contract, so a traced shell cannot print the URI. Log lines carry counts and the outcome marker only.
- NFR: `knowledge-base/engineering/architecture/nfr-register.md` NFR-040 ("Data Retention Policy") lists Supabase PostgreSQL as not implemented. This job is the retention control for the Inngest project, not for the app project. The register row for the app database stays as it is.
- Delivery: no new Terraform root and no new `terraform_data` provisioner. The timer is role-only on the dedicated host via the baked bootstrap. Host fan-out and twin parity are not the delivery path.
- Code-review overlap: 99 open issues labeled `code-review` were scanned for the planned paths (`inngest-bootstrap.sh`, `vector.toml`, `inngest-server.md`, the three legal docs, the article-30 register, the compliance posture, ADR-030). None cited them. Overlap is none.
- Tests come before the implementation that makes them pass. No package version bump. No Inngest pin bump.

### Attack surface

The job is a new writer on the Inngest Postgres owner role and, when the file exists, on the host SQLite file. It is not a new network listener. The dangerous paths are an age-only delete, an anchor deleted before its children, a delete of `events` or `history` that an unfinished run still references, and a log line that copies `event_data`. The guard and the fixture tests below are the checks on those paths. Redis, the app tables, and goose's version table are out of the statement list.

## Infrastructure

The timer is a unit file rendered by `apps/web-platform/infra/inngest-bootstrap.sh`, which is copied into the OCI image by the existing `mint-inngest-bootstrap-tag.yml` path filter (`apps/web-platform/infra/inngest*` and `apps/web-platform/infra/vector.*`). The image build is `build-inngest-bootstrap-image.yml`. The live host receives that image only through the existing `apply_target=inngest-host-replace` dispatch. No new Terraform root, no new provisioner, no secret write, and no dashboard step. Index creation uses the same URI the server already has, from the environment, and runs only on that ack-gated enable.

## Research Insights

### Premise validation

#5150 is open. `closedByPullRequestsReferences` is empty. The only open pull request naming 5150 is draft #11311 on this branch. The issue's SQLite-only premise does not describe the durable arm. The durable arm is Postgres when `INNGEST_POSTGRES_URI` is set. SQLite is the fail-safe and any leftover `main.db`. `--history-retention` is absent at v1.45.1. The upstream project now documents a status-gated SQL runbook and still ships no server-side retention flag. The legal "no automatic deletion" sentences still match the code, because no purge exists yet.

### Property list

1. Finished trace and log history expires after a few days on Soleur's own deployment, the same practice as Inngest Cloud.
2. In-flight runs (sleep, wait, debounce still open) are not broken.
3. The hosted shared store and the setup a deployment of this infra follows both get the bound.
4. The legal disclosures name the concrete bound.
5. The mechanism is durable. A one-off delete of production is not the deliverable. Production enablement stays behind the existing prod-ack.
6. The SQLite fail-safe is covered, because it can accumulate traces.

### Cut list

- Age-only delete of `events` or `history`. Buys a smaller disk. Breaks property 2. The upstream guide already refuses it.
- A one-off production delete. Buys an immediate shrink. Breaks property 5.
- A `--history-retention` flag. Absent at v1.45.1. The upstream guide says there is no retention flag and no in-server garbage collection. Article 30 already records that the flag is set nowhere.
- Pruning Redis. Redis holds the queue and in-flight run state, not finished traces. Breaks property 2.
- A new customer skill. No skill under `plugins/soleur/skills/` installs this store. `plugins/soleur/skills/trigger-cron/SKILL.md` fires crons. `operator-bootstrap` is post-merge staged scripts. The setup deployers follow is `inngest-bootstrap.sh` plus the runbook section `## SQLite event-store retention`.
- `VACUUM FULL` or a disk resize. The brief forbids the resize. `VACUUM FULL` rewrites the table and needs a second copy of a multi-gigabyte relation on a volume with about 2 GB free.
- `pg_cron` as the only mechanism. It can reach Postgres. It cannot open the host SQLite file. A workflow in GitHub Actions has the same hole unless it logs into the host, which the runbook forbids.
- An Inngest cron function as the scheduler. App crons are the canonical scheduled-work shape, and they cannot open `/var/lib/inngest/main.db`. They also cannot run when the store they are cleaning is the thing that is full.

### Value

Unbounded growth already forced an automatic disk expansion from 8 GB to 12 GB. The four history tables are the bulk of the 9.7 GB database. October 2026 alone accounts for 812k spans. Source: the parent read-only measurement dated 2026-10-27.

### Community and overlap

No project stack signature from the community-discovery table is present (no `pubspec.yaml`, `Cargo.toml`, `mix.exs`, `go.mod`, `Package.swift`, `build.gradle`, or `composer.json`). The discovery phase is skipped. The functional-discovery agent was not spawned (no subagent tool in this harness). In-process, no installed skill configures Inngest retention. Nothing is installed from a community registry.

### Network-outage hypothesis

The feature text does not match the SSH, timeout, or terraform-apply-plus-provisioner triggers. Skipped.

### Skill-description budget

No `SKILL.md` description is edited. Skipped.

## Files to Create

- `apps/web-platform/infra/inngest-trace-retention.sql` — Postgres pipelines A, B, and C, batched, children before anchors.
- `apps/web-platform/infra/inngest-trace-retention.sqlite.sql` — the same pipelines in SQLite dialect.
- `apps/web-platform/infra/inngest-trace-retention.sh` — runner. Postgres when `INNGEST_POSTGRES_URI` is set. SQLite when `main.db` exists. Batch cap, size budget, explain fail-closed, flock, xtrace refusal, count-only logs.
- `apps/web-platform/infra/inngest-trace-retention.test.sh` — fixture tests and the SQL guard. Written before the runner.
- `apps/web-platform/infra/inngest-trace-retention-probe.sh` — local self-test that prints the success marker. This is the discoverability command. Its external binaries are `bash` and `python3` (stdlib `sqlite3`). It does not call `date -d`, `timeout`, `flock`, or `stat -c`. `flock` belongs only to the Linux host unit.
- `scripts/followthroughs/inngest-trace-retention-5150.sh` — closes #5150 only after the live marker.
- `scripts/followthroughs/inngest-trace-retention-5150.test.sh` — stubbed Better Stack reader. Registered the same way sibling `scripts/followthroughs/*.test.sh` files are registered.

## Files to Edit

- `apps/web-platform/infra/inngest-bootstrap.sh` — render and enable `inngest-trace-retention.service` and `.timer`, copying the SQL and the runner into the image.
- `apps/web-platform/infra/vector.toml` — add `inngest-trace-retention.service` to both `include_units` and `exclude_units`.
- `apps/web-platform/test/infra/vector-admission.test.sh` — the exact `include_units` pin and the set-equality pin.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — assert the new unit is rendered.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — replace the superseded procedure under `## SQLite event-store retention` with the status-gated job, including the fail-safe file.
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — amendment. Finished trace and log history is bounded. Redis is not.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `inngestPostgres` description only.
- `docs/legal/data-protection-disclosure.md` — §2.3(o) names the bound.
- `docs/legal/privacy-policy.md` — the "performs no automatic deletion" sentence names the bound.
- `docs/legal/gdpr-policy.md` — the ADR-269 sentence names the bound.
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — mirror, same commit.
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — mirror, same commit.
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` — mirror, same commit.
- `knowledge-base/legal/article-30-register.md` — PA-13 (f), PA-21 (f), PA-22 (f), PA-27 (f), and PA-31 (f) where they describe this store.
- `knowledge-base/legal/compliance-posture.md` — PA-27 Active Items (iv) names the bound and points at the job.

## Implementation Phases

### Phase 1: Failing tests

Write `inngest-trace-retention.test.sh` against a temporary SQLite file and against the Postgres SQL text. Seed five situations: a finished run older than the window, a finished run newer than the window, an in-flight run older than the window (status 100 or 200, or a `function_runs` row with no `function_finishes` row), an old event referenced by that in-flight run, and an old event with no unfinished run. Assert only the safe set is deleted, and that children go before anchors. Assert the Postgres and SQLite texts name the same status set and the same unfinished-run guard. Assert no delete names Redis or the protected tables. Run the test. It fails because the runner does not exist yet.

### Phase 2: Runner

Write the two SQL files and the shell runner until Phase 1 is green. Index creation is a separate function the runner calls only when asked (`--ensure-indexes`), so the unit test never contacts a live project. The host enable path calls `--ensure-indexes` and only then installs the timer, so the first calendar fire is not an explain-refusal storm. A `traces` index on a 2.3 GB table can fail while free space is about 2 GB. That failure leaves the explain guard refusing deletes. The plan does not resize the disk. `idx_spans_run_id` already exists, so the spans delete does not need a new index.

### Phase 3: Host wiring

Render the timer and the oneshot service from the bootstrap, following the heartbeat timer's install path inside that script. `OnCalendar=daily`, `Persistent=false` so a fresh host does not fire a catch-up during boot, `RandomizedDelaySec` bounded. The service takes `flock -n` on `/run/lock/inngest-trace-retention.lock`, and writes a UTC-date marker only after a successful pass, so a failed pass is retried and a second successful start the same UTC date does not delete again. Extend the cloud-init bootstrap test and the Vector admission test. Add the unit to both Vector lists. Success logs are priority info, so they ship only because the unit is on `include_units`. A non-zero exit logs one `INNGEST_TRACE_RETENTION_OUTCOME=error` line at priority err, with counts only, so the existing priority arm can see it.

### Phase 4: Docs, ADR, C4, disclosures

Amend ADR-030, the C4 description, the runbook section, the legal surfaces, and the plugin mirror in one commit with the mechanism. Wording matches the pending legal ruling's assumed day count until the CLO replaces it. Do not publish a bound the job does not implement, and do not implement a job the disclosure does not name.

### Phase 5: Follow-through

The probe script's `--self-test` runs the purge on a temporary SQLite fixture and prints `INNGEST_TRACE_RETENTION_OUTCOME=ok`. The follow-through script exits 2 until a Better Stack row from the new unit contains that marker, and exits 0 only then. It treats a missing credential or a query failure as exit 2, never as success. It does not use a colon-question unset check. The positive control is a row the old image cannot emit.

## Alternative Approaches Considered

- Upstream 30-day example as the default. Safer for a full-length debounce's finished trace, looser than "a few days" and looser than Cloud Pro. Left to the pending technical ruling. The code reads the day count from one variable so a ruling change is one assignment.
- Delete the SQLite file outright when the durable arm is up. A degraded process may still have it open. Row deletes with the same predicate are enough.
- New ADR instead of amending ADR-030. The retention fact belongs on the substrate decision. A second ADR would split one story.
- Customer-facing skill. Nothing in the plugin install path runs an Inngest server. Cut.

## User-Brand Impact

- **If this lands broken, the user experiences:** in-flight sleeps, waits, and armed runs on the one shared scheduler can be dropped for every workspace, because every tenant's events sit in the same Inngest project.
- **If this leaks, the user's data is exposed via:** a log line that copied event payloads would put subject, sender, and recipients into the Better Stack source. The job logs counts only.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** one wrong predicate hits every tenant on the shared store, which is wider than a single-user incident. `requires_cpo_signoff` stays false because that flag is for the single-user tier.

## Observability

```yaml
liveness_signal:
  what: "journal line INNGEST_TRACE_RETENTION_OUTCOME=ok from inngest-trace-retention.service, shipped by vector source inngest_journald once the unit is on include_units"
  cadence: "daily, after OnCalendar fires"
  alert_target: "existing soleur-inngest vector source; a priority-err outcome=error line uses the source that already admits priority 3-4 from any unit"
  configured_in: "apps/web-platform/infra/vector.toml include_units and exclude_units"
error_reporting:
  destination: "Better Stack via the inngest host vector source; the job does not open a Sentry SDK"
  fail_loud: "INNGEST_TRACE_RETENTION_OUTCOME=error"
failure_modes:
  - mode: "runner exits non-zero, or the explain guard refuses a sequential scan, or the size budget trips"
    detection: "the outcome=error journal line, and the absence of outcome=ok for that UTC date"
    alert_route: "the existing inngest vector source's current route; this change adds no new monitor"
  - mode: "timer unit absent because the host image predates the merge"
    detection: "the follow-through stays at exit 2 until a row with the success marker exists; the mechanism PR does not close the issue"
    alert_route: "scripts/followthroughs/inngest-trace-retention-5150.sh via the existing follow-through sweeper"
logs:
  where: "journald unit inngest-trace-retention.service, then vector on the inngest host"
  retention: "Better Stack retention of the inngest source; the job's own rows are counts, not payloads"
discoverability_test:
  command: bash apps/web-platform/infra/inngest-trace-retention-probe.sh --self-test
  expected_output: "INNGEST_TRACE_RETENTION_OUTCOME=ok"
```

Check 10 runs the command in a sandbox with no credentials. The probe uses a temporary SQLite file and finishes well inside 15 seconds. It does not query Better Stack. The live marker is what the follow-through reads after the host replace.

## Encryption Posture

This change adds no store and no connection. The job writes to two stores that already exist, and it opens the Postgres store through the URI the Inngest server already uses (`inngest.tf` anchor `INNGEST_POSTGRES_URI (prd)`). It does not mint a URI and does not change TLS parameters. That URI is a Doppler value, not a Terraform resource, for the reason already recorded on that anchor.

```yaml
at_rest:
  - store: supabase.inngest
    mechanism: provider-managed:supabase-postgres-aes256
    evidence: "scripts/encryption-posture-ledger.json store supabase.inngest; attestation_url https://supabase.com/docs/guides/security; retrieved_on 2026-07-24"
    defends_against: "physical-media compromise of the managed Postgres storage"
    does_not_defend: "a leaked INNGEST_POSTGRES_URI, an owner-role query, or a bad retention predicate"
    disclosed_as: "docs/legal/data-protection-disclosure.md section 2.3(o)"
    live_verification: "unavailable:named SOC 2 attestation formalization pending; tracked #6911"
  - store: hcloud_volume.inngest_redis_luks
    mechanism: luks
    evidence: "apps/web-platform/infra/inngest-redis-luks.tf resource hcloud_volume.inngest_redis_luks"
    defends_against: "a seized disk or a raw snapshot of the Redis volume"
    does_not_defend: "a leaked passphrase, a process on the unlocked host, or loss of the sole copy"
    disclosed_as: "docs/legal/data-protection-disclosure.md section 2.3(o) names the Redis append-only file; this job does not delete it"
    live_verification: "unavailable:the hourly probe proves which device backs the data path, not the cipher; ledger row hcloud_volume.inngest_redis_luks"
in_transit:
  - connection: "inngest-trace-retention.service -> soleur-inngest-prd session pooler :5432"
    enforced_at: "apps/web-platform/infra/inngest.tf anchor INNGEST_POSTGRES_URI (prd); the runner passes that environment variable through and does not rewrite it"
    tls: "TLS as the existing pooler URI already negotiates; this plan does not add a second connection"
    cert_verification: off
    does_not_defend: "a URI that uses sslmode=require encrypts without verifying the server certificate; this plan does not claim verify-full because the URI is not in the repo and must not be printed"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "The runner reuses the existing URI. Recording certificate verification as off avoids claiming a pin this plan did not measure. The job adds no new hop."
  tracking_issue: "#6911"
  reevaluate_when: "the URI is shown to set sslmode=verify-full, or the #6911 attestation records customer-visible certificate verification"
  expires_on: "2027-01-25"
```

The SQLite file, when present, stays on the host root disk. This plan does not create that file and does not change its at-rest mechanism. The legal sentence names it as the fail-safe store.

## Task Design

```yaml
tasks:
  - task: inngest-trace-retention
    trigger: "systemd timer OnCalendar=daily on the dedicated inngest host"
    services: "Postgres via INNGEST_POSTGRES_URI when set; SQLite file /var/lib/inngest/main.db when present; journald"
    next: "nothing"
    human_reentry: "stop the timer unit and the service unit named inngest-trace-retention; the flock and the UTC-date marker keep a later start the same day from deleting twice"
    dedupe: "flock -n on /run/lock/inngest-trace-retention.lock plus a UTC-date marker written only after a successful pass, so a second start the same day exits without deleting"
    source_dedupe: "not a ticket source"
```

## Downtime & Cutover

Merging this diff does not take the scheduler offline. The mint publishes an image. The live host changes only on the existing ack-gated `apply_target=inngest-host-replace` dispatch, which births a fresh host (ADR-100) and then cuts over. That dispatch is the sign-off, and its window is the one that path already bounds. This plan adds no second window.

Offline-inducing operations considered and rejected: a non-concurrent index build, which would lock `spans` or `traces` for the build; `VACUUM FULL`, which rewrites the relation and needs a second copy; and an in-place restart of the running server. The default path is `CREATE INDEX CONCURRENTLY` on the session pooler, short batched deletes, and the existing fresh-host birth. `Persistent=false` keeps the new timer from firing a catch-up while that host is still booting.

Per stage: the mechanism PR is verified by the fixture suite before merge. The image publish is the mint. The host birth is verified by the existing replace path's own checks. Rollback of a bad image is another replace onto the previous `vinngest` tag. The retention job has no separate maintenance window.

## Guard Contract

### Guard 1 — status-gated retention SQL

**Property.** Every delete the retention runner executes removes only rows that the safe predicate allows, and it removes children before their anchor.

**Assembly.** The runner executes every file matching `inngest-trace-retention*.sql` beside itself. The guard walks that same glob and fails when the number of files it checked is not the glob count, so a second or third dialect file is in scope the moment the runner would execute it. The chokepoint is that glob. A delete that lives outside it is a bug in the runner, and the runner test asserts the runner's executed list equals the glob.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `status IN (50, 300, 400, 500, 600)` from the Postgres anchor so an age match alone deletes a status-100 run | RED |
| 2 | Point the guard at an empty directory so it checks zero files and would otherwise exit 0 | RED |
| 3 | Leave the Postgres file compliant and remove the unfinished-run guard from the SQLite `events` delete only | RED |
| 4 | Move the `trace_runs` delete above the `spans` delete | RED |
| 5 | Keep `received_at` older than the window on the `events` delete and drop the `NOT EXISTS` unfinished-run guard | RED |
| 6 | Edit the test so it ignores the guard's exit status and always reports success | RED |
| 7 | Add a third SQL file that repeats the same predicates with different whitespace and a comment | PASS |
| 8 | After the legal sentence is updated, confirm the SQL guard does not read that sentence; a disclosure-only edit stays green, and row 5 still goes red | RED on row 5 |

**Anchor.** The integer status set is pinned to Inngest v1.45.1 `trace_runs` statuses named in the upstream retention guide linked from References. The guard enforces that the Postgres file and every other glob match contain the same set. One diff can edit both files, so this proves cross-dialect consistency, not integrity against a future upstream status code. The pin comment names v1.45.1.

## Domain Review

Subagents are not available in this harness. Engineering, legal, and operations leaders were not spawned. The notes below are planner notes, not leader rulings. The parent spawns the CTO and the CLO before work. Issue #5150 was verified open in this session.

### Engineering

The change is an infra retention job on the existing Inngest host plus an ADR-030 amendment and a C4 description edit. Lane tokens `infra` and `data` force `cross-domain`. No new vendor.

### Legal

Privacy, the Data Protection Disclosure, the Article 30 register, and the compliance posture all change. The CLO ruling is pending. The plan still specifies the disclosure change so the work phase does not drop it.

### Operations

The timer is a host process on a host the repo already operates. No new vendor and no new procurement. The runbook section is the setup a deployment follows.

### Product

No new UI page, no route, and no component. Product/UX gate does not fire.

## GDPR / Compliance Gate

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

The canonical path regex matches because the plan creates `*.sql` files. The gate is advisory. It does not block, and it does not write `compliance-posture.md` by itself. Column values are not included. Names already published in the legal docs (`event_data`, subject, sender, recipients) are names, not row contents. No Art. 9 special-category column is added. No Critical finding. No escalation block.

### `GDPR-Art-5e` — retention metadata for an existing event store

**Severity:** Important
**Article:** Art. 5(1)(e)
**Location:** plan section Proposed Solution
**Pattern matched:** new SQL that deletes existing event-store rows; the current legal text says there is no automatic deletion
**Why this matters:** the store already holds payloads. The missing control is a bound. The job is that bound.
**What to do:** ship the status-gated job and name the day count in the disclosures listed under Proposed Solution. Do not add a new processing purpose.

### `GDPR-Art-6` — no new column

**Severity:** Suggestion
**Article:** Art. 6
**Location:** plan section Files to Create
**Pattern matched:** `*.sql` with no new table and no lawful-basis annotation
**Why this matters:** the Art. 6 check fires on new columns. This SQL deletes. It does not add a column.
**What to do:** do not invent a lawful-basis annotation on a delete script. The existing activities keep their recorded bases.

### `GDPR-Art-17` — not an erasure cascade

**Severity:** Suggestion
**Article:** Art. 17
**Location:** plan section Safe tables and predicates
**Pattern matched:** `DELETE` without a cascade to `public.users`
**Why this matters:** account erasure and retention expiry are different predicates. This job does not claim to satisfy an Article 17 request.
**What to do:** leave the app-database erasure cascade alone. Do not tell the disclosure that account deletion now clears Inngest.

### `GDPR-Art-17-caller` — no new restrict foreign key

**Severity:** Suggestion
**Article:** Art. 17
**Location:** plan section Files to Create
**Pattern matched:** no new anonymise RPC
**Why this matters:** the caller-site check does not fire.
**What to do:** no RPC wiring.

### `GDPR-Chapter-V` — no new vendor

**Severity:** Suggestion
**Article:** Art. 44–49
**Location:** plan section Domain Review
**Pattern matched:** no new non-EEA SDK or env var
**Why this matters:** Supabase EU and Better Stack are already recorded. This job adds no processor.
**What to do:** do not add a vendor row.

Corpus staleness banners, if the gate prints them at work time, do not pause this change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | [issue #5150] "implement an operator-side store maintenance bound (cron pruning `/var/lib/inngest` rows older than N days, or the Inngest server's own pruning mechanism if one ships)" | Phase 2 runner plus Phase 3 timer; the SQLite path is the fail-safe half, Postgres is the durable half, because the issue's path is not the live primary store | mapped |
| 2 | [issue #5150] "tighten DPD §2.3(o) + PA-27/PA-21/PA-22 retention cells from \"until operator-side maintenance\" to the concrete bound" | Phase 4 disclosures, including PA-13 (f) where it restates the same store | mapped |
| 3 | [brief] "Update Soleur's setup and skills so finished Inngest traces expire after a few days, the same practice as Inngest Cloud, for Soleur's own deployment and for other Soleur users." | Phase 3 bootstrap and runbook; hosted store is the shared project; no new skill (Cut List) | mapped |
| 4 | [brief] "Do not delete rows an in-flight run still needs." | Safe tables and predicates, Pipelines A–C | mapped |
| 5 | [brief] "The plan must say exactly which tables and which row predicate are safe." | Proposed Solution, Safe tables and predicates | mapped |
| 6 | [brief] "A SQLite fail-safe may still exist; if it can also accumulate traces, the plan must cover it too." | SQLite dialect file and the runner's `main.db` arm | mapped |
| 7 | [brief] "#5150 requires those statements to name the concrete bound. That disclosure update is in scope, not a follow-up." | Phase 4, same commit as the mechanism | mapped |
| 8 | [brief] "Production application of the job, if it is a prod write, stays behind the repo's existing prod-ack gate; the plan ships the mechanism." | Proposed Solution delivery paragraph; PR body uses `Ref #5150`; follow-through closes the issue | mapped |
| 9 | [brief] "Tests before implementation. No version bump." | Phase 1 before Phase 2; Technical Considerations, no pin bump and no package bump | mapped |
| 10 | [brief] "write a decision-challenges.md row with Class `technical` and Ruling `pending - assumed: 7 days for finished trace and log history (Inngest Cloud Pro trace-and-log window; \"a few days\"), deleting only rows no in-flight run still needs`" | decision-challenges file written with that ruling cell | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `inngest-trace-retention.sql` | "The plan must say exactly which tables and which row predicate are safe." | asked |
| `inngest-trace-retention.sqlite.sql` | "A SQLite fail-safe may still exist; if it can also accumulate traces, the plan must cover it too." | asked |
| `inngest-trace-retention.sh` | "implement an operator-side store maintenance bound (cron pruning `/var/lib/inngest` rows older than N days, or the Inngest server's own pruning mechanism if one ships)" | asked |
| `inngest-trace-retention.test.sh` | "Tests before implementation." | asked |
| `inngest-trace-retention-probe.sh` | "Tests before implementation." | inferred — justification: preflight Check 10 executes `discoverability_test.command` inside 15 seconds with an allowlisted first token, and a fixture probe is the command that can satisfy that without a live host |
| `inngest-trace-retention-5150.sh` | "Production application of the job, if it is a prod write, stays behind the repo's existing prod-ack gate; the plan ships the mechanism." | inferred — justification: the follow-through convention is how an issue stays open until a live marker exists, so a merge of inert code cannot close #5150 |
| `inngest-trace-retention-5150.test.sh` | "Tests before implementation." | inferred — justification: a follow-through that exits 0 on an empty read would close the issue; the sibling test pattern is what stops that |
| `inngest-bootstrap.sh` | "for Soleur's own deployment and for other Soleur users" | asked |
| `vector.toml` | "for Soleur's own deployment and for other Soleur users" | inferred — justification: info logs from a unit absent from both `include_units` and `exclude_units` never reach the inngest vector source, so the success marker the follow-through reads would not exist |
| `vector-admission.test.sh` | "Tests before implementation." | inferred — justification: the test pins the exact include list, and adding a unit without editing the pin leaves CI red |
| `cloud-init-inngest-bootstrap.test.sh` | "Tests before implementation." | inferred — justification: the bootstrap render test is what fails if the unit is not copied into the image |
| `inngest-server.md` | "for Soleur's own deployment and for other Soleur users" | asked |
| ADR-030 | "the same practice as Inngest Cloud" | inferred — justification: ADR-030 is the substrate decision that currently records no automatic deletion; leaving it unchanged falsifies the decision record the moment the job exists |
| `model.c4` | "the same practice as Inngest Cloud" | inferred — justification: the `inngestPostgres` description states unbounded run history; a description-only edit keeps cardinality stable |
| `data-protection-disclosure.md` and its plugin mirror | "tighten DPD §2.3(o) + PA-27/PA-21/PA-22 retention cells from \"until operator-side maintenance\" to the concrete bound" | asked |
| `privacy-policy.md` and its plugin mirror | "#5150 requires those statements to name the concrete bound." | asked |
| `gdpr-policy.md` and its plugin mirror | "#5150 requires those statements to name the concrete bound." | asked |
| `article-30-register.md` | "tighten DPD §2.3(o) + PA-27/PA-21/PA-22 retention cells from \"until operator-side maintenance\" to the concrete bound" | asked |
| `compliance-posture.md` | "That disclosure update is in scope, not a follow-up." | asked |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `plugins/soleur`, `docs`, `knowledge-base`, `scripts`
- Planned files: 22 | Estimated changed lines: 1540
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the file count is under 25 and the root count and the line estimate are over the threshold, so the default offer is a split between the host job and the legal text. That split is rejected because one half would publish a bound the job does not enforce and the other half would enforce a job the disclosure does not name. The issue exists to close that gap. The plugin mirror has to land in the same commit as `docs/legal` or `scripts/lint-legal-mirror-drift-baseline.sh` fails.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] A temporary SQLite fixture with the five situations in Phase 1 loses only the finished run older than the window, its children, and the old event that no unfinished run references. The fixture fails if that delete count is zero. A `traces` row with a null `run_id` remains.
- [ ] The same fixture keeps the in-flight run, its history, and the old event that run still references.
- [ ] The Postgres SQL and the SQLite SQL name the same terminal status set `(50, 300, 400, 500, 600)` and the same unfinished-run guard, and neither deletes `events` or `history` by age alone.
- [ ] No delete statement names `apps`, `functions`, `worker_connections`, `migrations`, `goose_db_version`, `queue_snapshot_chunks`, or Redis.
- [ ] The runner refuses to delete when the explain plan is a sequential scan on `spans`, `traces`, `events`, or `history`.
- [ ] The runner stops when `pg_database_size` grows past the invocation budget, and it never issues `VACUUM FULL`.
- [ ] `bash apps/web-platform/infra/inngest-trace-retention-probe.sh --self-test` prints `INNGEST_TRACE_RETENTION_OUTCOME=ok` and does not contact a network.
- [ ] The bootstrap renders `inngest-trace-retention.service` and `.timer`, and `vector.toml` lists that service in both `include_units` and `exclude_units`.
- [ ] Log lines from the runner contain counts and the outcome marker and do not contain `event_data`.
- [ ] DPD §2.3(o) and §2.3(aa), the privacy-policy store sentence, the gdpr-policy ADR-269 sentence, Article 30 PA-13 (f) / PA-21 (f) / PA-22 (f) / PA-27 (f) / PA-31 (f) where they describe this store, compliance-posture item (iv), and the three plugin mirrors name the 7-day bound and say a host not yet replaced onto an image containing the job is not yet pruning. Redis stays described as not age-deleted. Last Updated does not move. #10848 stays open.
- [ ] ADR-030's amendment states the bound. The `inngestPostgres` description states it. `bash plugins/soleur/test/c4-count-parity.test.sh` passes.
- [ ] The runbook section `## SQLite event-store retention` describes the status-gated job and the fail-safe file.
- [ ] No `package.json` version and no Inngest CLI pin changes.
- [ ] The mechanism PR body starts with the sentence that merging this diff does not mutate the live store, contains `Ref #5150`, and does not contain `Closes #5150`. Against a stubbed log query, the follow-through exits 0 only when the success marker is present and exits 2 when it is absent.

### Post-merge (operator)

- [ ] No new hand step. The live timer arrives only through the existing ack-gated `apply_target=inngest-host-replace` dispatch. The follow-through sweeper is what later reads the marker. Automation: that dispatch and the sweeper already exist.

## Test Scenarios

- **unit.** Given a finished run whose `ended_at` is older than 7 days and whose status is 300, when the runner executes, then its spans, traces, event batches, history, function_runs, function_finishes, and trace_runs rows are gone, and an unrelated fresh finished run remains.
- **unit.** Given a run with status 200 and `ended_at` older than 7 days, when the runner executes, then that run and its children remain.
- **unit.** Given a `function_runs` row with no `function_finishes` row and an event older than 7 days that it references, when the runner executes, then the event, the function_runs row, and its history remain.
- **unit.** Given an event older than 7 days that no unfinished run references, when the runner executes, then the event is deleted.
- **unit.** Given the Postgres file deletes `trace_runs` before `spans`, when the guard runs, then it exits non-zero.
- **unit.** Given the guard is pointed at a directory with no SQL files, when it runs, then it exits non-zero.
- **unit.** Given a third SQL file with the same predicates and extra comments, when the guard runs, then it exits zero.
- **integration.** Given the bootstrap render fixture, when the cloud-init test runs, then the unit files exist and the Vector lists both contain `inngest-trace-retention.service`.
- **unit.** Given a stubbed log query with no success marker, when the follow-through runs, then it exits 2. Given a stubbed row containing `INNGEST_TRACE_RETENTION_OUTCOME=ok` from the new unit, when it runs, then it exits 0.

No end-to-end scenario. The live host replace is outside this mechanism change. No scenario is e2e, so no pyramid-justified marker is required.

## Success Metrics

- The fixture suite shows zero deleted rows for every in-flight situation and a full delete for the one safe situation.
- After the ack-gated replace, one journal line per successful night carries `INNGEST_TRACE_RETENTION_OUTCOME=ok` and a count. The issue closes only when the follow-through sees that line.
- Disk shrink is not a success metric of the mechanism PR. Dead tuples reclaim on autovacuum, and the first catch-up is multi-night by design.

## Dependencies & Risks

- The 7-day window is an assumption until the CTO rules. The upstream guide's example is 30 days, and `MaxDebouncePeriod` is 7 days. The variable is the only place the number lives.
- Disclosure wording is an assumption until the CLO rules. The work phase uses the assumed sentence and does not block on a question to anyone outside the parent pipeline.
- First-night dead-tuple growth on a 12 GB volume with a 9.7 GB database can trip the size budget and leave most rows in place. That is the intended stop, not a failed predicate.
- `spans.run_id` text versus `trace_runs.run_id` char(26), and `bytea` run ids on history, will drop rows or delete the wrong rows if the SQL casts them differently from the fixture. The fixture uses the encodings from the v1.45.1 baseline.
- A host that is on the fail-safe and the durable URI at the same time is not a supported configuration. The runner still cleans both if both are present, so a leftover file cannot keep payloads after the durable arm returns.
- Index creation is production DDL and waits for the same ack as the first timer enable. Until those indexes exist, the explain guard deletes nothing. That is fail-closed. The `traces` index is the one most likely to miss, because the table is 2.3 GB and free space is about 2 GB.
- Scheduled-work precedent: 57 files match `apps/web-platform/server/inngest/functions/cron-`, and 22 workflows match `.github/workflows/scheduled-`. Neither shape is used. An app cron cannot open the host SQLite file and cannot run when the store is the outage. The host-timer precedent is `inngest-heartbeat.timer` and `inngest-server-probe.timer`, both rendered by `inngest-bootstrap.sh`. No new `scheduled-*.yml` is added.

## References & Research

- Issue #5150. Draft PR #11311.
- [Inngest Cloud limits](https://www.inngest.com/docs/durable-execution/limits) — Trace and log history 24h / 7d / 14d / up to 365d.
- [Self-host Inngest](https://www.inngest.com/docs/platform-and-operations/self-host-inngest) — rows are not removed automatically.
- [POSTGRES_RETENTION.md](https://github.com/inngest/inngest/blob/main/docs/POSTGRES_RETENTION.md) — status-gated pipelines. Upstream PR #4357 merged 2026-07-17.
- `apps/web-platform/infra/inngest-bootstrap.sh` durable arm versus fail-safe arm.
- `apps/web-platform/infra/inngest.tf` anchor `INNGEST_POSTGRES_URI (prd)`.
- `apps/web-platform/infra/vector.toml` anchors `include_units` and `exclude_units`.
- Runbook heading `## SQLite event-store retention`.
- ADR-030 and ADR-100.
- `model.c4` element `inngestPostgres`.
- NFR-040 in `knowledge-base/engineering/architecture/nfr-register.md`.
- Follow-through convention `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
