# Learning: every destructive datastore migration takes a recovery backup + a full inventory BEFORE + an after-inventory diff

category: best-practices
module: apps/web-platform/infra (inngest cutover), migrations, #5509

## Problem

The #5450 Inngest durable-backend cutover (SQLite-on-root-disk → Supabase Postgres + Redis) is destructive and forward-fix-only: Step 7 wipes `/var/lib/inngest`, and once a real reminder is armed against Postgres there is no safe rollback. The orchestration (built #5483, fixed #5492/#5503/#5505) could enumerate + re-arm armed reminders — but it had **no recovery backup** and **no full-state inventory**:

- No point-in-time artifact to restore from if the cutover corrupted/lost state.
- No before/after comparison to PROVE nothing was lost moving off the volume datastore. `op=enumerate` captured only armed `reminder.scheduled` events — not the full function list, the event-type set, or run state.

The operator caught both gaps at the cutover gate ("shall we back up the volume first and list all the jobs so we can recover and compare?") — exactly the right instinct, and exactly what the orchestration lacked.

## Solution / durable rule

Any destructive datastore migration (volume wipe, datastore swap, in-place schema rewrite that drops data, host re-provision that discards local state) MUST include all three, BEFORE the irreversible step:

1. **Recovery backup** — a restorable point-in-time copy of the doomed store. Prefer the no-SSH/no-manual mechanism the platform already affords: a Hetzner **server snapshot** via the hcloud API for a root-disk store (`POST /v1/servers/{id}/actions/create_image type=snapshot`, poll the action to `success`), a `pg_dump`/PITR for Postgres, an object-store copy for buckets. Log the artifact id + how to delete it once the migration is confirmed.
2. **Full inventory BEFORE** — capture the complete state the migration could lose, not just the slice you happen to be migrating. For Inngest: `{functions, event_names, armed_reminders}` from the loopback API (`/v1/functions` + `eventsV2`), not only the armed reminders. Save it as a run artifact.
3. **Inventory AFTER + diff** — re-capture the same shape post-migration and diff. Some keys must be identical by construction (Inngest functions re-register every deploy); others must be re-present after recovery (re-armed reminders) or empty-by-design (drained). An unexplained drop is a defect → restore from (1) before committing.

Bake all three into the migration's **workflow + runbook** as MANDATORY gates (here: `op=backup` + `op=inventory` ops in `cutover-inngest.yml`; runbook Steps 0.5 and 5), so the next migration inherits the safety net instead of rediscovering the gap at the gate.

## Key Insight

The slice you are migrating is not the slice you can lose. The Inngest cutover's stated risk was "armed reminders live only in Inngest state" — so the orchestration captured armed reminders. But a destructive wipe can also lose the function registrations and the event-type history; only a FULL inventory (not the migration-target slice) makes the before/after diff a real correctness proof. And a backup is the difference between "forward-fix-only" being a tripwire and being a recoverable decision.

Corollary (no-SSH): the backup and inventory must themselves be no-SSH (`hr-no-ssh-fallback-in-runbooks`). A server snapshot is a pure hcloud API call; the inventory is a webhook host op whose success-path output is pure JSON (#5503 — CombinedOutput merges streams, so the summary goes to journald only).

## Tags
category: best-practices
module: destructive-migration, backup, inventory, no-ssh, #5509
related: [[2026-06-17-webhook-combinedoutput-success-path-must-be-pure-json]], [[2026-06-18-coupled-registration-must-guard-the-actuating-surface]], [[2026-06-17-synchronous-webhook-consumer-must-dump-response-body]]
routed-from: knowledge-base/engineering/operations/runbooks/inngest-server.md (§Cutover procedure)
