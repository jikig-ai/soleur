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

**Flip-mechanism alternatives (Decision 6a, added 2026-07-08 Ref #6178 — all rejected):**
- **Force-replace-with-gated-cloud-init-`FLUSHALL`.** Rejected: recreates the host mid-window (cold
  OCI pull + cosign + bootstrap = minutes, plus 226/NAMESPACE re-pull risk), widening the bounded
  outage residual and adding failure surface at the worst moment. The pre-installed Doppler-armed
  oneshot flips **in place** instead.
- **A dedicated-host webhook reached via web-host fan-out.** Rejected: a new inbound control plane on
  the deny-all-public singleton enlarges its attack surface (SEC-H2). The Doppler-flag **poll** keeps
  the host inbound-closed.
- **A two-value `armed`/`done` flag** (instead of the 8-state FSM). Rejected: with only `armed`/`done`
  there is no `rollback` value the on-host oneshot can act on, so the **no-SSH rollback is unreachable**
  (P0-1) — the operator would have no no-SSH way to stop the dedicated scheduler. The FSM adds the
  `rollback`/`rolled-back`/`flipping`/`flushed`/`aborted` states that make rollback, mid-flip-reboot
  safety (the split `flipping` PRE-flush / `flushed` POST-flush checkpoints), and the DBSIZE-abort all
  expressible.
- **Disabling the poll timer after the forward flip** (the pre-review plan's "disable after flip").
  Rejected for the same reason: a disabled timer can never observe a later `INNGEST_CUTOVER_FLIP=rollback`
  write, again making the **no-SSH rollback unreachable** (P0-1). The reconciled rule is: the timer
  ships enabled and stays enabled forever; the FSM flag is the sole gate; no step ever disables the
  timer (the terminal-state no-ops make the steady 30s poll safe).

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
6a. **The Redis `FLUSHALL` + `DBSIZE==0` gate and the prod-Postgres flip restart execute ON the
   dedicated host via a Doppler-flag-armed, OCI-baked oneshot (`inngest-cutover-flip`) driven by a
   finite state machine — NOT a web-host webhook, and NOT a two-value flag** (added 2026-07-08,
   Ref #6178, folds a post-plan flow review). The dedicated host runs **no** `adnanh/webhook` /
   `hooks.json` / `ci-deploy.sh` and its Redis is loopback-bound (`bind 127.0.0.1`), so the web-host
   webhook (`deploy.soleur.ai/hooks/*`) cannot `FLUSHALL` it or `systemctl restart` inngest there;
   `INNGEST_POSTGRES_URI` is read only at `ExecStart`, so the flip needs an on-host process restart.
   The only no-SSH primitives on the deny-all-public singleton are cloud-init `runcmd` (fires on
   force-replace) and systemd units — so the gate is authored as an OCI-baked oneshot polled by a
   systemd `.timer` against a Doppler flag. The mechanism is fixed as:
   - **`INNGEST_CUTOVER_FLIP` is an 8-state FSM** on `soleur-inngest/prd` (`ignore_changes[value]`),
     not a two-value armed/done flag:
     `armed` → `flipping` → `flushed` → `done` (forward), `rollback` → `rolled-back` (reverse),
     terminal `aborted` (DBSIZE-gate trip **or** an unhandled failure — see the ERR trap below),
     and `unset`/other (no-op). `done`, `rolled-back`, `aborted`, and `unset` are idempotent no-ops.
   - **Forward-path ordering is `stop → FLUSHALL → assert DBSIZE==0 → flushed → start`** (the dark
     server is **stopped first** so it cannot write between the flush and the DBSIZE check). The
     transient is **split into two checkpoints** so a crash can neither skip the flush nor re-flush a
     prod queue (the #5450 re-flush trap, hardened):
     - `flipping` is written `armed → flipping` **before** Redis is touched. A resume from `flipping`
       **re-runs the WHOLE `stop → FLUSHALL → assert`** — this is SAFE because the server is still
       stopped/dark (nothing on prod yet), and it **closes the skip-flush window** where a crash
       between `set flipping` and the flush would otherwise resume straight into `start` against an
       un-flushed dark Redis (stale-cron double-fire).
     - `flushed` is written **after** the `DBSIZE==0` assert passes and **before** `start`. A resume
       from `flushed` **only** ensures `started → done` and **NEVER** re-`FLUSHALL`s — reaching
       `flushed` proves the flush succeeded and the queue is now on prod Postgres.
     A non-zero `DBSIZE` aborts loud: no start, and the flag → terminal `aborted`
     (`exit_code:1`; the poll halts — never re-attempts, never reads as success — only `done` does).
   - **An ERR trap makes every unhandled failure loud** (`set -Eeuo pipefail`): a failure of a flag
     write / `stop` / `start` emits an `unexpected-exit` marker **and** drives the flag to terminal
     `aborted`, so the next 30s poll halts on the no-op instead of resuming into a no-flush false
     `done` (the #5934 class — e.g. a `stop_server` failure after `flag → flipping` must not later
     read as success).
   - **The poll timer ships ENABLED and is NEVER disabled for the host's whole life.** The FSM flag
     is the **sole** gate. Keeping the timer enabled after the forward flip is what makes a later
     operator `INNGEST_CUTOVER_FLIP=rollback` Doppler write observable on the next 30s poll — i.e.
     it is what makes the **no-SSH rollback reachable** (P0-1). The `done`/`rolled-back`/`aborted`/
     `unset` no-ops make a benign 30s poll on the dark/live host safe.
   - **An `inngest-server.service` `ExecStartPre` arm-atomicity guard** (`inngest-server-flip-guard.sh`,
     P1-5) refuses to start (exit non-zero, blocking start) when `INNGEST_POSTGRES_URI` resolves to
     **prod** and the flag ∉ `{armed, flipping, done}` — closing the race where the prod URI is
     written before the gated flip and any non-arm restart (crash / `OnBootSec` / operator) would
     otherwise bring up a **second prod scheduler** against the still-dirty dark Redis.
   - **Flip-state is read no-SSH via Better Stack** (P0-2): the oneshot emits its verify-state as a
     `logger -t inngest-cutover-flip` JSON line, carried off-box by the already-shipped on-host
     Vector → Better Stack Logs journald shipper (source `soleur-inngest-vector-prd`, #6197). The
     operator confirms `exit_code:0` by pulling that log line, **never** by reading a state file on
     the deny-all-public host (`cat-inngest-cutover-state.sh` is an on-host debug aid only, not the
     gate).
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
sole scheduler (no `ignore_changes[user_data]`) → a cron-outage window.
<!-- lint-infra-ignore start -->
**This force-replace runs
via the operator's serialized full `terraform apply` (R2 concurrency group `terraform-apply-web-
platform-host`), in a maintenance window — NOT the `apply_target=inngest-host` dispatch job, whose
additive-only destroy-guard (0 resource_deletes) aborts on the `{delete,create}` a replace emits
(the dispatch is initial-provision only). A scoped guarded `-replace` mode for the dispatch is a
tracked follow-up if force-replaces become frequent.**
<!-- lint-infra-ignore end -->
The AOF volume is a separate resource that
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
  Follow-Through Enrollment. **Phase-1 caveat — RESOLVED (#6197):** the Vector journal→**Better
  Stack Logs** shipper (NOT Sentry — Vector pivoted Sentry→Better Stack in #4273/#5526; the earlier
  "Sentry" prose here was stale) is now WIRED on this cax11/ARM64 host: the Vector install is
  arch-parameterized (`VECTOR_CLI_ARCH` + an `aarch64-unknown-linux-musl` triple map, mirroring the
  Inngest-CLI arm64 pattern), an arm64 Vector SHA is pinned in `vector.tf`, and `BETTERSTACK_LOGS_TOKEN`
  is provisioned into the isolated `soleur-inngest/prd` project via a `doppler_secret` (Approach B —
  a sensitive no-default `var.betterstack_logs_token` from `prd_terraform`, so only the one 24-char
  token enters shared tfstate, NOT the full `soleur/prd` map). The boot isolation self-check
  (`cloud-init-inngest.yml`) now admits `BETTERSTACK_LOGS_TOKEN` as a TOP-LEVEL allowlist member
  (dark-boot secret count 4→5, live 5→6); its admission criterion is "names this host's runtime
  consumes" (not `INNGEST_`-prefixed). During the dark window the host still does not push the prod
  heartbeat (out-of-band `INNGEST_HEARTBEAT_URL` set only at cutover, to avoid dual-pusher masking of
  the still-serving co-located scheduler — review #6180), so a DARK, inert host that boot-bricks or
  errors is surfaced at the Phase-2 pre-flight registry-empty check + the in-surface bootstrap-stderr
  lines (deploy-status endpoint), not by continuous monitoring. The shipper is wired ahead of the
  Phase-2 cutover (when this becomes the live scheduler) — the alignment claim above holds from cutover.
- **Apply-path constraint (recorded #6197):** the additive-only `apply_target=inngest-host` dispatch
  CANNOT force-replace the host (its destroy-guard aborts on any delete), so a cloud-init/bootstrap
  change that force-replaces `hcloud_server.inngest` rides a NEW scoped `apply_target=inngest-host-replace`
  dispatch (mirroring `web-2-recreate`; a sourced gate permits exactly the server + its 2 id-referencing
  dependents and PRESERVES the durable Redis AOF volume `hcloud_volume.inngest_redis`). A net-new host
  (sub-case where the host is not yet in tfstate) instead rides the additive `inngest-host` create.

## Diagram

C4 container view edited in-place (`model.c4`): the `inngest` container technology →
`"Dedicated Hetzner host, private-net 10.0.1.40:8288/:8289"` (loopback string removed, AC5);
`api -> inngest` → `"HTTP private-net :8288"`; `hetzner -> inngest` and `doppler -> inngest`
annotated for the dedicated host + the `soleur-inngest` Doppler project. No new container/deployment
node (the model does not distinguish deployment nodes). Run `c4-code-syntax.test.ts` +
`c4-render.test.ts`.

**No C4 change from the Decision 6a amendment (Ref #6178).** The cutover-flip oneshot is an
**internal control mechanism on the already-modeled `inngest` node** — it adds no new
actor/external-system/data-store and no new access edge (it reuses the modeled
`inngestPostgres`/`inngestRedis` and the unchanged `api → inngest` relationship). Verified against
all three `.c4` files; the amendment touches no `.c4` prose.

## Addendum (2026-07-08) — dual-arch provisioning; provisioned amd64/cpx22

At Phase-2 provision time, Hetzner `cax11` (arm64/Ampere) was **out of stock across all EU
datacenters** (nbg1/hel1/fsn1) — as were the cheap Intel `cx*` types — so the initial
`apply_target=inngest-host` dispatch failed with `resource_unavailable`. The cheapest
in-stock 4 GB amd64 type was `cpx22` (~€19.49/mo vs cax11's ~€5.99/mo).

Resolution: the host was made **dual-arch**, mirroring the zot-registry pattern —
`local.inngest_arch = startswith(var.inngest_server_type, "cax") ? "arm64" : "amd64"` selects
the arch-matched inngest-CLI / Vector / Doppler-CLI download checksums. `var.inngest_server_type`
default flipped `cax11` → `cpx22`, so it currently provisions **amd64 (cpx22)**. Arch is **not
load-bearing** for this singleton scheduler (see Decision), so the earlier sections' `cax11`/ARM64
references describe the original intent, not the deployed reality. The host reverts to cax11
(cheaper) when Ampere restocks, via a host replace (`inngest-host-replace-gate`). See #6178.
