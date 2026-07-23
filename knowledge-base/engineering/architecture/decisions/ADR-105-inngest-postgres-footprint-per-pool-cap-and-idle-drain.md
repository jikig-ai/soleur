---
title: Inngest self-hosted Postgres footprint — low per-pool cap + idle drain; keep default_pool_size at 30
status: adopting
date: 2026-07-09
amends: none
supersedes: none
issue: 6258
related: [6178, 6230, 5558, 5559, 5560, 5562, 5563]
related_adrs: [ADR-100]
brand_survival_threshold: single-user incident
---

# ADR-105: Inngest self-hosted Postgres footprint — low per-pool cap + idle drain; keep `default_pool_size` at 30

## Context

The self-hosted `inngest start` server co-located on the web hosts connects to its dedicated
durable-backend Supabase project (**soleur-inngest-prd**, ref `pigsfuxruiopinouvjwy`) through the
Supavisor **session** pooler (`:5432`). Under back-to-back paginated GraphQL scans (`op=inventory`
/ `op=verify` in `.github/workflows/cutover-inngest.yml`, which drive the inngest server's own
Postgres-backed GQL API), the server's Postgres connection footprint **ratcheted to ~31 pinned
idle connections and never released them**, hitting the pooler's `pool_size` (measured 30) and
returning `FATAL: (EMAXCONNSESSION) max clients reached in session mode` (#6258).

The ExecStart carried **only** `--postgres-max-open-conns 10` (#5559). The recorded invariant
(`inngest.tf`, runbook) claimed that single client cap "bounds inngest's *total* connection count
under 15". That claim is **false**. `inngest start` (verified against the pinned CLI v1.19.4,
`cmd/start`) exposes four pool knobs and — critically — opens **separate Postgres pools per
subsystem** (queue / state / history / api), each honouring `--postgres-max-open-conns`
**independently**. The measured plateau (~31 ≈ 3 × 10 + 1) is the signature of per-subsystem pools:
the cap bounds each pool, **not the total**. So `10` × ~3 pools ratcheted past `pool_size` 30.

The default `--postgres-max-idle-conns` (10 per pool) meant every subsystem pool retained up to 10
pinned idle connections, and the default `--postgres-conn-max-idle-time` (5 min) held them long
enough to accumulate across probe bursts — the idle connections never released their Supavisor
session, so the pool ratcheted mid-scan.

This blocks the Inngest Phase-2 cutover (#6178): `op=execute`'s 2.1 capture, 2.2 quiesce, and
`op=verify` run these same scans back-to-back and would ratchet the pool to `EMAXCONNSESSION`
**mid-flip** — exactly when capture/quiesce/verify must be reliable to avoid silent reminder loss
or an undetected double-fire.

Brand-survival threshold: `single-user incident` — a lost or double-fired reminder is a per-user,
irreversible brand hit, and the cutover-gate reliability this fix restores is the only thing
standing between the flip and that outcome.

## Decision

1. **Bound the TOTAL footprint + drain idle connections at the CLIENT.** The durable ExecStart
   (`apps/web-platform/infra/inngest-bootstrap.sh`) carries:

   ```
   --postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 1
   ```

   - `--postgres-max-open-conns 5` — per-pool cap. Worst-case total = P × 5 ≤ **20** for P ≤ 4,
     comfortably under `pool_size` 30 with headroom for Supavisor warm connections + the mgmt probe.
     Still ≥ 5 conns/pool for throughput (alpha-internal < 10 events/sec — ample).
   - `--postgres-max-idle-conns 2` — retain ≤ 2 idle conns per pool (default 10) → worst-case pinned
     idle ≤ P × 2 = 8.
   - `--postgres-conn-max-idle-time 1` — close idle conns after 1 **MINUTE** so they release their
     Supavisor session (the release lever). ⚠ **This IntFlag is in MINUTES** (default 5), NOT
     seconds — verified against inngest v1.19.4 `cmd/start`. The originating plan's "SECS=30" was a
     unit mis-label; `30` would have meant 30 MINUTES (worse than the default). Corrected to `1`.

   These are **conservative fixed values, correct for any plausible pool count P ≤ 4**, so the fix
   ships without gating on a live prod measurement. The post-merge Phase-1 measurement *confirms* P
   and the plateau; it does not *determine* the values.

   `--postgres-max-open-conns` remains **first** in `BACKEND_FLAGS` — it is also the non-secret
   durable-detection sentinel (`inngest-inventory.sh`, `ci-deploy.sh`, `inngest-wiped-volume-verify.sh`
   use a substring match; `inngest.test.sh` anchors on it being first).

2. **Keep `default_pool_size` at 30 — do NOT execute the #5562 30→15 revert.** The #5562 decision's
   premise (that the client cap bounds inngest's *total* under 15) is falsified by the per-pool model:
   tightening the upstream pool to 15 while inngest's worst-case burst can approach ~20 would make
   `EMAXCONNSESSION` *more* likely, not less. The low client-side per-pool cap is the sole lever; the
   upstream stays 30. The #5562 revert is re-scoped to a follow-up (see `decision-challenges.md`).

3. **Reconcile the health-probe cap and gate the cutover flip.** `INNGEST_CLIENT_CAP` in
   `scheduled-inngest-health.yml` is reconciled from `10` to the post-fix worst-case total (`20`),
   and `cutover-inngest.yml` `op=execute` gains a fail-closed pool pre-check (readiness baseline +
   burst headroom) that runs before the flip.

## Considered Options

- **(chosen) Low per-pool cap (`open=5`) + idle drain (`idle=2`, `idle-time=1min`); keep
  `default_pool_size` at 30.** Bounds worst-case total under `pool_size` for any P ≤ 4 and releases
  pinned idle sessions. No prod-write, no sequencing hazard.
- **Client cap alone at 10 (status quo).** Rejected — per-pool, so it does not bound the total; the
  observed failure.
- **`pg_terminate_backend` idle-sweep as the fix.** Rejected as the fix — reactive, masks the leak;
  retained only as a documented emergency lever in the runbook.
- **Revert `default_pool_size` 30→15 (#5562 remediation #3).** Rejected — premise falsified by the
  per-pool model; a 15-slot upstream while inngest bursts to ~20 *worsens* the failure.

## Consequences

- The durable fix rides the immutable-redeploy path (`vinngest-v*` tag → `build-inngest-bootstrap-image.yml`
  → `ci-deploy.sh` unit reconcile-always restart) — no SSH, one unit restart per web host (crons
  de-plan until async re-arm; the already-accepted advisory for any inngest bootstrap change).
- The health probe's leading indicator now tracks the worst-case total footprint, keeping
  `pool_pressure`/`pool_exhausted` accurate.
- The cutover flip is gated on a clean pool, removing the mid-flip ratchet risk.
- `status: adopting` flips to `accepted` after the Phase-5 post-deploy controlled-burst re-measurement
  confirms the bounded plateau on both web hosts (no `EMAXCONNSESSION`).

## Precondition — exactly ONE prod-pool writer (added post-deploy, #6258/#5651)

**The per-instance cap (≤20) is sufficient ONLY while exactly ONE inngest-server writes to the prod
session pooler.** ADR-105 governs a *single* inngest instance's footprint; it does NOT model a
multi-writer topology.

Post-deploy verification (2026-07-09) surfaced the missing invariant: BOTH web hosts run co-located
inngest-servers against the same 30-slot session pooler — web-1 (`10.0.1.10`) AND the weight-0
warm-standby web-2 (`10.0.1.11`), per `inngest-host.tf:40` `web_host_private_ips`. Two writers ×
≤20 sessions each = 30–40 ≥ `pool_size` 30 → `EMAXCONNSESSION` under the paginated cutover scans,
with **zero** headroom for the scan's own connections. No per-instance cap or `default_pool_size`
tweak makes two writers fit with scan headroom — the constraint is topological, not sizing.

This is the exact single-writer contract `inngest-host.tf:8` records (OSS Inngest v1.x is single-writer;
two servers on one prod Postgres is the pathology **ADR-100 / #6178** exists to eliminate). Raising
`default_pool_size` to fit two writers is explicitly REJECTED: it would trade the visible
`EMAXCONNSESSION` for **silent double-firing of scheduled reminders** (web-2 self-arms oneshots into
its own Redis independent of LB weight — runbook DI-C3), which is strictly worse for the user-facing
payload.

- **Durable resolution:** complete **#6178** (dedicated singleton inngest, dark→live Postgres flip)
  — collapses to one prod-pool writer permanently. The web-2 quiesce is the operator-manual,
  cutover-gated step **#6230** (the automated per-host web→web fan-out #6227 was decided won't-build).
- **This ADR's cap is NOT falsified** — it remains correct and necessary for the post-cutover single
  writer. The incident was a topology contention ADR-105 never scoped, now recorded here as its
  binding precondition.
- **Verified no user harm (2026-07-09):** a read-only double-fire audit of the shared inngest backend
  over the 14-day two-writer window found **0** duplicate event-runs and **0** duplicate cron-ticks
  across 8,762 runs (99.6% completion) — inngest's shared-Postgres exactly-once claim prevented
  double-execution despite the separate per-host Redis queues. The `EMAXCONNSESSION` is isolated to
  the scan path (op=inventory/op=verify), not the reminder arm/fire path.

`status: adopting` therefore does NOT flip to `accepted` on the two-writer host set (the post-deploy
burst cannot pass while web-2 co-writes); it flips after **#6178** collapses to a single writer and
the burst re-measures clean.

## Alternatives Considered

See **Considered Options** above. The transaction pooler (`:6543`) was previously rejected (ADR-100
context / `inngest-bootstrap.sh`): it returns connections per-query but breaks inngest's sqlc prepared
statements — not an option here.

## Diagram

No C4 impact — a connection-pool *sizing* change adds/removes no element, edge, or `#external`
boundary. The `inngest` container and its `inngestPostgres` dedicated-project database (Supavisor
session pooler `:5432`) are already modeled (`model.c4`); this fix *restores* the "dedicated project
isolates connection budget" guarantee that element's description already asserts.
