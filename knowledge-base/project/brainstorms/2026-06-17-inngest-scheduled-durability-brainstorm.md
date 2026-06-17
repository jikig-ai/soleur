---
date: 2026-06-17
topic: inngest-scheduled-durability
issue: 5450
branch: feat-inngest-scheduled-durability
pr: 5459
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Durable backend for Inngest scheduled work (crons / oneshots / reminders)

## What We're Building

Migrate the self-hosted Inngest server from its default **bundled SQLite + in-memory Redis** (state on the *ephemeral root disk*) to a **durable backend**: **Supabase Postgres** as the event/state store (`--postgres-uri`) plus a **self-hosted durable Redis** (AOF-persisted on the existing `/mnt/data` volume) as the queue store. This closes the host-rebuild durability gap for the entire scheduled-work surface (57 fns) and corrects ADR-030's now-falsified "Hetzner backups mitigate" assumption.

Originating issue: **#5450** — found while verifying the #5432 otel-rebase reminder.

## Why This Approach

The operator chose the Postgres backend over the cheaper "move SQLite to the persistent volume" patch because it is the genuinely durable substrate (automated backups + PITR via Supabase) and is the path **ADR-030 already named** as the deferred Postgres migration.

The decisive reframe: **ADR-030 deferred Postgres specifically to avoid adding a "5th sub-processor."** But Supabase is *already* our primary database and an existing sub-processor — pointing Inngest at the same Supabase instance adds **no new legal surface**, dissolving the deferral's only blocking objection. The companion Redis is **self-hosted** (on our own host + volume), so it adds no sub-processor either.

### The durability matrix (filled from code — `main` @ 0f122c5c7)

