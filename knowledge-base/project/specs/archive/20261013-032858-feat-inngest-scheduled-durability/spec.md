---
feature: inngest-scheduled-durability
issue: 5450
branch: feat-inngest-scheduled-durability
pr: 5459
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-06-17
brainstorm: knowledge-base/project/brainstorms/2026-06-17-inngest-scheduled-durability-brainstorm.md
---

# Spec: Durable backend for Inngest scheduled work

## Problem Statement

The self-hosted Inngest server persists event/queue state to **bundled SQLite + in-memory Redis on the ephemeral root disk** (`--sqlite-dir /var/lib/inngest`). The only persistent Hetzner volume (`hcloud_volume.workspaces`) mounts at `/mnt/data` and does **not** hold Inngest state. A full host re-provision (`terraform` server-replace) boots a fresh root disk and **silently loses** all HTTP-armed `event-scheduled-reminder` entries (and any `oneshot-*` whose conditionally re-armed checkpoint diverged from its hardcoded boot-arm `ts`). Recurring `cron-*` and first-arm oneshots self-recover; reminders do not. ADR-030 documented the SQLite limitation as "Mitigated by: Hetzner backups" — false for the `tf` server-replace path, which does not restore from a backup.

## Goals

- G1: A host re-provision no longer silently drops any armed scheduled work (cron / oneshot / reminder).
- G2: Migrate Inngest's event/state store to **Supabase Postgres** (`--postgres-uri`), gaining Supabase automated backups + PITR.
- G3: Provide a durable **queue store** sufficient for armed-reminder survival (self-hosted Redis with AOF on `/mnt/data`, pending the FR1 empirical confirmation of whether Postgres-only suffices).
- G4: Amend ADR-030 (correct the falsified mitigation; record the "Supabase = no new sub-processor" reframe; flip the deferred Postgres migration to adopted).
- G5: Update the runbook durability matrix with a host-rebuild column distinct from "Dies with session?".

## Non-Goals

- High availability / multi-host Inngest (single host remains; only persistence is hardened).
- Adding any **new** third-party sub-processor (Upstash etc. explicitly rejected — Redis is self-hosted).
- Reworking the de-plan/async-re-arm behavior of recurring cron triggers (orthogonal; already self-heals).
- Migrating any other service's persistence.

## Functional Requirements

### FR1: Confirm the durability boundary empirically (BLOCKS FR2/FR3 scoping)
Arm a future-`ts` `event-scheduled-reminder`, restart Inngest under a **Postgres-only** config (default in-memory Redis), and verify whether the reminder still fires. Result decides whether durable Redis (FR3) is mandatory or optional hardening. Document the finding in the runbook.

### FR2: Supabase Postgres event/state backend
Point `inngest start` at Supabase via `--postgres-uri` using a dedicated `inngest` database/schema and a restricted role (not the app role). Update `inngest-bootstrap.sh` systemd `ExecStart` + Doppler `prd` secret. Confirm connection model (pooler vs direct, `--postgres-max-open-conns`).

### FR3: Durable queue store (self-hosted Redis)
If FR1 shows Postgres-only does not survive, add a self-hosted Redis systemd unit with AOF persistence under `/mnt/data/redis` (owned to the Redis user, 0750), `Restart=on-failure`, and wire `--redis-uri`. Reachable from a fresh-host `terraform apply`.

### FR4: ADR-030 amendment + runbook matrix update
Amend `ADR-030-inngest-as-durable-trigger-layer.md` (`## Trade-offs accepted`) and add a host-rebuild durability column to `inngest-oneshot-and-reminder-patterns.md`.

### FR5: Cutover safety
Enumerate armed reminders/oneshots before cutover; schedule the migration in a low-traffic window; re-arm known-pending items after cutover. Accept one-time in-flight SQLite loss.

## Technical Requirements

### TR1: Provisioning reachability
All new persistence config (Supabase URI secret, Redis unit/volume) must be applied by a `terraform apply` on a fresh host — no manual post-provision step (`hr-fresh-host-provisioning-reachable-from-terraform-apply`, `hr-no-ssh-fallback-in-runbooks`).

### TR2: Secret handling
Postgres URI lives in Doppler `prd` and is injected at `ExecStart` (mirror the existing `INNGEST_SIGNING_KEY`/`INNGEST_EVENT_KEY` pattern); never logged to the systemd journal.

### TR3: Observability
Health probe must verify backend connectivity (Postgres/Redis reachable), surfaced to Sentry/Better Stack without SSH (`hr-observability-as-plan-quality-gate`). Extend `verify_inngest_health` / cron monitors.

### TR4: Legal register
Confirm whether Inngest event payloads stored in Supabase introduce new personal-data categories; update the Article 30 register only if so.

## Acceptance Criteria (from issue #5450)

- [ ] Durability matrix filled empirically for all three classes (done from code in brainstorm; FR1 confirms the Postgres/Redis boundary).
- [ ] Decision recorded with rationale (Supabase Postgres + self-hosted Redis; ADR-030 amended).
- [ ] Re-arm/reconciliation path or runbook step for the residual gap (if FR1 shows one remains).
- [ ] Runbook "Dies with session?" column joined by a host-rebuild durability column per mechanism.
