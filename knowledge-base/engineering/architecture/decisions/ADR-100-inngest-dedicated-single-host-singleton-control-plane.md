---
adr: 100
title: Inngest as a dedicated single-host singleton control plane
status: adopting
date: 2026-07-07
amends: ADR-030
supersedes: none
issue: 6178
related: [5450, 6185, 6122]
related_adrs: [ADR-030, ADR-059, ADR-068, ADR-080, ADR-088, ADR-096]
brand_survival_threshold: single-user incident
---

# ADR-100: Inngest as a dedicated single-host singleton control plane

> **Status `adopting`** until the Phase-4 soak (7 days, per-`(function_id, startedAt-bucket)`
> exactly-once) verifies zero double-fire in prod. Flip `adopting → accepted` on soak success
> (plan Phase 4.3). Amends **ADR-030** (Inngest as durable trigger layer); does not supersede it.

## Context

ADR-030 deploys the self-hosted OSS Inngest server (`inngest start`, pinned server
`inngest/inngest:v1.19.4`) **co-located** on the web Hetzner host, bound `0.0.0.0:8288`
and reached by the app via the Docker host-gateway `host.docker.internal:8288`
(`inngest-bootstrap.sh:339`, `cloud-init.yml`). Isolation today is by **firewall**, not
loopback binding.

