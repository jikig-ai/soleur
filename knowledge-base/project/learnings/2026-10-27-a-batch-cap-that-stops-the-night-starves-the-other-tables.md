# Learning: a batch cap that stops the whole night starves the other tables

## Problem

The Inngest trace-retention job deletes finished trace and log history in bounded batches. The first cap treated any statement that still had eligible rows as a reason to abort the whole pass. On the production store the largest child is `spans` (about 1.74 million rows). At 40,000 rows a night that child alone needs many nights, and each aborted night left `history`, `events`, and the SQLite file untouched while those tables kept growing (about 38 MB a day), enough to refill the free space the prune is meant to recover.

The same runner had three smaller traps in the same pass. Python's `sqlite3` cursor reports `rowcount` -1 after a `DELETE`, so a zero-delete check written against `rowcount` never sees a drained batch. The Postgres millisecond cutoff `floor(extract(epoch) * 1000) - days * 86400000` overflows `int4` unless the product is cast to `bigint`. A Better Stack `JSONEachRow` line can be a JSON string whose payload is itself JSON, so a substring search for `INNGEST_TRACE_RETENTION_OUTCOME=ok` also matches a quoted failure row.

## Solution

A capped child holds only its own anchor. `trace_runs` is skipped when `spans`, `traces`, or `event_batches` is in that file's capped set. `function_finishes` is skipped when `history` or `function_runs` is. Every other statement still runs, including `history`, `events`, and the SQLite file. Each SQL file keeps its own capped set, so a Postgres `spans` cap does not skip the SQLite `trace_runs` anchor. After both stores, a non-empty union exits with `reason=batch_cap` and does not write the daily marker. `size_budget` still aborts inside the Postgres loop, before later statements and before SQLite.

The SQLite delete count is `SELECT changes()` immediately after the delete. The four Postgres `ended_at` cutoffs cast the millisecond product to `bigint`. The follow-through closer `json.loads` the line, loads again when the value is a string, and accepts the row only when `message` equals `INNGEST_TRACE_RETENTION_OUTCOME=ok` and `_SYSTEMD_UNIT` equals `inngest-trace-retention.service`.

The fixture that caps `spans` and `function_runs` at one batch asserts exit non-zero, `reason=batch_cap`, the anchors still present, `history` and the free event gone, and the marker absent. A later uncapped pass deletes the held anchors.

## Key Insight

A cap is a property of one statement, not of the night. Stopping the night protects the capped pipeline's anchor and starves every independent pipeline. Hold the anchor whose children remain, and keep deleting the pipelines that are already safe. The same job also lies if you trust `cursor.rowcount`, a 32-bit millisecond product, or a substring of a double-encoded log line.

## Session Errors

1. **The first review spawn asked for a structural seat under a type the roster does not list.** Recovery: that spawn was stopped and a general-purpose seat enumerated the one-line guard holes. **Prevention:** use a hyphenated id from the roster; a rejected type is one replacement, and the stopped id is not a second seat.
2. **A spans cap aborted `history` and `events` for the whole catch-up.** Recovery: `b269167bf2` holds only that pipeline's anchor and the retention suite pins the other deletes. **Prevention:** the per-statement cap and the fixture already cover this class; do not add an `AGENTS.md` rule while the always-loaded payload is in the WARN tier.
3. **`scripts/test-all.sh --capacity` printed `CAPACITY_CONTENDED`, so the local affected battery never started.** Recovery: fast checks and the retention suite ran; CI's required `test` check is the merge gate. **Prevention:** when the shared lock is contended, waive the local affected battery, run the cheap ratchet lane, and do not open a new issue for a waiver the operator already records.
4. **The article-30 bound can be split from the not-yet-pruning clause by a later sentence.** Recovery: the legal auditor cleared the three register sentences that keep both facts in one sentence. **Prevention:** do not add catch-up wording to those sentences, and do not move Last Updated.
5. **The plan write was denied once for operator-install framing (`hr-all-infrastructure-provisioning-servers`).** Recovery: the timer is installed by the baked bootstrap on the dedicated host, with no new Terraform root. **Prevention:** the IaC plan-write hook already blocks that framing.
6. **Compound's five documentation subagents were not spawned.** Recovery: this file was written from the review ledger and the suite. **Prevention:** say so in the deviation note; do not invent subagent findings.

## Tags

category: database-issues
module: inngest-trace-retention