| Failure mode | ~44 recurring `cron-*` | 5 `oneshot-*` (ADR-046, future-ts) | HTTP-armed `event-scheduled-reminder` |
|---|---|---|---|
| Inngest crash + `Restart=on-failure` | SQLite survives (same disk); triggers **de-plan → async re-arm** (redeploy or `--poll-interval`) | survives | survives |
| `systemctl restart inngest-server` | survives; de-plan → async re-arm (#5159) | survives | survives |
| Host **reboot** | root disk persists → survives; de-plan → async re-arm | survives | survives |
| Full **host re-provision** (`tf` server-replace) | **re-arms on web redeploy** (SDK `modified:true` sync) ✅ | **re-arms on container boot** (ADR-046 boot-arm block) ✅ *modulo conditional-re-arm drift* | **❌ LOST** — no boot re-arm; armed only in SQLite on the wiped root disk |

**Net gap today:** a host re-provision silently loses HTTP-armed reminders, plus any oneshot whose *conditionally* re-armed checkpoint (`step.run` re-arm to a new `ts`) diverged from its hardcoded boot-arm `ts`. Recurring crons and first-arm oneshots self-recover. This silent loss of an armed reminder is the **single-user-incident-class** trust vector.

### Evidence (code citations)
- SQLite on root disk: `apps/web-platform/infra/inngest-bootstrap.sh:103-105,167` (`--sqlite-dir /var/lib/inngest`, `mkdir -p /var/lib/inngest`).
- Only persistent volume mounts at `/mnt/data`, not `/var/lib/inngest`: `apps/web-platform/infra/server.tf:887-900` (`hcloud_volume.workspaces`), `ci-deploy.sh:540` (`-v /mnt/data/...`).
- De-plan / async re-arm asymmetry: `ci-deploy.sh:221-228,265-286` (#5159).
- Oneshot boot self-arm: ADR-046 `## Decision` (boot-arm in `server/index.ts` `app.prepare().then()`; "boot == deploy"); `oneshot-gdpr-gate-50d-eval.ts:367-383` (conditional `step.run` re-arm).
- Reminder arming has no boot re-arm: `event-scheduled-reminder.ts:1-9`, `app/api/internal/schedule-reminder/route.ts`.
- ADR-030 `## Trade-offs accepted` line 123: "SQLite single-host limitation… *Mitigated by: Hetzner backups*… Postgres migration deferred." — the falsified mitigation (a `tf` server-replace boots a fresh root disk; no backup restore).
- Inngest backend support (current docs, context7 `/inngest/website`): `inngest start --postgres-uri` GA since CLI v1.4.0 / Jan 2025; default is in-memory Redis + bundled SQLite; "for production, external Redis **and** Postgres are recommended."

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Backend target | **Supabase Postgres** (`--postgres-uri`) for event/state store | Durable + automated backups/PITR; already a sub-processor → no new legal surface; the ADR-030-named migration path |
| Queue store | **Self-hosted Redis, AOF-persisted on `/mnt/data`** | Inngest production setup needs external Redis; self-hosting adds no sub-processor and keeps the queue durable across host rebuild |
| Cheaper alt (volume-only SQLite move) | **Rejected by operator** | Closes the exact gap but stays single-host with no PITR; would only defer the Postgres migration again |
| ADR-030 | **Amend** | Record the falsified "Hetzner backups" mitigation; record the "Supabase = no new sub-processor" reframe; flip the deferred Postgres migration to adopted |
| Runbook matrix | **Update** `inngest-oneshot-and-reminder-patterns.md` | Add a host-rebuild durability column distinct from the existing "Dies with session?" column |
| Visual design | N/A — pure infra, no UI surface (Phase 3.55 skipped legitimately) | |

## Open Questions

1. **(LOAD-BEARING) Does Postgres-only persist scheduled/future events, or does the durable-reminder guarantee strictly require external Redis?** Docs frame Postgres as the *event store* and Redis as the *queue* ("events… scheduled via a queue"). Scheduled/delayed jobs are a queue concept → likely Redis-resident. **Empirical test for the work phase:** arm a future-`ts` reminder, restart Inngest under Postgres-only (in-memory Redis), confirm whether it still fires. If it does not, durable Redis is mandatory (not just "recommended"). This decides whether the Redis half is optional hardening or a hard requirement.
2. **In-flight cutover loss.** The migration abandons whatever is armed in the current `/var/lib/inngest` SQLite (one-time loss on the cutover deploy). Acceptable? Likely yes — pick a low-traffic window and re-arm any known-pending reminders/oneshots after cutover. Enumerate what is armed before cutover.
3. **Supabase connection model.** Inngest currently binds loopback-only; Postgres backend is an outbound connection — pooler vs direct, `--postgres-max-open-conns`, and a dedicated `inngest` database/schema + restricted role (not the app role). Confirm Supabase plan connection headroom.
4. **Redis persistence + permissions.** Redis AOF dir on `/mnt/data/redis`, owned to the Redis service user, 0750 — mirror the inngest/workspaces ownership pattern. systemd unit + `Restart=on-failure` like `inngest-server.service`.
5. **Availability coupling.** Pointing Inngest at Supabase couples scheduled-work availability to Supabase uptime; the in-memory fallback is gone. Acceptable for the durability gain, but note it.
6. **Conditional-re-arm drift on oneshots.** Independent of the backend: a durable backend fully fixes this (the re-armed `ts` is now persistent). Confirm the matrix cell flips to ✅ for all classes post-migration.

## Productize Candidate

None — this is a one-time substrate migration, not a recurring work pattern.

## Domain Assessments

**Assessed:** Engineering (CTO — via direct code/doc analysis), Legal (CLO — sub-processor surface), Operations (host/infra)

### Engineering
**Summary:** The host-rebuild gap is real and narrow (HTTP-armed reminders + conditional-re-arm-drift oneshots); recurring crons and first-arm oneshots self-recover. The durable fix is the ADR-030-named Postgres migration. The load-bearing unknown is whether scheduled events live in Postgres or the in-memory Redis queue — durable Redis is likely required for the reminder guarantee, matching Inngest's "external Redis + Postgres for production" recommendation.

### Legal
**Summary:** No new sub-processor. Supabase is already the primary DB and an existing sub-processor; self-hosted Redis runs on our own host. ADR-030's sole deferral reason (a 5th sub-processor) does not apply, so the migration can be adopted now. Update the Article 30 / data-processing register only if the Inngest event payloads stored in Supabase contain new personal-data categories — confirm at plan time.

### Operations
**Summary:** Adds two persistence dependencies (Supabase Postgres connection + self-hosted Redis systemd unit with AOF on `/mnt/data`). Both must be reachable from a `terraform apply` on a fresh host (`hr-fresh-host-provisioning-reachable-from-terraform-apply`). One-time in-flight cutover loss; sequence on a low-traffic window with pre-cutover enumeration of armed work.

## User-Brand Impact

- **Artifact:** the Inngest scheduled-work backend (the durable store behind every cron, self-armed oneshot, and HTTP-armed reminder).
- **Vector:** a host re-provision silently drops an armed reminder/oneshot with no error surfaced — the operator expects an action to fire and it never does.
- **Threshold:** single-user incident.