The active-active-N web goal (web-1 + web-2 both serving, more later) is **structurally
blocked** by this topology. OSS Inngest v1.x is single-writer (multi-server HA is an
unreleased roadmap item), and two inngest servers on the *same* prd Inngest Postgres both
fire every cron's schedule regardless of local `--sdk-url` — the shared Postgres tables drive
scheduling, not local registration. So N co-located servers ⇒ guaranteed N-times double-fire.
Today this is masked only by web-2 being pinned at Cloudflare LB weight 0 (`server.tf`). A
dedicated singleton is the prerequisite that lets web-2 be pooled (#6178; supersedes the
#5450 same-host cutover framing).

Brand-survival threshold: `single-user incident`. If this lands broken, scheduled agent runs
/ crons fire **zero** times (a cutover gap or the singleton down) or **N** times (two servers
on prod Postgres) — silently dropped or duplicated autonomous work, no error surfaced. CPO
sign-off carried from the brainstorm; `user-impact-reviewer` invoked at review.

**Phase-0 empirical spikes (2026-07-07, against the exact `inngest/inngest:v1.19.4` pin with
external Redis + Postgres — full evidence:
`knowledge-base/project/specs/feat-inngest-dedicated-host/phase0-empirical-spike.md`) resolved
the three load-bearing unknowns this ADR fixes:**
1. **Fan-out routing is ROUTE-ONCE.** Two `--sdk-url`s with the same app id collapse into ONE
   app (SDK keys apps by `appName = new Inngest({id})`, `InngestCommHandler.js:1271-1300`);
   the serve URL is a last-writer-wins property, not part of identity. Across 4 clean sends
   only one instance ever executed — invoke-all was never observed. `--sdk-url` is repeatable.
   But the winning URL *flaps* as the server re-polls each sdk-url → which replica serves a run
   is non-deterministic, and the flap window can transiently perturb ingest.
2. **Cron runs ARE enumerable in v1.19.4** via the top-level `runs(filter: RunsFilterV2!)`
   connection (no prior run ids needed) — see Decision. `scheduled_tick` does not exist;
   `cronSchedule`/`eventName` are `null` on run nodes. `startedAt` is present and reliable.
3. **A Redis `FLUSHALL` before the Postgres flip is MANDATORY** (empirically proven): with
   Redis retained across a Postgres swap, (a) in-flight `step.sleep`/queued jobs enqueued
   against DB-A execute against the fresh DB-B, (b) the cron schedule (lives in Redis
   `{queue}:queue:sorted:cron`) keeps firing against DB-B, (c) account-scoped idempotency keys
   from DB-A persist and mis-dedup DB-B runs. The plan's "SQLite-only fallback" assumption was
   wrong — `inngest start` exposes both `--redis-uri` and `--postgres-uri`, so the exact prod
   topology is locally testable, and it was.

## Considered Options

- **Option A — Dedicated single-host private-net singleton (CHOSEN).** One `hcloud_server.inngest`
  at `10.0.1.40` (modeled 1:1 on `zot-registry.tf`/`git-data.tf`), removed from web cloud-init so
  exactly-one-instance is enforced by topology; web backends reach it over the `10.0.1.0/24`
  subnet. Pros: structural impossibility of double-fire post-rollout; failure-domain isolation
  from web; all-web-hosts cold-boot decoupling; clean HA path (#6185). Cons: reduces durable-trigger
  availability from potentially-2 (co-located on web-1+web-2) to definitely-1 (SPOF, accepted); one
  new host + volume cost; a cloud-init edit force-replaces the singleton (maintenance-window gated).
- **Option B — Single-host role-guard** (keep co-located; elect one host as scheduler via a lock/flag).
  Rejected: a correlated web-1 failure takes the scheduler with it; the guard is a runtime
  invariant that can regress, vs. topology which cannot. Operator explicitly chose structural
  impossibility over a role-guard.
- **Option C — In-place on every host** (status quo extended to active-active). Rejected: guaranteed
  N-times double-fire on shared prod Postgres (the core problem).
- **Option D — HA failover pair.** Deferred to #6185 — single-writer OSS makes a hot pair non-trivial;
  the dedicated singleton is the prerequisite and buys exactly-once now.
- **Option E — Managed Inngest Cloud.** Declined: EU data-residency (state must stay in the EU
  Supabase project + host-local Redis; no new sub-processor).

## Decision

**Extract Inngest to one dedicated private-net Hetzner host (`hcloud_server.inngest`,
`10.0.1.40`, `cax11` ARM64) on a distinct non-prod Postgres backend until cutover; remove it
from web cloud-init.** The following sub-decisions are fixed by this ADR:

1. **Fan-out mechanism — single stable `--sdk-url`, VIP at N>1.** At cutover only web-1 serves
   (web-2 at LB weight 0), so the dedicated host runs a **single** `--sdk-url` to the active web
   backend's private interface (the degenerate, no-flap case of the route-once mechanism). When
   web-2 is pooled (Phase 4.2, separate work), migrate to a single stable `--sdk-url` at a
   **private VIP/LB** in front of the replicas — NOT a list of replica URLs — because the
   spike showed the last-writer-wins URL flaps under multi-url. Route-once means multi-url is
   *safe from duplicate execution* (an acceptable fallback), but the VIP is the deterministic
   primary for N>1. This defers the LB cost to when N>1 is actually reached.
2. **Hooks stay web-host-resident.** The dedicated host has no app (`rearm` posts to the local
   app's `/api/internal/schedule-reminder`) and no public ingress (the GH runner reaches only
   `deploy.soleur.ai`). Capture/rearm/inventory hooks run on the web host and reach the inngest
   host over the private net; the `op=capture` subpath on the web host stays writable through
   Phase-3 decommission.
3. **Signature verification is the SOLE `/api/inngest` boundary; `:8288/:8289` scoped by
   host-local nftables (SEC-H1/H2).** Hetzner firewalls filter only the *public* interface —
   intra-subnet traffic is open by network membership (`git-data.tf:200-204`,
   `firewall-9000-deny.test.sh:6-8`), so a `hcloud_firewall.web` inbound rule for `10.0.1.40`
   would be a **no-op** and is not claimed. The effective app boundary is fail-closed HMAC
   signature verification (`client.ts:43-50`, `route.ts:87`). The inngest control API
   (`:8288/v0/gql`, which the spike confirmed is **unauthenticated** in `start` mode) and Connect
   (`:8289`) are scoped by **host-local nftables on the inngest host's private interface**,
   allowing only the web-host private IPs (`10.0.1.10`/`.11`) and dropping peers (`.20` git-data,
   `.30` registry); `:8289` binds loopback if Connect is unused. Delivered as a cloud-init
   `write_files` script + a systemd oneshot re-run every boot (a reboot clears nftables), mirroring
   `cron-egress-nftables.sh`.
4. **Fresh signing/event keys (SEC-H3).** `INNGEST_SIGNING_KEY`/`INNGEST_EVENT_KEY` are freshly
   minted for the new boundary, NOT reused from the co-located host. Blast radius documented below.
5. **Secrets on a SEPARATE Doppler project `soleur-inngest`, not a `prd` branch config.** A branch
   config under `prd` resolves the environment's ROOT config as its base and would inherit all
   ~116 `soleur/prd` secrets incl. `SUPABASE_SERVICE_ROLE_KEY`
   (`2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`, #6122). Mirror the
   `soleur-registry` project pattern + the fail-closed boot self-check (cardinality + identity
   under the shipped scoped token).
6. **Dark→live is a Postgres flip GATED behind a Redis `FLUSHALL` + `DBSIZE==0` assertion**
   immediately before the flip (DI-C1, proven mandatory above). The dark host runs on a distinct
   non-prod Postgres firing zero prod crons at boot; the SQLite fail-safe is dropped (unreachable
   on a Redis-healthy host).
7. **Exactly-once soak invariant (DI-C2, demonstrably writable — AC13 satisfied).** The soak probe
   enumerates cron runs against v1.19.4 with:
   ```graphql
   query Enum($filter: RunsFilterV2!, $order: [RunsV2OrderBy!]!) {
     runs(first: 100, filter: $filter, orderBy: $order) {
       totalCount pageInfo { hasNextPage endCursor }
       edges { node { id functionID status queuedAt startedAt endedAt } }
     }
   }
   ```
   filter `{ from, until, timeField: STARTED_AT, functionIDs:[<cron UUID>] }`. Exactly-once ⇔ every
   occupied `(functionID, floor(startedAt / cron_period))` bucket has exactly one run. (Alternate:
   `eventsV2(includeInternalEvents:true)` surfaces `inngest/scheduled.timer` internal events with
   nested runs; the top-level `runs` query is cleaner.) `scheduled_tick` is removed everywhere.

## Consequences

**Easier:** active-active web becomes structurally safe (web-2 poolable at 4.2); inngest failure
domain isolated from the web app; all-web-hosts cold-boot no longer depends on inngest bootstrap;
a clean HA path (#6185).

**Harder / accepted:** durable-trigger availability drops from potentially-2 to definitely-1 (SPOF
— the single box down = zero crons fire until recovery; Postgres-durable state means delayed, not
lost; redundancy deferred #6185). Every future `cloud-init-inngest.yml` change force-replaces the
sole scheduler (no `ignore_changes[user_data]`) → a cron-outage window. **This force-replace runs
via the operator's serialized full `terraform apply` (R2 concurrency group `terraform-apply-web-
platform-host`), in a maintenance window — NOT the `apply_target=inngest-host` dispatch job, whose
additive-only destroy-guard (0 resource_deletes) aborts on the `{delete,create}` a replace emits
(the dispatch is initial-provision only). A scoped guarded `-replace` mode for the dispatch is a
tracked follow-up if force-replaces become frequent.** The AOF volume is a separate resource that
survives the replace. The Phase-2 cutover carries a bounded, operator-signed-off residual window
(quiesce-all → register).

**Blast radius (SEC-H3, documented not eliminated):** the signing key authorizes the entire ~60-
function registry, several running in the web-app process with full prd env (GHCR token minter,
agent-spawn, bug-fixer, TF-drift). Inngest-host compromise ≈ indirect arbitrary-app-code execution
with `SUPABASE_SERVICE_ROLE` — the separate Doppler project blocks *direct* secret read, not this.
Mitigations: fresh keys for the new boundary, nftables scoping of the control API, and a
per-invocation guard on the most dangerous functions (follow-up).

## Cost Impacts

One new Hetzner `cax11` (ARM64) host + one `hcloud_volume.inngest_redis` (default 10 GB, AOF).
No new SaaS/vendor: reuses the existing free-tier `betteruptime_heartbeat.inngest_prd`;
`betteruptime_policy` stays gated on `var.betterstack_paid_tier`. Prices reflect training data —
verify at Hetzner before apply. Record the recurring host+volume line in
`knowledge-base/operations/expenses.md` at ship (`wg-record-recurring-vendor-expense-before-ready`).

## NFR Impacts

Improves the "exactly-once scheduling under active-active web" property from **structurally
impossible** to **enforced-by-topology** (the load-bearing goal). Regresses durable-trigger
**availability** from potentially-2 to definitely-1 (SPOF) — a stated, accepted single-user-incident
tradeoff, restored to HA at #6185. No change to data-residency (state stays in the EU Supabase
project + host-local Redis).

## Principle Alignment

- **AP (Terraform-only infra):** Aligned — the host/volume/network/firewall land in the existing
  web-platform Terraform root (no new attestation), cloud-init-only apply (no `remote-exec`).
- **AP (Doppler secrets):** Aligned + hardened — a dedicated `soleur-inngest` project replaces the
  non-isolating branch-config pattern (#6122 precedent).
- **AP (no-SSH runbooks):** Aligned — remediation is via `apply_target=inngest-host` dispatch +
  the private-net inventory hook; no `ssh` in any new runbook (AC9).
- **AP (fail-loud observability):** Aligned at the LIVE (post-cutover) state — heartbeat pushed
  FROM the inngest host, missed heartbeat → Better Stack + P1; the soak probe fail-closed via
  Follow-Through Enrollment. **Phase-1 caveat (deferred, tracked):** the Vector journal→Sentry
  shipper is DEFERRED on this cax11/ARM64 host (Vector's download URL is x86_64-hardcoded; its
  BETTERSTACK_LOGS_TOKEN would need isolated-project provisioning), and the dark host does not push
  the prod heartbeat during the dark window (out-of-band `INNGEST_HEARTBEAT_URL` set at cutover, to
  avoid dual-pusher masking of the still-serving co-located scheduler — review #6180). So a DARK,
  inert host that boot-bricks or errors is surfaced at the Phase-2 pre-flight registry-empty check,
  not by continuous Sentry/heartbeat monitoring. Vector→Sentry + the dedicated-host heartbeat are
  wired before the Phase-2 cutover (when this becomes the live scheduler) — the alignment claim
  above holds from cutover onward.

## Diagram

C4 container view edited in-place (`model.c4`): the `inngest` container technology →
`"Dedicated Hetzner host, private-net 10.0.1.40:8288/:8289"` (loopback string removed, AC5);
`api -> inngest` → `"HTTP private-net :8288"`; `hetzner -> inngest` and `doppler -> inngest`
annotated for the dedicated host + the `soleur-inngest` Doppler project. No new container/deployment
node (the model does not distinguish deployment nodes). Run `c4-code-syntax.test.ts` +
`c4-render.test.ts`.
