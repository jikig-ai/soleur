---
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

> **Status `adopting`.** The Phase-4 soak (7 days, per-`(function_id, startedAt-bucket)`
> exactly-once) is the condition for flipping `adopting → accepted` (plan Phase 4.3).
> **It has not started.** The cutover did not hold: the dedicated host has served nothing since
> 2026-07-30 and `INNGEST_CUTOVER_FLIP` rests at `rollback`. See the
> [2026-08-12 addendum](#addendum--2026-08-12-7228--the-cutover-did-not-hold-and-the-soak-never-started)
> before treating any statement below as describing a running system. Amends **ADR-030** (Inngest
> as durable trigger layer); does not supersede it.

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
<!-- lint-infra-ignore start -->
- **A two-value `armed`/`done` flag** (instead of the 8-state FSM). Rejected: with only `armed`/`done`
  there is no `rollback` value the on-host oneshot can act on, so the **no-SSH rollback is unreachable**
  (P0-1) — the operator would have no no-SSH way to stop the dedicated scheduler. The FSM adds the
  `rollback`/`rolled-back`/`flipping`/`flushed`/`aborted` states that make rollback, mid-flip-reboot
  safety (the split `flipping` PRE-flush / `flushed` POST-flush checkpoints), and the DBSIZE-abort all
  expressible.
<!-- lint-infra-ignore end -->
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
   intra-subnet traffic is open by network membership (`git-data.tf, resource "hcloud_firewall" "git_data" — no rule blocks`,
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

   > **Amendment (2026-07-24, Ref #6178 cutover-502 — CORRECTS this decision).** Decision 4 was
   > **wrong** to treat `INNGEST_EVENT_KEY` / `INNGEST_SIGNING_KEY` as isolation-sensitive and mint
   > them **separately** per host. They are a **SHARED app↔host CHANNEL auth token**: the app
   > (`inngest.send()` / the `serve()` handler) and the dedicated host authenticate the SAME channel
   > with them, so they **MUST be common** across `soleur/prd` (the app) and `soleur-inngest/prd`
   > (the host). The #6178 host-cutover minted fresh host keys per this decision but **never
   > reconciled** them into `soleur/prd`; after the 2.4 app-repoint (`INNGEST_BASE_URL` →
   > `http://10.0.1.40:8288`) every app-originated send to the host was rejected against the stale
   > event key → the app route returned **HTTP 502** (`op=rearm` failed). The live fix copied the
   > host's event+signing key values into `soleur/prd` (out-of-band, which the `ignore_changes=[value]`
   > lifecycle on those `doppler_secret`s explicitly supports) and redeployed the web app.
   >
   > The isolation that actually matters — and **stays separate per host** — is **`INNGEST_POSTGRES_URI`
   > + `SUPABASE_SERVICE_ROLE`** (Decision 5, the `soleur-inngest` project boundary): those grant
   > data-plane access and must never be shared. The channel keys are auth for a shared message
   > channel and confer no such access, so sharing them across the two projects widens nothing.
   > **Durability (prevents recurrence):** `op=arm` now carries a **G3.5 channel-key parity HARD GATE**
   > (cutover-inngest.yml) that sha256-compares the app vs host `INNGEST_EVENT_KEY`/`INNGEST_SIGNING_KEY`
   > (value-silent, AC-NOBODY) and **refuses to arm the flip** if they diverge, with the reconcile +
   > redeploy remediation. Because `soleur/prd`'s keys carry `ignore_changes=[value]`, reconcile is via
   > the Doppler copy (or `terraform apply -replace=random_id.inngest_{event,signing}_key_dedicated`
   > + copy) + a web redeploy — **not** a naive `terraform apply`. See runbook §2.4.
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
     **prod** and the flag ∉ `{armed, flipping, flushed, done}` — closing the race where the prod URI is
     written before the gated flip and any non-arm restart (crash / `OnBootSec` / operator) would
     otherwise bring up a **second prod scheduler** against the still-dirty dark Redis.
     **`flushed` is in the allowlist (amended 2026-07-17, Ref #6553):** the forward path sets the flag
     to `flushed` **before** it invokes `start_server` (`:163,:172` above; `inngest-cutover-flip.sh:188→189`),
     and the `flushed`-RESUME arm (`inngest-cutover-flip.sh:240`) also calls `start_server` while the
     flag is `flushed`. Because `DBSIZE==0` is asserted **before** `flushed` is ever written
     (`inngest-cutover-flip.sh:178`), a start at `flushed` cannot double-fire against a dirty dark Redis
     — so the guard MUST allow it. Omitting `flushed` (the pre-#6553 allowlist) made the guard block the
     FSM's **own** controlled start, not merely an unplanned restart. This is a correction of an
     ADR-vs-code inconsistency: the omitted state is the very state the FSM starts the server at.
   - **Guard/FSM lockstep — class invariant (added 2026-07-17, Ref #6553):** the guard allowlist MUST
     be a **superset** of the set of FSM states in which the cutover-flip oneshot invokes `start_server`.
     Adding a new FSM state that precedes a `start_server` call without adding it to the guard allowlist
     re-introduces the self-block above. This is enforced mechanically by a source-derived drift guard in
     `inngest-server-flip-guard.test.sh` (derives both sets from source and FAILS on divergence), not just
     by the point-in-time string assertions.
   - **Flip-state is read no-SSH via Better Stack** (P0-2): the oneshot emits its verify-state as a
     `logger -t inngest-cutover-flip` JSON line, carried off-box by the already-shipped on-host
     Vector → Better Stack Logs journald shipper (source `soleur-inngest-vector-prd`, #6197). The
     operator confirms `exit_code:0` by pulling that log line, **never** by reading a state file on
     the deny-all-public host (`cat-inngest-cutover-state.sh` is an on-host debug aid only, not the
     gate).
   - **`done` is PROBE-DERIVED, not asserted (corrected 2026-08-12, Ref #7228).** As originally
     written, this decision's completion gate was `exit_code:0` on a run whose final act was
     `start_server` — that is `systemctl start`, which succeeds when systemd **accepted the unit**,
     not when inngest **bound :8288**. So `done` and its `exit_code:0` asserted a live host
     condition neither had measured. That is not a hypothetical: the 2026-07-30 host recorded
     `done`, never bound, and the flag still read `done` twelve days later (#7228).
     `inngest-cutover-flip.sh` now reaches `done` only through `verify_or_abort`, which requires a
     **bounded-window `/health` 200 AND a non-empty `v0/gql` registry** — both, because a 200 over
     an empty registry is a scheduler that serves and owns nothing. Any failure drives the flag to
     terminal `aborted` with a `verify-*` reason. The `exit_code:0` gate above is unchanged in
     form and is now worth what it claims, because the run can no longer exit 0 without the probe
     having passed.
   - **A `done` must be OWNED by the host acting on it (added 2026-08-12, Ref #7228).** The flag
     lives in Doppler, which **outlives the host**, so `done` says a flip completed without saying
     on which machine — and a replaced host boots into a predecessor's `done`, which the
     `ExecStartPre` allowlist above reads as ALLOW. That reaches the second-prod-scheduler state
     P1-5 exists to prevent *through* the guard rather than around it.
     The record is an **existence-only marker on the root disk** (`/var/lib/inngest-cutover/done-owner`),
     written by the flip FSM at the moment a verified flip completes and tested by the guard.
     The question is not *which* instance earned the `done` but the strictly weaker *did the machine
     currently booting earn it* — a yes/no — and root-disk persistence **is** that predicate: the
     marker survives a reboot (same machine) and cannot survive a replace or re-image (fresh disk).
     `/mnt/data` is the only mount on this host, so `/var/lib` has exactly host lifetime. This is the
     same durable-vs-ephemeral axis Decision 6's flush latch reasons about one tier up, inverted:
     that latch lives on `/mnt/data` **because** it must survive a replace; this marker lives on the
     root disk **because** it must not.
     **A Doppler key was rejected at review, on a defect not a preference.** A new
     `INNGEST_CUTOVER_DONE_INSTANCE` secret in `soleur-inngest/prd` is admitted by nothing: the boot
     isolation self-check in `cloud-init-inngest.yml` is an **exact-set** match that FATALs when the
     project holds any name outside its allowlist, so from the first stamped flip onward **every
     re-provision of this host would refuse to bootstrap** — no Vector, no inngest-server, no flip
     timer — precisely when an operator is recovering it. That is the #6178 recurrence this ADR
     already records for `CUTOVER_FLIP`. Admitting the key would also have worked, and would have
     made the guard's correctness depend on remembering an allowlist in a different file; the marker
     has no such coupling, and additionally drops an IMDS round-trip from a boot-critical path.
     Nothing here touches the flag **value**, so the guard's exact `case` match and the lockstep
     test's `flag_set`-literal derivation are both preserved — the original constraint.
     Scoped to `done` alone: the transient states belong to a flip in progress on this host and
     carry no marker yet, so gating them would deadlock the cutover.
   - **`aborted` means no scheduler is running here (added 2026-08-12, Ref #7228).** The
     probe-derived `done` above runs *after* `start_server`, so its refusal path is the first abort
     in this FSM that can be reached with a server already up — and `inngest-server.service` is
     `Type=simple` with `Restart=on-failure`. Returning without stopping it would leave a **live prod
     scheduler** (on the empty-registry arm it has already adopted prod Postgres, and per this ADR's
     own Context scheduling is driven by the shared Postgres tables regardless of local registration)
     while the flag records a terminal failure the guard will never let anyone restart from. So
     `verify_or_abort` stops the server before driving the flag terminal, preserving the invariant
     every other abort already had: `dbsize-nonzero` never starts, `rollback` stops, and this one
     stops too.
   - **Post-flush re-entry on a replaced host is `flushed`, not `arm` (added 2026-08-12, Ref #7228).**
     A replaced host blocked by the owner-marker check cannot recover via `op=arm`: the FSM's `armed`
     arm consults the monotonic flush latch on `/mnt/data`, which **survives the replace by design**,
     and correctly refuses the re-arm into terminal `aborted` — re-flushing there would wipe the live
     prod queue (#5450). The reachable re-entry is `INNGEST_CUTOVER_FLIP=flushed`: it starts the
     server, verifies it serves, records the owner marker and completes to `done` **without**
     re-running `FLUSHALL`. The guard's refusal message names this path, because a guard that
     recommends a remedy the system refuses is worse than one that stays silent.
   - **Class rule, extracted from both corrections above (added 2026-08-12, Ref #7228 — this is the
     generalisation, and it is why no separate ADR ordinal was minted for it):**
     *a terminal state that asserts a live host condition must be re-derived from a probe, and must
     not outlive the thing it asserts.* Both defects are instances: `done` asserted a bind it never
     measured, and then survived in Doppler across a host that never performed it. Applying the
     rule means (a) deriving the state from a measurement at the moment it is written, and (b)
     scoping it to the identity of the thing measured, so it cannot be inherited.
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

### Amendment (2026-07-12, Ref #6178) — no-SSH web-host scheduler quiesce/re-enable

The Phase-2 cutover's web-host scheduler **quiesce** (forward) and **re-enable** (rollback) are
performed **no-SSH** via the existing deploy webhook + pinned sudoers verbs — operators have no
SSH access (`hr-no-ssh-fallback-in-runbooks`). This mirrors the `INNGEST_RESTART` (#4538) no-SSH
restart precedent and the private-net deploy fan-out (ADR-068, #5274):

- **`op=quiesce-web`** → ci-deploy.sh's `quiesce inngest _ _` handler runs the pinned
  `INNGEST_QUIESCE` sudoers verbs (`systemctl stop` + `systemctl disable inngest-server.service`),
  fanned out per-host over the private net. It verifies not-serving **AND** unit-inactive **AND**
  not-enabled (the `disable` removes the `[Install]` symlink so a mid-window reboot cannot re-arm
  the old scheduler → the double-fire this prevents), then the workflow POLLS `/hooks/deploy-status`
  for the synchronous `quiesced` verdict (the unit's `TimeoutStopSec=180` makes an immediate probe
  race the async stop).
- **`op=rollback`** → ci-deploy.sh's `enable inngest _ _` handler runs the pinned `INNGEST_ENABLE`
  verb (`systemctl enable`) + the pre-existing `INNGEST_START` (#5450) verb (`systemctl start`) +
  a serving-and-enabled verify, in ONE flock-held handler, then polls deploy-status for `enabled`.

**Rejected alternative — fold re-enable into the shared `restart` handler.** Tempting (op=rollback's
existing `restart` would then re-enable "for free"), but **unsafe post-cutover**: the web hosts'
inngest is intentionally disabled (10.0.1.40 is the sole scheduler), so a routine
`restart-inngest-server.yml` restart (LB-routed to a web host) with a re-enable folded in would
RE-ENABLE the deliberately-disabled web scheduler → a second live scheduler on prod Postgres →
double-fire. `restart` MUST stay pure; only the deliberate `op=rollback` re-enables, via a distinct
`enable` verb. (Note also arch P2-4: even a PURE `restart` is unsafe on a web host post-cutover — it
STARTS the disabled unit for a transient double-fire, because the `ExecStartPre` flip-guard blocks
only the dedicated host. The web verbs to use post-cutover are `op=quiesce-web`/`op=rollback`, never
`restart`.)

**Security blast-radius expansion (security review P2).** The single shared webhook deploy secret
now authorizes a scheduler-**disable** (and, via `enable`, a fleet-wide **re-arm**), not just
deploy/restart — inside the existing "deploy secret == prod-write" boundary, but the secret-rotation
cadence should reflect the wider authority. The peer fan-out path
(`http://<ip>:9000/hooks/deploy-peer`) is HMAC + L3-firewall only (no CF-Access), so confirm the
web→web:9000 firewall source-restricts to peer hosts (already proven live by the deploy fan-out;
`firewall-9000-deny`). No new ADR ordinal — this is an extension of ADR-100's decision, not a new
architecture. No C4 impact (the `deploy-webhook → ci-deploy → inngest-server` control edge already
exists; `quiesce`/`enable` are additional verbs on the SAME edge, not a new relationship).

### Amendment (2026-07-12, Ref #6369) — Decision 6b: no-SSH `op=arm` arm-flip + reverse write

The Phase-2 cutover's **arm-flip** (the three writes to `soleur-inngest/prd`:
`INNGEST_POSTGRES_URI`, `INNGEST_HEARTBEAT_URL`, then `INNGEST_CUTOVER_FLIP=armed` last — the last
was the operator SEAM at `cutover-inngest.yml`) is now performed **no-SSH** by
`cutover-inngest.yml op=arm`, and the reverse `INNGEST_CUTOVER_FLIP=rollback` write is folded into
the existing `op=rollback` verb. This removes the last operator secret-write seam from the cutover.

- **Trust / ack (reconciles `hr-menu-option-ack-not-prod-write-auth`).** `op=arm`/`op=rollback` are
  prod-writes behind an **explicit dispatch** (same trust model as `op=quiesce-web`/`op=rollback`)
  **plus** a GitHub **Environment** (`inngest-cutover`) required-reviewer protection rule. The
  dispatch + the reviewer approval IS the explicit per-command go-ahead the hard rule requires; the
  rule kept the flip out of `op=execute`'s *auto-run* spine, not out of a separately-dispatched,
  human-approved verb. There is **no interactive pre-write value confirmation, by design** —
  AC-NOBODY forbids echoing the values.
- **Provisioning (reconciles `hr-all-infrastructure-provisioning`).** The write **token** is
  TF-provisioned (`doppler_service_token.inngest_arm_write`, read/write on the isolated
  `soleur-inngest/prd`, published as the repo secret `DOPPLER_TOKEN_INNGEST_ARM`). The human-ack
  gate is the `inngest-cutover` GitHub **Environment** (required-reviewer) declared on the op=arm /
  op=rollback **job** — the run waits for approval before any step executes. (The token is a repo
  secret rather than an environment secret because the TF GitHub App lacks permission to write
  environment secrets — a first-apply 403; the reviewer gate on the job preserves the ack either
  way. Fixed forward in #6369-followup.) This is the **first CI-consumed read/write token into the
  isolated `soleur-inngest` project** — the other token there is the host-boot token
  (`doppler_service_token.inngest`), which is also read/write as of #6178 (the flip FSM writes
  `INNGEST_CUTOVER_FLIP` under it) but is HOST-consumed, not CI-consumed; CI can now WRITE
  `soleur-inngest/prd` too. The token is a **standing read
  handle to the armed prod DSN** once op=arm runs, so it is revoked post-cutover.
- **Source-of-truth: read-through, no seed (CTO decision at /work).** The two source *values*
  remain out-of-band (they are not TF `doppler_secret` resources — dark-window heartbeat masking +
  a DB password TF never minted, `inngest-host.tf:137-166`). op=arm reads them **read-through from
  `soleur/prd_terraform`** via the workflow's existing read-only `DOPPLER_TOKEN` (the same
  config-scoped read `op=backup` uses for `HCLOUD_TOKEN`). The prod `INNGEST_POSTGRES_URI` already
  lives in `prd_terraform` (SHA-identical to canonical `prd`, `:5432` session pooler, distinct from
  the dark value), so there is **no operator secret-seed step and no stale-copy rotation-drift
  trap**. Reading the live canonical source at arm-time makes freshness *structural*; the G3
  positive prod-URI assertion (prod ≠ dark, `:5432` not `:6543`, prod host) + the G1 pre-write
  FSM-state guard remain the defense against writing a wrong/dark value. **Rejected:** (A) seed a
  narrow `INNGEST_POSTGRES_URI_PROD` config — removes no existing exposure (the value is already
  CI-readable) while adding a forbidden human pre-window seed + a drift trap that could arm a dead
  DSN and stall every user's crons; (B) a workflow step copying `prd_terraform`→narrow — machinery
  to relocate an already-readable value, inheriting (A)'s drift risk.

**Post-cutover revoke.**
<!-- lint-infra-ignore start -->
After `op=verify` confirms exactly-once (AC17), the write token is rotated + revoked
(`terraform apply -replace=doppler_service_token.inngest_arm_write` + `doppler configs tokens
revoke` the orphaned key) so no standing prod-DSN read handle survives (runbook § Rollback / Op
order 3b).
<!-- lint-infra-ignore end -->

**No C4 change (enumeration).** op=arm is a new *instance* of an already-modeled relationship, not a
new one: `doppler` (system), `betterstack` (system), `github`, `inngest`/`inngestPostgres`/
`inngestRedis` (containers/stores) are all in `model.c4`; the CI/TF→Doppler secret-**write**
relationship already exists at the C4 altitude (TF applies writes to Doppler via
`doppler_service_token.write`; the precedent write edge is `inngest -> doppler "Writes GHCR_READ_TOKEN"`,
`model.c4:404` — a Doppler-write edge, distinct from the `doppler -> inngest "Injects secrets"`
injection edge). op=arm writing `soleur-inngest/prd` is another edge of the same write relationship
type, not a new relationship — so no `model.c4`/`views.c4` edit. No new ADR ordinal
— this is an extension of ADR-100's Decision 6, mirroring the Ref #6178 amendment above.

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

**Regression back-ref (#6396):** defaulting `web_colocate_inngest = false` (#6178) silently dropped
the co-located web-host Vector journald/host_metrics shipper — a fresh web host installed Vector
ONLY inside the `%{ if web_colocate_inngest }` block, so post-cutover web hosts shipped **no** logs
to Better Stack. #6396 re-adds the shipper independently (ungated, baked into
`soleur-host-bootstrap.sh`, fail-open) + a terminal serving-block no-SSH cause breadcrumb + `host_id`
on `pull_failure_event`. See ADR-082 Item 5 (this is the decision that caused the regression #6396
closes).

**Create-time-render caveat (#6616):** the per-host `host_name` #6396 introduces is a
*construction-time render*, not a runtime-guaranteed 1:1 discriminator. A host that predates the
render and cannot re-run cloud-init (web-1, under `lifecycle{ignore_changes=[user_data]}`) keeps its
stale co-located-era `host_name=soleur-inngest-prd` until its next immutable recreate — so it collides
with the dedicated node on Better Stack source 2457081. Treat `host_name=soleur-inngest-prd` as suspect
until every emitting host is post-#6396-born; the live invariant is enforced by the #6616 read-only
follow-through (auto-closes on the web-1 recreate), not by the render alone. (The dedicated node's
telemetry `host` is `soleur-inngest` = its `hcloud_server.inngest` name, inngest-host.tf:202, and thus
its OS hostname — NOT `soleur-inngest-server-prd`, which is a `betteruptime_heartbeat` monitor name,
inngest.tf:291, and never appears in telemetry.)

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
  (dark-boot secret count 4→5, live 5→6; live is now 7 — see below); its admission criterion is "names this host's runtime
  consumes" (not `INNGEST_`-prefixed). During the dark window the host still does not push the prod
  heartbeat (out-of-band `INNGEST_HEARTBEAT_URL` set only at cutover, to avoid dual-pusher masking of
  the still-serving co-located scheduler — review #6180), so a DARK, inert host that boot-bricks or
  errors is surfaced at the Phase-2 pre-flight registry-empty check + the in-surface bootstrap-stderr
  lines (deploy-status endpoint), not by continuous monitoring. The shipper is wired ahead of the
  Phase-2 cutover (when this becomes the live scheduler) — the alignment claim above holds from cutover.
- **Amendment (#6178, 2026-07-23) — the allowlist must admit the CONTROL-PLANE names too, and the
  boot-brick is NOT loud.** `op=arm` writes `INNGEST_CUTOVER_FLIP` into this same isolated project,
  so the live count is **7**, not 6 (`INNGEST_CONFIG_DIGEST` makes 8 once `inngest-config-digest.tf`
  applies). The regex omitted `CUTOVER_FLIP`, so from the moment the cutover was armed every
  re-provision FATALed the exact-set check — no Vector, no inngest-server, no flip timer. The flip
  could therefore never run, and because Vector is installed BY the bootstrap the check gates, the
  failure shipped nothing off-box: it was silent for hours until the `SOLEUR_INNGEST_BOOT_STAGE`
  phone-home (#6702, curl-direct and Vector-independent) named `isolation-check-FAILED`.
  Two consequences worth recording against the #6197 reasoning above: (a) "a loud boot-brick beats a
  silent observability blind spot" does not hold as stated — here the boot-brick *was* the blind spot,
  because the shipper is downstream of the gate; (b) an exact-set allowlist makes the *safe* operation
  (adding a legitimate secret) fail closed, and that is precisely what the control plane does at
  runtime. Follow-ups filed: alarm on `SOLEUR_INNGEST_BOOT_STAGE`; derive the allowlist from the
  declared writers instead of hand-maintaining it; consider moving FSM/control state out of the
  secret project entirely.
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

## Addendum (2026-07-09) — git-data is the third host to adopt the scoped `-replace` dispatch (#6242)

`inngest-host-replace` (this ADR) was the **second** application of the scoped-`-replace`
non-SSH reprovision-dispatch mechanism (ADR-096's `registry-host-replace` was the first). #6242
adds **`git-data-host-replace`** as the **third**: a `workflow_dispatch` job running a scoped,
destroy-guarded `terraform apply -replace='hcloud_server.git_data'` (server + private NIC + BOTH
data volume attachments + firewall attachment; both `hcloud_volume.git_data*` and the LUKS
passphrase preserved by OMISSION). It closes git-data's standing zero-non-SSH-reprovision-capability
gap on the fleet's most irreplaceable data store.

This is a **re-application** of the established mechanism, not a novel decision — so it carries no
new ordinal of its own. The genuinely-new cross-cutting rule extracted from the #6238 recurrence
(a boot-armed non-paused heartbeat MUST have a mechanically-guarded reprovision path) is recorded
separately in **ADR-103**, whose `heartbeat-reprovision-parity` CI guard enforces it.

## Addendum (2026-07-15) — the dark backend is **soleur-dev**, and that co-tenancy is transient

**The fact, recorded here because it previously lived ONLY in a Terraform comment**
(`apps/web-platform/infra/inngest.tf:234-235`) and in a Doppler secret's value — neither of which
is a place an architecture reader looks:

> Until the cutover flips it, the dedicated Inngest host's **dark** Postgres backend is the
> **soleur-dev** Supabase project (`mlwiodleouzwniehynfz`), reached through its session pooler as
> username `postgres.mlwiodleouzwniehynfz`. `INNGEST_POSTGRES_URI` in Doppler `soleur-inngest/prd`
> resolves there. It is **not** "a distinct DB on soleur-inngest-prd".

**Why this matters beyond bookkeeping.** soleur-dev is the **app's dev project**. Pointing the dark
backend at it made that project **co-tenanted**: goose ran 2026-07-10 and created 14 Inngest tables
in the same `public` schema as the web-platform app's 52 dev tables. Two consequences followed, both
now closed:

1. **A live anon-write exposure.** Supabase default privileges auto-granted `anon`/`authenticated`
   full DML on the new tables, and soleur-dev's anon key **ships to browsers**. An anonymous caller
   held INSERT/UPDATE/DELETE/**TRUNCATE** on this host's scheduler state (advisor 2026-07-12; a
   `GET /rest/v1/apps` returned 310 bytes of real rows). Remediated by the table-scoped
   `0002_dev_inngest_tables_lockdown.sql` — see **ADR-030 I8** (by filename:
   `ADR-030-inngest-as-durable-trigger-layer.md`; the `ADR-030` ID is ambiguous, two files claim it).
2. **The existing prd lockdown became unsafe to point anywhere else.** `0001`'s Inngest-sentinel
   preflight infers *"goose tables exist ⟹ Inngest-only project"* — which the dark backend
   **falsified**, since soleur-dev satisfies it while hosting an entire app. Enforcement on a
   co-tenanted project MUST be table-scoped; see I8.

**Transient — with an atomic retirement.** This co-tenancy ends when `cutover-inngest.yml`'s
`op=arm` writes the prod DSN. The 14 tables then become orphans on the dev project and are dropped
in a tracked follow-up, which must retire `0002` + `apply-inngest-rls-dev.yml` **in the same change
as (or before) the drop** — otherwise `0002`'s positive sentinel RAISEs forever. The quieter failure
is worse: if the cutover lands and the drop does not, the sentinel still passes, the gate reports
`violations=0`, and the workflow stays **green forever defending a co-tenancy that no longer
exists**. Green cruft never annunciates. (Contrary to an earlier belief, soleur-dev is **not** a
rollback target: `op=arm` overwrites `INNGEST_POSTGRES_URI`, and the `rollback` arm writes only
`INNGEST_CUTOVER_FLIP` — no code path restores the dark DSN. The reason not to drop early is simply
that the dark host is **live** against soleur-dev until the flip.)


## Addendum — 2026-08-12 (#7228) — the cutover did not hold, and the soak never started

Appended rather than folded into the body above: everything before this section describes the
system this ADR **decided to build**, and it remains the accurate record of that decision. This
section records what the system **actually did**, which is a different claim, and one that any
reader of the sections above needs before acting on them.

**Measured, not inferred.** The dedicated host (`soleur-inngest`, 10.0.1.40, created
2026-07-30T15:13:06Z) boots and runs but has never bound `:8288`. It has shipped **zero** rows to
Better Stack; the web host's dispatches to it fail `connect ECONNREFUSED` at roughly 600 rows/hour
(re-measured 2026-08-11 12:15). `INNGEST_CUTOVER_FLIP` rests at **`rollback`** — not
`rolled-back`: run 31486949232 wrote the brake and then failed to confirm the terminal state
within 600s, because the confirmation is performed by the on-host FSM and shipped by the on-host
shipper, and the host ships nothing. It fail-closed correctly and withheld the second half.

**Consequences for the sections above, stated explicitly:**

1. **The Phase-4 soak never started.** Any statement in this ADR written in the present tense
   about a running dedicated scheduler describes an intention, not an observation.
2. **The co-located web-host Inngest is still the live scheduler.** It holds the entire function
   registry and is actively firing crons, which is why the 53 registered crons were **unaffected**
   by this incident (execution is pinned to web-1, #7230) while every *app-originated* event
   dispatch failed. The blast radius was fleet-wide for dispatch, not inbound-email only.
3. **Decision 6a's completion gate was not sufficient**, and is corrected in place above rather
   than here — the corrections belong with the decision they modify.
4. **The root cause of the bind failure is UNKNOWN and is deliberately not guessed at.** The
   deciding datum was an eight-marker `SOLEUR_INNGEST_BOOT_STAGE` boot trace whose sink retention
   is ~3 days against a 12-day-old boot: it is irrecoverable by construction, so no query can
   return it. Recording a plausible cause here would be the failure mode this project has
   already paid for once (`2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`).
   Resolution is a **diagnostic boot** — a guard-permitted start against a non-prod backend, so
   `is_prod=false` takes the guard's ALLOW arm and the host can attempt a bind and emit a
   discriminating `net-health` row with no path to a second prod scheduler. Tracked as **#7462**.

**What #7228's PR changed, and what it deliberately did not.** It ships detection that does not
depend on the broken host (a consumer-side probe on the web host, so it works the day it merges,
with no host replace), makes the host diagnosable when it is next replaced, and makes the
re-cutover safe. It does **not** restore the host: that is #7462, and #7228 / #6617 / #7308 are
therefore cited as `Ref` rather than closed by it. The twelve days of failed dispatches are
**accepted as lost** by operator decision (2026-08-11) — a decision, not an omission; no replay,
backfill or dead-letter path is in scope. An interim `INNGEST_BASE_URL` repoint was also declined,
deliberately: the dedicated host is to be fixed properly rather than returned to the co-located
operating point.


## Addendum — 2026-08-20 (#7462) — `op=arm` is idempotent, and the prod DSN in the dark slot is the steady state

Appended rather than folded into the 2026-07-15 addendum above: that addendum remains the accurate
record of what was decided and of the co-tenancy as it stood. This section records a consequence it
predicted in parentheses and treated as a footnote, which turned out to be load-bearing.

**What that addendum got right, and what followed from it.** It states: *"soleur-dev is not a
rollback target: `op=arm` overwrites `INNGEST_POSTGRES_URI`, and the `rollback` arm writes only
`INNGEST_CUTOVER_FLIP` — no code path restores the dark DSN."* Both halves are correct. The
consequence is that after the FIRST successful arm the dark slot holds the prod DSN permanently.

An `op=arm` succeeded on **2026-07-23T15:46Z** (Doppler config log for `soleur-inngest/prd`: three
writes inside one second by `user=inngest-cutover-arm` — the DSN, the heartbeat URL, and the flag).
Measured 2026-08-20, value-silently: `soleur-inngest/prd` and `soleur/prd_terraform`
`INNGEST_POSTGRES_URI` are byte-identical (sha256 prefix `7968f3d658c2`), both carrying the prod
project ref and neither carrying soleur-dev's.

**What broke.** G3 refused whenever the value it was about to write already equalled the value in
place. That condition became permanently true on 2026-07-23, so every subsequent arm was refused
regardless of readiness — the cutover could not be re-armed after a rollback, which is precisely
what rollback exists to allow. It blocked the 2026-08-20 attempt, at the cost of a ~7m38s web
scheduler gap and one missed timer tick.

**The decision.** `op=arm` is now **idempotent**. When the target value is already in place, G3
returns `skip-already-current` and the arm PROCEEDS. The DSN write is **not** skipped — an
earlier revision of this change branched the write on that outcome and the branch was removed
before merge: inverting its polarity skipped the write on the FIRST-arm transition, booting the
host onto the dark backend while reporting success, with the whole suite green. All three prod
writes are unconditional, which is strictly stronger — the arm ESTABLISHES the invariant rather
than observing it. Do not reintroduce the branch. The
heartbeat write and the `armed` write still run — skipping those would convert a successful arm into
a silent no-op.

**Why relaxing that guard costs no safety.** The hazard G3's own error text named ("would flip onto
the DARK backend") is held entirely by the positive prod-project pin evaluated immediately before it:
the dark backend is a *distinct Supabase project* and cannot carry the prod ref, so a value that
passes the pin routes to the prod project. "Prod by construction" was too strong as originally
written and is corrected here: the first two forms of the pin were defeated — a bare `*<ref>*`
substring accepted the ref in a password or query parameter, and pinning the pooler USERNAME
accepted `postgres.<prod-ref>` in front of ANY host, including `db.<dev-ref>.supabase.co`. The
shipped pin anchors the AUTHORITY (scheme + user + Supabase host suffix + port), requires exactly
one `@`, and rejects `,` and `host=`; twelve bypasses are permanent must-REFUSE fixtures. The equality test contributed nothing to that. The FLUSHALL
hazard is held by the monotonic latch in `inngest-cutover-flip.sh` (#7228 P0-5) — recorded **at the
flush** rather than at completion, fatal if unrecordable, and fronted by a durability gate that
refuses to flush when the latch cannot be durably written. Re-arming over an in-flight or completed
flip is held by G1. None of those changed.

The residual concentration is deliberate and worth stating: the prod project-ref pin is now the sole
guard against arming onto a non-prod Postgres. That is why the decision was extracted into a pure
`g3_decide` function with a mutation-tested suite — deleting the pin reddens the build.

**Two corrections to the record.**

1. **The diagnostic-boot premise is false — and it is stated INSIDE this ADR, not only in #7462's
   runbook.** The 2026-08-12 addendum above says verbatim: *"Resolution is a diagnostic boot — a
   guard-permitted start against a non-prod backend, so `is_prod=false` takes the guard's ALLOW arm."*
   Read that clause as SUPERSEDED. Only its first half is wrong: the backend is prod, and has been
   since 2026-07-23. The diagnostic boot itself still works, by a different mechanism than that
   sentence describes — `inngest-server-flip-guard.sh` derives `is_prod=false` from the unit file's
   SQLite-only sentinel, never from the DSN's value — so #7462's resolution path is intact. A reader
   of the correction alone would wrongly conclude it is dead. Anything reasoning from "the dark host
   points at soleur-dev" is reasoning about the system as it was before that date.
1a. **`op=arm` never read `INNGEST_DIAGNOSTIC_BOOT` until this change.** `inngest-bootstrap.sh` states
   the precondition in prose — *"This is NOT a cutover state: clear INNGEST_DIAGNOSTIC_BOOT before
   arming"* — and nothing enforced it; measured 2026-08-20, the flag was live at `1` and the arm
   contained zero references to it. Arming in that state would have run the FSM to `done`, quiescing
   the web scheduler and cutting over to a host whose ExecStart is SQLite-only with `--sdk-url` on a
   closed loopback port, i.e. serving no registry, while reporting success. G3.6 now refuses before
   any write.
2. **The prod DSN resting in the dark slot is the documented post-first-arm steady state, not drift
   to be corrected.** Restoring the soleur-dev DSN would re-create the co-tenancy this ADR wants
   retired and would be undone by the next arm anyway.

**Unchanged.** The soleur-dev co-tenancy defences (`0002_dev_inngest_tables_lockdown.sql`,
`apply-inngest-rls-dev.yml`) remain live and correct: the cutover has not held, so the retirement
sequencing described in the 2026-07-15 addendum still applies — but NOT unmodified, and the
difference is recorded rather than substituted silently. That addendum names its trigger as
"`op=arm` writes the prod DSN", and by that wording the trigger FIRED on 2026-07-23 and the
retirement was due. The condition that actually governs is the stricter one the follow-through
already uses (`scripts/followthroughs/inngest-rls-drop-6488.sh`): the flip reached `done` AND the
DSN is not the dev ref AND the soak elapsed. Read the 2026-07-15 trigger as superseded by that.
Its closing parenthetical — "the dark host is live against soleur-dev until the flip" — is also
dead: the host has never bound `:8288`. The conclusion (do not drop early) survives on the
different ground that the 14 tables still physically exist on soleur-dev. The forward/reverse
asymmetry for `INNGEST_POSTGRES_URI` is now deliberate rather than an omission — idempotence makes an
inverse unnecessary, which is why one was not added.
